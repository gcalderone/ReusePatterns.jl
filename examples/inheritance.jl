#_____________________________________________________________________
#                            Alice's code
#
using Statistics, ForwardCalls

abstract type AbstractPolygon end

abstract type Polygon <: AbstractPolygon end
mutable struct Concrete_Polygon <: Polygon
    x::Vector{Float64}
    y::Vector{Float64}
end
Polygon(args...; kw...) = Concrete_Polygon(args...; kw...)

# Retrieve the number of vertices, and their X and Y coordinates
vertices(p::Polygon) = length(p.x)
coords_x(p::Polygon) = p.x
coords_y(p::Polygon) = p.y

# Move, scale and rotate a polygon
function move!(p::Polygon, dx::Real, dy::Real)
    p.x .+= dx
    p.y .+= dy
end

function scale!(p::Polygon, scale::Real)
    m = mean(p.x); p.x = (p.x .- m) .* scale .+ m
    m = mean(p.y); p.y = (p.y .- m) .* scale .+ m
end

function rotate!(p::Polygon, angle_deg::Real)
    θ = float(angle_deg) * pi / 180
    R = [cos(θ) -sin(θ); sin(θ) cos(θ)]
    x = p.x .- mean(p.x)
    y = p.y .- mean(p.y)
    (x, y) = R * [x, y]
    p.x = x .+ mean(p.x)
    p.y = y .+ mean(p.y)
end

#_____________________________________________________________________
#                             Bob's code
#
abstract type RegularPolygon <: Polygon end
mutable struct Concrete_RegularPolygon <: RegularPolygon
    x::Vector{Float64}
    y::Vector{Float64}
    radius::Float64
end
RegularPolygon(args...; kw...) = Concrete_RegularPolygon(args...; kw...)

function RegularPolygon(n::Integer, radius::Real)
    @assert n >= 3
    θ = range(0, stop=2pi-(2pi/n), length=n)
    c = radius .* exp.(im .* θ)
    return RegularPolygon(real(c), imag(c), radius)
end

# Compute length of a side and the polygon area
side(p::RegularPolygon) = 2 * p.radius * sin(pi / vertices(p))
area(p::RegularPolygon) = side(p)^2 * vertices(p) / 4 / tan(pi / vertices(p))







function scale!(p::RegularPolygon, scale::Real)
    invoke(scale!, Tuple{supertype(RegularPolygon), typeof(scale)}, p, scale) # call "super" method
    p.radius *= scale        # update internal state
end

# Attach a label to a polygon
mutable struct Named{T} <: AbstractPolygon
    polygon::T
    name::String
end
Named{T}(name, args...; kw...) where T = Named{T}(T(args...; kw...), name)
name(p::Named) = p.name

# Forward methods from `Named` to `Polygon`
@forward (Named, :polygon) RegularPolygon
