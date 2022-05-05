module ReusePatterns
using InteractiveUtils
using Combinatorics

export forward, @forward,
    @copy_fields,
    @quasiabstract, concretetype, isquasiabstract, isquasiconcrete



"""
`forward(sender::Tuple{Type,Symbol}, receiver::Type, method::Method; withtypes=true, allargs=true)`

Return a `Vector{String}` containing the Julia code to properly forward `method` calls to from a `sender` type to a receiver type.

The `sender` tuple must contain a structure type, and a symbol with the name of one of its fields.

The `withtypes` keyword controls whether the forwarding method has type annotated arguments.  The `allargs` keyword controls whether all arguments should be used, or just the first ones up to the last containing the `receiver` type.

Both keywords are `true` by default, but they can be set to `false` to decrease the number of forwarded methods.

# Example:
Implement a wrapper for an `Int` object, and forward the `+` method accepting `Int`:
```julia-repl
struct Wrapper{T}
    wrappee::T
    extra
    Wrapper{T}(args...; kw...) where T = new(T(args...; kw...), nothing)
end

# Prepare and evaluate forwarding methods:
m = forward((Wrapper, :wrappee), Int, which(+, (Int, Int)))
eval.(Meta.parse.(m))

# Instantiate two wrapped `Int`
i1 = Wrapper{Int}(1)
i2 = Wrapper{Int}(2)

# And add them seamlessly
println(i1 +  2)
println( 1 + i2)
println(i1 + i2)
```
"""
function forward(sender::Tuple{Type,Symbol}, receiver::Type, method::Method;
                 withtypes=true, allargs=true)
    function newmethod(sender_type, sender_symb, argid, method, withtypes, allargs)
        s = "p" .* string.(1:method.nargs-1)
        (withtypes)  &&  (s .*= "::" .* string.(fieldtype.(Ref(method.sig), 2:method.nargs)))
        s[argid] .= "p" .* string.(argid) .* "::$sender_type"
        if !allargs
            s = s[1:argid[end]]
            push!(s, "args...")
        end

        # Module where the method is defined
        ff = fieldtype(method.sig, 1)
        if isabstracttype(ff)
            # costructors
            m = string(method.module.eval(:(parentmodule($(method.name)))))  # Constructor
        else
            # all methods except constructors
            m = string(parentmodule(ff))
        end
        m *= "."
        l = "$m:(" * string(method.name) * ")(" * join(s,", ") * "; kw..."
        m = string(method.module) * "."
        l *= ") = $m:(" * string(method.name) * ")("
        s = "p" .* string.(1:method.nargs-1)
        if !allargs
            s = s[1:argid[end]]
            push!(s, "args...")
        end
        s[argid] .= "getfield(" .* s[argid] .* ", :$sender_symb)"
        l *= join(s, ", ") * "; kw...)"
        l = join(split(l, "#"))
        return l
    end

    @assert isstructtype(sender[1])
    @assert sender[2] in fieldnames(sender[1])
    sender_type = string(parentmodule(sender[1])) * "." * string(nameof(sender[1]))
    sender_symb = string(sender[2])
    code = Vector{String}()

    # Search for receiver type in method arguments
    foundat = Vector{Int}()
    for i in 2:method.nargs
        argtype = fieldtype(method.sig, i)
        (sender[1] == argtype)  &&  (return code)
        if argtype != Any
            (typeintersect(receiver, argtype) != Union{})  &&  (push!(foundat, i-1))
        end
    end
    (length(foundat) == 0)  &&  (return code)
    if string(method.name)[1] == '@'
        @warn "Forwarding macros is not yet supported."  # TODO
        display(method)
        println()
        return code
    end

    for ii in combinations(foundat)
        push!(code, newmethod(sender_type, sender_symb, ii, method, withtypes, allargs))
    end

    tmp = split(string(method.module), ".")[1]
    code = "@eval " .* tmp .* " " .* code .*
        " # " .* string(method.file) .* ":" .* string(method.line)
    if  (tmp != "Base")  &&
        (tmp != "Main")
        pushfirst!(code, "using $tmp")
    end
    code = unique(code)
    return code
end


"""
`forward(sender::Tuple{Type,Symbol}, receiver::Type; super=true, kw...)`
"""
function forward(sender::Tuple{Type,Symbol}, receiver::Type; kw...)
    code = Vector{String}()
    for m in methodswith(receiver, supertypes=true)
        append!(code, forward(sender, receiver, m; kw...))
    end
    return unique(code)
end

