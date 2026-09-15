defmodule JidoAI.Examples.MethodAPITest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Request, Orchestration}
  alias Jido.AI.Reasoning.{ChainOfDraft, ChainOfThought}

  defp start(jido) do
    assert {:ok, definition} = JidoAI.Examples.MethodAPI.definition()
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp context(mock),
    do: %{ai: Map.new([:cot, :cod], &{&1, %{options: MockLLM.options(mock)}})}

  defp request(server, mock, method) do
    Request.create_and_send(server, "Solve",
      signal_type: "ai.#{method}.query",
      source: "/examples/method-api",
      context: context(mock)
    )
  end

  test "namespace method selection runs both profiles and reads their separate stored results", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:text, "Step 1: Add.\nConclusion: 4"}},
        %{reply: {:text, "1. Sum.\n#### 5"}}
      ])

    server = start(jido)
    assert ChainOfThought.get_steps(Server.agent(server)) == []
    assert ChainOfDraft.get_conclusion(Server.agent(server)) == nil
    assert {:ok, cot} = request(server, mock, :cot)
    assert {:ok, "4"} = Request.await(cot)
    assert {:ok, cod} = request(server, mock, :cod)
    assert {:ok, "5"} = Request.await(cod)
    agent = Server.agent(server)
    assert ChainOfThought.get_steps(agent) == [%{number: 1, content: "Add."}]
    assert ChainOfDraft.get_steps(agent) == [%{number: 1, content: "Sum."}]
    assert ChainOfThought.get_conclusion(agent, cot.id) == "4"
    assert ChainOfDraft.get_conclusion(agent, cod.id) == "5"
    assert ChainOfThought.get_raw_response(agent) == "Step 1: Add.\nConclusion: 4"
    assert ChainOfDraft.get_raw_response(agent) == "1. Sum.\n#### 5"
    assert ChainOfThought.get_steps(agent, cod.id) == []
    assert ChainOfDraft.get_raw_response(agent, "missing") == nil
    [first, second] = MockLLM.report(mock).requests
    assert hd(first.body["messages"])["content"] == ChainOfThought.default_system_prompt()
    assert hd(second.body["messages"])["content"] == ChainOfDraft.default_system_prompt()
    assert_script_done(mock)
  end

  test "a new pending or cancelled request cannot expose an earlier result as current", %{
    jido: jido
  } do
    {mock, _} =
      mock([
        %{reply: {:text, "Conclusion: first"}},
        %{reply: {:stream, [{:wait, :held}, %{content: "Conclusion: late"}], "stop"}}
      ])

    server = start(jido)
    assert {:ok, first} = request(server, mock, :cot)
    assert {:ok, "first"} = Request.await(first)
    assert {:ok, next} = request(server, mock, :cot)
    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    monitor = Process.monitor(provider)
    agent = Server.agent(server)
    assert ChainOfThought.get_conclusion(agent) == nil
    assert ChainOfThought.get_steps(agent) == []
    assert ChainOfThought.get_conclusion(agent, first.id) == "first"
    assert :ok = Orchestration.cancel(next)
    assert {:error, :cancelled} = Request.await(next)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert ChainOfThought.get_raw_response(Server.agent(server)) == nil
    assert_script_done(mock)
  end
end
