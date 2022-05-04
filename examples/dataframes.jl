using DataFrames, ReusePatterns

struct DataFrameMeta <: AbstractDataFrame
    p::DataFrame
    meta::Dict{String, Any}
    DataFrameMeta(args...; kw...) = new(DataFrame(args...; kw...), Dict{Symbol, Any}())
    DataFrameMeta(df::DataFrame) = new(df, Dict{Symbol, Any}())
end
meta(d::DataFrameMeta) = getfield(d,:meta)  # <-- new functionality added to DataFrameMeta
@forward((DataFrameMeta, :p), DataFrame)    # <-- reuse all existing functionalities

# Use a `DataFrameMeta` object as if it was a common DataFrame object ...
v = ["x","y","z"][rand(1:3, 10)]
df1 = DataFrameMeta(Any[collect(1:10), v, rand(10)], [:A, :B, :C])
df2 = DataFrameMeta(A = 1:10, B = v, C = rand(10))
dump(df1)
dump(df2)
describe(df2)
first(df1, 10)
df1[:, :A] .+ df2[:, :C]
df1[1:4, 1:2]
df1[:, [:A,:C]]
df1[1:2, [:A,:C]]
df1[:, [1,3]]
df1[1:4, :]
df1[1:4, :C]
df1[1:4, :C] = 40. * df1[1:4, :C]
[df1; df2]
size(df1)
meta(df1)["key"] = :value
meta(df1)["key"]
