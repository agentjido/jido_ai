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

  @doc """
  Evaluates an EEx template without printing compiler diagnostics.

  This wraps `EEx.eval_string/2` to suppress warning/error output that
  would otherwise pollute test output or logs.

  ## Parameters

  - `template` - The EEx template string
  - `opts` - Options to pass to `EEx.eval_string/2`

  ## Returns

  The rendered string result.

  ## Raises

  Raises the same exceptions as `EEx.eval_string/2` for invalid templates.
  """
  @spec eval_eex_quiet(String.t(), keyword()) :: String.t() | no_return()
  def eval_eex_quiet(template, opts \\ []) do
    {{status, result, stacktrace}, _diagnostics} =
      Code.with_diagnostics(fn ->
        try do
          {:ok, EEx.eval_string(template, opts), nil}
        rescue
          e -> {:raise, e, __STACKTRACE__}
        end
      end)

    case status do
      :ok -> result
      :raise -> reraise result, stacktrace
    end
  end
end
