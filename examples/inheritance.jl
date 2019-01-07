using ForwardCalls
using Statistics, Gnuplot

# Define a structure to store the vertices of a generic 2D shape
abstract type AbstractShape end
abstract type ΛShape <: AbstractShape end
mutable struct Shape <: ΛShape
    x::Vector{Float64}
    y::Vector{Float64}
end


# Methods to retrieve the X and Y coordinates of the vertices
coords_x(p::ΛShape) = p.x
coords_y(p::ΛShape) = p.y

# Methods to move, scale and rotate the shape
function move!(p::ΛShape, dx::Real, dy::Real)
    p.x .+= dx
    p.y .+= dy
end
function scale!(p::ΛShape, scale::Real)
    m = mean(p.x); p.x = (p.x .- m) .* scale .+ m
    m = mean(p.y); p.y = (p.y .- m) .* scale .+ m
end
function rotate!(p::ΛShape, angle_deg::Real)
    θ = float(angle_deg) * pi / 180
    R = [cos(θ) -sin(θ); sin(θ) cos(θ)]
    x = p.x .- mean(p.x)
    y = p.y .- mean(p.y)
    (x, y) = R * [x, y]
    p.x = x .+ mean(p.x)
    p.y = y .+ mean(p.y)
end


# Implement a structure for a regular polygon, whose vertices are
# stored in a `Shape` structure
abstract type ΛRegPolygon <: ΛShape end
mutable struct RegPolygon <: ΛRegPolygon
    @inherit_fields(Shape)
    n::Int
    radius::Float64
end

# RegPolygon constructor
function RegPolygon(n::Integer, radius::Real)
    @assert n >= 3
    θ = range(0, stop=2pi-(2pi/n), length=n)
    c = radius .* exp.(im .* θ)
    return RegPolygon(real(c), imag(c), n, radius)
end

# Methods to retrieve the number of vertices, the length of a side and
# the polygon area
vertices(p::ΛRegPolygon) = p.n
side(p::ΛRegPolygon) = 2 * p.radius * sin(pi / p.n)
area(p::ΛRegPolygon) = side(p)^2 * p.n / 4 / tan(pi / p.n)




# Overload the method `scale!` since this changes the size of the polygon
function scale!(p::ΛRegPolygon, scale::Real)
    invoke(scale!, Tuple{supertype(ΛRegPolygon), typeof(scale)}, p, scale) # call to "super" method
    p.radius *= scale
end


# Forward methods acting on `NamedRegPolygon` to those accepting a `RegPolygon` structure
abstract type ΛNamedRegPolygon <: ΛRegPolygon end
mutable struct NamedRegPolygon <: ΛNamedRegPolygon
    @inherit_fields(RegPolygon)
    name::String
end
name(p::ΛNamedRegPolygon) = p.name
NamedRegPolygon(name, args...; kw...) = NamedRegPolygon(getfield.(Ref(RegPolygon(args...; kw...)), fieldnames(RegPolygon))..., name)





# Methods to plot a shape (here I uses the `Gnuplot.jl` package, but
# any other would work...)
plotlabel(p::ΛShape) = "Shape (" * string(length(p.x)) * " vert.)"
plotlabel(p::ΛRegPolygon) = "RegPolygon (" * string(vertices(p)) * " vert., area=" * string(round(area(p) * 100) / 100) * ")"
plotlabel(p::ΛNamedRegPolygon) = name(p) * " (" * string(vertices(p)) * " vert., area=" * string(round(area(p) * 100) / 100) * ")"

function plot(p::ΛShape; dt=1, color="black")
    x = coords_x(p); x = [x; x[1]]
    y = coords_y(p); y = [y; y[1]]
    title = plotlabel(p)
    @gp :- x y "w l tit '$title' dt $dt lw 2 lc rgb '$color'"
end

# Finally, let's have fun with the shapes!
line = Shape([0., 1.], [0., 1.])
triangle = RegPolygon(3, 1)
square = NamedRegPolygon("Square", 4, 1)

@gp "set size ratio -1" "set grid" "set key bottom right" xr=(-1.5, 2.5) :-
Gnuplot.setverb(false)
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
p = NamedRegPolygon("Heptagon", 7, 1)
plot(p, color="orange", dt=4)
circle = NamedRegPolygon("Circle", 1000, 1)
plot(circle, color="dark-green", dt=4)
