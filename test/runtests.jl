using ReusePatterns
using Test


@quasiabstract struct Rectangle1
    width::Real 
    height::Real
end

@quasiabstract struct Rectangle2{T<:Real}
    width::T
    height::T 
end

@quasiabstract struct Rectangle3{T} <: Number
    width::T
    height::T 
end

@quasiabstract struct Rectangle4{T<:Real} <: Number
    width::T
    height::T 
end


@quasiabstract struct Box1 <: Rectangle1
    depth::Real 
end

@quasiabstract struct Box2{T<:Real} <: Rectangle2{T}
    depth::T
end

@quasiabstract struct Box3{T} <: Rectangle3{T}
    depth::T 
end

@quasiabstract struct Box4{T<:Real} <: Rectangle4{T}
    depth::T 
end




#_____________________________________________________________________
#                            Alice's code
#
using Statistics, ReusePatterns

abstract type AbstractPolygon end


@quasiabstract mutable struct Polygon <: AbstractPolygon
    x::Vector{Float64}
    y::Vector{Float64}
end


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

@quasiabstract mutable struct RegularPolygon <: Polygon


    radius::Float64
end


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



#_____________________________________________________________________
#                           Charlie's code
#

# Here I use `Gnuplot.jl`, but any other package would work...
#=
using Gnuplot
Gnuplot.setverb(false)
@gp "set size ratio -1" "set grid" "set key bottom right" xr=(-1.5, 2.5) :-
=#


# Methods to plot a Polygon
plotlabel(p::Polygon) = "Polygon (" * string(length(p.x)) * " vert.)"
plotlabel(p::RegularPolygon) = "RegularPolygon (" * string(vertices(p)) * " vert., area=" * string(round(area(p) * 100) / 100) * ")"
plotlabel(p::Named) = name(p) * " (" * string(vertices(p)) * " vert., area=" * string(round(area(p) * 100) / 100) * ")"
function plot(p::AbstractPolygon; dt=1, color="black")
    x = coords_x(p); x = [x; x[1]]
    y = coords_y(p); y = [y; y[1]]
    title = plotlabel(p)
    # @gp :- x y "w l tit '$title' dt $dt lw 2 lc rgb '$color'"
end

# Finally, let's have fun with the shapes!
line = Polygon([0., 1.], [0., 1.])
triangle = RegularPolygon(3, 1)
square = Named{RegularPolygon}("Square", 4, 1)

plot(line, color="black")
plot(triangle, color="blue")
plot(square, color="red")

rotate!(triangle, 90)
move!(triangle, 1, 1)
scale!(triangle, 0.32)
scale!(square, sqrt(2))

plot(triangle, color="blue", dt=2)
plot(square, color="red", dt=2)

# Increase number of vertices
p = Named{RegularPolygon}("Heptagon", 7, 1)
plot(p, color="orange", dt=4)
circle = Named{RegularPolygon}("Circle", 1000, 1)
plot(circle, color="dark-green", dt=4)

@testset "Array composition" begin
    # github.com/gcalderone/ReusePatterns.jl/issues/5
    struct MyArray{T, N}  # <: AbstractArray{T, N}
        a::Array{T, N}
        attr::Int
        MyArray(T, dims::NTuple{N, Int}) where {N} = new{T, N}(zeros(T, dims...), 1)
    end

    @forward((MyArray, :a), Array)

    a = MyArray(Float32, (1, 2, 3))

    # docs.julialang.org/en/v1/manual/interfaces/#man-interface-array
    a[1] = -1
    a[end] = 9
    @test a[1] == a[1, 1, 1] == -1
    @test a[end] == a[1, 2, 3] == 9

    @test size(a) == (1, 2, 3)
    @test length(a) == 6
    @test ndims(a) == 3
    @test firstindex(a) == 1
    @test lastindex(a) == 6
    @test axes(a, 1) == 1:1
    @test axes(a, 2) == 1:2
    @test axes(a, 3) == 1:3
    @test IndexStyle(a) == IndexLinear()

    @test_broken eltype(a) == Float32  # Any
    @test_broken similar(a) isa MyArray  # Array
    @test_broken copy(a) isa MyArray  # Array
end
