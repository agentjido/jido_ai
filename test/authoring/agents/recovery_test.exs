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

      if ctx.variant == :session do
        assert {:ok, _} = first
        assert {:ok, %{status: :failed, error: error}} = Jido.AI.Session.await(server, "failed", 5_000)
        assert is_exception(error)
        assert Jido.AgentServer.agent(server).state.requests["failed"].status == :failed
      else
        assert {:error, _} = first
      end

      state = Jido.AgentServer.agent(server).state
      assert state.reply == ""
      assert state.case_id == "case-17"
      assert length(MockLLM.report(mock).requests) == 1
      assert {:ok, _} = call(server, "next", context)

      if ctx.variant == :session,
        do: assert({:ok, %{status: :completed, result: "Recovered"}} = Jido.AI.Session.await(server, "next", 5_000))

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
      assert %Jido.Action.Error.InvalidInputError{} = error.details.jido_ai_cause
      assert Jido.AgentServer.agent(server).state === spec.initial
      assert length(MockLLM.report(mock).requests) == 1
      assert {:ok, agent} = call(server, "next", context)
      assert agent.state === %{spec.initial | reply: "Please supply an integer"}
      refute_received {:authoring_tool, _}
      assert %{remaining: [], unexpected: [], requests: [_, last]} = MockLLM.report(mock)
      refute Enum.any?(last.body["messages"], &(&1["role"] == "tool"))
    end
  end

  defp call(server, id, context) do
    signal = Jido.Signal.new!("case.assistant", %{query: "Help", request_id: id}, source: "/authoring")
    Jido.AgentServer.call(server, signal, context: context, timeout: 10_000)
  end
end
