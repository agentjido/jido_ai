defmodule Sparq.Handlers.Builtins do
  @moduledoc """
  Handles built-in arithmetic operations in the Sparq language.
  These are the core operations that are always available.
  """

  use Sparq.Handlers.Behaviour

  @type arithmetic_op :: :+ | :- | :* | :/
  @type arithmetic_result :: number()

  @impl true
  def handle(op, _meta, args, ctx) do
    case do_handle(op, args) do
      {:ok, result} -> {result, ctx}
      {:error, :division_by_zero} -> raise ArithmeticError, "division by zero"
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @impl true
  def validate(op, args) do
    with :ok <- validate_arity(args),
         :ok <- validate_types(args),
         :ok <- validate_division_by_zero(op, args) do
      :ok
    end
  end

  # Private handle functions

  defp do_handle(:+, [a, b]), do: {:ok, a + b}
  defp do_handle(:-, [a, b]), do: {:ok, a - b}
  defp do_handle(:*, [a, b]), do: {:ok, a * b}
  defp do_handle(:/, [_a, b]) when b == 0 or b == 0.0, do: {:error, :division_by_zero}
  defp do_handle(:/, [a, b]), do: {:ok, a / b}
  defp do_handle(op, _args), do: {:error, "Unknown builtin operation: #{inspect(op)}"}

  # Private validation functions

  defp validate_arity(args) when length(args) != 2, do: {:error, :invalid_arity}
  defp validate_arity(_args), do: :ok

  defp validate_types([a, b]) when not is_number(a) or not is_number(b),
    do: {:error, :invalid_type}

  defp validate_types(_args), do: :ok

  defp validate_division_by_zero(:/, [_a, b]) when b == 0 or b == 0.0,
    do: {:error, :division_by_zero}

  defp validate_division_by_zero(_op, _args), do: :ok
end
