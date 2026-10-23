defmodule JidoAI.Examples.SessionAgentTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.SessionAgent
  alias JidoAI.Examples.SessionAgent.{Agent, Ask, Turn}

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "the route uses one turn Action without a Flow helper macro" do
    assert [%{handler: %{kind: :action, target: Turn}}] = Agent.definition().routes
  end

  test "each constructor call seeds a fresh Session before caller state is merged" do
    assert {:ok, first} = SessionAgent.new(id: "session-agent-first", state: %{})
    assert {:ok, second} = SessionAgent.new(id: "session-agent-second")

    assert first.initial_state.session == first.state.session
    assert second.initial_state.session == second.state.session
    refute first.state.session.id == second.state.session.id
    refute first.state.session.thread.id == second.state.session.thread.id
  end

  test "a successful route returns and commits one typed Reply Signal" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert %ReqLLM.Output{type: :object} = options[:output]
      {:ok, response(model, context, %{"answer" => "Ready"})}
    end)

    assert {:ok, %Jido.Agent{module: Agent} = agent} =
             SessionAgent.new(id: "session-agent-success")

    session_id = agent.state.session.id
    request = Ask.new!(%{question: "Are you ready?"})

    assert {:ok, updated, [%Reply{signal: reply}]} = Agent.cmd(agent, request)
    assert reply.type == "examples.session_agent.answered"
    assert reply.data == %{answer: "Ready"}
    assert Jido.Signal.get_context(reply, "jidocausationid") == request.id
    assert updated.state.session.id == session_id
    assert updated.state.session.status == :open
    assert updated.state.session.metadata == %{example: "session_agent"}
    assert updated.state.session.thread.signals == [request, reply]
    assert updated.state.session.thread.rev == 2
  end

  @tag capture_log: true
  test "a provider error leaves Session state unchanged" do
    expect(ReqLLM, :generate_text, fn _model, _context, _options ->
      {:error, :provider_unavailable}
    end)

    assert {:ok, agent} = SessionAgent.new(id: "session-agent-failure")
    request = Ask.new!(%{question: "Are you ready?"})

    assert {:error, _reason} = Agent.cmd(agent, request)
    assert agent.state.session.thread.rev == 0
    assert agent.state.session.thread.signals == []
  end

  @tag capture_log: true
  test "a closed Session stops the action before a model request" do
    reject(ReqLLM, :generate_text, 3)

    {:ok, session} = Jido.Session.new!() |> Jido.Session.close()
    assert {:ok, agent} = SessionAgent.new(id: "session-agent-closed", state: %{session: session})
    request = Ask.new!(%{question: "Are you ready?"})

    assert {:error, _reason} = Agent.cmd(agent, request)
    assert agent.state.session == session
    assert agent.state.session.thread.rev == 0
  end

  defp response(model, context, object) do
    %ReqLLM.Response{
      id: "session-agent-response",
      model: model,
      context: context,
      message: ReqLLM.Context.assistant(""),
      object: object
    }
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
