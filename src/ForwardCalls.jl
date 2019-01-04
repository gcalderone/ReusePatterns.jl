module ForwardCalls

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


forward(derived::Type, fieldname::Symbol, parent::T) where T <:Type = forward(derived, fieldname, [parent; supertypes(parent)], methodswith(parent, supertypes=true))
forward(derived::Type, fieldname::Symbol, parents::Vector{<:Type}, method::Method) = forward(derived, fieldname, parents, [method])
forward(derived::Type, fieldname::Symbol, parent::Type, methods::Vector{Method}) = forward(derived, fieldname, [parent], methods)

function forward(derived::Type, fieldname::Symbol, parents::Vector{<:Type})
    out = Vector{String}()
    for p in parents
        append!(out, forward(derived, fieldname, p))
    end
    return unique(out)
end


function forward(derived::Type, fieldname::Symbol, parents::Vector{<:Type}, methods::Vector{Method})
    codeeval = Vector{String}()
    toImport = Vector{String}()
    for m in methods
        accum = Vector{Int}()
        for i in 2:m.nargs
            (fieldtype(m.sig, i) in parents)  &&  (push!(accum, i-1))
        end
        if length(accum) == 0
            @info "Skipping method since it doesn't involve any of the destination types"
            display(m);  println();  continue
        end
        s = "p" .* string.(1:accum[end])
        s[accum] .*= "::$derived"
        l = string(m.name) * "(" * join(s,", ") * ", args...; kw..."
        l *= ") = " * string(m.name) * "(" 
        s = "p" .* string.(1:accum[end])
        s[accum] .= "getfield(" .* s[accum] .* ", :$fieldname)"
        l *= join(s, ", ") * ", args...; kw...)"
        l = join(split(l, "#"))
        push!(codeeval, l)
        push!(toImport, string(m.module) * "." * string(m.name))
    end
    toImport = "import " .* unique(toImport)
    prepend!(codeeval, toImport)
    codeeval = unique(codeeval)
    return codeeval
end

macro forward(derived, fieldname, parents)
    code = forward(eval(derived), eval(fieldname), eval(parents))
    out = Expr(:block)
    for l in code
        push!(out.args, Meta.parse(l))
    end
    return esc(out)
end

end # module
