defmodule Jido.AI.Reasoning.TreeOfThoughts.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Agent.StateOp
  alias Jido.AI.Reasoning.TreeOfThoughts.Strategy, as: TreeOfThoughts

  # Helper to create a mock agent
  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = TreeOfThoughts.init(agent, ctx)
      agent
    end)
  end

  defmodule OrderingSlowTool do
    use Jido.Action,
      name: "ordering_slow_tool",
      description: "Ordering test slow tool",
      schema: Zoi.object(%{})

    def run(_params, _context), do: {:ok, %{tool: :slow}}
  end

  defmodule OrderingFastTool do
    use Jido.Action,
      name: "ordering_fast_tool",
      description: "Ordering test fast tool",
      schema: Zoi.object(%{})

    def run(_params, _context), do: {:ok, %{tool: :fast}}
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
      assert is_map(state[:config])
    end

    test "uses default model when not specified" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:config].model == Jido.AI.resolve_model(:fast)
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

    test "uses custom branching_factor when provided" do
      agent = create_agent(branching_factor: 5)
      state = StratState.get(agent, %{})

      assert state[:config].branching_factor == 5
      assert state[:branching_factor] == 5
    end

    test "uses custom max_depth when provided" do
      agent = create_agent(max_depth: 4)
      state = StratState.get(agent, %{})

      assert state[:config].max_depth == 4
      assert state[:max_depth] == 4
    end

    test "uses custom traversal_strategy when provided" do
      agent = create_agent(traversal_strategy: :dfs)
      state = StratState.get(agent, %{})

      assert state[:config].traversal_strategy == :dfs
      assert state[:traversal_strategy] == :dfs
    end

    test "uses default values when not provided" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:branching_factor] == 3
      assert state[:max_depth] == 3
      assert state[:traversal_strategy] == :best_first
      assert state[:top_k] == 3
      assert state[:min_depth] == 2
      assert state[:max_nodes] == 100
      assert state[:max_duration_ms] == nil
      assert state[:beam_width] == nil
      assert state[:config].max_tool_round_trips == 3
      assert state[:config].tool_timeout_ms == 15_000
      assert state[:config].tool_max_retries == 1
      assert state[:config].tool_retry_backoff_ms == 200
    end

    test "uses custom structured controls when provided" do
      agent =
        create_agent(
          top_k: 4,
          min_depth: 1,
          max_nodes: 55,
          max_duration_ms: 1_500,
          beam_width: 2,
          early_success_threshold: 0.9,
          convergence_window: 3,
          min_score_improvement: 0.01,
          max_parse_retries: 2,
          max_tool_round_trips: 4
        )

      state = StratState.get(agent, %{})

      assert state[:top_k] == 4
      assert state[:min_depth] == 1
      assert state[:max_nodes] == 55
      assert state[:max_duration_ms] == 1_500
      assert state[:beam_width] == 2
      assert state[:config].early_success_threshold == 0.9
      assert state[:config].convergence_window == 3
      assert state[:config].min_score_improvement == 0.01
      assert state[:config].max_parse_retries == 2
      assert state[:config].max_tool_round_trips == 4
    end
  end

  # ============================================================================
  # Action Specs
  # ============================================================================

  describe "action_spec/1" do
    test "returns spec for start action" do
      spec = TreeOfThoughts.action_spec(TreeOfThoughts.start_action())
      assert spec.name == "tot.start"
      assert spec.doc =~ "Tree-of-Thoughts"
    end

    test "returns spec for llm_result action" do
      spec = TreeOfThoughts.action_spec(TreeOfThoughts.llm_result_action())
      assert spec.name == "tot.llm_result"
    end

    test "returns spec for llm_partial action" do
      spec = TreeOfThoughts.action_spec(TreeOfThoughts.llm_partial_action())
      assert spec.name == "tot.llm_partial"
    end

    test "returns nil for unknown action" do
      assert TreeOfThoughts.action_spec(:unknown) == nil
    end
  end

  # ============================================================================
  # Signal Routes
  # ============================================================================

  describe "signal_routes/1" do
    test "returns expected signal routes" do
      routes = TreeOfThoughts.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["ai.tot.query"] == {:strategy_cmd, :tot_start}
      assert route_map["ai.llm.response"] == {:strategy_cmd, :tot_llm_result}
      assert route_map["ai.llm.delta"] == {:strategy_cmd, :tot_llm_partial}
      assert route_map["ai.tool.result"] == {:strategy_cmd, :tot_tool_result}
      assert route_map["ai.request.error"] == {:strategy_cmd, :tot_request_error}
    end
  end

  # ============================================================================
  # cmd/3 - Start Instruction
  # ============================================================================

  describe "cmd/3 with start instruction" do
    test "processes start instruction and returns directive" do
      agent = create_agent()

      instruction = %Jido.Instruction{
        action: TreeOfThoughts.start_action(),
        params: %{prompt: "Solve the puzzle"}
      }

      {agent, directives} = TreeOfThoughts.cmd(agent, [instruction], %{})

      # Should have transitioned to generating
      state = StratState.get(agent, %{})
      assert state[:status] == :generating
      assert state[:prompt] == "Solve the puzzle"

      # Should have returned a LLMStream directive
      assert length(directives) == 1
      [directive] = directives
      assert directive.__struct__ == Jido.AI.Directive.LLMStream
    end

    test "directive contains correct model from config" do
      agent = create_agent(model: "test:model")

      instruction = %Jido.Instruction{
        action: TreeOfThoughts.start_action(),
        params: %{prompt: "Test"}
      }

      {_agent, [directive]} = TreeOfThoughts.cmd(agent, [instruction], %{})

      assert directive.model == "test:model"
    end

    test "creates root node on start" do
      agent = create_agent()

      instruction = %Jido.Instruction{
        action: TreeOfThoughts.start_action(),
        params: %{prompt: "Problem to solve"}
      }

      {agent, _directives} = TreeOfThoughts.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      assert state[:root_id] != nil
      assert Map.has_key?(state[:nodes], state[:root_id])

      root = state[:nodes][state[:root_id]]
      assert root.content == "Problem to solve"
      assert root.depth == 0
    end
  end

  # ============================================================================
  # cmd/3 - LLM Result Instruction
  # ============================================================================

  describe "cmd/3 with llm_result instruction" do
    test "processes thoughts from LLM response" do
      agent = create_agent()

      # First start exploration
      start_instruction = %Jido.Instruction{
        action: TreeOfThoughts.start_action(),
        params: %{prompt: "Solve puzzle"}
      }

      {agent, _} = TreeOfThoughts.cmd(agent, [start_instruction], %{})

      # Get the call_id
      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      # Now send result with thoughts
      result_instruction = %Jido.Instruction{
        action: TreeOfThoughts.llm_result_action(),
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "1. Approach A\n2. Approach B\n3. Approach C"}}
        }
      }

      {agent, directives} = TreeOfThoughts.cmd(agent, [result_instruction], %{})

      state = StratState.get(agent, %{})
      # Should now be evaluating the thoughts
      assert state[:status] == :evaluating
      assert length(state[:pending_thoughts]) == 3

      # Should have an evaluation directive
      assert length(directives) == 1
    end
  end

  describe "tool round ordering" do
    test "applies effects and builds follow-up tool messages in original call order" do
      agent = create_agent(tools: [OrderingSlowTool, OrderingFastTool])

      turn =
        Jido.AI.Turn.from_result_map(%{
          type: :tool_calls,
          text: "Tool round",
          tool_calls: [
            %{id: "call_1", name: OrderingSlowTool.name(), arguments: %{}},
            %{id: "call_2", name: OrderingFastTool.name(), arguments: %{}}
          ],
          usage: %{}
        })

      state = StratState.get(agent, %{})

      configured_state =
        state
        |> Map.put(:pending_tool_calls, %{
          "call_1" => %{call_id: "call_1", tool_name: OrderingSlowTool.name(), arguments: %{}},
          "call_2" => %{call_id: "call_2", tool_name: OrderingFastTool.name(), arguments: %{}}
        })
        |> Map.put(:pending_tool_call_order, ["call_1", "call_2"])
        |> Map.put(:pending_tool_results, %{})
        |> Map.put(:pending_tool_call_id, "llm_order_1")
        |> Map.put(:pending_tool_turn, turn)
        |> Map.put(:llm_call_aliases, %{
          "llm_order_1" => [
            %{role: :user, content: "Order test"}
          ]
        })
        |> Map.put(:config, Map.merge(state[:config] || %{}, %{model: "test:model"}))

      agent = StratState.put(agent, configured_state)

      second_result_instruction = %Jido.Instruction{
        action: TreeOfThoughts.tool_result_action(),
        params: %{
          call_id: "call_2",
          tool_name: OrderingFastTool.name(),
          result: {:ok, %{tool: :fast}, [%StateOp.SetState{attrs: %{tot_order_marker: 2}}]}
        }
      }

      {agent, directives} = TreeOfThoughts.cmd(agent, [second_result_instruction], %{})
      assert directives == []
      refute Map.has_key?(agent.state, :tot_order_marker)

      first_result_instruction = %Jido.Instruction{
        action: TreeOfThoughts.tool_result_action(),
        params: %{
          call_id: "call_1",
          tool_name: OrderingSlowTool.name(),
          result: {:ok, %{tool: :slow}, [%StateOp.SetState{attrs: %{tot_order_marker: 1}}]}
        }
      }

      {agent, [followup_directive]} = TreeOfThoughts.cmd(agent, [first_result_instruction], %{})
      assert %Jido.AI.Directive.LLMStream{} = followup_directive
      assert agent.state.tot_order_marker == 2

      assert tool_message_ids(followup_directive.context) == ["call_1", "call_2"]
    end
  end

  # ============================================================================
  # Snapshot
  # ============================================================================

  describe "snapshot/2" do
    test "returns idle snapshot for new agent" do
      agent = create_agent()
      snapshot = TreeOfThoughts.snapshot(agent, %{})

      assert snapshot.status == :idle
      assert snapshot.done? == false
    end

    test "returns running snapshot during exploration" do
      agent = create_agent()

      start = %Jido.Instruction{action: :tot_start, params: %{prompt: "Test"}}
      {agent, _} = TreeOfThoughts.cmd(agent, [start], %{})

      snapshot = TreeOfThoughts.snapshot(agent, %{})

      assert snapshot.status == :running
      assert snapshot.done? == false
      assert snapshot.details[:phase] == :generating
    end

    test "includes tree details in snapshot" do
      agent = create_agent(branching_factor: 4, max_depth: 5, traversal_strategy: :dfs)

      snapshot = TreeOfThoughts.snapshot(agent, %{})

      assert snapshot.details[:branching_factor] == 4
      assert snapshot.details[:max_depth] == 5
      assert snapshot.details[:traversal_strategy] == :dfs
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  describe "get_nodes/1" do
    test "returns nodes from agent state" do
      agent = create_agent()

      start = %Jido.Instruction{action: :tot_start, params: %{prompt: "Test"}}
      {agent, _} = TreeOfThoughts.cmd(agent, [start], %{})

      nodes = TreeOfThoughts.get_nodes(agent)
      assert is_map(nodes)
      # Just root initially
      assert map_size(nodes) == 1
    end

    test "returns empty map for agent without nodes" do
      agent = create_agent()
      nodes = TreeOfThoughts.get_nodes(agent)
      assert nodes == %{}
    end
  end

  describe "get_solution_path/1" do
    test "returns empty list for agent without solution" do
      agent = create_agent()
      path = TreeOfThoughts.get_solution_path(agent)
      assert path == []
    end
  end

  describe "get_result/1" do
    test "returns nil for agent without result" do
      agent = create_agent()
      assert TreeOfThoughts.get_result(agent) == nil
    end
  end

  # ============================================================================
  # Action Helper Functions
  # ============================================================================

  describe "action helper functions" do
    test "start_action/0 returns correct atom" do
      assert TreeOfThoughts.start_action() == :tot_start
    end

    test "llm_result_action/0 returns correct atom" do
      assert TreeOfThoughts.llm_result_action() == :tot_llm_result
    end

    test "llm_partial_action/0 returns correct atom" do
      assert TreeOfThoughts.llm_partial_action() == :tot_llm_partial
    end

    test "tool action helpers return correct atoms" do
      assert TreeOfThoughts.tool_result_action() == :tot_tool_result
    end
  end

  # ============================================================================
  # Traversal Strategy Configuration
  # ============================================================================

  describe "traversal strategy configuration" do
    test "bfs strategy is preserved through init" do
      agent = create_agent(traversal_strategy: :bfs)
      state = StratState.get(agent, %{})

      assert state[:traversal_strategy] == :bfs
    end

    test "dfs strategy is preserved through init" do
      agent = create_agent(traversal_strategy: :dfs)
      state = StratState.get(agent, %{})

      assert state[:traversal_strategy] == :dfs
    end

    test "best_first strategy is preserved through init" do
      agent = create_agent(traversal_strategy: :best_first)
      state = StratState.get(agent, %{})

      assert state[:traversal_strategy] == :best_first
    end
  end

  defp tool_message_ids(context) when is_list(context) do
    context
    |> Enum.filter(fn message ->
      role = Map.get(message, :role, Map.get(message, "role"))
      role in [:tool, "tool"]
    end)
    |> Enum.map(fn message ->
      Map.get(message, :tool_call_id, Map.get(message, "tool_call_id"))
    end)
  end
end