"""
`@forward(sender, receiver, ekws...)`

Evaluate the Julia code to forward methods.  The syntax is exactly the same as the `forward` function.

# Example:
```julia-repl
julia> struct Book
    title::String
    author::String
end
julia> Base.show(io::IO, b::Book) = println(io, "\$(b.title) (by \$(b.author))")
julia> Base.print(b::Book) = println("In a hole in the ground there lived a hobbit...")
julia> author(b::Book) = b.author

julia> struct PaperBook
    b::Book
    number_of_pages::Int
end
julia> @forward((PaperBook, :b), Book)
julia> pages(book::PaperBook) = book.number_of_pages

julia> struct Edition
    b::PaperBook
    year::Int
end
julia> @forward((Edition, :b), PaperBook)
julia> year(book::Edition) = book.year

julia> book = Edition(PaperBook(Book("The Hobbit", "J.R.R. Tolkien"), 374), 2013)

julia> print(author(book), ", ", pages(book), " pages, Ed. ", year(book))
J.R.R. Tolkien, 374 pages, Ed. 2013

julia> print(book)
In a hole in the ground there lived a hobbit...
```
"""
macro forward(sender, receiver, ekws...)
    kws = Vector{Pair{Symbol,Any}}()
    for kw in ekws
        if isa(kw, Expr)  &&  (kw.head == :(=))
            push!(kws, Pair(kw.args[1], kw.args[2]))
        else
            error("The @forward macro requires two arguments and (optionally) the same keywords accepted by forward()")
        end
    end

    out = quote
        counterr = 0
        mylist = forward($sender, $receiver; $kws...)
        for line in mylist
            try
                eval(Meta.parse("$line"))
            catch err
                global counterr += 1
                println()
                println("$line")
                @error err;
            end
        end
        if counterr > 0
            println(counterr, " method(s) raised an error")
        end
    end
    return esc(out)
end


"""
`@copy_fields T`

Copy all field definitions from a structure into another.

# Example
```julia-repl

julia> struct First
    field1
    field2::Int
end
julia> struct Second
    @copy_fields(First)
    field3::String
end

julia> println(fieldnames(Second))
(:field1, :filed2, :field3)

julia> println(fieldtype.(Second, fieldnames(Second)))
(Any, Int64, String)
```
"""
macro copy_fields(T)
    out = Expr(:block)
    for name in fieldnames(__module__.eval(T))
        e = Expr(Symbol("::"))
        push!(e.args, name)
        push!(e.args, fieldtype(__module__.eval(T), name))
        push!(out.args, e)
    end
    return esc(out)
end


# New methods for the following functions will be implemented when the @quasiabstract macro is invoked
"""
`concretetype(T::Type)`

Return the concrete type associated with the *quasi abstract* type `T`. If `T` is not *quasi abstract* returns nothing.

See also: `@quasiabstract`
"""
concretetype(T::Type) = nothing


"""
`isquasiabstract(T::Type)`

Return `true` if `T` is *quasi abstract*, `false` otherwise.

See also: `@quasiabstract`
"""
isquasiabstract(T::Type) = false


"""
`isquasiconcrete(T::Type)`

Return `true` if `T` is a concrete type associated to a *quasi abstract* type, `false` otherwise.

See also: `@quasiabstract`
"""
isquasiconcrete(T::Type) = false



