#_____________________________________________________________________
#                           Charlie's code
#

# Here I use `Gnuplot.jl`, but any other package would work...

using Gnuplot
@gp "set size ratio -1" "set grid" "set key bottom right" xr=(-1.5, 2.5) :-


# Methods to plot a Polygon
plotlabel(p::Polygon) = "Polygon (" * string(length(p.x)) * " vert.)"
plotlabel(p::RegularPolygon) = "RegularPolygon (" * string(vertices(p)) * " vert., area=" * string(round(area(p) * 100) / 100) * ")"
plotlabel(p::Named) = name(p) * " (" * string(vertices(p)) * " vert., area=" * string(round(area(p) * 100) / 100) * ")"
function plot(p::AbstractPolygon; dt=1, color="black")
    x = coords_x(p); x = [x; x[1]]
    y = coords_y(p); y = [y; y[1]]
    title = plotlabel(p)
    @gp :- x y "w l tit '$title' dt $dt lw 2 lc rgb '$color'"
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
