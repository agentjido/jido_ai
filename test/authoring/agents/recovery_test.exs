Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.RecoveryTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias Jido.AI.Test.MockLLM
  alias JidoAITest.Authoring.Agents.Corpus

  setup do
    jido = :"authoring_recovery_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    {:ok, jido: jido}
  end

  for form <- Corpus.forms(), variant <- [:simple, :session] do
    @tag form: form, variant: variant
    test "#{variant}/#{form}: provider failure preserves domain state and permits recovery", ctx do
      spec = Corpus.load!(ctx.variant)

      mock =
        start_supervised!(
          {MockLLM, script: [%{reply: {:error, 400, "Invalid request"}}, %{reply: {:text, "Recovered"}}]}
        )

      context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
      {:ok, server} = Jido.start_agent(ctx.jido, Corpus.definition(spec, ctx.form))
      first = call(server, "failed", context)

      assert {:error, error} = first
      assert is_exception(error) or (is_map(error) and is_binary(error.message))
      assert Jido.AgentServer.agent(server).state.requests["failed"].status == :failed

      state = Jido.AgentServer.agent(server).state
      assert state.reply == ""
      assert state.case_id == "case-17"
      assert length(MockLLM.report(mock).requests) == 1
      assert {:ok, _} = call(server, "next", context)

      assert {:ok, %{status: :completed, result: "Recovered"}} = Jido.AI.Orchestration.await(server, "next", 5_000)

      assert Jido.AgentServer.agent(server).state.reply == "Recovered"
      assert %{remaining: [], unexpected: [], requests: [_, _]} = MockLLM.report(mock)
    end
  end

  for form <- Corpus.forms() do
    @tag form: form
    test "#{form}: invalid tool arguments fail without tool work and permit a new request", %{jido: jido, form: form} do
      spec = Corpus.load!(:tool)

      mock =
        start_supervised!(
          {MockLLM,
           script: [
             %{reply: {:tools, [%{id: "bad-tool", name: "double", arguments: %{value: "not an integer"}}]}},
             %{reply: {:text, "Please supply an integer"}}
           ]}
        )

      context = %{observer: self(), ai: %{assistant: %{options: MockLLM.options(mock)}}}
      {:ok, server} = Jido.start_agent(jido, Corpus.definition(spec, form))
      assert {:error, error} = call(server, "bad-tool", context)
      assert [%{path: [:value], code: :invalid_type}] = error.details.errors
      assert Map.delete(Jido.AgentServer.agent(server).state, :requests) === Map.delete(spec.initial, :requests)
      assert length(MockLLM.report(mock).requests) == 1
      assert {:ok, agent} = call(server, "next", context)

      assert Map.delete(agent.state, :requests) ===
               Map.delete(%{spec.initial | reply: "Please supply an integer"}, :requests)

      refute_received {:authoring_tool, _}
      assert %{remaining: [], unexpected: [], requests: [_, last]} = MockLLM.report(mock)
      refute Enum.any?(last.body["messages"], &(&1["role"] == "tool"))
    end
  end

  defp call(server, id, context) do
    signal = Jido.Signal.new!("case.assistant", %{query: "Help", request_id: id}, source: "/authoring")
    Jido.AI.Test.Requests.call_and_await(server, signal, context: context, timeout: 10_000)
  end
end
