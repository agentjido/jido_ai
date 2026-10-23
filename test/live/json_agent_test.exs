defmodule Jido.AI.Live.JSONAgentTest do
  use Jido.AI.Test.LiveCase, async: false

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.JSONAgent, as: Example
  alias JidoAI.Examples.JSONAgent.Ask

  test "an imported JSON Agent makes a real routed request" do
    input = "This request has no arithmetic. Do not call a tool. Return answer Imported and confidence 0.8."
    assert {:ok, definition} = Example.import()

    agent = Jido.Agent.instantiate!(definition, id: "live-imported-json-ai")
    request = Ask.new!(%{question: input})

    {result, _trace} =
      capture_live(agent, input, "imported_json_agent", [], fn ->
        with {:ok, _agent, [%Reply{signal: reply}]} <- Jido.Agent.cmd(agent, request) do
          send(self(), {:json_reply, reply})
          {:ok, reply.data}
        end
      end)

    assert {:ok, %{answer: answer, confidence: confidence}} = result
    assert_receive {:json_reply, reply}
    assert reply.type == "examples.json_ai.answered"
    assert is_binary(answer)
    assert confidence >= 0 and confidence <= 1
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end
end
