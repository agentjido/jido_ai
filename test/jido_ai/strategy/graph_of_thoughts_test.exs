defmodule Jido.AI.Strategies.GraphOfThoughtsTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Strategies.GraphOfThoughts

  # Helper to create a mock agent
  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = GraphOfThoughts.init(agent, ctx)
      agent
    end)
  end

  # ============================================================================
  # Action Atoms
  # ============================================================================

  describe "action atoms" do
    test "start_action/0 returns :got_start" do
      assert GraphOfThoughts.start_action() == :got_start
    end

    test "llm_result_action/0 returns :got_llm_result" do
      assert GraphOfThoughts.llm_result_action() == :got_llm_result
    end

    test "llm_partial_action/0 returns :got_llm_partial" do
      assert GraphOfThoughts.llm_partial_action() == :got_llm_partial
    end
  end

  # ============================================================================
  # Initialization
  # ============================================================================

  describe "init/2" do
    test "initializes agent with machine state" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:status] == :idle
      assert state[:nodes] == %{}
      assert state[:edges] == []
      assert is_map(state[:config])
    end

    test "uses default model when not specified" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:config].model == "anthropic:claude-haiku-4-5"
    end

    test "resolves model aliases" do
      agent = create_agent(model: :fast)
      state = StratState.get(agent, %{})

      assert state[:config].model == Jido.AI.resolve_model(:fast)
    end

    test "passes through string model specs" do
      agent = create_agent(model: "openai:gpt-4")
      state = StratState.get(agent, %{})

      assert state[:config].model == "openai:gpt-4"
    end

    test "uses custom max_nodes when provided" do
      agent = create_agent(max_nodes: 10)
      state = StratState.get(agent, %{})

      assert state[:max_nodes] == 10
    end

    test "uses custom max_depth when provided" do
      agent = create_agent(max_depth: 3)
      state = StratState.get(agent, %{})

      assert state[:max_depth] == 3
    end

    test "uses custom aggregation_strategy when provided" do
      agent = create_agent(aggregation_strategy: :voting)
      state = StratState.get(agent, %{})

      assert state[:aggregation_strategy] == :voting
    end
  end

  # ============================================================================
  # Signal Routes
  # ============================================================================

  describe "signal_routes/1" do
    test "returns correct signal routes" do
      routes = GraphOfThoughts.signal_routes(%{})

      assert {"ai.got.query", {:strategy_cmd, :got_start}} in routes
      assert {"ai.llm.response", {:strategy_cmd, :got_llm_result}} in routes
      assert {"ai.llm.delta", {:strategy_cmd, :got_llm_partial}} in routes
    end
  end

  # ============================================================================
  # cmd/3 with start instruction
  # ============================================================================

  describe "cmd/3 with start instruction" do
    test "processes start instruction and returns directive" do
      agent = create_agent()
      instruction = %{action: :got_start, params: %{prompt: "Analyze this problem"}}

      {_agent, directives} = GraphOfThoughts.cmd(agent, [instruction], %{})

      assert length(directives) == 1
      assert %Jido.AI.Directive.LLMStream{} = hd(directives)
    end

    test "directive contains correct model from config" do
      agent = create_agent(model: "anthropic:claude-sonnet-4-20250514")
      instruction = %{action: :got_start, params: %{prompt: "Problem"}}

      {_agent, [directive]} = GraphOfThoughts.cmd(agent, [instruction], %{})

      assert directive.model == "anthropic:claude-sonnet-4-20250514"
    end

    test "updates agent state to generating" do
      agent = create_agent()
      instruction = %{action: :got_start, params: %{prompt: "Problem"}}

      {updated_agent, _} = GraphOfThoughts.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:status] == :generating
    end

    test "creates root node in state" do
      agent = create_agent()
      instruction = %{action: :got_start, params: %{prompt: "Test problem"}}

      {updated_agent, _} = GraphOfThoughts.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert map_size(state[:nodes]) == 1
      assert state[:root_id] != nil
    end
  end

  # ============================================================================
  # cmd/3 with llm_result instruction
  # ============================================================================

  describe "cmd/3 with llm_result instruction" do
    test "processes LLM result with thought generation" do
      agent = create_agent()
      start_instruction = %{action: :got_start, params: %{prompt: "Problem"}}

      {agent, _} = GraphOfThoughts.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      result_instruction = %{
        action: :got_llm_result,
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "Here is my analysis..."}}
        }
      }

      {updated_agent, _} = GraphOfThoughts.cmd(agent, [result_instruction], %{})

      updated_state = StratState.get(updated_agent, %{})
      # Should have created new node
      assert map_size(updated_state[:nodes]) >= 2
    end
  end

  # ============================================================================
  # cmd/3 with llm_partial instruction
  # ============================================================================

  describe "cmd/3 with llm_partial instruction" do
    test "accumulates streaming text" do
      agent = create_agent()
      start_instruction = %{action: :got_start, params: %{prompt: "Problem"}}

      {agent, _} = GraphOfThoughts.cmd(agent, [start_instruction], %{})

      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      partial1 = %{
        action: :got_llm_partial,
        params: %{call_id: call_id, delta: "Hello ", chunk_type: :content}
      }

      partial2 = %{
        action: :got_llm_partial,
        params: %{call_id: call_id, delta: "World", chunk_type: :content}
      }

      {agent, _} = GraphOfThoughts.cmd(agent, [partial1], %{})
      {agent, _} = GraphOfThoughts.cmd(agent, [partial2], %{})

      state = StratState.get(agent, %{})
      assert state[:streaming_text] == "Hello World"
    end
  end

  # ============================================================================
  # snapshot/2
  # ============================================================================

  describe "snapshot/2" do
    test "returns idle snapshot" do
      agent = create_agent()
      snapshot = GraphOfThoughts.snapshot(agent, %{})

      assert snapshot.status == :idle
      assert snapshot.done? == false
    end

    test "returns generating snapshot with node info" do
      agent = create_agent()
      instruction = %{action: :got_start, params: %{prompt: "Problem"}}

      {agent, _} = GraphOfThoughts.cmd(agent, [instruction], %{})

      snapshot = GraphOfThoughts.snapshot(agent, %{})
      assert snapshot.status == :running
      assert snapshot.done? == false
      assert snapshot.details.node_count == 1
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  describe "helper functions" do
    test "get_nodes/1 returns nodes from agent state" do
      agent = create_agent()
      instruction = %{action: :got_start, params: %{prompt: "Problem"}}

      {agent, _} = GraphOfThoughts.cmd(agent, [instruction], %{})

      nodes = GraphOfThoughts.get_nodes(agent)
      assert length(nodes) == 1
    end

    test "get_edges/1 returns edges from agent state" do
      agent = create_agent()
      instruction = %{action: :got_start, params: %{prompt: "Problem"}}

      {agent, _} = GraphOfThoughts.cmd(agent, [instruction], %{})

      # Initially no edges (just root)
      edges = GraphOfThoughts.get_edges(agent)
      assert edges == []
    end

    test "get_result/1 returns nil when not completed" do
      agent = create_agent()
      assert GraphOfThoughts.get_result(agent) == nil
    end

    test "get_best_node/1 returns nil when no scored nodes" do
      agent = create_agent()
      assert GraphOfThoughts.get_best_node(agent) == nil
    end

    test "get_solution_path/1 returns empty when no best leaf" do
      agent = create_agent()
      assert GraphOfThoughts.get_solution_path(agent) == []
    end
  end
end