"""
`@quasiabstract expression`

Create a *quasi abstract* type.

This macro accepts an expression defining a (mutable or immutable) structure, and outputs the code for two new type definitions:
- an abstract type with the same name and (if given) supertype of the input structure;
- a concrete structure definition with name prefix `Concrete_`, subtyping the abstract type defined above.

The relation between the types ensure there will be a single concrete type associated to the abstract one, hence you can use the abstract type to annotate method arguments, and be sure to receive the associated concrete type, or one of its subtypes (which shares all field names and types of the ancestors).

The concrete type associated to an *quasi abstract* type can be retrieved with the `concretetype` function.  The `Concrete_` prefix can be customized passing a second symbol argument to the macro.

These newly defined types allows to easily implement concrete subtyping: simply use the *quasi abstract* type name for both object construction and to annotate method arguments.

# Example:
```julia-repl
julia> @quasiabstract struct Book
    title::String
    author::String
end
julia> Base.show(io::IO, b::Book) = println(io, "\$(b.title) (by \$(b.author))")
julia> Base.print(b::Book) = println("In a hole in the ground there lived a hobbit...")
julia> author(b::Book) = b.author

julia> @quasiabstract struct PaperBook <: Book
    number_of_pages::Int
end
julia> pages(book::PaperBook) = book.number_of_pages

julia> @quasiabstract struct Edition <: PaperBook
    year::Int
end
julia> year(book::Edition) = book.year

julia> println(fieldnames(concretetype(Edition)))
(:title, :author, :number_of_pages, :year)

julia> book = Edition("The Hobbit", "J.R.R. Tolkien", 374, 2013)

julia> print(author(book), ", ", pages(book), " pages, Ed. ", year(book))
J.R.R. Tolkien, 374 pages, Ed. 2013

julia> print(book)
In a hole in the ground there lived a hobbit...

julia> @assert isquasiconcrete(typeof(book))

julia> @assert isquasiabstract(supertype(typeof(book)))

julia> @assert concretetype(supertype(typeof(book))) === typeof(book)
```
"""
macro quasiabstract(expr, prefix::Symbol=:Concrete_)
    function change_symbol!(expr, from::Symbol, to::Symbol)
        if isa(expr, Expr)
            for i in 1:length(expr.args)
                if isa(expr.args[i], Symbol)  &&  (expr.args[i] == from)
                    expr.args[1] = to
                else
                    if isa(expr.args[i], Expr)
                        change_symbol!(expr.args[i], from, to)
                    end
                end
            end
        end
    end
    drop_parameter_types(expr::Symbol) = expr
    function drop_parameter_types(_aaa::Expr)
        aaa = deepcopy(_aaa)
        for ii in 1:length(aaa.args)
            if isa(aaa.args[ii], Expr)  &&  (aaa.args[ii].head == :<:)
                insert!(aaa.args, ii, aaa.args[ii].args[1])
                deleteat!(aaa.args, ii+1)
            end
        end
        return aaa
    end
    function prepare_where(expr::Expr, orig::Expr)
        @assert expr.head == :curly
        whereclause = Expr(:where)
        push!(whereclause.args, orig)
        for i in 2:length(expr.args)
            @assert (isa(expr.args[i], Symbol)  ||  (isa(expr.args[i], Expr)  &&  (expr.args[i].head == :<:)))
            push!(whereclause.args, expr.args[i])
        end
        return whereclause
    end

    @assert isa(expr, Expr)
    @assert expr.head == :struct "Expression must be a `struct`"

    # Ensure there is room for the super type in the expression
    if isa(expr.args[2], Symbol)
        name = deepcopy(expr.args[2])
        deleteat!(expr.args, 2)
        insert!(expr.args, 2, Expr(:<:, name, :Any))
    end
    if isa(expr.args[2], Expr)  &&  (expr.args[2].head != :<:)
        insert!(expr.args, 2, Expr(:<:, expr.args[2], :Any))
        deleteat!(expr.args, 3)
    end
    @assert isa(expr.args[2], Expr)
    @assert expr.args[2].head == :<:

    # Get name and super type
    tmp = expr.args[2].args[1]
    @assert (isa(tmp, Symbol)  ||  (isa(tmp, Expr)  &&  (tmp.head == :curly)))
    name = deepcopy(tmp)
    name_symb = (isa(tmp, Symbol)  ?  tmp  :  tmp.args[1])

    tmp = expr.args[2].args[2]
    @assert (isa(tmp, Symbol)  ||  (isa(tmp, Expr)  &&  ((tmp.head == :curly) || (tmp.head == :(.)))))
    super = deepcopy(tmp)
    super_symb = ((isa(tmp, Expr)  &&  (tmp.head == :curly))  ?  tmp.args[1]  :  tmp)

    # Output abstract type
    out = Expr(:block)
    push!(out.args, :(abstract type $name <: $super end))

    # Change name in input expression
    concrete_symb = Symbol(prefix, name_symb)
    if isa(name, Symbol)
        concrete = concrete_symb
    else
        concrete = deepcopy(name)
        change_symbol!(concrete, name_symb, concrete_symb)
    end
    change_symbol!(expr, name_symb, concrete_symb)

    # Drop all types from parameters in `name`, or they'll raise syntax errors
    name = drop_parameter_types(name)

    # Change super type in input expression to actual name
    deleteat!(expr.args[2].args, 2)
    insert!(  expr.args[2].args, 2, name)

    # If an ancestor type is quasi abstract retrieve the associated
    # concrete type and add its fields as members
    p = __module__.eval(super_symb)
    while (p != Any)
        if isquasiabstract(p)
            parent = concretetype(p)
            for i in fieldcount(parent):-1:1
                e = Expr(Symbol("::"))
                push!(e.args, fieldname(parent, i))
                push!(e.args, fieldtype(parent, i))
                pushfirst!(expr.args[3].args, e)
            end
            break
        end
        p = __module__.eval(supertype(p))
    end

    # Add modified input structure to output
    push!(out.args, expr)

    # Add a constructor whose name is the same as the abstract type
    if isa(name, Expr)
        whereclause = prepare_where(name, :($name(args...; kw...)))
        push!(out.args, :($whereclause = $concrete(args...; kw...)))
    else
        push!(out.args, :($name(args...; kw...) = $concrete(args...; kw...)))
    end

    # Add `concretetype`, `isquasiabstract` and `isquasiconcrete` methods
    push!(out.args, :(ReusePatterns.concretetype(::Type{$name_symb}) = $concrete_symb))
    push!(out.args, :(ReusePatterns.isquasiabstract(::Type{$name_symb}) = true))
    push!(out.args, :(ReusePatterns.isquasiconcrete(::Type{$concrete_symb}) = true))

    if isa(name, Expr)
        whereclause = prepare_where(name, :(ReusePatterns.concretetype(::Type{$name})))
        push!(out.args, :($whereclause = $concrete))

        whereclause = prepare_where(name, :(ReusePatterns.isquasiabstract(::Type{$name})))
        push!(out.args, :($whereclause = true))

        # Drop all types from parameters in `concrete`, or they'll raise syntax errors
        concrete = drop_parameter_types(concrete)

        whereclause = prepare_where(name, :(ReusePatterns.isquasiconcrete(::Type{$concrete})))
        push!(out.args, :($whereclause = true))
    end
    return esc(out)
end

end # module
