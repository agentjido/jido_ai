defmodule JidoAI.Examples.CallableReasoningTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias JidoAI.Examples.CallableReasoning

  test "a host Profile controls the Action and route without changing case state", %{jido: jido} do
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Conclusion: Four"}}, 2))
    context = bind(context, jido)
    params = %{prompt: "Explain this answer"}
    assert {:ok, result} = Jido.Exec.run(RunStrategy, params, context, timeout: 8_000)
    assert result.status == :success and result.output == "Four"
    assert result.usage.total_tokens == 15
    server = start_agent(jido, CallableReasoning.Agent.new!())
    signal = Jido.Signal.new!("reasoning.run", params, source: "/examples/reasoning")
    assert {:ok, agent} = Server.call(server, signal, context: context, timeout: 8_000)
    assert agent.state.result.output == "Four"
    assert agent.state.calls == 1 and agent.state.case_id == "case-17"

    for request <- MockLLM.report(mock).requests do
      assert hd(request.body["messages"])["content"] == "Use the host facts"
    end

    assert_script_done(mock)
  end

  test "legacy configuration fails before a provider call", %{jido: jido} do
    {mock, context} = mock([])
    assert {:error, _} = Jido.Exec.run(RunStrategy, %{prompt: "Task", strategy: :cot}, bind(context, jido))
    assert_script_done(mock)
  end

  test "Exec cancellation stops the private Session and provider", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :held, {:text, "Late answer"}}}])
    execution = Jido.Exec.run_async(RunStrategy, %{prompt: "Task"}, bind(context, jido), timeout: 8_000)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    [{_, server}] = Jido.list_agents(jido)
    session = Server.children(server)[{:plugin, Jido.AI.Session.Plugin}].pid
    refs = for pid <- [server, session, provider], do: {Process.monitor(pid), pid}
    assert :ok = Jido.Exec.cancel(execution)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 2_000)
    assert Jido.list_agents(jido) == []
  end

  defp bind(context, jido) do
    profile =
      Jido.AI.Profile.new!(%{
        id: :review,
        model: MockLLM.model(),
        reasoning: :chain_of_thought,
        instructions: "Use the host facts",
        controls: %{timeout: 5_000},
        requests: %{mode: :session},
        result: %{into: :answer}
      })

    Map.merge(context, %{
      jido: jido,
      jido_ai_callable_profile: profile,
      ai: Map.put(context.ai, :review, %{options: context.model_options})
    })
  end
end
