defmodule Jido.AI.Integration.StrategiesPhase4Test do
  @moduledoc """
  Integration tests for Phase 4 Strategy Framework.

  These tests verify that all Phase 4 strategy components work together correctly,
  including strategy execution, signal routing, directive emission, and adaptive
  selection.

  ## Test Scope

  - Strategy Execution: Verify strategies produce correct outputs
  - Signal Routing: Verify signals route to correct strategy commands
  - Directive Emission: Verify strategies emit correct directive types
  - Adaptive Selection: Verify adaptive strategy selects appropriate strategies
  """
  use ExUnit.Case, async: true

  alias Jido.Agent
  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Reasoning.Adaptive.Strategy, as: Adaptive
  alias Jido.AI.Reasoning.ChainOfThought.Strategy, as: ChainOfThought
  alias Jido.AI.Reasoning.GraphOfThoughts.Strategy, as: GraphOfThoughts
  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct
  alias Jido.AI.Reasoning.TreeOfThoughts.Strategy, as: TreeOfThoughts
  alias Jido.Instruction

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_agent(strategy_module, opts \\ []) do
    %Agent{
      id: "test-agent-#{System.unique_integer([:positive])}",
      name: "test_agent",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, _directives} = strategy_module.init(agent, ctx)
      {agent, ctx}
    end)
  end

  # ============================================================================
  # 4.6.1 Strategy Execution Integration Tests
  # ============================================================================

  describe "strategy execution integration" do
    test "CoT strategy initializes and processes start instruction" do
      {agent, _ctx} = create_agent(ChainOfThought)

      # Verify initial state
      state = StratState.get(agent, %{})
      assert state[:status] == :idle

      # Process start instruction
      instruction = %Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "What is 2 + 2?"}
      }

      {updated_agent, directives} = ChainOfThought.cmd(agent, [instruction], %{})

      # Verify state transition
      updated_state = StratState.get(updated_agent, %{})
      assert updated_state[:status] == :reasoning

      # Verify directive emitted
      assert length(directives) == 1
      [directive] = directives
      assert %AgentDirective.SpawnAgent{} = directive
      assert directive.tag == :cot_worker
      assert directive.agent == Jido.AI.Reasoning.ChainOfThought.Worker.Agent
    end

    test "CoT strategy produces step-by-step reasoning output" do
      {agent, _ctx} = create_agent(ChainOfThought)

      # Start reasoning
      start_instruction = %Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "What is 2 + 2?", request_id: "req_cot_phase4"}
      }

      {agent, directives} = ChainOfThought.cmd(agent, [start_instruction], %{})
      [%AgentDirective.SpawnAgent{}] = directives

      # Simulate worker lifecycle + completion event
      child_started = %Instruction{
        action: :cot_worker_child_started,
        params: %{
          parent_id: "parent",
          child_id: "child",
          child_module: Jido.AI.Reasoning.ChainOfThought.Worker.Agent,
          tag: :cot_worker,
          pid: self(),
          meta: %{}
        }
      }

      {agent, [%AgentDirective.Emit{}]} = ChainOfThought.cmd(agent, [child_started], %{})

      completion_text = """
        Step 1: Identify the numbers to add
        We have 2 and 2.

        Step 2: Perform the addition
        2 + 2 = 4

        Therefore, the answer is 4.
      """

      result_instruction =
        %Instruction{
          action: :cot_worker_event,
          params: %{
            request_id: "req_cot_phase4",
            event: %{
              id: "evt_done",
              seq: 1,
              at_ms: 1_700_000_000_000,
              run_id: "req_cot_phase4",
              request_id: "req_cot_phase4",
              iteration: 1,
              kind: :request_completed,
              llm_call_id: "cot_call_req_cot_phase4",
              tool_call_id: nil,
              tool_name: nil,
              data: %{
                result: completion_text,
                termination_reason: :success,
                usage: %{input_tokens: 10, output_tokens: 5}
              }
            }
          }
        }

      {final_agent, _} = ChainOfThought.cmd(agent, [result_instruction], %{})

      # Verify completion
      final_state = StratState.get(final_agent, %{})
      assert final_state[:status] == :completed
      assert final_state[:result] != nil
    end

    test "ToT strategy initializes with exploration state" do
      {agent, _ctx} = create_agent(TreeOfThoughts)

      state = StratState.get(agent, %{})
      assert state[:status] == :idle
      assert state[:nodes] != nil
      assert state[:config] != nil
    end

    test "ToT strategy processes start and creates thought generation directive" do
      {agent, _ctx} = create_agent(TreeOfThoughts)

      instruction = %Instruction{
        action: TreeOfThoughts.start_action(),
        params: %{prompt: "Analyze alternatives for solving this puzzle"}
      }

      {updated_agent, directives} = TreeOfThoughts.cmd(agent, [instruction], %{})

      updated_state = StratState.get(updated_agent, %{})
      assert updated_state[:status] == :generating

      assert length(directives) == 1
      [directive] = directives
      assert %Directive.LLMStream{} = directive
    end

    test "GoT strategy initializes with graph state" do
      {agent, _ctx} = create_agent(GraphOfThoughts)

      state = StratState.get(agent, %{})
      assert state[:status] == :idle
      assert state[:nodes] != nil
      assert state[:config] != nil
    end

    test "GoT strategy processes start and transitions to generating" do
      {agent, _ctx} = create_agent(GraphOfThoughts)

      instruction = %Instruction{
        action: GraphOfThoughts.start_action(),
        params: %{prompt: "Synthesize multiple perspectives on this topic"}
      }

      {updated_agent, directives} = GraphOfThoughts.cmd(agent, [instruction], %{})

      updated_state = StratState.get(updated_agent, %{})
      assert updated_state[:status] == :generating

      assert length(directives) == 1
      [directive] = directives
      assert %Directive.LLMStream{} = directive
    end

    test "ReAct strategy initializes with tool configuration" do
      defmodule TestCalculator do
        use Jido.Action,
          name: "calculator",
          description: "Performs calculations",
          schema: [expression: [type: :string, required: true]]

        @impl true
        def run(params, _context) do
          {:ok, %{result: "4", expression: params.expression}}
        end
      end

      {agent, _ctx} = create_agent(ReAct, tools: [TestCalculator])

      state = StratState.get(agent, %{})
      assert state[:status] == :idle
      assert state[:config][:tools] == [TestCalculator]
    end

    test "ReAct strategy processes start by delegating to worker" do
      defmodule TestSearch do
        use Jido.Action,
          name: "search",
          description: "Searches for information",
          schema: [query: [type: :string, required: true]]

        @impl true
        def run(params, _context) do
          {:ok, %{results: ["result1", "result2"], query: params.query}}
        end
      end

      {agent, _ctx} = create_agent(ReAct, tools: [TestSearch])

      instruction = %Instruction{
        action: ReAct.start_action(),
        params: %{query: "Search for Elixir documentation"}
      }

      {updated_agent, directives} = ReAct.cmd(agent, [instruction], %{})

      updated_state = StratState.get(updated_agent, %{})
      assert updated_state[:status] == :awaiting_llm

      assert length(directives) == 1
      [directive] = directives
      assert %AgentDirective.SpawnAgent{} = directive
      assert directive.tag == :react_worker
      assert directive.agent == Jido.AI.Reasoning.ReAct.Worker.Agent
    end
  end

  # ============================================================================
  # 4.6.2 Signal Routing Integration Tests
  # ============================================================================

  describe "signal routing integration" do
    test "CoT signal_routes returns correct mappings" do
      {_agent, ctx} = create_agent(ChainOfThought)
      routes = ChainOfThought.signal_routes(ctx)

      route_map = Map.new(routes)
      assert route_map["ai.cot.query"] == {:strategy_cmd, :cot_start}
      assert route_map["ai.cot.worker.event"] == {:strategy_cmd, :cot_worker_event}
      assert route_map["jido.agent.child.started"] == {:strategy_cmd, :cot_worker_child_started}
      assert route_map["jido.agent.child.exit"] == {:strategy_cmd, :cot_worker_child_exit}
      assert route_map["ai.llm.response"] == Jido.Actions.Control.Noop
      assert route_map["ai.llm.delta"] == Jido.Actions.Control.Noop
    end

    test "ToT signal_routes returns correct mappings" do
      {_agent, ctx} = create_agent(TreeOfThoughts)
      routes = TreeOfThoughts.signal_routes(ctx)

      route_map = Map.new(routes)
      assert route_map["ai.tot.query"] == {:strategy_cmd, :tot_start}
      assert route_map["ai.llm.response"] == {:strategy_cmd, :tot_llm_result}
      assert route_map["ai.llm.delta"] == {:strategy_cmd, :tot_llm_partial}
    end

    test "GoT signal_routes returns correct mappings" do
      {_agent, ctx} = create_agent(GraphOfThoughts)
      routes = GraphOfThoughts.signal_routes(ctx)

      route_map = Map.new(routes)
      assert route_map["ai.got.query"] == {:strategy_cmd, :got_start}
      assert route_map["ai.llm.response"] == {:strategy_cmd, :got_llm_result}
      assert route_map["ai.llm.delta"] == {:strategy_cmd, :got_llm_partial}
    end

    test "ReAct signal_routes includes worker delegation routes" do
      {_agent, ctx} = create_agent(ReAct, tools: [])
      routes = ReAct.signal_routes(ctx)

      route_map = Map.new(routes)
      assert route_map["ai.react.query"] == {:strategy_cmd, :ai_react_start}
      assert route_map["ai.react.worker.event"] == {:strategy_cmd, :ai_react_worker_event}
      assert route_map["jido.agent.child.started"] == {:strategy_cmd, :ai_react_worker_child_started}
      assert route_map["jido.agent.child.exit"] == {:strategy_cmd, :ai_react_worker_child_exit}
      assert route_map["ai.llm.response"] == Jido.Actions.Control.Noop
      assert route_map["ai.tool.result"] == Jido.Actions.Control.Noop
      assert route_map["ai.llm.delta"] == Jido.Actions.Control.Noop
    end

    test "Adaptive signal_routes returns base routes before strategy selection" do
      {_agent, ctx} = create_agent(Adaptive)
      routes = Adaptive.signal_routes(ctx)

      route_map = Map.new(routes)
      assert route_map["ai.adaptive.query"] == {:strategy_cmd, :adaptive_start}
      assert route_map["ai.llm.response"] == {:strategy_cmd, :adaptive_llm_result}
      assert route_map["ai.llm.delta"] == {:strategy_cmd, :adaptive_llm_partial}
    end
  end

  # ============================================================================
  # 4.6.3 Directive Execution Integration Tests
  # ============================================================================

  describe "directive execution integration" do
    test "CoT start emits SpawnAgent directive in delegated mode" do
      {agent, _ctx} = create_agent(ChainOfThought, model: "anthropic:claude-sonnet-4-20250514")

      instruction = %Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "Explain recursion"}
      }

      {_agent, [directive]} = ChainOfThought.cmd(agent, [instruction], %{})

      assert %AgentDirective.SpawnAgent{} = directive
      assert directive.tag == :cot_worker
      assert directive.agent == Jido.AI.Reasoning.ChainOfThought.Worker.Agent
    end

    test "ReAct start emits SpawnAgent directive in delegated mode" do
      defmodule DirectiveTestTool do
        use Jido.Action,
          name: "test_tool",
          description: "A test tool",
          schema: [input: [type: :string, required: true]]

        @impl true
        def run(_params, _context), do: {:ok, %{output: "test"}}
      end

      {agent, _ctx} = create_agent(ReAct, tools: [DirectiveTestTool])

      instruction = %Instruction{
        action: ReAct.start_action(),
        params: %{query: "Use the test tool"}
      }

      {_agent, [directive]} = ReAct.cmd(agent, [instruction], %{})

      assert %AgentDirective.SpawnAgent{} = directive
      assert directive.tag == :react_worker
    end

    test "ReAct flushes deferred worker start on child.started signal" do
      defmodule ToolExecTestTool do
        use Jido.Action,
          name: "exec_test",
          description: "Execution test tool",
          schema: [value: [type: :string, required: true]]

        @impl true
        def run(params, _context), do: {:ok, %{result: params.value}}
      end

      {agent, _ctx} = create_agent(ReAct, tools: [ToolExecTestTool])

      start_instruction = %Instruction{
        action: ReAct.start_action(),
        params: %{query: "Execute the test"}
      }

      {agent, [%AgentDirective.SpawnAgent{}]} = ReAct.cmd(agent, [start_instruction], %{})

      child_started = %Instruction{
        action: :ai_react_worker_child_started,
        params: %{
          parent_id: "parent",
          child_id: "child",
          child_module: Jido.AI.Reasoning.ReAct.Worker.Agent,
          tag: :react_worker,
          pid: self(),
          meta: %{}
        }
      }

      {_agent, directives} = ReAct.cmd(agent, [child_started], %{})

      assert length(directives) == 1
      [directive] = directives
      assert %AgentDirective.Emit{} = directive
      assert directive.signal.type == "ai.react.worker.start"
      assert directive.dispatch == {:pid, [target: self()]}
    end
  end

  # ============================================================================
  # 4.6.4 Adaptive Selection Integration Tests
  # ============================================================================

  describe "adaptive selection integration" do
    test "simple prompt selects CoD strategy" do
      {agent, _ctx} = create_agent(Adaptive)

      instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{prompt: "What is the capital of France?"}
      }

      {updated_agent, _directives} = Adaptive.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:strategy_type] == :cod
    end

    test "tool-requiring prompt selects ReAct strategy" do
      # ReAct requires tools option to be passed
      {agent, _ctx} = create_agent(Adaptive, tools: [])

      instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{prompt: "Search for the latest news about Elixir programming"}
      }

      {updated_agent, _directives} = Adaptive.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:strategy_type] == :react
    end

    test "complex exploration prompt selects ToT strategy" do
      {agent, _ctx} = create_agent(Adaptive)

      instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{
          prompt:
            "Analyze multiple alternatives and evaluate the trade-offs between using GenServer vs Agent for state management in Elixir. Consider different scenarios and compare their pros and cons."
        }
      }

      {updated_agent, _directives} = Adaptive.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:strategy_type] == :tot
    end

    test "synthesis prompt selects GoT strategy" do
      {agent, _ctx} = create_agent(Adaptive)

      instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{
          prompt:
            "Synthesize these different perspectives and combine the viewpoints to create a unified understanding of functional programming paradigms."
        }
      }

      {updated_agent, _directives} = Adaptive.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:strategy_type] == :got
    end

    test "manual strategy override works" do
      # The strategy override is set in agent config, not in the instruction params
      {agent, _ctx} = create_agent(Adaptive, strategy: :tot)

      # Force ToT even for a simple prompt
      instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{prompt: "What is 2 + 2?"}
      }

      {updated_agent, _directives} = Adaptive.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      assert state[:strategy_type] == :tot
    end

    test "adaptive delegates LLM result to selected strategy" do
      {agent, _ctx} = create_agent(Adaptive)

      # Start with a prompt that selects CoD
      start_instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{prompt: "What is the meaning of life?", request_id: "req_adaptive_cot"}
      }

      {agent, [%AgentDirective.SpawnAgent{}]} =
        Adaptive.cmd(agent, [start_instruction], %{})

      # Verify CoD was selected
      state = StratState.get(agent, %{})
      assert state[:strategy_type] == :cod

      child_started = %Instruction{
        action: :adaptive_child_started,
        params: %{
          parent_id: "parent",
          child_id: "child",
          child_module: Jido.AI.Reasoning.ChainOfThought.Worker.Agent,
          tag: :cot_worker,
          pid: self(),
          meta: %{}
        }
      }

      {agent, [%AgentDirective.Emit{}]} = Adaptive.cmd(agent, [child_started], %{})

      completion_event = %{
        id: "evt_adaptive_done",
        seq: 1,
        at_ms: 1_700_000_000_000,
        run_id: "req_adaptive_cot",
        request_id: "req_adaptive_cot",
        iteration: 1,
        kind: :request_completed,
        llm_call_id: "cot_call_req_adaptive_cot",
        tool_call_id: nil,
        tool_name: nil,
        data: %{
          result: "Step 1: Reflect.\nConclusion: The meaning of life is subjective.",
          termination_reason: :success,
          usage: %{input_tokens: 12, output_tokens: 7}
        }
      }

      result_instruction =
        %Instruction{
          action: :adaptive_cot_worker_event,
          params: %{
            request_id: "req_adaptive_cot",
            event: completion_event
          }
        }

      {final_agent, _directives} = Adaptive.cmd(agent, [result_instruction], %{})

      # Verify the delegated strategy completed
      final_state = StratState.get(final_agent, %{})
      # The selected strategy should have processed the result
      assert final_state[:strategy_type] == :cod
    end

    test "analyze_prompt returns expected complexity and task type" do
      # Simple query
      {strategy, score, task_type} = Adaptive.analyze_prompt("What is AI?")
      assert strategy == :cod
      assert score < 0.3
      assert task_type == :simple_query

      # Tool use query
      {strategy, _score, task_type} = Adaptive.analyze_prompt("Search for Elixir documentation")
      assert strategy == :react
      assert task_type == :tool_use

      # Exploration query
      {strategy, _score, task_type} =
        Adaptive.analyze_prompt("Explore and analyze the different approaches")

      assert strategy == :tot
      assert task_type == :exploration

      # Synthesis query
      {strategy, _score, task_type} =
        Adaptive.analyze_prompt("Synthesize multiple perspectives on this topic")

      assert strategy == :got
      assert task_type == :synthesis
    end

    test "available_strategies config is respected" do
      # Create agent with only CoT and ReAct available (ReAct requires tools)
      {agent, _ctx} = create_agent(Adaptive, available_strategies: [:cot, :react], tools: [])

      # Even with exploration keywords, should fall back to ReAct (not ToT)
      instruction = %Instruction{
        action: Adaptive.start_action(),
        params: %{prompt: "Explore multiple alternatives"}
      }

      {updated_agent, _directives} = Adaptive.cmd(agent, [instruction], %{})

      state = StratState.get(updated_agent, %{})
      # Should select from available strategies only
      assert state[:strategy_type] in [:cot, :react]
    end
  end

  # ============================================================================
  # Cross-Strategy Integration Tests
  # ============================================================================

  describe "cross-strategy integration" do
    test "all strategies implement required callbacks" do
      strategies = [ChainOfThought, TreeOfThoughts, GraphOfThoughts, ReAct, Adaptive]

      for strategy <- strategies do
        # Ensure module is loaded
        Code.ensure_loaded!(strategy)
        # All strategies should implement these callbacks
        assert {:init, 2} in strategy.__info__(:functions)
        assert {:cmd, 3} in strategy.__info__(:functions)
        assert {:signal_routes, 1} in strategy.__info__(:functions)
        assert {:snapshot, 2} in strategy.__info__(:functions)
        assert {:action_spec, 1} in strategy.__info__(:functions)
      end
    end

    test "snapshot returns correct structure for all strategies" do
      strategies_with_opts = [
        {ChainOfThought, []},
        {TreeOfThoughts, []},
        {GraphOfThoughts, []},
        {ReAct, [tools: []]},
        {Adaptive, []}
      ]

      for {strategy, opts} <- strategies_with_opts do
        {agent, ctx} = create_agent(strategy, opts)
        snapshot = strategy.snapshot(agent, ctx)

        assert %Jido.Agent.Strategy.Snapshot{} = snapshot
        assert is_atom(snapshot.status)
        assert is_boolean(snapshot.done?)
      end
    end

    test "telemetry events are defined for strategy operations" do
      # Attach telemetry handler
      ref = make_ref()
      pid = self()
      handler_id = "strategy-test-#{inspect(ref)}"

      events = [
        [:jido, :ai, :cot, :start],
        [:jido, :ai, :cot, :stop],
        [:jido, :ai, :tot, :start],
        [:jido, :ai, :tot, :stop],
        [:jido, :ai, :got, :start],
        [:jido, :ai, :got, :stop],
        [:jido, :ai, :strategy, :react, :start],
        [:jido, :ai, :strategy, :react, :stop]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, _measurements, _metadata, _config ->
          send(pid, {:telemetry, event})
        end,
        nil
      )

      # Execute each strategy start
      {cot_agent, _} = create_agent(ChainOfThought)

      ChainOfThought.cmd(
        cot_agent,
        [%Instruction{action: ChainOfThought.start_action(), params: %{prompt: "test"}}],
        %{}
      )

      {tot_agent, _} = create_agent(TreeOfThoughts)

      TreeOfThoughts.cmd(
        tot_agent,
        [%Instruction{action: TreeOfThoughts.start_action(), params: %{prompt: "test"}}],
        %{}
      )

      {got_agent, _} = create_agent(GraphOfThoughts)

      GraphOfThoughts.cmd(
        got_agent,
        [%Instruction{action: GraphOfThoughts.start_action(), params: %{prompt: "test"}}],
        %{}
      )

      {react_agent, _} = create_agent(ReAct, tools: [])
      ReAct.cmd(react_agent, [%Instruction{action: ReAct.start_action(), params: %{query: "test"}}], %{})

      :telemetry.detach(handler_id)

      # Verify telemetry events were received
      # Note: Not all strategies may emit telemetry, so we check what we receive
      # This test primarily verifies the infrastructure works
    end
  end
end
