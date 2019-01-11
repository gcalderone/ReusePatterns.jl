# ReusePatterns.jl
## Simple tools to implement *inheritance* and *composition* patterns in Julia.

[![Build Status](https://travis-ci.org/gcalderone/ReusePatterns.jl.svg?branch=master)](https://travis-ci.org/gcalderone/ReusePatterns.jl)

Assume an author **A** (say, Alice) wrote a very powerful Julia code, extensively used by user **C** (say, Charlie).  The best code reusing practice in this "two actors" scenario is the package deployment, thoroughly discussed in the Julia manual.  Now assume a third person **B** (say, Bob) slip between Alice and Charlie: he wish to reuse Alice's code to provide more complex/extended functionalities to Charlie.  Most likely Bob will need a more sophisticated reuse pattern...

This package provides a few tools to facilitate Bob's work in reusing Alice's code, by mean of the most common reuse patterns: *composition* and *inheritance*.  Also, it aims to relieve Charlie from dealing with the underlying details, and seamlessly use the new functionalities introduced by Bob without changing the code dealing with Alice's package.


**IMPORTANT NOTE:**

*Inheritance* is not supported in Julia by design, and although it can be realized through this package (or similar ones, see *Links* below), it is a discouraged practice: *composition* should be the preferred approach.

Still there can be cases where the *inheritance* approach turns out to be the most simple and straightforward way to solve a problem, while pursuing the same goal with *composition* would imply flooding the dispatch table with a lot of boiler plate code.  In these cases I believe it may be worth following the *inheritance* approach.

Besides, the **ReusePatterns.jl** package allows to test both approaches, and check which one provides the best solution.

The motivation to develop this package stems from the following posts on the Discourse:
- https://discourse.julialang.org/t/how-to-add-metadata-info-to-a-dataframe/11168
- https://discourse.julialang.org/t/composition-and-inheritance-the-julian-way/11231

but several other topics apply as well (see list in the *Links* section below).


## Composition

With [composition](https://en.wikipedia.org/wiki/Object_composition) we wrap an Alice's object into a structure implemented by Bob, and let Charlie use the latter without even knowing if it actually is the original Alice's object or the Bob's one.

We pursue this goal by automatically forwarding all methods calls from Bob's structure to the appropriate Alice's object.

The *composition* approach has the following advantages:
- It is applicable even if Alice and Bob do not agree on a particular type architecture;
- it is the recommended Julian way to pursue code reusing;

...and disadvantages:
- It may be cumbersome to apply if the number of involved methods is very high, or if the method definitions are spread across many modules;
- *composition* is not recursive, i.e. if further users (**D**an, **E**mily, etc.) build composite layers on top of Bob's one they'll need to implement new forwarding methods.
- It introduces a small overhead for each composition layer, resulting in performance loss;

### Example:

Alice implemented the [DataFrames](https://github.com/JuliaData/DataFrames.jl) package, Bob
wish to add metadata informations to a DataFrame object (see [here](https://discourse.julialang.org/t/how-to-add-metadata-info-to-a-dataframe/11168)), and Charlie wants to use the metadata added by Bob by saving most of its code already working on Alice's package:
```julia
# Bob's code
using DataFrames, ReusePatterns

struct DataFrameMeta <: AbstractDataFrame
    p::DataFrame
    meta::Dict{String, Any}
    DataFrameMeta(args...; kw...) = new(DataFrame(args...; kw...), Dict{Symbol, Any}())
    DataFrameMeta(df::DataFrame) = new(df, Dict{Symbol, Any}())
end
meta(d::DataFrameMeta) = getfield(d,:meta)  # <-- new functionality added to DataFrame
@forward((DataFrameMeta, :p), DataFrame)    # <-- reuse all existing functionalities

# Chalie's code
df = DataFrameMeta(A = 1:10, B = ["x","y","z"][rand(1:3, 10)], C = rand(10))
meta(df)["Source"] = "Bob"
show(df)

# ... use `df` as if it was a common DataFrame object ...
```
The key line here is:
```julia
@forward((DataFrameMeta, :p), DataFrame)
```
The `@forward` macro identifies all methods accepting a `DataFrame` object, and defines new methods with the same name and arguments, but accepting `DataFrameMeta` arguments in place of the `DataFrame`  ones.  The purpose of each newly defined method is simply to forward the call to the original method, passing the `DataFrame` object stored in the `:p` field.

The **ReusePatterns.jl** package exports the following functions and macros aimed to implement  composition in Julia:
- `forward`: return a `Vector{String}` with the code to properly forward method calls;
- `@forward`: forward method calls from an object to a field structure;

Each function and macro has its own online documentation accessible by prepending `?` to the name.


## Simple inheritance

- `@copy_fields`: copy field names and types from one structure to another.

Each function and macro has its own online documentation accessible by prepending `?` to the name.


The *simple inheritance* approach has the following advantages:

- It is the simple most approach, by far simpler than *composition*, involving just a code copy/paste among structure definitions.  Such task can be automatized with the `@copy_fields` macro;
- It is a recursive approach, i.e. if further users (**D**an, **E**mily, etc.) inherits from Bob's structure they will  have all the inherited behavior for free;
- There is no overhead or performance loss.

...and disadvantages:
- it is applicable **only if** if all the argument type annotations in Alice's method signatures are abstract, **and if** Bob uses concrete types that share at least a common field subset with those used by Alice;
- Charlie may break Alice's or Bob's code by using a concrete type without the required fields.  Moreover, Dan may break Alice's, Bob's or Chharlie's code, Emily may break A's, B's, C's, D's code, and so on...



## Inheritance (advanced approach)
- `@inheritable`: define a new *inheritable* type with an associate concrete structure;
- `concretetype`, `concretesubtypes`: return the concrete type and the subtypes respectively, associated to an *inheritable* type;
- `isinheritable`: test whether a type is *inheritable*;
- `inheritablesubtypes`: return *inheritable subtypes.

Each function and macro has its own online documentation accessible by prepending `?` to the name.


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
