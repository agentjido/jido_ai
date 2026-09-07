defmodule Jido.AI.Tools.Arithmetic do
  @moduledoc """
  Provides basic arithmetic operations as actions. The operations defined here are obviously trivial.
  This module is intended to be used as a reference for how to write your own actions.

  This module defines a set of arithmetic actions that can be used in actions:
  - Add: Adds two numbers together
  - Subtract: Subtracts one number from another
  - Multiply: Multiplies two numbers
  - Divide: Divides one number by another, handling division by zero
  - Square: Squares a number

  Each action is implemented as a separate submodule and follows the Jido.Action behavior.
  """

  alias Jido.Action

  defmodule Add do
    @moduledoc false
    use Action,
      name: "add",
      description: "Adds two numbers",
      schema:
        Zoi.object(%{
          value: Zoi.float(description: "The first number to add"),
          amount: Zoi.float(description: "The second number to add")
        })

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value + amount}}
    end
  end

  defmodule Subtract do
    @moduledoc false
    use Action,
      name: "subtract",
      description: "Subtracts one number from another",
      schema:
        Zoi.object(%{
          value: Zoi.float(description: "The number to subtract from"),
          amount: Zoi.float(description: "The number to subtract")
        })

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value - amount}}
    end
  end

  defmodule Multiply do
    @moduledoc false
    use Action,
      name: "multiply",
      description: "Multiplies two numbers",
      schema:
        Zoi.object(%{
          value: Zoi.float(description: "The first number to multiply"),
          amount: Zoi.float(description: "The second number to multiply")
        })

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value * amount}}
    end
  end

  defmodule Divide do
    @moduledoc false
    use Action,
      name: "divide",
      description: "Divides one number by another",
      schema:
        Zoi.object(%{
          value: Zoi.float(description: "The number to be divided (dividend)"),
          amount: Zoi.float(description: "The number to divide by (divisor)")
        })

    @spec run(map(), map()) :: {:ok, map()} | {:error, String.t()}
    def run(%{value: _value, amount: amount}, _context) when amount == 0 or amount == 0.0 do
      {:error, "Cannot divide by zero"}
    end

    def run(%{value: value, amount: amount}, _context) do
      {:ok, %{result: value / amount}}
    end
  end

  defmodule Square do
    @moduledoc false
    use Action,
      name: "square",
      description: "Squares a number",
      schema: Zoi.object(%{value: Zoi.float(description: "The number to be squared")})

    @spec run(map(), map()) :: {:ok, map()}
    def run(%{value: value}, _context) do
      {:ok, %{result: value * value}}
    end
  end
end
