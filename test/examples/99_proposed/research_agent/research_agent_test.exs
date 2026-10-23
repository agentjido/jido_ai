defmodule JidoAI.Examples.Proposed.ResearchAgentTest do
  use Jido.AI.Test.ReqLLMCase, async: false

  alias Jido.Agent.Directive.Reply
  alias JidoAI.Examples.Proposed.ResearchAgent

  alias JidoAI.Examples.Proposed.ResearchAgent.{
    Agent,
    Ask,
    ResearchFlow,
    SearchSources,
    Turn,
    ValidateRequest,
    Worker
  }

  @moduletag :example

  test "the definition combines the current core and AI DSL" do
    definition = Agent.definition()
    config = Jido.AI.Plugin.config(definition)
    reasoning_path = [host: Jido.AI.Plugin, declaration: :reasoning, role: :flow]

    assert definition.metadata == %{
             category: "proposed",
             purpose: "kitchen_sink_research_example"
           }

    assert config.reasoning == Jido.Flow.Inline.target!(Agent, reasoning_path)

    assert Enum.map(config.tools, &{&1.kind, &1.target, &1.name}) == [
             {:action, SearchSources, "search_sources"},
             {:flow, ResearchFlow, "research_brief"}
           ]

    assert config.controls.input == ValidateRequest
    inline_output = config.controls.output
    assert function_exported?(inline_output, :__jido_inline_action__, 0)

    assert config.controls == %{
             timeout: 30_000,
             max_iterations: 4,
             max_model_calls: 4,
             max_tool_calls: 6,
             input: ValidateRequest,
             output: inline_output
           }

    assert Enum.any?(definition.routes, &(&1.handler == %{kind: :action, target: Turn}))

    assert Enum.any?(
             definition.routes,
             &(&1.handler == %{kind: :forward, target: %{kind: :agent, name: :worker}})
           )

    assert [%{name: :worker, definition: worker}] = definition.topology.agents
    assert worker == Worker

    assert [
             %{
               path: "examples.proposed.research.work.completed",
               from: %{kind: :agent, name: :worker},
               to: %{kind: :agent, name: :root},
               delivery: :single
             }
           ] = definition.topology.connections
  end

  test "the Flow tool runs local Actions without a model" do
    assert {:ok, result} =
             Jido.Exec.run(ResearchFlow, %{query: "Jido Agent state", limit: 2}, %{})

    assert result.sources == [
             "local://research/jido-agent-state/1",
             "local://research/jido-agent-state/2"
           ]

    assert result.brief ==
             "Research for Jido Agent state: local://research/jido-agent-state/1, " <>
               "local://research/jido-agent-state/2"
  end

  test "each constructor call computes a fresh Session" do
    assert {:ok, first} = ResearchAgent.new(id: "proposed-research-first")
    assert {:ok, second} = ResearchAgent.new(id: "proposed-research-second")

    assert first.initial_state == %{}
    assert second.initial_state == %{}
    refute first.state.session.id == second.state.session.id
    refute first.state.session.thread.id == second.state.session.thread.id
    assert first.state.status == "idle"
    assert first.state.request_count == 0
  end

  test "the routed request applies controls and commits a structured Session turn" do
    expected = %{
      answer: "The DSL composes static definitions before runtime.",
      sources: ["local://research/jido-agent-dsl/1"],
      confidence: 0.9
    }

    expect(ReqLLM, :generate_text, fn model, context, options ->
      assert model == "openai:gpt-4o-mini"
      assert Enum.map(options[:tools], & &1.name) == ["search_sources", "research_brief"]
      assert %ReqLLM.Output{type: :object, schema: schema} = options[:output]
      assert schema == Ask.output_schema()
      assert options[:receive_timeout] in 1..30_000

      {:ok,
       object_response(
         model,
         context,
         %{
           "answer" => expected.answer,
           "sources" => expected.sources,
           "confidence" => expected.confidence
         },
         id: "proposed-research-response"
       )}
    end)

    assert {:ok, agent} = ResearchAgent.new(id: "proposed-research-success")
    request = Ask.new!(%{query: "How does the Jido Agent DSL compose?"})

    assert {:ok, updated, [%Reply{signal: reply}]} =
             Agent.cmd(agent, request, context: %{role: :researcher})

    assert reply.type == "examples.proposed.research.answered"
    assert reply.data == expected
    assert updated.state.status == "ready"
    assert updated.state.last_query == "How does the Jido Agent DSL compose?"
    assert updated.state.request_count == 1
    assert updated.state.session.thread.signals == [request, reply]
  end

  @tag capture_log: true
  test "the module input control rejects a caller before a model request" do
    reject(ReqLLM, :generate_text, 3)

    assert {:ok, agent} = ResearchAgent.new(id: "proposed-research-denied")
    request = Ask.new!(%{query: "Explain the Jido Agent state boundary"})

    assert {:error, _reason} = Agent.cmd(agent, request)
    assert agent.state.session.thread.signals == []
  end
end
