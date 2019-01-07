module ForwardCalls
using InteractiveUtils
export supertypes, forward, @forward, @inherit_fields, @inheritance

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


# function forward(send::Tuple{Type,Symbol}, recvs::Vector{<:Type}; kw...)
#     out = Vector{String}()
#     for recv in recvs
#         append!(out, forward(send, recv; kw...))
#     end
#     return unique(out)
# end

function forward(send::Tuple{Type,Symbol}, recv::T; super=false, kw...) where T <: Type
    tt = [recv]
    (super)  &&  (append!(tt, supertypes(recv)))
    return forward(send, tt, methodswith(recv, supertypes=super); kw...)
end

forward(send::Tuple{Type,Symbol}, recvs::Vector{<:Type}, method::Method; kw...) = forward(send, recvs, [method]; kw...)
forward(send::Tuple{Type,Symbol}, recv::Type, methods::Vector{Method}; kw...) = forward(send, [recv], methods; kw...)

function forward(send::Tuple{Type,Symbol}, recvs::Vector{T}, methods::Vector{Method};
                 usetypes=false, useallargs=false) where T <: Type
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

macro inheritance(prefix, expr)
    @assert isa(prefix, Symbol)
    @assert isa(expr, Expr)
    @assert expr.head == :struct "Expression must be a `struct`"
    if isa(expr.args[2], Expr)  &&  (expr.args[2].head == :<:)
        name = expr.args[2].args[1]
        base_type = __module__.eval(expr.args[2].args[2])
        #base_type = Expr(:., parentmodule(base), nameof(base))
    else
        name = expr.args[2]
        base_type = Any
    end
    out = Expr(:block)
    abstract_type = Symbol(prefix, name)

    if base_type == Any
        push!(out.args, :(abstract type $abstract_type end))
        expr.args[2] = :($name <: $abstract_type)
        push!(out.args, expr)
    else
        if !isconcretetype(base_type)
            push!(out.args, :(abstract type $abstract_type <: $base_type end))
            expr.args[2].args[2] = abstract_type
            push!(out.args, expr)
        else
            lbase_type = __module__.eval(supertype(base_type))
            push!(out.args, :(abstract type $abstract_type <: $lbase_type end))
            expr.args[2].args[2] = abstract_type
            parentfields = Expr(:block)
            for i in fieldcount(base_type):-1:1
                name = fieldname(base_type, i)
                e = Expr(Symbol("::"))
                push!(e.args, name)
                push!(e.args, fieldtype(base_type, name))
                pushfirst!(expr.args[3].args, e)
            end
            push!(out.args, expr)
        end
    end
    return esc(out)
end

end # module
