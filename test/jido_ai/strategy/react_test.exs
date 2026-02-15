defmodule Jido.AI.Strategies.ReActTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Directive
  alias Jido.AI.Strategies.ReAct

  # Test action module
  defmodule TestCalculator do
    use Jido.Action,
      name: "calculator",
      description: "A simple calculator"

    def run(%{operation: "add", a: a, b: b}, _ctx), do: {:ok, %{result: a + b}}
    def run(%{operation: "multiply", a: a, b: b}, _ctx), do: {:ok, %{result: a * b}}
  end

  defmodule TestSearch do
    use Jido.Action,
      name: "search",
      description: "Search for information"

    def run(%{query: query}, _ctx), do: {:ok, %{results: ["Found: #{query}"]}}
  end

  # Helper to create a mock agent
  defp create_agent(opts) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = ReAct.init(agent, ctx)
      agent
    end)
  end

  # ============================================================================
  # Model Alias Resolution
  # ============================================================================

  describe "model alias resolution" do
    test "resolves :fast alias to full model spec" do
      agent = create_agent(tools: [TestCalculator], model: :fast)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.model == Jido.AI.resolve_model(:fast)
      assert is_binary(config.model)
      assert String.contains?(config.model, ":")
    end

    test "resolves :capable alias to full model spec" do
      agent = create_agent(tools: [TestCalculator], model: :capable)
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.model == Jido.AI.resolve_model(:capable)
    end

    test "passes through string model specs unchanged" do
      agent = create_agent(tools: [TestCalculator], model: "openai:gpt-4")
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.model == "openai:gpt-4"
    end

    test "uses default model when not specified" do
      agent = create_agent(tools: [TestCalculator])
      state = StratState.get(agent, %{})
      config = state[:config]

      # Default is "anthropic:claude-haiku-4-5"
      assert config.model == "anthropic:claude-haiku-4-5"
    end
  end

  # ============================================================================
  # Snapshot with Usage and Duration
  # ============================================================================

  describe "snapshot/2" do
    test "includes usage in details when present" do
      agent = create_agent(tools: [TestCalculator])

      # Manually set usage in state
      state = StratState.get(agent, %{})
      state = put_in(state, [:usage], %{input_tokens: 100, output_tokens: 50})
      agent = StratState.put(agent, state)

      snapshot = ReAct.snapshot(agent, %{})

      assert snapshot.details[:usage] == %{input_tokens: 100, output_tokens: 50}
    end

    test "includes duration_ms when started_at is set" do
      agent = create_agent(tools: [TestCalculator])

      # Manually set started_at
      state = StratState.get(agent, %{})
      started_at = System.monotonic_time(:millisecond) - 1000
      state = put_in(state, [:started_at], started_at)
      agent = StratState.put(agent, state)

      snapshot = ReAct.snapshot(agent, %{})

      assert is_integer(snapshot.details[:duration_ms])
      assert snapshot.details[:duration_ms] >= 1000
    end

    test "excludes empty usage from details" do
      agent = create_agent(tools: [TestCalculator])
      snapshot = ReAct.snapshot(agent, %{})

      # Empty usage should not be included
      refute Map.has_key?(snapshot.details, :usage)
    end
  end

  # ============================================================================
  # Dynamic Tool Registration
  # ============================================================================

  describe "dynamic tool registration" do
    test "register_tool adds tool to config" do
      agent = create_agent(tools: [TestCalculator])

      # Get initial tools
      initial_tools = ReAct.list_tools(agent)
      assert TestCalculator in initial_tools
      refute TestSearch in initial_tools

      # Register new tool
      instruction = %Jido.Instruction{
        action: ReAct.register_tool_action(),
        params: %{tool_module: TestSearch}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      # Verify tool was added
      tools = ReAct.list_tools(agent)
      assert TestCalculator in tools
      assert TestSearch in tools
    end

    test "unregister_tool removes tool from config" do
      agent = create_agent(tools: [TestCalculator, TestSearch])

      # Verify both tools present
      initial_tools = ReAct.list_tools(agent)
      assert TestCalculator in initial_tools
      assert TestSearch in initial_tools

      # Unregister search
      instruction = %Jido.Instruction{
        action: ReAct.unregister_tool_action(),
        params: %{tool_name: "search"}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      # Verify search was removed
      tools = ReAct.list_tools(agent)
      assert TestCalculator in tools
      refute TestSearch in tools
    end

    test "register_tool updates actions_by_name" do
      agent = create_agent(tools: [TestCalculator])

      # Register new tool
      instruction = %Jido.Instruction{
        action: ReAct.register_tool_action(),
        params: %{tool_module: TestSearch}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      # Verify actions_by_name was updated
      state = StratState.get(agent, %{})
      config = state[:config]

      assert Map.has_key?(config.actions_by_name, "search")
      assert config.actions_by_name["search"] == TestSearch
    end
  end

  # ============================================================================
  # Action Specs
  # ============================================================================

  describe "action_spec/1" do
    test "returns spec for start action" do
      spec = ReAct.action_spec(ReAct.start_action())
      assert spec.name == "ai.react.start"
      assert spec.doc =~ "Start a new ReAct conversation"
    end

    test "returns spec for register_tool action" do
      spec = ReAct.action_spec(ReAct.register_tool_action())
      assert spec.name == "ai.react.register_tool"
      assert spec.doc =~ "Register a new tool"
    end

    test "returns spec for unregister_tool action" do
      spec = ReAct.action_spec(ReAct.unregister_tool_action())
      assert spec.name == "ai.react.unregister_tool"
      assert spec.doc =~ "Unregister a tool"
    end

    test "returns nil for unknown action" do
      assert ReAct.action_spec(:unknown_action) == nil
    end
  end

  # ============================================================================
  # Signal Routes
  # ============================================================================

  describe "signal_routes/1" do
    test "returns expected signal routes" do
      routes = ReAct.signal_routes(%{})

      route_map = Map.new(routes)

      assert route_map["ai.react.query"] == {:strategy_cmd, :ai_react_start}
      assert route_map["ai.llm.response"] == {:strategy_cmd, :ai_react_llm_result}
      assert route_map["ai.tool.result"] == {:strategy_cmd, :ai_react_tool_result}
      assert route_map["ai.llm.delta"] == {:strategy_cmd, :ai_react_llm_partial}
      assert route_map["ai.react.cancel"] == {:strategy_cmd, :ai_react_cancel}
      assert route_map["ai.request.error"] == {:strategy_cmd, :ai_react_request_error}
    end
  end

  # ============================================================================
  # tools config
  # ============================================================================

  describe "tools config" do
    test "builds actions_by_name from tools list" do
      agent = create_agent(tools: [TestCalculator])
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.actions_by_name == %{"calculator" => TestCalculator}
    end

    test "includes tools in reqllm_tools" do
      agent = create_agent(tools: [TestCalculator])
      state = StratState.get(agent, %{})
      config = state[:config]

      assert length(config.reqllm_tools) == 1
    end
  end

  # ============================================================================
  # Public Helper Functions
  # ============================================================================

  describe "action helper functions" do
    test "start_action/0 returns correct atom" do
      assert ReAct.start_action() == :ai_react_start
    end

    test "llm_result_action/0 returns correct atom" do
      assert ReAct.llm_result_action() == :ai_react_llm_result
    end

    test "tool_result_action/0 returns correct atom" do
      assert ReAct.tool_result_action() == :ai_react_tool_result
    end

    test "llm_partial_action/0 returns correct atom" do
      assert ReAct.llm_partial_action() == :ai_react_llm_partial
    end

    test "register_tool_action/0 returns correct atom" do
      assert ReAct.register_tool_action() == :ai_react_register_tool
    end

    test "unregister_tool_action/0 returns correct atom" do
      assert ReAct.unregister_tool_action() == :ai_react_unregister_tool
    end

    test "cancel_action/0 returns correct atom" do
      assert ReAct.cancel_action() == :ai_react_cancel
    end

    test "request_error_action/0 returns correct atom" do
      assert ReAct.request_error_action() == :ai_react_request_error
    end
  end

  # ============================================================================
  # list_tools/1
  # ============================================================================

  describe "list_tools/1" do
    test "returns list of tool modules" do
      agent = create_agent(tools: [TestCalculator, TestSearch])
      tools = ReAct.list_tools(agent)

      assert is_list(tools)
      assert TestCalculator in tools
      assert TestSearch in tools
    end

    test "returns empty list for agent without config" do
      # Create a bare agent without init
      agent = %Jido.Agent{
        id: "bare-agent",
        name: "bare",
        state: %{}
      }

      tools = ReAct.list_tools(agent)
      assert tools == []
    end
  end

  # ============================================================================
  # Tool Context Management
  # ============================================================================

  describe "base_tool_context configuration" do
    test "base_tool_context defaults to empty map" do
      agent = create_agent(tools: [TestCalculator])
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.base_tool_context == %{}
    end

    test "base_tool_context can be set via options" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{tenant: "acme", actor: :admin})
      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.base_tool_context == %{tenant: "acme", actor: :admin}
    end

    test "base_tool_context from agent.state takes precedence over opts" do
      # Create agent with tool_context in state
      agent = %Jido.Agent{
        id: "test-agent",
        name: "test",
        state: %{tool_context: %{from_state: true}}
      }

      ctx = %{strategy_opts: [tools: [TestCalculator], tool_context: %{from_opts: true}]}
      {agent, []} = ReAct.init(agent, ctx)

      state = StratState.get(agent, %{})
      config = state[:config]

      # State should take precedence
      assert config.base_tool_context == %{from_state: true}
    end
  end

  describe "set_tool_context action" do
    test "set_tool_context_action/0 returns correct atom" do
      assert ReAct.set_tool_context_action() == :ai_react_set_tool_context
    end

    test "action_spec returns spec for set_tool_context" do
      spec = ReAct.action_spec(ReAct.set_tool_context_action())
      assert spec.name == "ai.react.set_tool_context"
      assert spec.doc =~ "Update the tool context"
    end

    test "set_tool_context replaces base_tool_context" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{initial: "value"})

      instruction = %Jido.Instruction{
        action: ReAct.set_tool_context_action(),
        params: %{tool_context: %{new_key: "new_value"}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      config = state[:config]

      # REPLACES (not merges) to prevent indefinite key accumulation
      assert config.base_tool_context == %{new_key: "new_value"}
      refute Map.has_key?(config.base_tool_context, :initial)
    end

    test "set_tool_context with empty map clears base_tool_context" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{existing: "value"})

      instruction = %Jido.Instruction{
        action: ReAct.set_tool_context_action(),
        params: %{tool_context: %{}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      config = state[:config]

      # Empty map replaces, so base_tool_context is now empty
      assert config.base_tool_context == %{}
    end
  end

  describe "per-request tool_context in start instruction" do
    test "start with tool_context stores in run_tool_context, not base" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{base: "context"})

      instruction = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "test query", tool_context: %{request_id: "req-123"}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      config = state[:config]

      # base_tool_context remains unchanged (persistent)
      assert config.base_tool_context[:base] == "context"
      refute Map.has_key?(config.base_tool_context, :request_id)

      # run_tool_context has per-request context (ephemeral)
      assert state[:run_tool_context][:request_id] == "req-123"
    end

    test "start without tool_context preserves base_tool_context" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{existing: "value"})

      instruction = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "test query"}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      config = state[:config]

      assert config.base_tool_context[:existing] == "value"
    end

    test "run_tool_context cleared after completion prevents leakage" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{base: "value"})

      # First request with tenant_a context
      instruction1 = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "first query", tool_context: %{tenant_id: "tenant_a"}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction1], %{})
      state = StratState.get(agent, %{})

      # Run context should have tenant_a during the request
      assert state[:run_tool_context][:tenant_id] == "tenant_a"

      # Simulate completion by directly sending a final answer result
      # For now, just verify base_tool_context is not polluted
      config = state[:config]
      refute Map.has_key?(config.base_tool_context, :tenant_id)
    end

    test "set_tool_context action replaces base_tool_context" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{old_key: "old_value"})

      instruction = %Jido.Instruction{
        action: ReAct.set_tool_context_action(),
        params: %{tool_context: %{new_key: "new_value"}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction], %{})

      state = StratState.get(agent, %{})
      config = state[:config]

      # set_tool_context REPLACES, not merges (prevents key accumulation)
      assert config.base_tool_context == %{new_key: "new_value"}
      refute Map.has_key?(config.base_tool_context, :old_key)
    end
  end

  # ============================================================================
  # Issue #6 Fix: Tool Context Leakage Prevention
  # ============================================================================

  describe "cross-request isolation - Issue #6 fix" do
    test "run_tool_context is cleared on completion, preventing leakage" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{base: "value"})

      # First request from "tenant_a"
      instruction1 = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "first query", tool_context: %{tenant_id: "tenant_a", secret: "a_secret"}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction1], %{})
      state = StratState.get(agent, %{})

      # Run context has tenant_a's data
      assert state[:run_tool_context][:tenant_id] == "tenant_a"
      assert state[:run_tool_context][:secret] == "a_secret"

      # Simulate receiving a final answer (causes transition to :completed)
      llm_result_instruction = %Jido.Instruction{
        action: ReAct.llm_result_action(),
        params: %{
          call_id: state[:current_llm_call_id],
          result: {:ok, %{type: :final_answer, text: "Final answer"}}
        }
      }

      {agent, _directives} = ReAct.cmd(agent, [llm_result_instruction], %{})
      state = StratState.get(agent, %{})

      # After completion, run_tool_context should be cleared
      assert state[:status] == :completed
      assert state[:run_tool_context] == nil

      # base_tool_context remains intact
      config = state[:config]
      assert config.base_tool_context[:base] == "value"
      refute Map.has_key?(config.base_tool_context, :tenant_id)
      refute Map.has_key?(config.base_tool_context, :secret)
    end

    test "second request does not see first request's run_tool_context" do
      agent = create_agent(tools: [TestCalculator], tool_context: %{base: "value"})

      # First request from "tenant_a"
      instruction1 = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "first query", tool_context: %{tenant_id: "tenant_a"}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction1], %{})

      # Simulate completion
      state = StratState.get(agent, %{})

      llm_result = %Jido.Instruction{
        action: ReAct.llm_result_action(),
        params: %{
          call_id: state[:current_llm_call_id],
          result: {:ok, %{type: :final_answer, text: "Done"}}
        }
      }

      {agent, _directives} = ReAct.cmd(agent, [llm_result], %{})

      # Second request from "tenant_b" - should NOT see tenant_a's context
      instruction2 = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "second query", tool_context: %{tenant_id: "tenant_b"}}
      }

      {agent, _directives} = ReAct.cmd(agent, [instruction2], %{})
      state = StratState.get(agent, %{})

      # Only tenant_b's context, no leakage from tenant_a
      assert state[:run_tool_context] == %{tenant_id: "tenant_b"}
      refute Map.has_key?(state[:run_tool_context], :secret)
    end
  end

  # ============================================================================
  # Issue #1 Fix: Unknown Tool Handling
  # ============================================================================

  describe "unknown tool handling - Issue #1 fix" do
    test "emits EmitToolError directive for unknown tool call" do
      agent = create_agent(tools: [TestCalculator])

      start_instruction = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "Use an unknown tool"}
      }

      {agent, _} = ReAct.cmd(agent, [start_instruction], %{})
      state = StratState.get(agent, %{})

      llm_result_instruction = %Jido.Instruction{
        action: ReAct.llm_result_action(),
        params: %{
          call_id: state[:current_llm_call_id],
          result:
            {:ok,
             %{
               type: :tool_calls,
               text: "",
               tool_calls: [%{id: "tc_1", name: "unknown_tool", arguments: %{}}]
             }}
        }
      }

      {_agent, directives} = ReAct.cmd(agent, [llm_result_instruction], %{})

      assert [%Directive.EmitToolError{} = directive] = directives
      assert directive.tool_name == "unknown_tool"
      assert {:unknown_tool, _} = directive.error
    end
  end

  # ============================================================================
  # Issue #3 Fix: Busy State Rejection
  # ============================================================================

  describe "busy state handling - Issue #3 fix" do
    test "emits EmitRequestError directive when a second request starts while busy" do
      agent = create_agent(tools: [TestCalculator])

      first_request = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "first", request_id: "req_1"}
      }

      {agent, _} = ReAct.cmd(agent, [first_request], %{})

      second_request = %Jido.Instruction{
        action: ReAct.start_action(),
        params: %{query: "second", request_id: "req_2"}
      }

      {agent, directives} = ReAct.cmd(agent, [second_request], %{})

      assert [%Directive.EmitRequestError{} = directive] = directives
      assert directive.request_id == "req_2"
      assert directive.reason == :busy

      state = StratState.get(agent, %{})
      assert state[:status] == :awaiting_llm
    end
  end
end
