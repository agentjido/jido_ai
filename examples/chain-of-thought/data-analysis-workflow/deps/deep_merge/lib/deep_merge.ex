defmodule DeepMerge do
  @moduledoc """
  Provides functionality for deeply/recursively merging structures (normally for
  `Map` and `Keyword`).

  If you want to change the deep merge behavior of a custom struct,
  please have a look at the `DeepMerge.Resolver` protocol.
  """

  alias DeepMerge.Resolver
  @continue_symbol :__deep_merge_continue

  @doc """
  Deeply merges two maps or keyword list `original` and `override`.

  In more detail, if two conflicting values are maps or keyword lists themselves
  then they will also be merged recursively. This is an extension in that sense
  to what `Map.merge/2` and `Keyword.merge/2` do as it doesn't just override map
  or keyword values but tries to merge them.

  It does not merge structs or structs with maps. If you want your structs to be
  merged then please have a look at the `DeepMerge.Resolver` protocol and
  consider implementing/deriving it.

  Also, while it says `Map` and `Keyword` here, it is really dependent on which
  types implement the `DeepMerge.Resolver` protocol, which by default are `Map`
  and `Keyword`.

  ## Examples

      iex> DeepMerge.deep_merge(%{a: 1, b: [x: 10, y: 9]}, %{b: [y: 20, z: 30], c: 4})
      %{a: 1, b: [x: 10, y: 20, z: 30], c: 4}

      iex> DeepMerge.deep_merge(%{a: 1, b: %{x: 10, y: 9}}, %{b: %{y: 20, z: 30}, c: 4})
      %{a: 1, b: %{x: 10, y: 20, z: 30}, c: 4}

      iex> DeepMerge.deep_merge(%{a: 1, b: %{x: 10, y: 9}}, %{b: %{y: 20, z: 30}, c: 4})
      %{a: 1, b: %{x: 10, y: 20, z: 30}, c: 4}

      iex> DeepMerge.deep_merge([a: 1, b: [x: 10, y: 9]], [b: [y: 20, z: 30], c: 4])
      [a: 1, b: [x: 10, y: 20, z: 30], c: 4]

      iex> DeepMerge.deep_merge(%{a: 1, b: 2}, %{b: 3, c: 4})
      %{a: 1, b: 3, c: 4}

      iex> DeepMerge.deep_merge(%{a: 1, b: %{x: 10, y: 9}}, %{b: 5, c: 4})
      %{a: 1, b: 5, c: 4}

      iex> DeepMerge.deep_merge([a: [b: [c: 1, d: 2], e: [24]]], [a: [b: [f: 3], e: [42, 100]]])
      [a: [b: [c: 1, d: 2, f: 3], e: [42, 100]]]

      iex> DeepMerge.deep_merge(%{a: 1, b: 5}, %{b: %{x: 10, y: 9}, c: 4})
      %{a: 1, b: %{x: 10, y: 9}, c: 4}

      iex> DeepMerge.deep_merge(%{a: [b: %{c: [d: "foo", e: 2]}]}, %{a: [b: %{c: [d: "bar"]}]})
      %{a: [b: %{c: [e: 2, d: "bar"]}]}
  """
  @spec deep_merge(map() | keyword(), map | keyword()) :: map() | keyword()
  def deep_merge(original, override)
      when (is_map(original) or is_list(original)) and (is_map(override) or is_list(override)) do
    standard_resolve(nil, original, override)
  end

  @doc """
  A variant of `DeepMerge.deep_merge/2` that allows to modify the merge behavior
  through the additional passed in function.

  This is similar to the relationship between `Map.merge/2` and `Map.merge/3`
  and the structure of the function is exactly the same, e.g. the passed in
  arguments are `key`, `original` and `override`.

  The function is called before a merge is performed. If it returns any value
  that value is inserted at that point during the deep_merge. If the deep merge
  should continue like normal you need to return the symbol returned by
  `DeepMerge.continue_deep_merge/0`.

  If the merge conflict occurs at the top level then `key` is `nil`.

  The example shows how this can be used to modify `deep_merge` not to merge
  keyword lists, in case you don't like that behavior.

  ## Examples

      iex> resolver = fn
      ...> (_, original, override) when is_list(original) and is_list(override) ->
      ...>   override
      ...> (_, _original, _override) ->
      ...>   DeepMerge.continue_deep_merge
      ...> end
      iex> DeepMerge.deep_merge(%{a: %{b: 1}, c: [d: 1]},
      ...> %{a: %{z: 5}, c: [x: 0]}, resolver)
      %{a: %{b: 1, z: 5}, c: [x: 0]}
  """
  @spec deep_merge(map() | keyword(), map() | keyword(), (any(), any() -> any())) ::
          map() | keyword()
  def deep_merge(original, override, resolve_function)
      when (is_map(original) or is_list(original)) and (is_map(override) or is_list(override)) do
    resolver = build_resolver(resolve_function)
    resolver.(nil, original, override)
  end

  @doc """
  The symbol to return in the function in `deep_merge/3` when deep merging
  should continue as normal.

  ## Examples

      iex> DeepMerge.continue_deep_merge
      :__deep_merge_continue
  """
  @spec continue_deep_merge() :: :__deep_merge_continue
  def continue_deep_merge, do: @continue_symbol

  @spec build_resolver((any(), any() -> any())) :: (any(), any(), any() -> any())
  defp build_resolver(resolve_function) do
    my_resolver = fn key, base, override, fun ->
      resolved_value = resolve_function.(key, base, override)

      case resolved_value do
        @continue_symbol ->
          continue_deep_merge(base, override, fun)

        _anything ->
          resolved_value
      end
    end

    rebuild_resolver(my_resolver)
  end

  defp rebuild_resolver(resolve_function) do
    fn key, base, override ->
      resolve_function.(key, base, override, resolve_function)
    end
  end

  defp continue_deep_merge(base, override, fun) do
    resolver = rebuild_resolver(fun)
    Resolver.resolve(base, override, resolver)
  end

  defp standard_resolve(_key, original, override) do
    Resolver.resolve(original, override, &standard_resolve/3)
  end
end
