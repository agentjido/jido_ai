Code.require_file("../support/agents/corpus.exs", __DIR__)

defmodule JidoAITest.Authoring.Agents.OpenFindingsTest do
  use ExUnit.Case, async: false
  @moduletag :authoring
  alias JidoAITest.Authoring.Agents.Corpus

  # Keep the finding IDs and file path stable for review. All tests assert fixes.
  @tag bug: "AI-AUTH-006"
  test "AI-AUTH-006: block metadata composes with max_state_size" do
    Code.compile_string("""
    defmodule JidoAITest.Authoring.Agents.Fixtures.SizedBlockMetadata do
      use Jido.AI.Agent, name: "sized_block", max_state_size: 4096
      agent do
        schema Zoi.object(%{})
        metadata %{owner: "author"}
      end
    end
    """)

    module = JidoAITest.Authoring.Agents.Fixtures.SizedBlockMetadata
    assert apply(module, :definition, []).metadata == %{owner: "author", jido_ai_max_state_size: 4096}
  end

  @tag bug: "AI-AUTH-007"
  test "AI-AUTH-007: public export returns a structured error for rich model records" do
    spec = Corpus.load!(:simple)
    definition = Corpus.definition(spec, :map)

    for format <- [:map, :json, :yaml] do
      assert {:error, %Jido.AI.Error.Validation.Invalid{field: "models.default.model"} = error} =
               Jido.AI.export(definition, format, registries: %{schemas: %{"domain" => definition.schema}})

      assert Exception.message(error) =~ "core Agent Codec with a Registry"
    end
  end

  @tag bug: "AI-AUTH-009"
  test "AI-AUTH-009: required MCP source rejects native execution before model work" do
    spec = Corpus.load!(:simple)

    profiles =
      Enum.map(
        spec.profiles,
        &Map.put(&1, :tool_sources, [
          %{kind: :mcp_tools, endpoint: :authoring_missing_endpoint, required: true, discover: true}
        ])
      )

    assert {:ok, definition} = Jido.AI.Authoring.lower(spec.attrs, profiles)
    assert [%{required: true}] = Jido.AI.Agent.profile(definition, :assistant).tool_sources
    jido = :"authoring_source_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    mock = start_supervised!({Jido.AI.Test.MockLLM, script: []})
    {:ok, server} = Jido.start_agent(jido, definition)
    signal = Jido.Signal.new!("case.assistant", %{query: "Use required tools"}, source: "/authoring")

    before = Jido.AgentServer.snapshot(server)

    assert {:error, %Jido.AI.Error.Validation.Invalid{field: "tool_sources"}} =
             Jido.AgentServer.call(server, signal,
               context: %{ai: %{assistant: %{options: Jido.AI.Test.MockLLM.options(mock)}}},
               timeout: 10_000
             )

    assert Jido.AgentServer.snapshot(server) === before
    assert %{remaining: [], unexpected: [], requests: []} = Jido.AI.Test.MockLLM.report(mock)
  end

  @tag bug: "AI-AUTH-008"
  test "AI-AUTH-008: core instantiation enforces an authored AI state-size limit" do
    spec = Corpus.load!(:simple)
    attrs = Map.update!(spec.attrs, :metadata, &Map.put(&1, Jido.AI.Authoring.state_size_key(), 4096))
    {:ok, definition} = Jido.AI.Authoring.lower(attrs, spec.profiles)
    oversized = %{reply: String.duplicate("x", 5000)}

    for result <- [
          Jido.AI.Agent.from_initial_state(definition, oversized),
          Jido.Agent.instantiate(definition, state: oversized)
        ] do
      assert {:error, error} = result
      assert Jido.AI.Authoring.state_size_error?(error)
    end

    assert Jido.AI.Authoring.state_size_limit(definition) == 4096
  end
end
