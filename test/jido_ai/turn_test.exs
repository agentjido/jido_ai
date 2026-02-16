defmodule Jido.AI.TurnTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Turn

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

  describe "from_response/2" do
    test "classifies final answer and extracts thinking/text content" do
      response = %{
        message: %{
          content: [
            %{type: :thinking, thinking: "let me think"},
            %{type: :text, text: "hello"},
            %{type: :text, text: "world"}
          ],
          tool_calls: nil
        },
        finish_reason: :stop,
        usage: %{input_tokens: 10, output_tokens: 5}
      }

      turn = Turn.from_response(response, model: "anthropic:claude-haiku-4-5")

      assert turn.type == :final_answer
      assert turn.text == "hello\nworld"
      assert turn.thinking_content == "let me think"
      assert turn.tool_calls == []
      assert turn.usage == %{input_tokens: 10, output_tokens: 5}
      assert turn.model == "anthropic:claude-haiku-4-5"
    end

    test "classifies tool calls from finish reason and tool call payload" do
      response = %{
        message: %{
          content: "",
          tool_calls: [
            %{id: "tc_1", name: "calculator", arguments: %{a: 1, b: 2}}
          ]
        },
        finish_reason: :tool_calls,
        usage: %{"input_tokens" => "2", "output_tokens" => "3"}
      }

      turn = Turn.from_response(response)

      assert turn.type == :tool_calls
      assert length(turn.tool_calls) == 1
      assert turn.usage == %{input_tokens: 2, output_tokens: 3}
      assert Turn.needs_tools?(turn)
    end

    test "uses ReqLLM.Response classification for canonical responses" do
      response = %ReqLLM.Response{
        id: "resp_1",
        model: "anthropic:claude-haiku-4-5",
        context: ReqLLM.Context.new(),
        message:
          ReqLLM.Context.assistant("",
            tool_calls: [ReqLLM.ToolCall.new("tc_1", "calculator", ~s({"a":1,"b":2}))]
          ),
        stream?: false,
        stream: nil,
        usage: %{"input_tokens" => "4", "output_tokens" => "2"},
        finish_reason: :tool_calls,
        provider_meta: %{},
        error: nil
      }

      turn = Turn.from_response(response)

      assert turn.type == :tool_calls
      assert turn.text == ""
      assert turn.thinking_content == nil
      assert turn.tool_calls == [%{id: "tc_1", name: "calculator", arguments: %{"a" => 1, "b" => 2}}]
      assert turn.usage == %{input_tokens: 4, output_tokens: 2}
      assert turn.model == "anthropic:claude-haiku-4-5"
    end
  end

  describe "message projections" do
    test "projects assistant message and tool messages" do
      turn =
        %Turn{
          type: :tool_calls,
          text: "",
          tool_calls: [%{id: "tc_1", name: "calculator", arguments: %{a: 5, b: 3}}]
        }
        |> Turn.with_tool_results([
          %{id: "tc_1", name: "calculator", content: "{\"result\":8}", raw_result: {:ok, %{result: 8}}}
        ])

      assert Turn.assistant_message(turn) == %{
               role: :assistant,
               content: "",
               tool_calls: [%{id: "tc_1", name: "calculator", arguments: %{a: 5, b: 3}}]
             }

      assert Turn.tool_messages(turn) == [
               %{role: :tool, tool_call_id: "tc_1", name: "calculator", content: "{\"result\":8}"}
             ]
    end
  end

  describe "format_tool_result_content/1" do
    test "formats common success and error shapes" do
      assert Turn.format_tool_result_content({:ok, %{value: 1}}) == "{\"value\":1}"
      assert Turn.format_tool_result_content({:error, %{message: "boom"}}) == "boom"
      assert Turn.format_tool_result_content({:error, :badarg}) == ":badarg"
    end
  end

  describe "run_tools/3" do
    test "executes tool calls and appends normalized tool results" do
      turn = %Turn{
        type: :tool_calls,
        text: "",
        tool_calls: [
          %{id: "tc_1", name: "calculator", arguments: %{"operation" => "add", "a" => 5, "b" => 3}}
        ]
      }

      context = %{tools: %{Calculator.name() => Calculator}}

      assert {:ok, updated_turn} = Turn.run_tools(turn, context, timeout: 1000)
      assert length(updated_turn.tool_results) == 1

      [tool_result] = updated_turn.tool_results
      assert tool_result.id == "tc_1"
      assert tool_result.name == "calculator"
      assert tool_result.content == "{\"result\":8}"
      assert tool_result.raw_result == {:ok, %{result: 8}}
    end

    test "returns original turn when no tool calls are requested" do
      turn = %Turn{type: :final_answer, text: "done", tool_calls: []}
      assert {:ok, ^turn} = Turn.run_tools(turn, %{})
    end
  end
end
