module ForwardCalls
using InteractiveUtils
export supertypes, forward, @forward, @inherit_fields, concretetype, isinheritable, @inheritable

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





# function forward(send::Tuple{Type,Symbol}, recvs::Vector{<:Type}; kw...)
#     out = Vector{String}()
#     for recv in recvs
#         append!(out, forward(send, recv; kw...))
#     end
#     return unique(out)
# end

function forward(send::Tuple{Type,Symbol}, recv::T; super=true, kw...) where T <: Type
    tt = [recv]
    (super)  &&  (append!(tt, supertypes(recv)))
    return forward(send, tt, methodswith(recv, supertypes=super); kw...)
end

forward(send::Tuple{Type,Symbol}, recvs::Vector{<:Type}, method::Method; kw...) = forward(send, recvs, [method]; kw...)
forward(send::Tuple{Type,Symbol}, recv::Type, methods::Vector{Method}; kw...) = forward(send, [recv], methods; kw...)

function forward(send::Tuple{Type,Symbol}, recvs::Vector{T}, methods::Vector{Method};
                 usetypes=true, useallargs=true) where T <: Type
    function fwd_method_as_string(send_type, send_symb, argid, method, usetypes, useallargs)
        #pf(m, s) = @eval(m, parentmodule($s))
        s = "p" .* string.(1:method.nargs-1)
        (usetypes)  &&
            (s .*= "::" .* string.(fieldtype.(Ref(method.sig), 2:method.nargs)))
        s[argid] .= "p" .* string.(argid) .* "::$send_type"
        if !useallargs
            s = s[1:argid[end]]
            push!(s, "args...")
        end
        m = string(method.module.eval(:(parentmodule($(method.name))))) * "."
        l = "$m:(" * string(method.name) * ")(" * join(s,", ") * "; kw..."

        m = string(method.module) * "."
        l *= ") = $m:(" * string(method.name) * ")("
        s = "p" .* string.(1:method.nargs-1)
        if !useallargs
            s = s[1:argid[end]]
            push!(s, "args...")
        end
        s[argid] .= "getfield(" .* s[argid] .* ", :$send_symb)"
        l *= join(s, ", ") * "; kw...)"
        l = join(split(l, "#"))
        return l
    end

    @assert length(findall(isconcretetype.(recvs))) .<= 1 "Multiple concrete types in receivers array"

    modu = Vector{Module}()
    code = Vector{String}()
    send_type = string(parentmodule(send[1])) * "." * string(nameof(send[1]))
    send_symb = string(send[2])

    for method in methods
        if method.name == :eval
            @warn "Skipping `eval` method"
            continue
        end
        # Seacrh for receiver types in method arguments
        foundat = Vector{Int}()
        foundsender = false
        for i in 2:method.nargs
            argtype = fieldtype(method.sig, i)
            if argtype != Any
                if send[1] == argtype
                    foundsender = true
                    break
                end
                for recvtype in recvs
                    tt = typeintersect(recvtype, argtype)
                    if tt != Union{}
                        push!(foundat, i-1)
                        break
                    end
                end
            end
        end
        (foundsender)  &&  (continue)  # Avoid redefining methods involving sender
        if length(foundat) == 0
            @warn "Skipping method since it doesn't involve any of the destination types"
            display(method);  println();  continue
        end

        if length(foundat) > 1  # TODO: consider all possible combinations
            for argid in foundat
                l = fwd_method_as_string(send_type, send_symb, [argid], method, usetypes, useallargs)
                push!(code, l)
                push!(modu, method.module)
            end
        end
        l = fwd_method_as_string(send_type, send_symb, foundat, method, usetypes, useallargs)
        push!(code, l)
        push!(modu, method.module)
    end
    ii = unique(i->code[i], 1:length(code))
    modu = modu[ii]
    code = code[ii]
    return (modu, code)
end


macro forward(send, recvs, ekws...)
    kws = Vector{Pair{Symbol,Any}}()
    for kw in ekws
        push!(kws, Pair(kw.args[1], kw.args[2]))
    end
    out = quote
        (m, code) = forward($send, $recvs; $kws...)
        for i in 1:length(code)
            line = code[i]
            try
                m[i].eval(Meta.parse("eval(:($line))"))
            catch err
                println()
                println("Module: $(m[i])")
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
