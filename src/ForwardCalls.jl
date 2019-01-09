module ForwardCalls
using InteractiveUtils

export supertypes, forward, @forward,
    @inherit_fields, concretetype, isinheritable, @inheritable

"""
supertypes(T::Type)

Returns a vector array with all supertypes of type `T` (excluding `Any`).
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

```
struct Wrapper{T}
    wrappee::T
    extra
    Wrapper{T}(args...; kw...) where T = new(T(args...; kw...), nothing)
end
eval.(Meta.parse.(forward((Wrapper, :wrappee), Int, which(+, (Int, Int)))))

i1 = Wrapper{Int}(1)
i2 = Wrapper{Int}(2)
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
    foundsender = false
    for i in 2:method.nargs
        argtype = fieldtype(method.sig, i)
        if argtype != Any
            @assert sender[1] != argtype
            (typeintersect(receiver, argtype) != Union{})  &&  (push!(foundat, i-1))
        end
    end
    (length(foundat) == 0)  &&  (return code)
    
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
    code = unique(code)
    return "@eval " .* string(method.module) .* " " .* code
end


function forward(sender::Tuple{Type,Symbol}, receiver::Type, methods::Vector{Method}; kw...)
    code = Vector{String}()
    for m in methods
        append!(code, forward(sender, receiver, m; kw...))
    end
    code = unique(code)
    return code
end

function forward(sender::Tuple{Type,Symbol}, receivers::Vector{T}, methods; kw...) where T <: Type
    code = Vector{String}()
    for t in receivers
        append!(code, forward(sender, t, methods; kw...))
    end
    code = unique(code)
    return code
end

function forward(sender::Tuple{Type,Symbol}, receiver::Type; super=true, kw...)
    tt = [receiver]
    (super)  &&  (append!(tt, supertypes(receiver)))
    return forward(sender, tt, methodswith(receiver, supertypes=super); kw...)
end



macro forward(sender, receiver, ekws...)
    kws = Vector{Pair{Symbol,Any}}()
    for kw in ekws
        push!(kws, Pair(kw.args[1], kw.args[2]))
    end
    out = quote
        for line in forward($sender, $receiver; $kws...)
            try
                eval(Meta.parse("$line"))
            catch err
                println()
                println("$line")
                @error err;
            end
        end
    end
    return esc(out)
end



macro inherit_fields(T)
    out = Expr(:block)
    for name in fieldnames(__module__.eval(T))
        e = Expr(Symbol("::"))
        push!(e.args, name)
        push!(e.args, fieldtype(__module__.eval(T), name))
        push!(out.args, e)
    end
    return esc(out)
end


function concretetype(T::Type)
    (T == Any)  &&  (return nothing)
    for sub in subtypes(T)
        if isconcretetype(sub)
            if match(r"^Concrete_", string(nameof(sub))) != nothing
                return sub
            end
        end
    end
    return nothing
end
isinheritable(T) = concretetype(T) != nothing


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
