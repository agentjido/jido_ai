defmodule Jido.AI.Runner.ChainOfThought.ExecutionHookTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.ExecutionHook

  alias Jido.AI.Runner.ChainOfThought.ExecutionHook.{
    DataFlowDependency,
    ErrorPoint,
    ExecutionPlan,
    ExecutionStep
  }

  describe "should_generate_execution_plan?/1" do
    test "returns true when enable_execution_cot is not set" do
      agent = %{state: %{}}
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
    end

    test "returns true when enable_execution_cot is true" do
      agent = %{state: %{enable_execution_cot: true}}
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
    end

    test "returns false when enable_execution_cot is false" do
      agent = %{state: %{enable_execution_cot: false}}
      assert ExecutionHook.should_generate_execution_plan?(agent) == false
    end

    test "returns true for nil state" do
      agent = %{state: nil}
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
    end
  end

  describe "enrich_agent_with_execution_plan/2" do
    test "adds execution plan to agent state" do
      agent = %{state: %{existing: "data"}}

      plan = %ExecutionPlan{
        steps: [],
        data_flow: [],
        error_points: [],
        execution_strategy: "Test strategy",
        timestamp: DateTime.utc_now()
      }

      updated_agent = ExecutionHook.enrich_agent_with_execution_plan(agent, plan)

      assert updated_agent.state.execution_plan == plan
      assert updated_agent.state.existing == "data"
    end

    test "creates state map if agent has no state" do
      agent = %{state: nil}

      plan = %ExecutionPlan{
        execution_strategy: "Test strategy",
        timestamp: DateTime.utc_now()
      }

      updated_agent = ExecutionHook.enrich_agent_with_execution_plan(agent, plan)

      assert updated_agent.state.execution_plan == plan
    end

    test "overwrites existing execution plan" do
      old_plan = %ExecutionPlan{
        execution_strategy: "Old strategy",
        timestamp: DateTime.utc_now()
      }

      agent = %{state: %{execution_plan: old_plan}}

      new_plan = %ExecutionPlan{
        execution_strategy: "New strategy",
        timestamp: DateTime.utc_now()
      }

      updated_agent = ExecutionHook.enrich_agent_with_execution_plan(agent, new_plan)

      assert updated_agent.state.execution_plan == new_plan
      assert updated_agent.state.execution_plan.execution_strategy == "New strategy"
    end
  end

  describe "get_execution_plan/1" do
    test "extracts execution plan from agent state" do
      plan = %ExecutionPlan{
        execution_strategy: "Test strategy",
        timestamp: DateTime.utc_now()
      }

      agent = %{state: %{execution_plan: plan}}

      assert {:ok, retrieved_plan} = ExecutionHook.get_execution_plan(agent)
      assert retrieved_plan == plan
    end

    test "returns error when no execution plan exists" do
      agent = %{state: %{}}

      assert {:error, :no_plan} = ExecutionHook.get_execution_plan(agent)
    end

    test "returns error when agent has no state" do
      agent = %{state: nil}

      assert {:error, :no_plan} = ExecutionHook.get_execution_plan(agent)
    end

    test "returns error when execution_plan is invalid" do
      agent = %{state: %{execution_plan: "invalid"}}

      assert {:error, :invalid_plan} = ExecutionHook.get_execution_plan(agent)
    end
  end

  describe "generate_execution_plan/1" do
    test "returns agent unchanged when execution analysis is disabled" do
      agent = %{
        id: "test",
        state: %{enable_execution_cot: false},
        pending_instructions: :queue.new()
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      assert result_agent == agent
      refute Map.has_key?(result_agent.state, :execution_plan)
    end

    test "returns agent unchanged when no instructions" do
      agent = %{
        id: "test",
        state: %{},
        pending_instructions: :queue.new()
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      assert result_agent == agent
      refute Map.has_key?(result_agent.state, :execution_plan)
    end

    @tag :skip
    @tag :requires_llm
    test "generates execution plan when enabled with instructions" do
      instruction = build_instruction(TestAction, %{value: 42})
      queue = :queue.from_list([instruction])

      agent = %{
        id: "test",
        state: %{},
        pending_instructions: queue
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      assert {:ok, plan} = ExecutionHook.get_execution_plan(result_agent)
      assert is_binary(plan.execution_strategy)
      assert is_list(plan.steps)
      assert is_list(plan.data_flow)
      assert is_list(plan.error_points)
      assert %DateTime{} = plan.timestamp
    end

    @tag :skip
    @tag :requires_llm
    test "returns agent unchanged on LLM error (graceful degradation)" do
      instruction = build_instruction(TestAction, %{value: 42})
      queue = :queue.from_list([instruction])

      agent = %{
        id: "test",
        state: %{execution_model: "invalid-model"},
        pending_instructions: queue
      }

      # Should not raise, should return agent unchanged
      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      # Agent should be returned (graceful degradation)
      assert result_agent.id == agent.id
    end

    test "handles agent without pending_instructions field" do
      agent = %{
        id: "test",
        state: %{}
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      assert result_agent == agent
    end

    test "handles invalid pending_instructions queue" do
      agent = %{
        id: "test",
        state: %{},
        pending_instructions: "invalid"
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      assert result_agent == agent
    end
  end

  describe "ExecutionPlan struct" do
    test "requires execution_strategy and timestamp" do
      plan = %ExecutionPlan{
        execution_strategy: "Sequential execution",
        timestamp: DateTime.utc_now()
      }

      assert plan.execution_strategy == "Sequential execution"
      assert %DateTime{} = plan.timestamp
    end

    test "has default empty lists for optional fields" do
      plan = %ExecutionPlan{
        execution_strategy: "Test",
        timestamp: DateTime.utc_now()
      }

      assert plan.steps == []
      assert plan.data_flow == []
      assert plan.error_points == []
    end

    test "accepts lists for steps, data_flow, and error_points" do
      step = %ExecutionStep{
        index: 0,
        action: "TestAction",
        params_summary: "value: 42"
      }

      dependency = %DataFlowDependency{
        from_step: 0,
        to_step: 1,
        data_key: "result"
      }

      error_point = %ErrorPoint{
        step: 0,
        type: :validation,
        description: "Missing input"
      }

      plan = %ExecutionPlan{
        execution_strategy: "Test",
        steps: [step],
        data_flow: [dependency],
        error_points: [error_point],
        timestamp: DateTime.utc_now()
      }

      assert length(plan.steps) == 1
      assert length(plan.data_flow) == 1
      assert length(plan.error_points) == 1
    end
  end

  describe "ExecutionStep struct" do
    test "requires index and action" do
      step = %ExecutionStep{
        index: 0,
        action: "TestAction"
      }

      assert step.index == 0
      assert step.action == "TestAction"
    end

    test "has default empty lists and strings" do
      step = %ExecutionStep{
        index: 0,
        action: "TestAction"
      }

      assert step.params_summary == ""
      assert step.expected_inputs == []
      assert step.expected_outputs == []
      assert step.depends_on == []
    end

    test "accepts all optional fields" do
      step = %ExecutionStep{
        index: 1,
        action: "ProcessData",
        params_summary: "input: data",
        expected_inputs: ["data"],
        expected_outputs: ["result"],
        depends_on: [0]
      }

      assert step.index == 1
      assert step.params_summary == "input: data"
      assert step.expected_inputs == ["data"]
      assert step.expected_outputs == ["result"]
      assert step.depends_on == [0]
    end
  end

  describe "DataFlowDependency struct" do
    test "requires from_step, to_step, and data_key" do
      dep = %DataFlowDependency{
        from_step: 0,
        to_step: 1,
        data_key: "result"
      }

      assert dep.from_step == 0
      assert dep.to_step == 1
      assert dep.data_key == "result"
    end

    test "has default dependency_type of :required" do
      dep = %DataFlowDependency{
        from_step: 0,
        to_step: 1,
        data_key: "result"
      }

      assert dep.dependency_type == :required
    end

    test "accepts custom dependency_type" do
      dep = %DataFlowDependency{
        from_step: 0,
        to_step: 1,
        data_key: "result",
        dependency_type: :optional
      }

      assert dep.dependency_type == :optional
    end
  end

  describe "ErrorPoint struct" do
    test "requires step, type, and description" do
      error = %ErrorPoint{
        step: 0,
        type: :validation,
        description: "Missing required input"
      }

      assert error.step == 0
      assert error.type == :validation
      assert error.description == "Missing required input"
    end

    test "has default empty mitigation" do
      error = %ErrorPoint{
        step: 0,
        type: :validation,
        description: "Error"
      }

      assert error.mitigation == ""
    end

    test "accepts mitigation" do
      error = %ErrorPoint{
        step: 0,
        type: :validation,
        description: "Missing input",
        mitigation: "Provide default value"
      }

      assert error.mitigation == "Provide default value"
    end
  end

  describe "context enrichment for validation" do
    test "execution plan is accessible after enrichment" do
      agent = %{state: %{}}

      step = %ExecutionStep{
        index: 0,
        action: "ProcessData",
        expected_inputs: ["data"],
        expected_outputs: ["result"]
      }

      plan = %ExecutionPlan{
        execution_strategy: "Sequential processing",
        steps: [step],
        data_flow: [],
        error_points: [],
        timestamp: DateTime.utc_now()
      }

      enriched_agent = ExecutionHook.enrich_agent_with_execution_plan(agent, plan)

      # Simulate validation hook accessing plan
      {:ok, retrieved_plan} = ExecutionHook.get_execution_plan(enriched_agent)

      assert retrieved_plan.execution_strategy == "Sequential processing"
      assert length(retrieved_plan.steps) == 1
      assert hd(retrieved_plan.steps).action == "ProcessData"
    end

    test "multiple enrichments preserve other state" do
      agent = %{state: %{user_data: "important", counter: 42}}

      plan1 = %ExecutionPlan{
        execution_strategy: "First strategy",
        timestamp: DateTime.utc_now()
      }

      agent = ExecutionHook.enrich_agent_with_execution_plan(agent, plan1)

      plan2 = %ExecutionPlan{
        execution_strategy: "Second strategy",
        timestamp: DateTime.utc_now()
      }

      agent = ExecutionHook.enrich_agent_with_execution_plan(agent, plan2)

      # State should preserve non-plan data
      assert agent.state.user_data == "important"
      assert agent.state.counter == 42

      # Plan should be updated
      {:ok, current_plan} = ExecutionHook.get_execution_plan(agent)
      assert current_plan.execution_strategy == "Second strategy"
    end
  end

  describe "opt-in behavior" do
    test "execution analysis is enabled by default" do
      agent = %{state: %{}}
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
    end

    test "execution analysis can be explicitly enabled" do
      agent = %{state: %{enable_execution_cot: true}}
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
    end

    test "execution analysis can be explicitly disabled" do
      agent = %{state: %{enable_execution_cot: false}}
      assert ExecutionHook.should_generate_execution_plan?(agent) == false
    end

    test "disabled analysis skips generation entirely" do
      instruction = build_instruction(TestAction, %{value: 1})
      queue = :queue.from_list([instruction])

      agent = %{
        id: "test",
        state: %{enable_execution_cot: false, existing: "data"},
        pending_instructions: queue
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      # Agent should be completely unchanged
      assert result_agent == agent
      assert result_agent.state == %{enable_execution_cot: false, existing: "data"}
      refute Map.has_key?(result_agent.state, :execution_plan)
    end
  end

  describe "integration with planning context" do
    test "execution plan can access planning reasoning" do
      # This would be set by on_before_plan
      planning = %{
        goal: "Process data efficiently",
        analysis: "Multi-step workflow",
        dependencies: ["Step 1 before Step 2"]
      }

      agent = %{
        id: "test",
        state: %{planning_cot: planning},
        pending_instructions: :queue.new()
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      # Agent should still have planning context
      assert result_agent.state.planning_cot == planning
    end

    test "execution hook preserves planning context after enrichment" do
      planning = %{
        goal: "Test goal",
        analysis: "Test analysis"
      }

      agent = %{
        state: %{planning_cot: planning}
      }

      plan = %ExecutionPlan{
        execution_strategy: "Test",
        timestamp: DateTime.utc_now()
      }

      enriched_agent = ExecutionHook.enrich_agent_with_execution_plan(agent, plan)

      # Both planning and execution should be present
      assert enriched_agent.state.planning_cot == planning
      assert {:ok, _} = ExecutionHook.get_execution_plan(enriched_agent)
    end
  end

  # Test Helpers

  defp build_instruction(action_module, params) do
    %{
      action: action_module,
      params: params,
      id: "instruction-#{:rand.uniform(10000)}"
    }
  end

  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      schema: [value: [type: :integer]]

    def run(params, _context) do
      {:ok, %{result: params.value}}
    end
  end
end
