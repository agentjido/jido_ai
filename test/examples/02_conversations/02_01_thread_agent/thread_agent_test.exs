defmodule JidoAI.Examples.ThreadAgentTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.ThreadAgent.{Agent, Ask, Turn}

  @moduletag :example

  test "the route uses one turn Action without a Flow helper macro" do
    assert [%{handler: %{kind: :action, target: Turn}}] = Agent.definition().routes
  end

  test "each constructor call initializes a fresh Thread when state does not supply one" do
    assert {:ok, first} = Agent.instantiate(id: "thread-agent-first", state: %{})
    assert {:ok, second} = Agent.instantiate(id: "thread-agent-second")

    assert first.initial_state == %{}
    assert second.initial_state == %{}
    refute first.state.thread.id == second.state.thread.id
  end

  test "the initializer preserves a supplied Thread" do
    thread = Jido.Thread.new!(id: "thread-agent-restored")

    assert {:ok, agent} =
             Agent.instantiate(id: "thread-agent-with-state", state: %{thread: thread})

    assert agent.state.thread == thread
  end

  test "a successful route commits and returns one complete Thread turn" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert %ReqLLM.Output{type: :object} = options[:output]
      {:ok, object_response(model, context, %{"answer" => "Ready"}, id: "thread-agent-response")}
    end)

    assert {:ok, %Jido.Agent{module: Agent} = agent} =
             Agent.instantiate(id: "thread-agent-success")

    request = Ask.new!(%{question: "Are you ready?"})

    assert {:ok, updated, [%Reply{signal: reply}]} = Jido.Agent.cmd(agent, request)
    assert reply.type == "examples.thread_agent.answered"
    assert reply.data == %{answer: "Ready"}
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
    assert updated.state.thread.signals == [request, reply]
    assert updated.state.thread.rev == 2
    assert Jido.PortableTerm.valid?(updated.state.thread)
  end

  @tag capture_log: true
  test "a provider failure leaves the Agent Thread unchanged" do
    expect(ReqLLM, :generate_text, fn _model, _context, _options ->
      {:error, :provider_unavailable}
    end)

    assert {:ok, agent} = Agent.instantiate(id: "thread-agent-failure")
    request = Ask.new!(%{question: "Are you ready?"})

    assert {:error, _reason} = Jido.Agent.cmd(agent, request)
    assert agent.state.thread.rev == 0
    assert agent.state.thread.signals == []
  end
end
