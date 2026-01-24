defmodule Jido.AI.Accuracy.Helpers do
  @moduledoc """
  Shared helper functions for accuracy modules.

  This module provides common utility functions used across multiple
  accuracy-related modules to avoid code duplication.
  """

  @doc """
  Gets an attribute value from a keyword list or map.

  When `attrs` is a keyword list, uses `Keyword.get/3`.
  When `attrs` is a map, uses `Map.get/3`.

  ## Parameters

  - `attrs` - A keyword list or map containing attributes
  - `key` - The key to look up
  - `default` - The default value to return if the key is not found (default: `nil`)

  ## Examples

      iex> Helpers.get_attr([name: "test"], :name)
      "test"

      iex> Helpers.get_attr([name: "test"], :age, 25)
      25

      iex> Helpers.get_attr(%{name: "test"}, :name)
      "test"

      iex> Helpers.get_attr(%{name: "test"}, :age, 25)
      25

  """
  @spec get_attr(keyword() | map(), atom()) :: any()
  @spec get_attr(keyword() | map(), atom(), any()) :: any()
  def get_attr(attrs, key, default \\ nil)

  def get_attr(attrs, key, default) when is_list(attrs) do
    Keyword.get(attrs, key, default)
  end

  def get_attr(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, default)
  end
end
