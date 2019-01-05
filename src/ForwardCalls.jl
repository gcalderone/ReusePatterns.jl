module ForwardCalls
using InteractiveUtils
export forward, @forward

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


function forward(send::Tuple{Type,Symbol}, recvs::Vector{<:Type}; kw...)
    out = Vector{String}()
    for recv in recvs
        append!(out, forward(send, recv; kw...))
    end
    return unique(out)
end

function forward(send::Tuple{Type,Symbol}, recv::T; super=false, kw...) where T <: Type
    tt = [recv]
    (super)  &&  (append!(tt, supertypes(recv)))
    return forward(send, tt, methodswith(recv, supertypes=super); kw...)
end

forward(send::Tuple{Type,Symbol}, recvs::Vector{<:Type}, method::Method; kw...) = forward(send, recvs, [method]; kw...)
forward(send::Tuple{Type,Symbol}, recv::Type, methods::Vector{Method}; kw...) = forward(send, [recv], methods; kw...) 

function forward(send::Tuple{Type,Symbol}, recvs::Vector{T}, methods::Vector{Method};
                 usetypes=false, useallargs=false) where T <: Type
    function pf(m, s)
        return @eval(m, parentmodule($s))
    end
    @assert length(findall(isconcretetype.(recvs))) .<= 1 "Multiple concrete types in receivers array"

    outmodule = parentmodule(recvs[1])
    for i in 2:length(recvs)
        @assert outmodule == parentmodule(recvs[i]) "All receveiver types must be defined in the same module"
    end
    
    code = Vector{String}()
    send_type = string(parentmodule(send[1])) * "." * string(nameof(send[1]))
    send_symb = string(send[2])
    
    for method in methods
        if string(method.name) == "eval"
            @warn "Skipping `eval` method"
            continue
        end

        accum = Vector{Int}()
        for i in 2:method.nargs
            argtype = fieldtype(method.sig, i)
            if argtype != Any
                for recvtype in recvs
                    tt = typeintersect(recvtype, argtype)
                    if tt != Union{}
                        push!(accum, i-1)
                        break
                    end
                end
            end
        end
        if length(accum) == 0
            @warn "Skipping method since it doesn't involve any of the destination types"
            display(method);  println();  continue
        end

        s = "p" .* string.(1:method.nargs-1)
        if usetypes
            s .*= "::" .* string.(fieldtype.(Ref(method.sig), 2:method.nargs))
        end
        s[accum] .= "p" .* string.(accum) .* "::$send_type"
        if !useallargs
            s = s[1:accum[end]]
            push!(s, "args...")
        end
        l = string(pf(method.module, method.name)) * ".:(" * string(method.name) * ")(" * join(s,", ") * "; kw..."
        l *= ") = " * string(method.module) * ".:(" * string(method.name) * ")("
        
        s = "p" .* string.(1:method.nargs-1)
        if !useallargs
            s = s[1:accum[end]]
            push!(s, "args...")
        end
        s[accum] .= "getfield(" .* s[accum] .* ", :$send_symb)"
        l *= join(s, ", ") * "; kw...)"
        l = join(split(l, "#"))
        push!(code, l)
    end
    ii = unique(i->code[i], 1:length(code))
    code = code[ii]
    return (outmodule, code)
end


macro forward(send, recvs, ekws...)
    kws = Vector{Pair{Symbol,Any}}()
    for kw in ekws
        push!(kws, Pair(kw.args[1], kw.args[2]))
    end
    out = :(
        (m, code) = forward($send, $recvs; $kws...);
        for line in code;
          #println("$line");
          m.eval(Meta.parse("eval(:($line))"));
        end;
    )
    return esc(out)
end

end # module
