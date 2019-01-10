module ForwardCalls
using InteractiveUtils

# TODO
# - forward macro calls

export supertypes, forward, @forward,
    @copy_fields, concretetype, isinheritable, @inheritable


"""
`supertypes(T::Type)`

Returns a vector with all supertypes of type `T` (excluding `Any`).

# Example
```julia-repl
julia> println(supertypes(Int))
Type[Signed, Integer, Real, Number]
```
"""
function supertypes(T::Type)::Vector{Type}
    out = Vector{Type}()
    st = supertype(T)
    if st != Any
        push!(out, st)
        push!(out, supertypes(st)...)
    end
    return out
end


"""
`forward(sender::Tuple{Type,Symbol}, receiver::Type, method::Method; withtypes=true, allargs=true)`

Return a `Vector{String}` containing the Julia code to properly forward `method` calls to from a `sender` type to a receiver type.

The `sender` tuple must contain a structure type, and a symbol with the name of one of its fields.

The `withtypes` keyword controls whether the forwarding method has type annotated arguments.  The `allargs` keyword controls wether all arguments should be used, or just the first ones up to the last containing the `receiver` type.

Both keywords are `true` by defult, but they can be set to `false` to decrease the number of forwarding methods.

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
        m = string(method.module.eval(:(parentmodule($(method.name))))) * "."
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

    sender_type = string(parentmodule(sender[1])) * "." * string(nameof(sender[1]))
    sender_symb = string(sender[2])
    code = Vector{String}()
    
    # Seacrh for receiver type in method arguments
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
        @warn "Forwarding macros is not yet supported."
        display(method)
        println()
        return code
    end
    
    for argid in foundat
        push!(code, newmethod(sender_type, sender_symb, [argid], method, withtypes, allargs))
    end
    if length(foundat) > 1
        push!(code, newmethod(sender_type, sender_symb, foundat, method, withtypes, allargs))
        if length(foundat) >= 3
            @warn "The following method accept the same argument three or more times.  Not all combinations will be automatically forwarded."
            display(method)
            println()
        end
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
`forward(sender::Tuple{Type,Symbol}, receiver::Type, methods::Vector{Method}; kw...)`
"""
function forward(sender::Tuple{Type,Symbol}, receiver::Type, methods::Vector{Method}; kw...)
    code = Vector{String}()
    for m in methods
        append!(code, forward(sender, receiver, m; kw...))
    end
    code = unique(code)
    return code
end

"""
`forward(sender::Tuple{Type,Symbol}, receivers::Vector{T}, methods; kw...)`
"""
function forward(sender::Tuple{Type,Symbol}, receivers::Vector{T}, methods; kw...) where T <: Type
    code = Vector{String}()
    for t in receivers
        append!(code, forward(sender, t, methods; kw...))
    end
    code = unique(code)
    return code
end

"""
`forward(sender::Tuple{Type,Symbol}, receiver::Type; super=true, kw...)`

Wrapper for `forward(send, receiver, supertypes(receiver, super=super); kw...)`
"""
function forward(sender::Tuple{Type,Symbol}, receiver::Type; super=true, kw...)
    tt = [receiver]
    (super)  &&  (append!(tt, supertypes(receiver)))
    return forward(sender, tt, methodswith(receiver, supertypes=super); kw...)
end

"""
`@forward(sender, receiver, ekws...)`

Evaluate the Julia code to forward methods.  The syntax is exactly the same as the `forward` function.
"""
macro forward(sender, receiver, ekws...)
    kws = Vector{Pair{Symbol,Any}}()
    methods = nothing
    for kw in ekws
        if isa(kw, Expr)  &&  (kw.head == :(=))
            push!(kws, Pair(kw.args[1], kw.args[2]))
        else
            @assert methods == nothing "Too many arguments"
            methods = kw
        end
    end
    out = quote
        counterr = 0
        if $methods == nothing
            list = forward($sender, $receiver; $kws...)
        else
            list = forward($sender, $receiver, $methods; $kws...)
        end
        for line in list
            try
                eval(Meta.parse("$line"))
            catch err
                global counterr += 1
                println()
                println("$line")
                @error err;
            end
        end
        println(length(list) - counterr, " method(s) forwarded")
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


