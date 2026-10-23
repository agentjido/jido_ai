defmodule JidoAI.Examples.ThreadAgentTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.ThreadAgent
  alias JidoAI.Examples.ThreadAgent.{Agent, Ask, Turn}

  @moduletag :example

  setup :set_mimic_global
  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "the route uses one turn Action without a Flow helper macro" do
    assert [%{handler: %{kind: :action, target: Turn}}] = Agent.definition().routes
  end

  test "each constructor call seeds a fresh Thread before caller state is merged" do
    assert {:ok, first} = ThreadAgent.new(id: "thread-agent-first", state: %{})
    assert {:ok, second} = ThreadAgent.new(id: "thread-agent-second")

    assert first.initial_state.thread == first.state.thread
    assert second.initial_state.thread == second.state.thread
    refute first.state.thread.id == second.state.thread.id
  end

  test "a successful route commits and returns one complete Thread turn" do
    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert %ReqLLM.Output{type: :object} = options[:output]
      {:ok, response(model, context, %{"answer" => "Ready"})}
    end)

    assert {:ok, %Jido.Agent{module: Agent} = agent} =
             ThreadAgent.new(id: "thread-agent-success")

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

    assert {:ok, agent} = ThreadAgent.new(id: "thread-agent-failure")
    request = Ask.new!(%{question: "Are you ready?"})

    assert {:error, _reason} = Jido.Agent.cmd(agent, request)
    assert agent.state.thread.rev == 0
    assert agent.state.thread.signals == []
  end

  defp response(model, context, object) do
    %ReqLLM.Response{
      id: "thread-agent-response",
      model: model,
      context: context,
      message: ReqLLM.Context.assistant(""),
      object: object
    }
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
