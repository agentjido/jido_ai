defmodule SparqTest.ASTCase do
  @moduledoc """
  Provides helper functions and assertions for testing AST evaluation in Sparq.

  ## Example

      use SparqTest.ASTCase

      test "evaluates basic arithmetic" do
        ast = script([
          declare(:x, 5),
          declare(:y, 10),
          {:add, [], [var(:x), var(:y)]}
        ])

        assert_eval ast, 15
      end
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import SparqTest.ASTCase
      alias Sparq.{Core, Context}
    end
  end

  @doc """
  Evaluates an AST and returns the result value.
  Raises on error.
  """
  def eval_ast(ast) do
    case Sparq.Core.execute(ast) do
      {:ok, value, _ctx} -> value
      {:error, error, _ctx} -> raise "Evaluation error: #{error.message}"
    end
  end

  @doc """
  Evaluates an AST and returns both result and context.
  Useful for testing side effects and context changes.
  """
  def eval_ast_with_ctx(ast) do
    case Sparq.Core.execute(ast) do
      {:ok, value, ctx} -> {value, ctx}
      {:error, error, _ctx} -> raise "Evaluation error: #{error.message}"
    end
  end

  @doc """
  Asserts that evaluating the AST produces the expected value.
  """
  def assert_eval(ast, expected) do
    result = eval_ast(ast)
    ExUnit.Assertions.assert(result == expected)
  end

  @doc """
  Creates a script node wrapping the given expressions.
  A script is the top-level container for Sparq code.
  """
  def script(exprs) when is_list(exprs) do
    {:script, [], exprs}
  end

  @doc """
  Creates a block node containing the given expressions.
  Blocks create a new scope for variables.
  """
  def block(exprs) when is_list(exprs) do
    {:block, [], exprs}
  end

  @doc """
  Creates a variable declaration with optional type.
  Types can be :let or :const.
  """
  def declare(name, value, type \\ :let) when type in [:let, :const] do
    {:bind, [], [name, value, type]}
  end

  @doc """
  Creates a variable reference node.
  """
  def var(name) when is_atom(name) do
    {:var, [], name}
  end

  def wrap_in_block(exprs) when is_list(exprs) do
    {:block, [], exprs}
  end

  def wrap_in_block(expr) do
    {:block, [], [expr]}
  end
end
