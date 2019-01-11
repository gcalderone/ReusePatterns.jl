# ReusePatterns.jl
## Simple tools to implement *inheritance* and *composition* patterns in Julia.

[![Build Status](https://travis-ci.org/gcalderone/ReusePatterns.jl.svg?branch=master)](https://travis-ci.org/gcalderone/ReusePatterns.jl)

Assume an author **A** (say, Alice) wrote a very useful package, and another autor **B** (say, Bob) wish to reuse that code to provide more complex/extended functionalities to a final user **C** (say, Charlie).

This package provides a few tools to facilitate Bob's work in reusing Alice's code, by mean of the most common reuse patterns: *composition* and *inheritance*.  Also, it aims to relieve Charlie from dealing with the underlying details, and seamlessly use the new functionalities introduced by Bob without changing the code dealing with Alice's package.


**IMPORTANT NOTE:**

*Inheritance* is not supported in Julia by design, and although it can be realized through this package (or similar ones, see *Links* below), it is a discouraged practice: *composition* should be the preferred approach.

Still there can be cases where the *inheritance* approach turns out to be the most simple and straightforward way to solve a problem, while pursuing the same goal with *composition* implies flooding the dispatch table with a lot of boiler plate code.  In these cases I believe it may be worth following the *inheritance* approach.

Besides, the **ReusePatterns.jl** package allows to test both approaches, and check which one provides the best solution.

The motivation to develop this package stems from the following posts on the Discourse:
- https://discourse.julialang.org/t/how-to-add-metadata-info-to-a-dataframe/11168
- https://discourse.julialang.org/t/composition-and-inheritance-the-julian-way/11231

but several other topics apply as well (see list in the *Links* section below).





## Composition

With [composition](https://en.wikipedia.org/wiki/Object_composition) we wrap an Alice's object into a structure implemented by Bob, and let Charlie use the latter without even knowing if it actually is the original Alice's object or the Bob's one.

We pursue this goal by automatically forwarding all methods calls from Bob's structure to the appropriate Alice's object.

### Example:

Alice implemented the [DataFrame](https://github.com/JuliaData/DataFrames.jl) package, Bob
wish to add metadata informations to a DataFrame object (see [here](https://discourse.julialang.org/t/how-to-add-metadata-info-to-a-dataframe/11168), and Charlie wants to use the metadata added by Bob without touching its code working with Alice's dataframes:
```julia
using DataFrames, ReusePatterns

struct DataFrameMeta <: AbstractDataFrame
    p::DataFrame
    meta::Dict{Symbol, Any}
    DataFrameMeta(args...; kw...) = new(DataFrame(args...; kw...), Dict{Symbol, Any}())
    DataFrameMeta(df::DataFrame) = new(df, Dict{Symbol, Any}())
end
@forward((DataFrameMeta, :p), DataFrame)
meta(d::DataFrameMeta) = getfield(d,:meta)
```



### Tools provided by the **ReusePatterns.jl** package:


## Inheritance (simple approach)

## Inheritance (advanced approach)

## Complete examples



## Links 

### Related topics on Discourse and other websites:
- https://discourse.julialang.org/t/guidelines-to-distinguish-concrete-from-abstract-types/19162


### Pacakges providing similar functionalities:
(in no particolar order)

- https://github.com/JuliaArbTypes/TypedDelegation.jl
- https://github.com/AleMorales/ModularTypes.jl
- https://github.com/JuliaCollections/DataStructures.jl/blob/master/src/delegate.jl
- https://github.com/Jeffrey-Sarnoff/Delegate.jl
- https://github.com/rjplevin/Classes.jl
- https://github.com/jasonmorton/Typeclass.jl
- https://github.com/KlausC/TypeEmulator.jl
- https://github.com/MikeInnes/Lazy.jl (`@forward` macro)
- https://github.com/tbreloff/ConcreteAbstractions.jl