"""
`concretetype(T::Type)`

Return the concrete type associated with the *inheritable* abstract type `T`. If `T` is not *inheritable* returns nothing.

See also: `@inheritable`
"""
function concretetype(T::Type)
    (T == Any)  &&  (return nothing)
    @assert isabstracttype(T) "Input type must be an abstract type"
    for sub in subtypes(T)
        if isconcretetype(sub)
            if match(r"^Concrete_", string(nameof(sub))) != nothing
                return sub
            end
        end
    end
    return nothing
end


"""
`isinheritable(T::Type)`

Return `true` if the the abstract type `T` is *inheritable*, `false` otherwise.

See also: `@inheritable`
"""
isinheritable(T) = concretetype(T) != nothing


"""
`@inheritable expression`

Create an *inheritable* structure definition.

This macro accepts an expression defining a (mutable or immutable) structure, and outputs the code for two new type definitions:
- an abstract type with the same name and (if given) supertype of the input structure;
- a concrete structure definition with name prefix `Concrete_`, subtyping the abstract type defined above.

The relation between these types ensure there will be a single concrete type associated to the abstract one, hence you can use the abstract type to annotate method arguments, and be sure to receive the associated concrete type, or one of its subtypes (which shares all field name and type of the ancestor).

The concrete type associated to an *inheritable* abstract type can be retrieved with the `concretetype` function.

These newly defined types allows to easily implement single inheritance in Julia: simply use the abstract type name for both object construction and to annotate method arguments.  

# Example:
```julia-repl
julia> @inheritable struct Bird
    weight::Float64
end

julia> fly(b::Bird) = "Flying..."
julia> weight(b::Bird) = b.weight

julia> @inheritable struct Duck <: Bird
    color::String
end

julia> quack(d::Duck) = "Quack!!!"

julia> println(fieldnames(concretetype(Duck)))
(:weight, :color)

julia> duck = Duck(1.0, "Brown")
Concrete_Duck(1.0, "Brown")

julia> fly(duck)
"Flying..."

julia> quack(duck)
"Quack!!!"
```
"""
macro inheritable(expr)
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

    @assert isa(expr, Expr)
    @assert expr.head == :struct "Expression must be a `struct`"

    # Ensure there is room for the super type in the expression
    if isa(expr.args[2], Symbol)
        name = deepcopy(expr.args[2])
        deleteat!(expr.args, 2)
        insert!(expr.args, 2, Expr(:<:, name, :Any))
    end
    if isa(expr.args[2], Expr)  &&  (expr.args[2].head == :curly)
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
    @assert (isa(tmp, Symbol)  ||  (isa(tmp, Expr)  &&  (tmp.head == :curly)))
    super = deepcopy(tmp)
    super_symb = (isa(tmp, Symbol)  ?  tmp  :  tmp.args[1])

    # Output abstract type
    out = Expr(:block)
    push!(out.args, :(abstract type $name <: $super end))

    # Change name in input expression
    concrete_symb = Symbol(:Concrete_, name_symb)
    if isa(name, Symbol)
        concrete = concrete_symb
    else
        concrete = deepcopy(name)
        change_symbol!(concrete, name_symb, concrete_symb)
    end
    change_symbol!(expr    , name_symb, concrete_symb)

    # Change super type in input expression to actual name
    deleteat!(expr.args[2].args, 2)
    insert!(  expr.args[2].args, 2, name)

    # If super type is inheritable retrieve the associated concrete
    # type and add its fields as members
    parent = concretetype(__module__.eval(super))
    if parent != nothing
        for i in fieldcount(parent):-1:1
            e = Expr(Symbol("::"))
            push!(e.args, fieldname(parent, i))
            push!(e.args, fieldtype(parent, i))
            pushfirst!(expr.args[3].args, e)
        end
    end

    # Add modified input structure to output
    push!(out.args, expr)

    # Add a constructor whose name is the same as the abstract type
    push!(out.args, :($name(args...; kw...) = $concrete(args...; kw...)))

    return esc(out)
end

end # module
