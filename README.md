# ReusePatterns.jl
## Simple tools to implement *composition* and *concrete subtyping* patterns in Julia.

[![Build Status](https://travis-ci.org/gcalderone/ReusePatterns.jl.svg?branch=master)](https://travis-ci.org/gcalderone/ReusePatterns.jl)

Assume an author **A** (say, Alice) wrote a very powerful Julia code, extensively used by user **C** (say, Charlie).  The best code reusing practice in this "two actors" scenario is the package deployment, thoroughly discussed in the Julia manual.  Now assume a third person **B** (say, Bob) slip between Alice and Charlie: he wish to reuse Alice's code to provide more complex/extended functionalities to Charlie.  Most likely Bob will need a more sophisticated reuse pattern...

This package provides a few tools to facilitate Bob's work in reusing Alice's code, by mean of two of the most common reuse patterns: *composition* and *subtyping* ([implementation inheritance](https://en.wikipedia.org/wiki/Inheritance_(object-oriented_programming)) is not supported in Julia), and check which one provides the best solution.  Also, it aims to relieve Charlie from dealing with the underlying details, and seamlessly use the new functionalities introduced by Bob without modifying the code dealing with Alice's package.

The motivation to develop this package stems from the following posts on the Discourse:
- https://discourse.julialang.org/t/how-to-add-metadata-info-to-a-dataframe/11168
- https://discourse.julialang.org/t/composition-and-inheritance-the-julian-way/11231

but several other topics apply as well (see list in the *Links* section below).


## Installation
The **ReusePatterns.jl** package is currently under testing, hence you may download the development version with:
```julia
using Pkg
Pkg.develop("https://github.com/gcalderone/ReusePatterns.jl")
```

## Composition

With [composition](https://en.wikipedia.org/wiki/Object_composition) we wrap an Alice's object into a structure implemented by Bob, and let Charlie use the latter without even knowing if it actually is the original Alice's object or the Bob's one.

We pursue this goal by automatically forwarding all methods calls from Bob's structure to the appropriate Alice's object.

### Example:
Alice implemented a code to keep track of all her books, but forgot to add room for the number of pages and the issue year of each book.  Bob wishes to add these informations, and to provide the final functionalities to Charlie:
```julia
# #####  Alice's code  #####
julia> struct Book
      title::String
      author::String
  end
julia> Base.show(io::IO, b::Book) = println(io, "$(b.title) (by $(b.author))")
julia> Base.print(b::Book) = println("In a hole in the ground there lived a hobbit...")
julia> author(b::Book) = b.author

# #####  Bob's code  #####
julia> struct PaperBook
    b::Book
    number_of_pages::Int
end
julia> @forward((PaperBook, :b), Book)
julia> pages(book::PaperBook) = book.number_of_pages

julia> struct Edition
    b::PaperBook
    year::Int
end
julia> @forward((Edition, :b), PaperBook)
julia> year(book::Edition) = book.year

# #####  Charlie's code  #####
julia> book = Edition(PaperBook(Book("The Hobbit", "J.R.R. Tolkien"), 374), 2013)

julia> print(author(book), ", ", pages(book), " pages, Ed. ", year(book))
J.R.R. Tolkien, 374 pages, Ed. 2013

julia> print(book)
In a hole in the ground there lived a hobbit...
```
The key lines here are:
```julia
@forward((PaperBook, :b), Book)
@forward((Edition, :b), PaperBook)
```
The `@forward` macro identifies all methods accepting a `Book` object, and defines new methods with the same name and arguments, but accepting `PaperBook` arguments in place of the `Book`  ones.  The purpose of each newly defined method is simply to forward the call to the original method, passing the `Book` object stored in the `:p` field.  The second lines do the same job forwarding calls from `Edition` objects to `PaperBook` ones.

The **ReusePatterns.jl** package exports the following functions and macros aimed to support *composition* in Julia:
- `forward`: return a `Vector{String}` with the code to properly forward method calls;
- `@forward`: forward method calls from an object to a field structure;

Continuing the previous example:
```
julia> forward((Edition, :b), PaperBook)
4-element Array{String,1}:
 "@eval Main Base.:(print)(p1::Main.Edition; kw...) = Main.:(print)(getfield(p1, :b); kw...) # none:1"
 "@eval Main Base.:(show)(p1::IO, p2::Main.Edition; kw...) = Main.:(show)(p1, getfield(p2, :b); kw...) # none:1"
 "@eval Main Main.:(author)(p1::Main.Edition; kw...) = Main.:(author)(getfield(p1, :b); kw...) # none:1"
 "@eval Main Main.:(pages)(p1::Main.Edition; kw...) = Main.:(pages)(getfield(p1, :b); kw...) # REPL[12]:1"
```

Each function and macro has its own online documentation accessible by prepending `?` to the name.

The *composition* approach has the following advantages:
- It is applicable even if Alice and Bob do not agree on a particular type architecture;
- it is the recommended Julian way to pursue code reusing;

...and disadvantages:
- It may be cumbersome to apply if the number of involved methods is very high, or if the method definitions are spread across many modules;
- *composition* is not recursive, i.e. if further users (**D**an, **E**mily, etc.) build composite layers on top of Bob's one they'll need to implement new forwarding methods;
- It introduces a small overhead for each composition layer, resulting in performance loss;


## Concrete subtyping
Julia supports [subtyping](https://en.wikipedia.org/wiki/Subtyping) of abstract types, allowing to build type hierarchies where each node provides the same behavior as all its descendants, i.e. each abstract type can be [substituted](https://en.wikipedia.org/wiki/Liskov_substitution_principle) with any of its subtypes.  This is one of the most powerful feature in Julia: in a function argument you may require an *AbstractArray* and seamlessly work with any of its concrete implementations (e.g. dense, strided or sparse arrays, ranges, etc.). This mechanism actually stem from a **rigid separation** of the desired behavior for a type (represented by the abstract type and the [interface](https://docs.julialang.org/en/v1/manual/interfaces) definition) and the actual machine implementation (represented by the concrete type and the interface implementations).

However, in Julia you can only subtype abstract types, hence this powerful substitutability mechanism can not be pushed beyond a concrete type. Citing the [manual](https://docs.julialang.org/en/v1/manual/types): *this [limitation] might at first seem unduly restrictive, [but] it has many beneficial consequences with surprisingly few drawbacks.*

The most striking drawback pops out in the case Alice defines an abstract type with only one subtype, namely a concrete one.  Clearly, in all methods requiring access to the actual data representation, the argument types will be annotated with the concrete type, not the abstract one.  This is an important protection against Alice's package misuse: those methods require **exactly** that concrete type, not something else, even if it is a subtype of the same parent abstract type.  However, this is a serious problem for Bob, since he can not reuse those methods even if he defines concrete structures with the same contents as Alice's one (plus something else).

The **ReusePatterns.jl** package allows to overtake this limitation by introducing the concept of *quasi abstract* type, i.e. a type without a rigid separation between a type behaviour and its concrete implementation.  Operatively, a *quasi abstract* type is an abstract type satisfying the following constraints:

1 - it can have as many abstract or *quasi abstract* subtypes as desired, but it can have **only one** concrete subtype (the so called *assocated concrete type*);
2 - if a *quasi abstract* type has another *quasi abstract* type among its ancestors, its associated concrete type must have (at least) the same field names and types of the ancestor associated data structure.

Note that for the example discussed above constraint 1 is not an actual limitation, since Alice already defined only one concrete type.  Also note that constraint 2 implies *concrete structure subtyping*.

The `@quasiabstract` macro provided by the **ReusePatterns.jl** package, ensure the above constraints are properly observed.

simply forget about the associated concrete type

The guidelines to exploit *quasi abstract* types are straightforward:
- define the *quasi abstract* type as a simple structure;
- although two types are actually defined under the hood, you may simply forget about the concrete one, and safely use the abstract one for object creation, method argument annotations, etc.


### Example:
As for the *composition* case discussed above, assume alice implemented a code to keep track of all her books, but forgot to add room for the number of pages and the issue year of each book.  Bob wishes to add these informations, and to provide the final functionalities to Charlie.
```julia
# #####  Alice's code  #####
julia> @quasiabstract struct Book
      title::String
      author::String
  end
julia> Base.show(io::IO, b::Book) = println(io, "$(b.title) (by $(b.author))")
julia> Base.print(b::Book) = println("In a hole in the ground there lived a hobbit...")
julia> author(b::Book) = b.author

# #####  Bob's code  #####
julia> @quasiabstract struct PaperBook <: Book
    number_of_pages::Int
end
julia> pages(book::PaperBook) = book.number_of_pages

julia> @quasiabstract struct Edition <: PaperBook
    year::Int
end
julia> year(book::Edition) = book.year

julia> println(fieldnames(concretetype(Edition)))
(:title, :author, :number_of_pages, :year)

# #####  Charlie's code  #####
julia> book = Edition("The Hobbit", "J.R.R. Tolkien", 374, 2013)

julia> print(author(book), ", ", pages(book), " pages, Ed. ", year(book))
J.R.R. Tolkien, 374 pages, Ed. 2013

julia> print(book)
In a hole in the ground there lived a hobbit...
```


The **ReusePatterns.jl** package exports the following functions and macros aimed to support *concrete subtyping* in Julia:

- `@quasiabstract`: define a new *quasi abstract* type, i.e. a pair of an abstract and an (exclusively associated) concrete types;
- `concretetype`: return the concrete type associated to a *quasi abstract* type;
- `isquasiabstract`: test whether a type is *quasi abstract*;
- `isquasiconcrete`: test whether a type is the concrete type associated to a *quasi abstract* type.

Continuing the above example:
```julia
julia> isquasiconcrete(typeof(book))
true

julia> isquasiabstract(supertype(typeof(book)))
true

julia> concretetype(supertype(typeof(book))) === typeof(book)
true
```

Each function and macro has its own online documentation accessible by prepending `?` to the name.



This *concrete subtyping* approach has the following advantages:

- It is a recursive approach, i.e. if further users (**D**an, **E**mily, etc.) subtypes Bob's structure they will have all the inherited behavior for free;
- There is no overhead or performance loss.

...and disadvantages:
- it is applicable **only if** if both Alice and Bob agrees to use *quasi abstract* types.
- Charlie may break Alice's or Bob's code by using a concrete type with the *quasi abstract* type as ancestor, but without the required fields.  However, this problem can be easily fixed by adding the following check in the methods accepting a subtyped *quasi abstract* type, e.g. in the `pages` method shown above:
```julia
function pages(book::PaperBook)
    @assert isquasiconcretetype(typeof(book))
    book.number_of_pages
end
```
Note also that `isquasiconcretetype` is a pure function, hence it can be used as a trait.


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
