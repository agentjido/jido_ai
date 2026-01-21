# DeepMerge [![Hex Version](https://img.shields.io/hexpm/v/deep_merge.svg)](https://hex.pm/packages/deep_merge) [![docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/deep_merge/) [![Build Status](https://travis-ci.org/PragTob/deep_merge.svg?branch=master)](https://travis-ci.org/PragTob/deep_merge) [![Coverage Status](https://coveralls.io/repos/github/PragTob/deep_merge/badge.svg?branch=master)](https://coveralls.io/github/PragTob/deep_merge?branch=master) [![Inline docs](http://inch-ci.org/github/PragTob/deep_merge.svg?branch=master)](http://inch-ci.org/github/PragTob/deep_merge)

Provides functionality for "deep merging" maps and keyword lists in elixir, which is if during merging both values at the same key are maps/keyword lists merge them recursively. This is done via a protocol so can be extended for your own structs/data types if needbe.

```
iex> DeepMerge.deep_merge(%{a: 1, b: [x: 10, y: 9]}, %{b: [y: 20, z: 30], c: 4})
%{a: 1, b: [x: 10, y: 20, z: 30], c: 4}
```

This functionality can be useful for instance when merging a default configuration with a user supplied custom configuration:

```elixir
DeepMerge.deep_merge(default_config, custom_config) # => merged configuration
```

Further features include:

* It handles both maps and keyword lists
* It does not merge structs or maps with structs…
* …but you can implement the simple DeepMerge.Resolver protocol for types/structs of your choice to also make them deep mergable (there is also a default implementation)
* a deep_merge/3 variant that gets a function similar to Map.merge/3 to modify the merging behavior, for instance in case you don't want keyword lists to be merged or you want all lists to be appended

I wanted this to be a feature of Elixir itself, however the proposal [was rejected](https://github.com/elixir-lang/elixir/pull/5339) hence this library exists :)

## Installation

Add `deep_merge` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:deep_merge, "~> 1.0"}]
  end
  ```

## General Usage - deep_merge/2

Using this library is quite simple (and you might also want to look at the [hexdocs](https://hexdocs.pm/deep_merge/api-reference.html)) - just pass two structures to be deep merged into `DeepMerge.deep_merge/2`:

```elixir
iex> DeepMerge.deep_merge(%{a: 1, b: %{x: 10, y: 9}}, %{b: %{y: 20, z: 30}, c: 4})
%{a: 1, b: %{x: 10, y: 20, z: 30}, c: 4}

iex> DeepMerge.deep_merge([a: 1, b: [x: 10, y: 9]], [b: [y: 20, z: 30], c: 4])
[a: 1, b: [x: 10, y: 20, z: 30], c: 4]
```

It is worth noting that structs are not deeply merged - not with each other and not with normal maps. This is because structs, while internally a map, are more like their own data types and therefore should not be deeply merged... unless you implement the protocol provided by this library for them.

## Customization via protocols

What is merged and how is defined by implementing the `DeepMerge.Resolver` protocol. This library implements it for `Map`, `List` and falls back to `Any` (where the right hand side value/override is taken).

If you want your own struct to be deeply merged you can simply `@derive` the protocole:

```elixir
defmodule Derived do
  @derive [DeepMerge.Resolver]
  defstruct [:attrs]
end
```


If you want to change the deep merge for a custom struct you can do so. An example implementation might look like this if you want to deeply merge your struct but only against non `nil` values (because all keys are always there) if you merge against the same struct (but still merge with maps):

```elixir
defimpl DeepMerge.Resolver, for: MyStruct do
  def resolve(original, override = %MyStruct{}, resolver) do
    cleaned_override =
      override
      |> Map.from_struct()
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Map.merge(original, cleaned_override, resolver)
  end

  def resolve(original, override, resolver) when is_map(override) do
    Map.merge(original, override, resolver)
  end
end
```

In this implementation, `MyStruct` structs are merged with other `MyStruct` structs, omitting nil values. The arguments passed to `resolve` are the original value (left hand side) and the override value (right hand side, which would normally replace the original). The third parameter is a `resolver` function which you can pass to `Map.merge/3`/`Keyword.merge/3` to continue the deep merge.

## Customization via deep_merge/3

There is another deep merge variant that is a bit like `Map.merge/3` as it takes an additional function which you can use to alter the deep merge behavior:

```elixir
iex> resolver = fn
...> (_, original, override) when is_list(original) and is_list(override) ->
...>   override
...> (_, _original, _override) ->
...>   DeepMerge.continue_deep_merge
...> end
iex> DeepMerge.deep_merge(%{a: %{b: 1}, c: [d: 1]},
...> %{a: %{z: 5}, c: [x: 0]}, resolver)
%{a: %{b: 1, z: 5}, c: [x: 0]}
```

This function is called for a given merge conflict with the key where it occured and the two conflicting values. Whatever value is returned in this function is inserted at that point in the structure - unless `DeepMerge.continue_deep_merge` is returned in which case the deep merge continues as normal.

When would you want to use this versus a protocol? The best use case I can think of is when you want to alter behavior for which a protocol is already implemented or if you care about specific keys.

In the example above the behavior is changed so that keyword lists are not deep_merged (if they were the result would contain `c: [d: 1, x:0]`), but maps still are if that's what you are looking for.

## Do I really need a library for this?

Well not necessarily, no. There are [very simple implementations for maps that use Map.merge/3](http://stackoverflow.com/a/38865647).

There are subtle things that can be missed there though (and I missed the first time around):

* the most simple implementation also merges structs which is not always what you want
* For keyword lists on the other hand you gotta be careful that you don't accidentally merge keyword lists with lists as that's [currently possible](https://github.com/elixir-lang/elixir/issues/5395)
* you might want to further adopt the implementation, in [benchee](https://github.com/bencheeorg/benchee) we have 2 custom implementations of the protocol due to our needs

This library takes care of those problems and will take care of further problems/edge cases should they appear so you can focus on your business logic.

At the same time it offers extension mechanisms through protocols and a function in `deep_merge/3`. So, it should be adjustable to your use case and if not please open an issue :)

## Considered feature-complete

Unless you come with great feature ideas of course ;) So if you come here and there are no recent commits, don't worry - there are no known bugs or whatever. It's a small little library that does its job.