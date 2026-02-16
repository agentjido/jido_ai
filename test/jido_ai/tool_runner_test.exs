defmodule Jido.AI.ToolRunnerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{ToolRunner, Turn}

  @moduletag :unit

  defmodule Calculator do
    use Jido.Action,
      name: "calculator",
      description: "Test calculator",
      schema:
        Zoi.object(%{
          operation: Zoi.string(),
          a: Zoi.integer(),
          b: Zoi.integer()
        })

    def run(%{operation: "add", a: a, b: b}, _context), do: {:ok, %{result: a + b}}
    def run(_params, _context), do: {:error, :unsupported_operation}
  end

  describe "run_turn/3" do
    test "executes tool calls and appends normalized tool results" do
      turn = %Turn{
        type: :tool_calls,
        text: "",
        tool_calls: [
          %{id: "tc_1", name: "calculator", arguments: %{"operation" => "add", "a" => 5, "b" => 3}}
        ]
      }

      context = %{tools: %{Calculator.name() => Calculator}}

      assert {:ok, updated_turn} = ToolRunner.run_turn(turn, context, timeout: 1000)
      assert length(updated_turn.tool_results) == 1

      [tool_result] = updated_turn.tool_results
      assert tool_result.id == "tc_1"
      assert tool_result.name == "calculator"
      assert tool_result.content == "{\"result\":8}"
      assert tool_result.raw_result == {:ok, %{result: 8}}
    end

    test "returns original turn when no tool calls are requested" do
      turn = %Turn{type: :final_answer, text: "done", tool_calls: []}
      assert {:ok, ^turn} = ToolRunner.run_turn(turn, %{})
    end
  end
end
