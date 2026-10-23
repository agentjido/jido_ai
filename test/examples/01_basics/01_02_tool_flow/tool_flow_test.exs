defmodule JidoAI.Examples.ToolFlowTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.AI.ToolAdapter
  alias JidoAI.Examples.ToolFlow.{Agent, Multiply, MultiplyFlow}

  @moduletag :example

  test "the Agent runs an Action tool and continues the response" do
    expect(ReqLLM, :generate_text, 2, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert Enum.map(options[:tools], & &1.name) == ["multiply", "multiply_flow"]

      case ReqLLM.Context.to_list(context) do
        [_system, _user] ->
          call = ReqLLM.ToolCall.new("call-1", "multiply", ~s({"left":6,"right":7}))
          {:ok, tool_response(model, context, [call], id: "tool-request")}

        [_system, _user, %{role: :assistant}, tool_result] ->
          assert tool_result.role == :tool
          assert tool_result.name == "multiply"
          assert tool_result.metadata.tool_output == %{product: 42}

          {:ok, text_response(model, context, "The product is 42.", id: "tool-answer")}
      end
    end)

    assert Agent.generate("What is 6 times 7?") == {:ok, "The product is 42."}
  end

  test "the Agent runs a Flow tool as a child of the ReAct Flow" do
    expect(ReqLLM, :generate_text, 2, fn model, context, _options ->
      case ReqLLM.Context.to_list(context) do
        [_system, _user] ->
          call = ReqLLM.ToolCall.new("flow-call-1", "multiply_flow", ~s({"left":3,"right":5}))
          {:ok, tool_response(model, context, [call], id: "flow-tool-request")}

        [_system, _user, %{role: :assistant}, tool_result] ->
          assert tool_result.name == "multiply_flow"
          assert tool_result.metadata.tool_output == %{product: 15}
          {:ok, text_response(model, context, "The product is 15.", id: "tool-answer")}
      end
    end)

    assert {:ok, result} = Agent.reason("What is 3 times 5?")
    assert result.output == "The product is 15."
    assert result.usage == %{model_calls: 2, tool_calls: 1, iterations: 1}

    assert Enum.map(result.trace, & &1.type) == [
             :request_started,
             :model_completed,
             :tool_round_completed,
             :model_completed,
             :request_completed
           ]

    assert tool_round = Enum.find(result.trace, &(&1.type == :tool_round_completed))

    assert tool_round.data.calls == [
             %{
               id: "flow-call-1",
               name: "multiply_flow",
               kind: :flow,
               status: :ok,
               output: %{type: :map, keys: ["product"]}
             }
           ]
  end

  test "one request can expose only a declared tool subset" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert Enum.map(options[:tools], & &1.name) == ["multiply"]
      {:ok, text_response(model, context, "Only multiply was visible.", id: "tool-answer")}
    end)

    assert Agent.generate("Use the allowed tool if needed", visible_tools: [:multiply]) ==
             {:ok, "Only multiply was visible."}
  end

  test "an invalid call prevents the complete tool batch from running" do
    {:ok, counter} = Elixir.Agent.start_link(fn -> 0 end)

    expect(ReqLLM, :generate_text, 2, fn model, context, _options ->
      case ReqLLM.Context.to_list(context) do
        [_system, _user] ->
          calls = [
            ReqLLM.ToolCall.new("known-1", "multiply", ~s({"left":6,"right":7})),
            ReqLLM.ToolCall.new("unknown-1", "missing", ~s({}))
          ]

          {:ok, tool_response(model, context, calls, id: "invalid-tool-batch")}

        [_system, _user, %{role: :assistant}, first_error, second_error] ->
          assert first_error.role == :tool
          assert first_error.tool_call_id == "known-1"
          assert first_error.metadata.is_error
          assert second_error.role == :tool
          assert second_error.tool_call_id == "unknown-1"
          assert second_error.metadata.is_error

          {:ok, text_response(model, context, "I could not run that batch.", id: "tool-answer")}
      end
    end)

    assert Agent.generate("Use both tools", jido_context: %{counter: counter}) ==
             {:ok, "I could not run that batch."}

    assert Elixir.Agent.get(counter, & &1) == 0
  end

  test "the adapter can run a Flow tool" do
    assert {:ok, tool} = ToolAdapter.from_executable(MultiplyFlow)
    assert ReqLLM.Tool.execute(tool, %{"left" => 3, "right" => 5}) == {:ok, %{product: 15}}

    assert {:ok, action_tool} = ToolAdapter.from_executable(Multiply)
    assert action_tool.name == "multiply"
  end
end
