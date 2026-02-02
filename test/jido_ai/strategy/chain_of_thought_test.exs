defmodule Jido.AI.Strategies.ChainOfThoughtTest do
  use ExUnit.Case, async: true

  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.ChainOfThought.Machine
  alias Jido.AI.Strategies.ChainOfThought

  # Helper to create a mock agent
  defp create_agent(opts \\ []) do
    %Jido.Agent{
      id: "test-agent",
      name: "test",
      state: %{}
    }
    |> then(fn agent ->
      ctx = %{strategy_opts: opts}
      {agent, []} = ChainOfThought.init(agent, ctx)
      agent
    end)
  end

  # ============================================================================
  # Initialization
  # ============================================================================

  describe "init/2" do
    test "initializes agent with machine state" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:status] == :idle
      assert state[:steps] == []
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

    test "uses custom system prompt when provided" do
      custom_prompt = "Custom thinking prompt"
      agent = create_agent(system_prompt: custom_prompt)
      state = StratState.get(agent, %{})

      assert state[:config].system_prompt == custom_prompt
    end

    test "uses default system prompt when not provided" do
      agent = create_agent()
      state = StratState.get(agent, %{})

      assert state[:config].system_prompt == Machine.default_system_prompt()
    end
  end

  # ============================================================================
  # Action Specs
  # ============================================================================

  describe "action_spec/1" do
    test "returns spec for start action" do
      spec = ChainOfThought.action_spec(ChainOfThought.start_action())
      assert spec.name == "cot.start"
      assert spec.doc =~ "Chain-of-Thought"
    end

    test "returns spec for llm_result action" do
      spec = ChainOfThought.action_spec(ChainOfThought.llm_result_action())
      assert spec.name == "cot.llm_result"
    end

    test "returns spec for llm_partial action" do
      spec = ChainOfThought.action_spec(ChainOfThought.llm_partial_action())
      assert spec.name == "cot.llm_partial"
    end

    test "returns nil for unknown action" do
      assert ChainOfThought.action_spec(:unknown) == nil
    end
  end

  # ============================================================================
  # Signal Routes
  # ============================================================================

  describe "signal_routes/1" do
    test "returns expected signal routes" do
      routes = ChainOfThought.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["cot.query"] == {:strategy_cmd, :cot_start}
      assert route_map["react.llm.response"] == {:strategy_cmd, :cot_llm_result}
      assert route_map["react.llm.delta"] == {:strategy_cmd, :cot_llm_partial}
    end
  end

  # ============================================================================
  # cmd/3 - Start Instruction
  # ============================================================================

  describe "cmd/3 with start instruction" do
    test "processes start instruction and returns directive" do
      agent = create_agent()

      instruction = %Jido.Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "What is 2+2?"}
      }

      {agent, directives} = ChainOfThought.cmd(agent, [instruction], %{})

      # Should have transitioned to reasoning
      state = StratState.get(agent, %{})
      assert state[:status] == :reasoning
      assert state[:prompt] == "What is 2+2?"

      # Should have returned a ReqLLMStream directive
      assert length(directives) == 1
      [directive] = directives
      assert directive.__struct__ == Jido.AI.Directive.ReqLLMStream
    end

    test "directive contains correct model from config" do
      agent = create_agent(model: "test:model")

      instruction = %Jido.Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "Test"}
      }

      {_agent, [directive]} = ChainOfThought.cmd(agent, [instruction], %{})

      assert directive.model == "test:model"
    end
  end

  # ============================================================================
  # cmd/3 - LLM Result Instruction
  # ============================================================================

  describe "cmd/3 with llm_result instruction" do
    test "processes successful result" do
      agent = create_agent()

      # First start a reasoning session
      start_instruction = %Jido.Instruction{
        action: ChainOfThought.start_action(),
        params: %{prompt: "What is 2+2?"}
      }

      {agent, _} = ChainOfThought.cmd(agent, [start_instruction], %{})

      # Get the call_id
      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      # Now send result
      result_instruction = %Jido.Instruction{
        action: ChainOfThought.llm_result_action(),
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "Step 1: Add. Conclusion: 4"}}
        }
      }

      {agent, _} = ChainOfThought.cmd(agent, [result_instruction], %{})

      state = StratState.get(agent, %{})
      assert state[:status] == :completed
      assert state[:termination_reason] == :success
    end
  end

  # ============================================================================
  # Snapshot
  # ============================================================================

  describe "snapshot/2" do
    test "returns idle snapshot for new agent" do
      agent = create_agent()
      snapshot = ChainOfThought.snapshot(agent, %{})

      assert snapshot.status == :idle
      assert snapshot.done? == false
    end

    test "returns success snapshot for completed agent" do
      agent = create_agent()

      # Start and complete
      start = %Jido.Instruction{action: :cot_start, params: %{prompt: "Test"}}
      {agent, _} = ChainOfThought.cmd(agent, [start], %{})

      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      result = %Jido.Instruction{
        action: :cot_llm_result,
        params: %{call_id: call_id, result: {:ok, %{text: "Step 1: Do. Answer: Done"}}}
      }

      {agent, _} = ChainOfThought.cmd(agent, [result], %{})

      snapshot = ChainOfThought.snapshot(agent, %{})

      assert snapshot.status == :success
      assert snapshot.done? == true
      assert snapshot.result =~ "Done"
    end

    test "includes steps in details" do
      agent = create_agent()

      start = %Jido.Instruction{action: :cot_start, params: %{prompt: "Test"}}
      {agent, _} = ChainOfThought.cmd(agent, [start], %{})

      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      result = %Jido.Instruction{
        action: :cot_llm_result,
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "Step 1: First.\nStep 2: Second.\nConclusion: Done"}}
        }
      }

      {agent, _} = ChainOfThought.cmd(agent, [result], %{})

      snapshot = ChainOfThought.snapshot(agent, %{})

      assert snapshot.details[:steps_count] == 2
      assert length(snapshot.details[:steps]) == 2
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  describe "get_steps/1" do
    test "returns steps from agent state" do
      agent = create_agent()

      start = %Jido.Instruction{action: :cot_start, params: %{prompt: "Test"}}
      {agent, _} = ChainOfThought.cmd(agent, [start], %{})

      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      result = %Jido.Instruction{
        action: :cot_llm_result,
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "Step 1: First.\nStep 2: Second.\nConclusion: Done"}}
        }
      }

      {agent, _} = ChainOfThought.cmd(agent, [result], %{})

      steps = ChainOfThought.get_steps(agent)
      assert length(steps) == 2
      assert Enum.at(steps, 0).number == 1
    end

    test "returns empty list for agent without steps" do
      agent = create_agent()
      steps = ChainOfThought.get_steps(agent)
      assert steps == []
    end
  end

  describe "get_conclusion/1" do
    test "returns conclusion from agent state" do
      agent = create_agent()

      start = %Jido.Instruction{action: :cot_start, params: %{prompt: "Test"}}
      {agent, _} = ChainOfThought.cmd(agent, [start], %{})

      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      result = %Jido.Instruction{
        action: :cot_llm_result,
        params: %{
          call_id: call_id,
          result: {:ok, %{text: "Step 1: Do.\nConclusion: The answer is 42."}}
        }
      }

      {agent, _} = ChainOfThought.cmd(agent, [result], %{})

      conclusion = ChainOfThought.get_conclusion(agent)
      assert conclusion =~ "The answer is 42"
    end

    test "returns nil for agent without conclusion" do
      agent = create_agent()
      assert ChainOfThought.get_conclusion(agent) == nil
    end
  end

  describe "get_raw_response/1" do
    test "returns raw response from agent state" do
      agent = create_agent()

      start = %Jido.Instruction{action: :cot_start, params: %{prompt: "Test"}}
      {agent, _} = ChainOfThought.cmd(agent, [start], %{})

      state = StratState.get(agent, %{})
      call_id = state[:current_call_id]

      raw = "Step 1: Do.\nConclusion: Done."

      result = %Jido.Instruction{
        action: :cot_llm_result,
        params: %{call_id: call_id, result: {:ok, %{text: raw}}}
      }

      {agent, _} = ChainOfThought.cmd(agent, [result], %{})

      assert ChainOfThought.get_raw_response(agent) == raw
    end
  end

  # ============================================================================
  # Action Helper Functions
  # ============================================================================

  describe "action helper functions" do
    test "start_action/0 returns correct atom" do
      assert ChainOfThought.start_action() == :cot_start
    end

    test "llm_result_action/0 returns correct atom" do
      assert ChainOfThought.llm_result_action() == :cot_llm_result
    end

    test "llm_partial_action/0 returns correct atom" do
      assert ChainOfThought.llm_partial_action() == :cot_llm_partial
    end
  end
end
