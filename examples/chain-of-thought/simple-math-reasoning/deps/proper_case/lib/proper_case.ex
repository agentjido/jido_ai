defmodule ProperCase do
  @moduledoc """
  An Elixir library that converts keys in maps between `snake_case` and `camel_case`
  """

  import String, only: [first: 1, replace: 4, downcase: 1, upcase: 1]

  @doc """
  Converts all the keys in a map to `camelCase` if mode is :lower or `CamleCase` if mode is :upper.
  If the map is a struct with no `Enumerable` implementation,
  the struct is considered to be a single value.
  """
  def to_camel_case(any), do: to_camel_case(any, :lower)

  def to_camel_case(map, mode) when is_map(map) do
    try do
      for {key, val} <- map,
          into: %{},
          do: {camel_case(key, mode), to_camel_case(val, mode)}
    rescue
      # Not Enumerable
      Protocol.UndefinedError -> map
    end
  end

  def to_camel_case(list, mode) when is_list(list) do
    list
    |> Enum.map(&to_camel_case(&1, mode))
  end

  def to_camel_case(final_val, _mode), do: final_val

  @doc """
  Converts all the keys in a map to `snake_case`.
  If the map is a struct with no `Enumerable` implementation,
  the struct is considered to be a single value.
  """
  def to_snake_case(map) when is_map(map) do
    try do
      for {key, val} <- map,
          into: %{},
          do: {snake_case(key), to_snake_case(val)}
    rescue
      # Not Enumerable
      Protocol.UndefinedError -> map
    end
  end

  def to_snake_case(list) when is_list(list) do
    list
    |> Enum.map(&to_snake_case/1)
  end

  def to_snake_case(other_types), do: other_types

  @doc """
  Converts an atom to a `camelCase` string
  """
  def camel_case(key), do: camel_case(key, :lower)

  def camel_case(key, mode) when is_atom(key) do
    key
    |> Atom.to_string()
    |> camel_case(mode)
  end

  def camel_case(val, _mode) when is_number(val), do: val

  @doc """
  Converts a string to `camelCase`
  """
  def camel_case("_" <> rest, mode) do
    "_#{camel_case(rest, mode)}"
  end

  def camel_case(key, :lower) when is_binary(key) do
    first_char = key |> first

    key
    |> Macro.camelize()
    |> replace(upcase(first_char), downcase(first_char), global: false)
  end

  def camel_case(key, :upper) when is_binary(key) do
    key
    |> Macro.camelize()
  end

  @doc """
  Converts an to `snake_case` string`
  """
  def snake_case(val) when is_atom(val) do
    val
    |> Atom.to_string()
    |> Macro.underscore()
  end

  def snake_case(val) when is_number(val) do
    val
  end

  @doc """
  Converts a string to `snake_case`
  """
  def snake_case(val) do
    val
    |> String.replace(" ", "")
    |> Macro.underscore()
  end
end
