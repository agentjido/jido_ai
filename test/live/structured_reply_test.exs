defmodule Jido.AI.Live.StructuredReplyTest do
  use Jido.AI.Test.LiveCase, async: false

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.StructuredOutput.Agent

  test "a real model returns a reply shaped by the route" do
    input = "Return an assessment with answer Ready and confidence 0.9."
    agent = Agent.instantiate!(id: "live-structured-output")
    request = Agent.ask_signal!(%{question: input})

    {result, _trace} =
      capture_live(agent, input, "structured_reply", [], fn ->
        with {:ok, _agent, [%Reply{signal: reply}]} <- Agent.cmd(agent, request) do
          send(self(), {:structured_reply, reply})
          {:ok, reply.data}
        end
      end)

    assert {:ok, %{answer: answer, confidence: confidence}} = result
    assert_receive {:structured_reply, reply}
    assert reply.type == "examples.structured_output.answered"
    assert is_binary(answer)
    assert confidence >= 0 and confidence <= 1
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end
end
