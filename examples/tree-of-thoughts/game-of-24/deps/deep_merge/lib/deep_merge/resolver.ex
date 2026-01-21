defprotocol DeepMerge.Resolver do
  @moduledoc """
  Protocol defining how conflicts during deep_merge should be resolved.

  As part of the DeepMerge library this protocol is already implemented for
  `Map` and `List` as well as a fallback to `Any` (which just always takes the
  override).

  If you want your custom structs to also be deeply mergable and not just
  override one another (default behaviour) you can derive the protocol:

      defmodule Derived do
        @derive [DeepMerge.Resolver]
        defstruct [:attrs]
      end

  It will then automatically be deeply merged with structs of its own kind, not
  with other structs or maps though.
  """
  @fallback_to_any true

  @doc """
  Defines what happens when a merge conflict occurs on this struct during a
  deep_merge.

  Can be implemented for additional data types to implement custom deep merging
  behavior.

  The passed in values are:
    * `original` - the value in the original data structure, usually left side
    argument
    * `override` - the value with which `original` would be overridden in a
    normal `Map.merge/2`
    * `resolver` - the function used by DeepMerge to resolve merge conflicts,
    i.e. what you can pass to `Map.merge/3` and `Keyword.merge/3` to continue
    deeply merging.

  An example implementation might look like this if you want to deeply merge
  your struct but only against non `nil` values (because all keys are always there)
  if you merge against the same struct (but still merge with maps):

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
  """
  def resolve(original, override, resolver)
end

defimpl DeepMerge.Resolver, for: Map do
  @doc """
  Resolve the merge between two maps by continuing to deeply merge them.

  Don't merge structs or if its any other type take the override value.
  """
  def resolve(_original, override = %{__struct__: _}, _fun) do
    override
  end

  def resolve(original, override, resolver) when is_map(override) do
    Map.merge(original, override, resolver)
  end

  def resolve(_original, override, _fun), do: override
end

defimpl DeepMerge.Resolver, for: List do
  @doc """
  Deeply merge keyword lists but avoid overriding a keywords with an empty list.
  """
  def resolve(original = [{_k, _v} | _], override = [{_, _} | _], resolver) do
    Keyword.merge(original, override, resolver)
  end

  def resolve(original = [{_k, _v} | _tail], _override = [], _fun) do
    original
  end

  def resolve(_original, override, _fun), do: override
end

defimpl DeepMerge.Resolver, for: Any do
  @doc """
  Fall back to always taking the override.

  Also the implementation for `@derive [DeppMerge.Resolver]` where structs of the same type that
  implement the protocol are deeply merged.
  """
  def resolve(original = %{__struct__: struct}, override = %{__struct__: struct}, resolver) do
    implementors = get_implementors(DeepMerge.Resolver.__protocol__(:impls))

    if Enum.member?(implementors, struct) do
      Map.merge(original, override, resolver)
    else
      override
    end
  end

  def resolve(_original, override, _fun), do: override

  defp get_implementors({:consolidated, implementors}), do: implementors

  defp get_implementors(:not_consolidated) do
    IO.warn(
      "Protocols not consolidated and trying to merge two structs of the same type. Not supported!"
    )

    # let the code work with override semantics without being intrusive
    []
  end
end
