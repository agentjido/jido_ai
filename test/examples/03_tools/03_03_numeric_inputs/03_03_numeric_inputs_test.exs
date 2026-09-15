defmodule JidoAI.Examples.NumericInputsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Session}
  alias JidoAI.Examples.NumericInputs.Agent

  defp request(server, context) do
    Request.create_and_send(server, "Read numbers",
      signal_type: "ai.numeric",
      source: "/examples/numeric-inputs",
      context: context,
      stream_to: self()
    )
  end

  for tool <- ["numeric_input", "numeric_flow"] do
    test "#{tool} converts complete numeric strings and nested values before execution", %{
      jido: jido
    } do
      arguments = %{count: "0", factor: "1.5", items: [%{count: "-2", factor: 3}]}
      call = %{id: "numbers", name: unquote(tool), arguments: arguments}
      {mock, context} = mock([%{reply: {:tools, [call]}}, %{reply: {:text, "Read"}}])
      server = start_agent(jido, Agent.new!())
      assert {:ok, handle} = request(server, context)
      assert {:ok, "Read"} = Request.await(handle)

      assert_receive {:jido_ai_request_event, %{kind: :tool_started, tool_name: unquote(tool)}}
      refute_received {:jido_ai_request_event, %{kind: :tool_started}}

      [_, second] = MockLLM.report(mock).requests
      assert [message] = Enum.filter(second.body["messages"], &(&1["role"] == "tool"))
      assert message["tool_call_id"] == "numbers"

      assert Jason.decode!(message["content"]) == %{
               "ok" => true,
               "result" => %{
                 "count" => 0,
                 "factor" => 1.5,
                 "items" => [%{"count" => -2, "factor" => 3.0}]
               }
             }

      record = Server.agent(server).state.requests[handle.id]

      assert [%{status: :ok, attempts: 1, result: {:ok, %{count: 0, factor: 1.5}, []}}] =
               record.meta.tool_results

      [%{result: {:ok, %{items: [%{factor: factor}]}, []}}] = record.meta.tool_results
      assert factor === 3.0

      assert record.meta.model_calls == 2
      assert {:ok, %{live: nil, details: %{phase: :request_completed}}} = Session.snapshot(server)
      assert_script_done(mock)
    end

    test "#{tool} rejects a malformed number before any call in the batch starts", %{jido: jido} do
      valid = %{
        id: "valid",
        name: unquote(tool),
        arguments: %{count: "1", factor: "2", items: []}
      }

      invalid = %{
        id: "invalid",
        name: unquote(tool),
        arguments: %{count: "2x", factor: "2", items: []}
      }

      {mock, context} = mock([%{reply: {:tools, [valid, invalid]}}])
      server = start_agent(jido, Agent.new!())
      assert {:ok, handle} = request(server, context)
      assert {:error, reason} = Request.await(handle)
      assert Jido.AI.Error.normalize(reason).type == :validation_error
      refute_received {:jido_ai_request_event, %{kind: :tool_started}}
      assert length(MockLLM.report(mock).requests) == 1
      assert Server.agent(server).state.requests[handle.id].status == :failed
      assert Server.agent(server).state.reply == ""
      assert {:ok, %{live: nil, details: %{phase: :request_failed}}} = Session.snapshot(server)
      assert_script_done(mock)
    end
  end
end
