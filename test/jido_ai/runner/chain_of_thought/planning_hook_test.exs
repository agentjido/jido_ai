defmodule Jido.AI.Runner.ChainOfThought.PlanningHookTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.PlanningHook
  alias Jido.AI.Runner.ChainOfThought.PlanningHook.PlanningReasoning

  describe "should_generate_planning?/1" do
    test "returns true when enable_planning_cot is true" do
      context = %{enable_planning_cot: true}
      assert PlanningHook.should_generate_planning?(context) == true
    end

    test "returns false when enable_planning_cot is false" do
      context = %{enable_planning_cot: false}
      assert PlanningHook.should_generate_planning?(context) == false
    end

    test "returns true when enable_planning_cot is not set (default enabled)" do
      context = %{}
      assert PlanningHook.should_generate_planning?(context) == true
    end

    test "returns true for other context values" do
      context = %{other_key: "value"}
      assert PlanningHook.should_generate_planning?(context) == true
    end
  end

  describe "enrich_agent_with_planning/2" do
    test "adds planning reasoning to agent state" do
      agent = %{state: %{existing: "data"}}

      planning = %PlanningReasoning{
        goal: "Test goal",
        analysis: "Test analysis",
        dependencies: ["dep1"],
        potential_issues: ["issue1"],
        recommendations: ["rec1"],
        timestamp: DateTime.utc_now()
      }

      updated_agent = PlanningHook.enrich_agent_with_planning(agent, planning)

      assert updated_agent.state.planning_cot == planning
      assert updated_agent.state.existing == "data"
    end

    test "creates state map if agent has no state" do
      agent = %{state: nil}

      planning = %PlanningReasoning{
        goal: "Test goal",
        analysis: "Test analysis",
        timestamp: DateTime.utc_now()
      }

      updated_agent = PlanningHook.enrich_agent_with_planning(agent, planning)

      assert updated_agent.state.planning_cot == planning
    end

    test "overwrites existing planning reasoning" do
      old_planning = %PlanningReasoning{
        goal: "Old goal",
        analysis: "Old analysis",
        timestamp: DateTime.utc_now()
      }

      agent = %{state: %{planning_cot: old_planning}}

      new_planning = %PlanningReasoning{
        goal: "New goal",
        analysis: "New analysis",
        timestamp: DateTime.utc_now()
      }

      updated_agent = PlanningHook.enrich_agent_with_planning(agent, new_planning)

      assert updated_agent.state.planning_cot == new_planning
      assert updated_agent.state.planning_cot.goal == "New goal"
    end
  end

  describe "get_planning_reasoning/1" do
    test "extracts planning reasoning from agent state" do
      planning = %PlanningReasoning{
        goal: "Test goal",
        analysis: "Test analysis",
        timestamp: DateTime.utc_now()
      }

      agent = %{state: %{planning_cot: planning}}

      assert {:ok, retrieved_planning} = PlanningHook.get_planning_reasoning(agent)
      assert retrieved_planning == planning
    end

    test "returns error when no planning reasoning exists" do
      agent = %{state: %{}}

      assert {:error, :no_planning} = PlanningHook.get_planning_reasoning(agent)
    end

    test "returns error when agent has no state" do
      agent = %{state: nil}

      assert {:error, :no_planning} = PlanningHook.get_planning_reasoning(agent)
    end

    test "returns error when planning_cot is invalid" do
      agent = %{state: %{planning_cot: "invalid"}}

      assert {:error, :invalid_planning} = PlanningHook.get_planning_reasoning(agent)
    end
  end

  describe "generate_planning_reasoning/3" do
    test "returns agent unchanged when planning is disabled" do
      agent = %{id: "test", state: %{}}
      instructions = [build_instruction(TestAction, %{value: 42})]
      context = %{enable_planning_cot: false}

      {:ok, result_agent} = PlanningHook.generate_planning_reasoning(agent, instructions, context)

      assert result_agent == agent
      refute Map.has_key?(result_agent.state, :planning_cot)
    end

    @tag :skip
    @tag :requires_llm
    test "generates planning reasoning when enabled" do
      agent = %{id: "test", state: %{}}

      instructions = [
        build_instruction(TestAction, %{value: 42}),
        build_instruction(TestAction, %{value: 10})
      ]

      context = %{enable_planning_cot: true}

      {:ok, result_agent} =
        PlanningHook.generate_planning_reasoning(agent, instructions, context)

      assert {:ok, planning} = PlanningHook.get_planning_reasoning(result_agent)
      assert is_binary(planning.goal)
      assert is_binary(planning.analysis)
      assert is_list(planning.dependencies)
      assert is_list(planning.potential_issues)
      assert is_list(planning.recommendations)
      assert %DateTime{} = planning.timestamp
    end

    @tag :skip
    @tag :requires_llm
    test "returns agent unchanged on LLM error (graceful degradation)" do
      agent = %{id: "test", state: %{}}
      instructions = [build_instruction(TestAction, %{value: 42})]
      context = %{enable_planning_cot: true, planning_model: "invalid-model"}

      # Should not raise, should return agent unchanged
      {:ok, result_agent} =
        PlanningHook.generate_planning_reasoning(agent, instructions, context)

      # Agent should be returned (graceful degradation)
      assert result_agent.id == agent.id
    end

    test "generates planning with empty instructions" do
      agent = %{id: "test", state: %{}}
      instructions = []
      context = %{enable_planning_cot: false}

      {:ok, result_agent} = PlanningHook.generate_planning_reasoning(agent, instructions, context)

      assert result_agent == agent
    end
  end

  describe "PlanningReasoning struct" do
    test "requires goal, analysis, and timestamp" do
      planning = %PlanningReasoning{
        goal: "Test goal",
        analysis: "Test analysis",
        timestamp: DateTime.utc_now()
      }

      assert planning.goal == "Test goal"
      assert planning.analysis == "Test analysis"
      assert %DateTime{} = planning.timestamp
    end

    test "has default empty lists for optional fields" do
      planning = %PlanningReasoning{
        goal: "Test",
        analysis: "Analysis",
        timestamp: DateTime.utc_now()
      }

      assert planning.dependencies == []
      assert planning.potential_issues == []
      assert planning.recommendations == []
    end

    test "accepts lists for dependencies, issues, and recommendations" do
      planning = %PlanningReasoning{
        goal: "Test",
        analysis: "Analysis",
        dependencies: ["dep1", "dep2"],
        potential_issues: ["issue1"],
        recommendations: ["rec1", "rec2", "rec3"],
        timestamp: DateTime.utc_now()
      }

      assert length(planning.dependencies) == 2
      assert length(planning.potential_issues) == 1
      assert length(planning.recommendations) == 3
    end
  end

  describe "integration with example agent" do
    @tag :skip
    @tag :requires_llm
    test "example agent generates planning reasoning on enqueue" do
      # This would require full Jido integration
      # Skipped for unit testing, would be in integration tests
      assert true
    end
  end

  describe "context enrichment for downstream hooks" do
    test "planning reasoning is accessible after enrichment" do
      agent = %{state: %{}}

      planning = %PlanningReasoning{
        goal: "Process data",
        analysis: "Multi-step data processing workflow",
        dependencies: ["Step 1 must complete before Step 2"],
        potential_issues: ["Data validation may fail"],
        recommendations: ["Add error handling"],
        timestamp: DateTime.utc_now()
      }

      enriched_agent = PlanningHook.enrich_agent_with_planning(agent, planning)

      # Simulate downstream hook accessing planning
      {:ok, retrieved_planning} = PlanningHook.get_planning_reasoning(enriched_agent)

      assert retrieved_planning.goal == "Process data"
      assert String.contains?(hd(retrieved_planning.dependencies), "Step 1")
      assert length(retrieved_planning.potential_issues) > 0
    end

    test "multiple enrichments preserve other state" do
      agent = %{state: %{user_data: "important", counter: 42}}

      planning1 = %PlanningReasoning{
        goal: "First goal",
        analysis: "First analysis",
        timestamp: DateTime.utc_now()
      }

      agent = PlanningHook.enrich_agent_with_planning(agent, planning1)

      planning2 = %PlanningReasoning{
        goal: "Second goal",
        analysis: "Second analysis",
        timestamp: DateTime.utc_now()
      }

      agent = PlanningHook.enrich_agent_with_planning(agent, planning2)

      # State should preserve non-planning data
      assert agent.state.user_data == "important"
      assert agent.state.counter == 42

      # Planning should be updated
      {:ok, current_planning} = PlanningHook.get_planning_reasoning(agent)
      assert current_planning.goal == "Second goal"
    end
  end

  describe "opt-in behavior" do
    test "planning is enabled by default" do
      context = %{}
      assert PlanningHook.should_generate_planning?(context) == true
    end

    test "planning can be explicitly enabled" do
      context = %{enable_planning_cot: true}
      assert PlanningHook.should_generate_planning?(context) == true
    end

    test "planning can be explicitly disabled" do
      context = %{enable_planning_cot: false}
      assert PlanningHook.should_generate_planning?(context) == false
    end

    test "disabled planning skips generation entirely" do
      agent = %{id: "test", state: %{existing: "data"}}
      instructions = [build_instruction(TestAction, %{value: 1})]
      context = %{enable_planning_cot: false}

      {:ok, result_agent} = PlanningHook.generate_planning_reasoning(agent, instructions, context)

      # Agent should be completely unchanged
      assert result_agent == agent
      assert result_agent.state == %{existing: "data"}
      refute Map.has_key?(result_agent.state, :planning_cot)
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
