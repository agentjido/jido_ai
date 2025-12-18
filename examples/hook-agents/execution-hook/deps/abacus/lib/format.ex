defmodule Abacus.Format do
  #TODO old!

  @moduledoc """
  Function definitions on how to pretty-print expressions.

  See `Abacus.format/1` for more information.
  """

  @binary_operators [:add, :subtract, :divide, :multiply, :power,
    :and, :or, :xor, :shift_left, :shift_right,
    :eq, :neq, :gt, :gte, :lt, :lte,
    :logical_and, :logical_or]
  @unary_operators [:logical_not, :not, :factorial]
  @operators Enum.concat([@binary_operators, @unary_operators])

  @spec format(expr::tuple | number | boolean | nil) :: String.t
  def format(number) when is_integer(number), do: Integer.to_string(number)
  def format(number) when is_float(number), do: Float.to_string(number)
  def format(string) when is_binary(string) do

  end

  def format({operator, a, b} = expr) when operator in @binary_operators do
    op_string = format(operator)

    lhs = format a
    rhs = format b

    without_parantheses = "#{lhs} #{op_string} #{rhs}"
    with_left_parantheses = "(#{lhs}) #{op_string} #{rhs}"
    with_right_parantheses = "#{lhs} #{op_string} (#{rhs})"
    with_both_parantheses = "(#{lhs}) #{op_string} (#{rhs})"

    result = {
      Abacus.parse(without_parantheses),
      Abacus.parse(with_left_parantheses),
      Abacus.parse(with_right_parantheses),
      Abacus.parse(with_both_parantheses)
    }

    case result do
      {{:ok, ^expr}, _, _, _} -> without_parantheses
      {_, {:ok, ^expr}, _, _} -> with_left_parantheses
      {_, _, {:ok, ^expr}, _} -> with_right_parantheses
      {_, _, _, {:ok, ^expr}} -> with_both_parantheses
    end
  end

  def format({:function, name, arguments}) do
    arguments = arguments
    |> Enum.map(&format/1)
    |> Enum.join(", ")

    "#{name}(#{arguments})"
  end

  def format({:factorial, a} = expr) do
    a = format a
    with_parantheses = "(#{a})!"
    without_parantheses = "#{a}!"

    result = {
      Abacus.parse(without_parantheses),
      Abacus.parse(with_parantheses)
    }

    case result do
      {{:ok, ^expr}, _} -> without_parantheses
      {_, {:ok, ^expr}} -> with_parantheses
    end
  end

  def format({operator, a} = expr) when operator in @unary_operators do
    a = format a
    op = format operator
    with_parantheses = "#{op}(#{a})"
    without_parantheses = "#{op}#{a}"

    result = {
      Abacus.parse(without_parantheses),
      Abacus.parse(with_parantheses)
    }

    case result do
      {{:ok, ^expr}, _} -> without_parantheses
      {_, {:ok, ^expr}} -> with_parantheses
    end
  end

  def format({:ternary_if, condition, if_true, if_false} = expr) do
    fcondition = format condition
    ftrue = format if_true
    ffalse = format if_false

    v = [false, true]

    permutations = for c <- v, t <- v, f <- v do
      format = "#{parantheses fcondition, c} ? #{parantheses ftrue, t} : #{parantheses ffalse, f}"
      {:ok, expr} = Abacus.parse(format)
      {format, expr}
    end

    {format, _} = permutations
    |> Enum.filter(fn {_format, e} -> e == expr end)
    |> List.first

    format
  end

  def format(operator) when operator in @operators do
    case operator do
      :add -> "+"
      :subtract -> "-"
      :divide -> "/"
      :multiply -> "*"
      :power -> "^"
      :and -> "&"
      :or -> "|"
      :xor -> "|^"
      :not -> "~"
      :shift_left -> "<<"
      :shift_right -> ">>"
      :eq -> "=="
      :neq -> "!="
      :gt -> ">"
      :gte -> ">="
      :lt -> "<"
      :lte -> "<="
      :logical_and -> "&&"
      :logical_or -> "||"
      :logical_not -> "not"
    end
  end

  def format({:access, [{:variable, name} | rest]}) do
    case rest do
      [] -> name
      [{:index, _} | _] -> "#{name}#{format {:access, rest}}"
      [{:variable, _} | _] -> "#{name}.#{format {:access, rest}}"
    end
  end

  def format({:access, [{:index, expr} | rest]}) do
    case rest do
      [] -> "[#{format expr}]"
      [{:index, _} | _] -> "[#{format expr}]#{format {:access, rest}}"
      [{:variable, _} | _] -> "[#{format expr}].#{format {:access, rest}}"
    end
  end

  def format(false), do: "false"
  def format(true), do: "true"
  def format(nil), do: "null"

  def format(expr), do: {:error, "Can't format #{inspect expr}"}

  defp parantheses(expr, true), do: "(#{expr})"
  defp parantheses(expr, false), do: expr
end
