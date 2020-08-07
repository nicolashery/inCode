Enhancing Functor Structures Step-By-Step (Part 1)
==================================================

> Originally posted by [Justin Le](https://blog.jle.im/).
> [Read online!](https://blog.jle.im/entry/enhancing-functor-structures-step-by-step-1.html)

A style of Haskell programming that I've been pretty excited about with over the
past year or so is something that I can maybe call a "functor structure"
designed pattern. This is the interest that culminated in my [Functor
Combinatorpedia](https://blog.jle.im/entry/functor-combinatorpedia.html) post
last year and the
[functor-combinators](https://hackage.haskell.org/package/functor-combinators)
library. In the blog post I called this style the "functor combinator" style
because it involved building these functor structures out of small, simple
pieces. This is just one way to build functor structures --- you could always
just make them directly from scratch, but they can get rather messy and it's
often times easier to use pre-made structures that have all the helper functions
already defined for you. But I never really talked about *how* you would build
them from scratch, and also never really explored the more exotic types of
lowercase-f functors in Hask --- contravariant functors and invariant functors.

In this post we're going to be exploring these different types of functor
structures step-by-step, by starting with a simple useful structure and
enhancing it piece by piece. This process reflects a lot of the way I personally
work through these things --- I normally don't get the whole powerful structure
all the way; instead I incrementally add things as I see how things fit
together.

We're going build the tools to describe a *json schema*, in the form of an
algebraic data type -- sums and products. We'll start off just building things
we can use to *describe* the schema (by printing out documentation), and by the
end of the journey we'll also be able to parse and generate values with our
schema.

This series is designed for an intermediate Haskeller with familiarity in things
like monadic parser combinators.

The Schema
----------

Let's start with the simplest level of describing our schema: a plain ol' AST
describing the possibilities our schema can take.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/doc.hs#L10-L32

data Schema =
      RecordType  [Field]
    | SumType     [Choice]
    | SchemaLeaf  Primitive
  deriving Show

data Choice = Choice
    { choiceName  :: String
    , choiceValue :: Schema
    }
  deriving Show

data Field = Field
    { fieldName  :: String
    , fieldValue :: Schema
    }
  deriving Show

data Primitive =
      PString
    | PNumber
    | PBool
  deriving Show
```

Our schema will either represent a record of many different fields, a sum of
many different options, or a primitive value. If it's a sum type, it'll be
described by a list of `Choice`, which describes each branch. If it's a record
type, it'll be described by a list of `Field`, which describes each field. If
it's a primitive type, it'll a `Primitive`, which is either a string, number, or
boolean.

Our end goal is to be able to write a schema for a type like

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/doc.hs#L34-L37

data Customer =
      CPerson   { cpName :: String, cpAge :: Int }
    | CBusiness { cbEmployees :: Int }
  deriving Show
```

and be able to represent documenting, parsing, and printing it all within
`Schema`. For our basic `Schema` above, this looks like:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/doc.hs#L39-L53

customerSchema :: Schema
customerSchema = SumType
    [ Choice
        { choiceName  = "Person"
        , choiceValue = RecordType
            [ Field { fieldName = "Name", fieldValue = SchemaLeaf PString }
            , Field { fieldName = "Age" , fieldValue = SchemaLeaf PNumber }
            ]
        }
    , Choice
        { choiceName  = "Business"
        , choiceValue = RecordType
            [ Field { fieldName = "Employees", fieldValue = SchemaLeaf PNumber } ]
        }
    ]
```

And a value like

``` {.haskell}
PCustomer { cpName = "Sam", cpAge = 40 }
```

might be represented by a json value like

``` {.json}
{ "tag": "Customer", 
  "contents":
    { "Name": "Sam"
    , "Age": 40.0
    }
}
```

Documentation
-------------

Using our schema type, let's make a documentation generator. It'll take a
`Schema` and nicely formatted documentation describing what the schema itself.

To make our lives easier, we'll be using the
*[prettyprinter](https://hackage.haskell.org/package/prettyprinter)* library,
which will handle indentation, horizontal and vertical concatenation, and other
printing concerns for us.

The structure of this will match the structure of our future schema processors
--- you'll find they all look like this in some form or another!

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/doc.hs#L55-L62

schemaDoc
    :: String       -- ^ name
    -> Schema       -- ^ schema
    -> PP.Doc x
schemaDoc title = \case
    RecordType fs -> recordDoc title fs
    SumType cs    -> sumDoc title cs
    SchemaLeaf p  -> leafDoc title p
```

So `schemaDoc` will take the name of our type and a schema, and generate a
`PP.Doc x`, the type of a text document in the *prettyprinter* library.[^1]
Nothing too fancy here other than simply matching on what type of schema we're
dealing with, and dispatching a different function for each type.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/doc.hs#L64-L72

recordDoc :: String -> [Field] -> PP.Doc x
recordDoc title fs = PP.vsep [
      PP.pretty ("{" <> title <> "}")
    , PP.indent 2 . PP.vsep $
        map (\fld -> "*" PP.<+> PP.indent 2 (fieldDoc fld)) fs
    ]
  where
    fieldDoc :: Field -> PP.Doc x
    fieldDoc Field{..} = schemaDoc fieldName fieldValue
```

First, the `RecordType` handler uses `PP.vsep`, which takes a list of docs and
concatenates them together vertically. The first doc is the title around curly
braces, and the second doc is a `*`'d list of `fieldDoc` for each `fs`,
concatenated vertically and indented two spaces.

`fieldDoc` itself is then going to recursively call `schemaDoc` with the field
name as the title and the field value as the sub-schema.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/doc.hs#L74-L83

sumDoc :: String -> [Choice] -> PP.Doc x
sumDoc title cs = PP.vsep [
      PP.pretty ("(" <> title <> ")")
    , "Choice of:"
    , PP.indent 2 . PP.vsep $
        map choiceDoc cs
    ]
  where
    choiceDoc :: Choice -> PP.Doc x
    choiceDoc Choice{..} = schemaDoc choiceName choiceValue
```

The `SumType` handler is going to be doing more or less the same thing, except
surrounding the title in `(` `)` parentheses. There's another line `Choice of:`,
followed by the list of each choice, vertically concatenated and indented twice.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/doc.hs#L85-L93

leafDoc :: String -> Primitive -> PP.Doc x
leafDoc title p = PP.pretty (title <> ":")
           PP.<+> primDoc p
  where
    primDoc :: Primitive -> PP.Doc x
    primDoc = \case
      PString -> "string"
      PNumber -> "number"
      PBool   -> "bool"
```

Finally, the `leafDoc` handler prints out the schema of a single list: it gives
the name of the leaf and then either `"string"`, `"number"`, or `"bool"`.

Hopefully that wasn't too bad! There were a lot of moving parts because we have
a recursive data type, but in the end hopefully each specific branch was
self-contained enough to understand on their own. We can test it out on
`customerSchema`, taking advantage of the fact that `PP.Doc`'s `Show` instance
will render the document:

    ghci> schemaDoc "Customer" customerSchema
    (Customer)
    Choice of:
      {Person}
        *   Name: string
        *   Age: number
      {Business}
        *   Employees: number

It works!

Parsing with Covariance
-----------------------

Now, let's talk about using our `Schema` type to define a json parser. We're
going to rewrite `Schema` to take a type parameter to represent the type we want
to parse into. A `Schema a` will be a schema that can be used to generate
documentation *and* describe a parser of `a`s. In the end, we want
`customerSchema :: Schema Customer`, and a function like

``` {.haskell}
schemaParser :: Schema a -> Parse ErrType a
```

to generate a json parser of `a`s. We'll be using the json parser type
`Parse err a` from
*[aeson-better-errors](https://hackage.haskell.org/package/aeson-better-errors)*
(not because of the better errors, but just because it's closer to an actual
incremental/stateful parser than other alternatives out there), which can be run
with `parse :: Parse err a -> ByteString -> Either (ParseError err) a`. So our
final interface will look like:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/parse.hs#L142-L143

parseSchema :: Schema a -> ByteString -> Either (A.ParseError ErrType) a
parseSchema sc = A.parse (schemaParser sc)
```

To do this, we now have to include information on "how to parse an `a`" in our
schema. Remember that our actual json format is pretty fixed/structured, so we
don't need to address things like how to encode sum types within our `Schema`
type itself. The only variation that our `Schema` can express can be isolated to
one place: the `Primitive` type.

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/parse.hs#L43-L56

data Primitive a =
      PString (String -> Maybe a)
    | PNumber (Scientific -> Maybe a)
    | PBool   (Bool -> Maybe a)
  deriving Functor

pString :: Primitive String
pString = PString Just

pInt :: Primitive Int
pInt = PNumber toBoundedInteger

pBool :: Primitive Bool
pBool = PBool Just
```

And that's it! Different data types will parse these primitive values in
different ways, but other than that, everything is sort of already
pre-determined. Remember, our `Schema` type is only meant to express the
different ways our rigidly defined structure can vary.

### Finding Ap

However, this small change (and adding the type parameter) leaves in a
predicament. What should `Schema` look like?

At first glance, we might think we could just write

``` {.haskell}
data Schema a =
      RecordType  [Field a]
    | SumType     [Choice a]
    | SchemaLeaf  (Primitive a)
  deriving Functor

-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/parse.hs#L31-L41

data Field a = Field
    { fieldName  :: String
    , fieldValue :: Schema a
    }
  deriving Functor

data Choice a = Choice
    { choiceName  :: String
    , choiceValue :: Schema a
    }
  deriving Functor
```

But there's a problem here: `RecordType` is a combination of `Field`s,
but...each `Field` is of a different type! For example, in our `Customer`
example, the `Person` branch has two fields: `Name` and `Age`. Our name schema
would look like `nameField :: Field String`, and our age schema would look like
`ageField :: Field Int`...and so you can't really put that into a list like
`[Field a]` since they each have different types. And further more, we want a
final `Customer` (in our `Schema Customer`), a type which is different from both
`String` and `Int`.

What we need is a way to express heterogeneous collection/sequence of `Field a`,
coupled with a way of "combining" all of them to create an aggregate value of a
final type. A type that says "use a bunch of `Field` of `x`s of different types
to generate a final `a`".

There are a couple of ways to arrive at this mystery type. One way is to
recognize "combine a bunch of `f x`s of different types to create an `f b`" is
essentially the MO of the *Applicative* abstraction, and so essentially we want
to give `Field` some sort of `Applicative` structure. And so we can reach for
"the type that gives something an `Applicative` structure", the [free
applicative](https://hackage.haskell.org/package/free/docs/Control-Applicative-Free.html).

Another way is to think about it as an enhancement along a functor combinator
described in the [functor
combinatorpedia](https://blog.jle.im/entry/functor-combinatorpedia.html). Here
we know we want to enhance `Field` in a specific way, so we can scan the list of
functor combinators until there is one that we need. And scrolling down, we see:

> [**Ap / Ap1 **](https://blog.jle.im/entry/functor-combinatorpedia.html#ap-ap1)
>
> **Origin**:
> *[Control.Applicative.Free](https://hackage.haskell.org/package/free/docs/Control-Applicative-Free.html)*
> /
> *[Data.Functor.Apply.Free](https://hackage.haskell.org/package/functor-combinators/docs/Data-Functor-Apply-Free.html)*
>
> **Enhancement**: The ability to provide multiple `f`s that the interpreter
> *must* consume *all* of. (...)
>
> While `ListF` may be considered "multiple options *offered*", `Ap` can be
> considered "multiple actions all *required*". The interpreter must
> consume/interpret *all* of the multiple `f`s in order to interpret an `Ap`.
>
> Note that ordering is not enforced: while the consumer must handle each `f`
> eventually, they are free to handle it in whatever order they desire. In fact,
> they could even all be handled in parallel. See `Free` for a version where
> ordering is enforced.
>
> ...
>
> Because this has an `Applicative` instance, you can use
> `(<*>) :: Ap f (a -> b) -> Ap f a -> Ap f b` to sequence multiple `Ap f`s
> together, and `pure :: a -> Ap f a` to produce a "no-op" `Ap` without any
> `f`s.

That sounds like it matches to me! In order to parse a `RecordType`, we need to
parse *every* `Field`. It doesn't make any sense to skip one field or the other:
they all need to be processed and parsed. This sounds like just the thing we
need.

The description here also gives a clue for what we might want to use for
`SumType` (`ListF` sounds like a good companion for the behavior we want sum
type parsers to have)

Another way to come to this conclusion is to think about it in terms of
tensoring functors: "how do we want to tensor together *two* `Field`s"?

Well, earlier we said that we want to combine fields of different types, while
also providing a way of combining the two types together to create a final
aggregate type. We can express this in Haskell with something like:

``` {.haskell}
data TwoFields = forall x y. TwoFields (Field x) (Field y) (x -> y -> a)
```

In existential syntax, this says that `TwoFields a` consists of `Field x` and
`Field y` of a "hidden" `x` and `y`, as well as a function to combine the `x`
and `y` to make an `a`.

We can look up what type of tensor this is in the functor combinatorpedia.
Scrolling down, we see:

> [**Day**](https://blog.jle.im/entry/functor-combinatorpedia.html#day)
>
> **Origin**:
> *[Data.Functor.Day](https://hackage.haskell.org/package/kan-extensions/docs/Data-Functor-Day.html)*
>
> **Mixing Strategy**: "Both, together forever": provide values from *both*
> functors, and the user *must* also *use* both.
>
> ...
>
> Unlike for `:*:`, you always have to interpret *both* functor values in order
> to interpret a `Day`. It's a "full mixing".
>
> The mechanism for this is interesting in and of itself. Looking at the
> definition of the data type:
>
> ``` {.haskell}
> data Day f g a = forall x y. Day (f x) (g y) (x -> y -> a)
> ```
>
> We see that because `x` and `y` are "hidden" from the external world, we can't
> directly use them without applying the "joining" function `x -> y -> a`. Due
> to how existential types work, we can't get anything out of it that "contains"
> `x` or `y`. Because of this, *using* the joining function requires *both*
> `f x` and `g y`. If we only use `f x`, we can only get, at best,`f (y -> a)`;
> if we only use `g y`, we can only get, at best, `g (x -> a)`. In order to
> fully eliminate *both* existential variables, we need to get the `x` and `y`
> from *both* `f x` and `g y`, as if the two values held separate halves of the
> key.

It seems as if our `TwoFields` is exactly `Day Field Field`, so we're on the
right track.

Reading further on in the `Day` section, we see that a list of "`f`s dayed with
each other multiple times" is precisely `Ap f`.

### Using Ap

With this let's write our final `Schema` type:

``` {.haskell}
-- source: https://github.com/mstksg/inCode/tree/master/code-samples/functor-structures/parse.hs#L25-L29

data Schema a =
      RecordType  (Ap Field a)
    | SumType     (ListF Choice a)
    | SchemaLeaf  (Primitive a)
  deriving Functor
```

--------------------------------------------------------------------------------

Hi, thanks for reading! You can reach me via email at <justin@jle.im>, or at
twitter at [\@mstk](https://twitter.com/mstk)! This post and all others are
published under the [CC-BY-NC-ND
3.0](https://creativecommons.org/licenses/by-nc-nd/3.0/) license. Corrections
and edits via pull request are welcome and encouraged at [the source
repository](https://github.com/mstksg/inCode).

If you feel inclined, or this post was particularly helpful for you, why not
consider [supporting me on Patreon](https://www.patreon.com/justinle/overview),
or a [BTC donation](bitcoin:3D7rmAYgbDnp4gp4rf22THsGt74fNucPDU)? :)

[^1]: I'm using `x` as the name of the type variable (instead of something more
    traditional like `a`) to indicate that it isn't meant to be referenced or
    used anywhere in any consistent way. Just remember it doesn't mean anything
    special syntactically!