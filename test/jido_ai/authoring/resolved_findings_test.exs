defmodule Jido.AI.Authoring.ResolvedFindingsTest do
  use ExUnit.Case, async: false
  alias Jido.AI.Authoring
  alias Jido.AI.Profile
  alias Jido.AI.Test.MockLLM

  defmodule SizedBlock do
    use Jido.AI.Agent, name: "sized_block_regression", max_state_size: 4096

    agent do
      metadata %{owner: "author"}
      schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

      ai :assistant do
        model MockLLM.model()
        result into: :reply
      end
    end

    routes do
      route "ask", ai: :assistant
    end
  end

  test "block metadata and the size limit survive Builder and Codec" do
    original = SizedBlock.definition()
    assert original.metadata == %{owner: "author", jido_ai_max_state_size: 4096}
    {:ok, document, registry} = Jido.Agent.Codec.encode(original)
    {:ok, decoded} = Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(document)), registry)
    built = Jido.Agent.Builder.new(SizedBlock) |> Jido.Agent.Builder.build!()

    for source <- [original, built, decoded] do
      assert source === original
      assert {:ok, _} = Jido.Agent.instantiate(source)
      assert {:error, error} = Jido.Agent.instantiate(source, state: %{reply: String.duplicate("x", 5000)})
      assert Authoring.state_size_error?(error)
    end
  end

  test "Zoi validates the actual state and includes Plugin-owned fields in its byte limit" do
    agent = SizedBlock.new!()
    size = :erlang.external_size(agent.state)

    for {limit, valid?} <- [{size, true}, {size - 1, false}] do
      {:ok, source} =
        Authoring.lower(
          %{
            name: "byte_boundary",
            schema: Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}),
            metadata: %{jido_ai_max_state_size: limit},
            routes: [{"ask", Authoring.ai(:assistant)}]
          },
          [Profile.new!(id: :assistant, model: MockLLM.model(), result: %{into: :reply})]
        )

      # Use a plain field schema so the fixture's existing 4096-byte refinement
      # cannot account for the exact boundary under test.
      result = Jido.Agent.instantiate(source)
      if valid?, do: assert({:ok, _} = result), else: assert({:error, _} = result)
    end

    assert {:error, error} = Jido.Agent.set(agent, %{reply: String.duplicate("x", 5000)})
    assert Authoring.state_size_error?(error)
    assert agent.state.reply == ""
  end

  test "oversized model output is rejected without a commit and a later request succeeds" do
    jido = :"sized_runtime_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})

    mock =
      start_supervised!({MockLLM, script: [%{reply: {:text, String.duplicate("x", 5000)}}, %{reply: {:text, "Next"}}]})

    {:ok, server} = Jido.start_agent(jido, SizedBlock)
    before = Jido.AgentServer.snapshot(server)
    context = %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
    assert {:error, _} = SizedBlock.ask_sync(server, "Large", context: context)
    state = Jido.AgentServer.agent(server).state
    assert Map.delete(state, :requests) === Map.delete(before.agent.state, :requests)
    assert [{_, %{status: :failed}}] = Map.to_list(state.requests)
    assert {:ok, "Next"} = SizedBlock.ask_sync(server, "Small", context: context)
    assert %{remaining: [], unexpected: [], requests: [_, _]} = MockLLM.report(mock)
  end

  test "stored schemas using the old validate MFA enforce the limit too" do
    schema = Zoi.object(%{reply: Zoi.string()}) |> Zoi.refine({Jido.AI.Execution.StateSize, :validate, [100]})
    assert {:ok, _} = Zoi.parse(schema, %{reply: "Small"})
    assert {:error, errors} = Zoi.parse(schema, %{reply: String.duplicate("x", 200)})
    assert Authoring.state_size_error?(errors)
  end

  test "explicit metadata conflicts remain errors with max_state_size" do
    assert_raise CompileError, ~r/Fields declared in both keyword and block form/, fn ->
      Code.compile_string("""
      defmodule Jido.AI.Authoring.ResolvedFindingsTest.MetadataConflict do
        use Jido.AI.Agent, name: "conflict", max_state_size: 4096, metadata: %{owner: "first"}
        agent do
          metadata %{owner: "second"}
          schema Zoi.object(%{})
        end
      end
      """)
    end
  end

  test "unsupported sources on another profile do not block a static profile" do
    jido = :"selected_source_#{System.unique_integer([:positive])}"
    start_supervised!({Jido, name: jido})
    mock = start_supervised!({MockLLM, script: [%{reply: {:text, "Allowed"}}]})
    static = Profile.new!(id: :assistant, model: MockLLM.model(), result: %{into: :reply})

    dynamic =
      Profile.new!(%{Map.from_struct(static) | id: :dynamic, tool_sources: [%{kind: :browser, name: :missing_browser}]})

    {:ok, definition} =
      Authoring.lower(
        %{
          name: "selected_source",
          schema: Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}),
          routes: [{"ask", Authoring.ai(:assistant)}, {"dynamic", Authoring.ai(:dynamic)}]
        },
        [static, dynamic]
      )

    {:ok, server} = Jido.start_agent(jido, definition)
    signal = Jido.Signal.new!("ask", %{query: "Help"}, source: "/test")

    assert {:ok, agent} =
             Jido.AI.Test.Requests.call_and_await(server, signal,
               context: %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
             )

    assert agent.state.reply == "Allowed"
    assert %{remaining: [], unexpected: [], requests: [_]} = MockLLM.report(mock)
  end

  for format <- [:map, :json, :yaml] do
    @tag format: format
    test "#{format}: rich model export is a structured error for both Profile and Agent", %{format: format} do
      for source <- [SizedBlock.definition(), SizedBlock.ai_profile(:assistant)] do
        assert {:error, %Jido.AI.Error.Validation.Invalid{field: "models.default.model"} = error} =
                 Jido.AI.export(source, format, registries: %{schemas: %{"state" => SizedBlock.schema()}})

        assert Exception.message(error) =~ "core Agent Codec"
      end
    end
  end

  for mode <- [:turn, :session], required <- [true, false] do
    @tag mode: mode, required: required
    test "#{mode}/required=#{required}: unsupported sources cannot reach the provider", ctx do
      jido = :"unsupported_source_#{System.unique_integer([:positive])}"
      start_supervised!({Jido, name: jido})
      mock = start_supervised!({MockLLM, script: []})

      profile =
        Profile.new!(
          id: :assistant,
          model: MockLLM.model(),
          result: %{into: :reply},
          tool_sources: [%{kind: :mcp_tools, endpoint: :missing_regression_endpoint, required: ctx.required}]
        )

      {:ok, definition} =
        Authoring.lower(
          %{
            name: "source_boundary",
            schema: Zoi.object(%{reply: Zoi.string() |> Zoi.default("")}),
            routes: [{"ask", Authoring.ai(:assistant)}]
          },
          [profile]
        )

      {:ok, server} = Jido.start_agent(jido, definition)
      before = Jido.AgentServer.snapshot(server)
      signal = Jido.Signal.new!("ask", %{query: "No", request_id: "rejected"}, source: "/test")

      assert {:error, %Jido.AI.Error.Validation.Invalid{field: "tool_sources"}} =
               Jido.AI.Test.Requests.call_and_await(server, signal,
                 context: %{ai: %{assistant: %{options: MockLLM.options(mock)}}}
               )

      assert Jido.AgentServer.snapshot(server) === before
      assert %{remaining: [], unexpected: [], requests: []} = MockLLM.report(mock)
    end
  end
end
