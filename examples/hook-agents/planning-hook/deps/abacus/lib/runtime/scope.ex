defmodule Abacus.Runtime.Scope do
  @moduledoc """
  Contains helper functions to work with the scope of an Abacus script at runtime
  """

  @doc """
  Tries to get values from a subject.

  Subjects can be:

   * maps
   * keyword lists
   * lists (with integer keys)
   * nil (special case so access to undefined variables will not crash execution)

  Keys can be:

   * strings
   * atoms (you can pass a resolve map that converts the given atom key into a string key)
   * positive integers (for lists only)

  The Abacus parser will reference this function extensively like this:

  `a.b[2]` will turn into

  ```
  get_in(get_in(var0, :var1, var_lookup), 2, var_lookup)
  ```

  in this case, `var_lookup` will be:

  ```
  %{
    var1: "a",
    var2: "b"
  }
  ```
  """
  @type key :: String.t | atom
  @type index :: integer
  @spec get_in(nil, key | index, map) :: nil
  @spec get_in(map, key, map) :: nil | term
  @spec get_in(list, index, map) :: nil | term
  @spec get_in(list, key, map) :: nil | term
  def get_in(subject, key_or_index, var_lookup \\ %{})
  def get_in(nil, _, _), do: nil
  def get_in(subject, key, lookup) when is_atom(key) do
    key = Map.get(lookup, key, to_string(key))
    get_in(subject, key, lookup)
  end
  def get_in(subject, key, _) when (is_map(subject) or is_list(subject)) and is_binary(key) do
    Enum.reduce_while(subject, nil, fn {k, v}, _ ->
      case to_string(k) do
        ^key -> {:halt, v}
        _ -> {:cont, nil}
      end
    end)
  end
  def get_in(list, index, _) when is_list(list) and is_integer(index) and index >= 0 do
    Enum.at(list, index, nil)
  end

  @doc """
  Renames first-level variables into their respective `:"var\#{x}"` atoms
  """
  def prepare_scope(scope, lookup) when is_map(scope) or is_list(scope) do
    scope = Map.merge(default_scope(), Enum.into(scope, %{}))
    Enum.map(scope, fn
      {k, v} ->
        case Map.get(lookup, to_string(k)) do
          nil ->
            # will not be used anyway
            {k, v}
          varname ->
            {varname, v}
        end
      v ->
        v
    end)
    |> Enum.filter(fn
      {bin, _} when is_binary(bin) -> false
      _ -> true
    end)
  end
  def prepare_scope(primitive, _), do: primitive

  @math_funs_1 ~w[
    acos
    acosh
    asin
    asinh
    atan
    atanh
    ceil
    cos
    cosh
    exp
    floor
    log
    log10
    log2
    sin
    sinh
    sqrt
    tan
    tanh
  ]a

  @doc """
  Returns a scope with some default functions and constants
  """
  def default_scope do
    constants = %{
      PI: :math.pi(),
      round: &apply(Float, :round, [&1, &2])
    }

    Enum.map(@math_funs_1, fn fun ->
      {fun, &apply(:math, fun, [&1])}
    end)
    |> Enum.into(%{})
    |> Map.merge(constants)
  end
end
