defmodule Abacus.Runtime.Helpers do
  def cast_for_comparison(atom) when is_atom(atom) do
    to_string(atom)
  end
  def cast_for_comparison(other) do
    other
  end

  @type operator :: :== | :!= | :> | :< | :<= | :>=
  @spec compare(operator, any, any) :: boolean
  def compare(op, lhs, rhs) do
    compare(op, lhs, rhs, typeof(lhs), typeof(rhs))
  end

  @spec compare(operator, any, any, atom, atom) :: boolean
  def compare(op, lhs, rhs, type, type) do
    apply(Kernel, op, [lhs, rhs])
  end
  def compare(op, lhs, rhs, lt, rt) when lt in ~w[float integer]a and rt in ~w[float integer]a do
    apply(Kernel, op, [lhs, rhs])
  end
  def compare(op, _, _, lt, rt) when lt != rt and op in ~w[== > < >= <=]a, do: false
  def compare(:!=, _, _, lt, rt) when lt != rt, do: true

  @type typeof :: :atom | :binary | :float | :integer | :list | :map
  @spec typeof(any) :: typeof
  def typeof(a) when is_atom(a), do: :atom
  def typeof(b) when is_binary(b), do: :binary
  def typeof(i) when is_integer(i), do: :integer
  def typeof(f) when is_float(f), do: :float
  def typeof(b) when is_boolean(b), do: :boolean
  def typeof(m) when is_map(m), do: :map
  def typeof(l) when is_list(l), do: :list

  @moduledoc """
  Utility functions
  """

  @doc """
  Returns the factorial of n.

  ## Example

  ```
  iex(2)> factorial(0)
  1
  iex(3)> factorial(1)
  1
  iex(4)> factorial(2)
  2
  iex(5)> factorial(3)
  6
  iex(6)> factorial(4)
  24
  iex(7)> factorial(5)
  120
  ```
  """
  @spec factorial(number) :: number
  def factorial(0), do: 1
  def factorial(n) when n > 0 do
    _factorial(1, n, 1)
  end

  def _factorial(n, m, r) when n < m do
     _factorial(n + 1, m, r * (n + 1))
  end

  def _factorial(n, n, r), do: r

  def unescape_string(list) do
    list
    |> :unicode.characters_to_binary()
    |> String.replace_leading("\"", "")
    |> String.replace_trailing("\"", "")
    |> String.replace(~r/\\("|\\)/, "\\g{1}")
  end
end
