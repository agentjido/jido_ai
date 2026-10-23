defmodule JidoAI.Examples.ToolFlowTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Jido.AI.ToolAdapter
  alias JidoAI.Examples.ToolFlow.{Agent, Multiply, MultiplyFlow}

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "the Agent runs an Action tool and continues the response" do
    expect(ReqLLM, :generate_text, 2, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert Enum.map(options[:tools], & &1.name) == ["multiply", "multiply_flow"]

      case ReqLLM.Context.to_list(context) do
        [_system, _user] ->
          call = ReqLLM.ToolCall.new("call-1", "multiply", ~s({"left":6,"right":7}))
          message = ReqLLM.Context.assistant("", tool_calls: [call])

          {:ok,
           %ReqLLM.Response{
             id: "tool-request",
             model: model,
             context: ReqLLM.Context.append(context, message),
             message: message
           }}

        [_system, _user, %{role: :assistant}, tool_result] ->
          assert tool_result.role == :tool
          assert tool_result.name == "multiply"
          assert tool_result.metadata.tool_output == %{product: 42}

          {:ok, response(model, context, "The product is 42.")}
      end
    end)

    assert Agent.generate("What is 6 times 7?") == {:ok, "The product is 42."}
  end

  test "the Agent runs a Flow tool as a child of the ReAct Flow" do
    expect(ReqLLM, :generate_text, 2, fn model, context, _options ->
      case ReqLLM.Context.to_list(context) do
        [_system, _user] ->
          call = ReqLLM.ToolCall.new("flow-call-1", "multiply_flow", ~s({"left":3,"right":5}))
          message = ReqLLM.Context.assistant("", tool_calls: [call])

          {:ok,
           %ReqLLM.Response{
             id: "flow-tool-request",
             model: model,
             context: ReqLLM.Context.append(context, message),
             message: message
           }}

        [_system, _user, %{role: :assistant}, tool_result] ->
          assert tool_result.name == "multiply_flow"
          assert tool_result.metadata.tool_output == %{product: 15}
          {:ok, response(model, context, "The product is 15.")}
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

    assert tool_round.calls == [
             %{
               id: "flow-call-1",
               name: "multiply_flow",
               kind: :flow,
               status: :ok,
               output: %{type: :map, keys: ["product"]}
             }
           ]
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

          message = ReqLLM.Context.assistant("", tool_calls: calls)

          {:ok,
           %ReqLLM.Response{
             id: "invalid-tool-batch",
             model: model,
             context: ReqLLM.Context.append(context, message),
             message: message
           }}

        [_system, _user, %{role: :assistant}, first_error, second_error] ->
          assert first_error.role == :tool
          assert first_error.tool_call_id == "known-1"
          assert first_error.metadata.is_error
          assert second_error.role == :tool
          assert second_error.tool_call_id == "unknown-1"
          assert second_error.metadata.is_error

          {:ok, response(model, context, "I could not run that batch.")}
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

  defp response(model, context, text) do
    %ReqLLM.Response{
      id: "tool-answer",
      model: model,
      context: context,
      message: ReqLLM.Context.assistant(text)
    }
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
