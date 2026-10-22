defmodule Jido.AI.Live.StructuredReplyTest do
  use Jido.AI.Test.LiveCase, async: false

  alias Jido.Agent.Directive.Emit
  alias JidoAI.Examples.StructuredOutput.{Agent, Ask}

  test "a real model returns a routed reply shaped by a Signal Action" do
    input = "Return an assessment with answer Ready and confidence 0.9."
    agent = Agent.instantiate!(id: "live-structured-output")
    request = Ask.new!(%{question: input})

    {result, _trace} =
      capture_live(agent, input, "structured_reply", [], fn ->
        with {:ok, _agent, [%Emit{signal: reply}]} <- Agent.cmd(agent, request) do
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
