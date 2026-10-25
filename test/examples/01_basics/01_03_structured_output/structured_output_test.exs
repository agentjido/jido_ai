defmodule JidoAI.Examples.StructuredOutputTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.StructuredOutput.{Agent, Ask}

  @moduletag :example

  test "the Agent embeds its reasoning Flow" do
    reasoning = Jido.AI.Plugin.config(Agent).reasoning
    path = [host: Jido.AI.Plugin, declaration: :reasoning, role: :flow]

    assert reasoning == Jido.Flow.Inline.target!(Agent, path)
    assert reasoning.__jido_inline_flow__() == {Agent, path}
  end

  test "the route shapes and returns the structured Reply" do
    expected = %{answer: "Ready", confidence: 0.9}

    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert %ReqLLM.Output{type: :object, schema: schema} = options[:output]
      assert schema == Ask.output_schema()
      assert options[:receive_timeout] in 1..60_000

      {:ok, object_response(model, context, %{"answer" => "Ready", "confidence" => 0.9}, id: "structured-example")}
    end)

    agent = Agent.instantiate!(id: "structured-output")
    request = Agent.ask_signal!(%{question: "Are we ready?"})

    assert {:ok, ^agent, [%Reply{signal: reply}]} = Agent.cmd(agent, request)
    assert reply.type == "examples.structured_output.answered"
    assert reply.data == expected
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
  end
end
