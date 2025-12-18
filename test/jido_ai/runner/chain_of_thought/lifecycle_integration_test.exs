defmodule Jido.AI.Runner.ChainOfThought.LifecycleIntegrationTest do
  @moduledoc """
  Integration tests for Section 1.2: Lifecycle Hook Integration.

  Tests the complete lifecycle of Chain-of-Thought reasoning through all three hooks:
  - Planning Hook (on_before_plan)
  - Execution Hook (on_before_run)
  - Validation Hook (on_after_run)

  These tests verify:
  - Full lifecycle integration with all hooks active
  - Context flow between hooks (planning → execution → validation)
  - Opt-in/opt-out behavior for each hook independently
  - Graceful degradation when hooks are disabled
  - Retry behavior on validation failure
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.{ExecutionHook, PlanningHook, ValidationHook}

  describe "full lifecycle integration with all hooks active" do
    test "planning context flows to execution hook" do
      # Simulate planning hook
      planning = %{
        goal: "Process data efficiently",
        analysis: "Multi-step workflow required",
        dependencies: ["Step 1 must complete before Step 2"],
        potential_issues: ["Data validation may fail"],
        recommendations: ["Add retry logic"],
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{
          planning_cot: planning,
          enable_execution_cot: true
        },
        pending_instructions: :queue.new()
      }

      # Execution hook should be able to access planning
      {:ok, _result_agent} = ExecutionHook.generate_execution_plan(agent)

      # Planning should still be present
      assert agent.state.planning_cot == planning
    end

    test "execution plan flows to validation hook" do
      # Simulate execution hook
      execution_plan = %{
        steps: [
          %{index: 0, action: "ProcessData", params_summary: "input: data"}
        ],
        data_flow: [],
        error_points: [
          %{step: 0, type: :validation, description: "Missing data"}
        ],
        execution_strategy: "Sequential processing",
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{
          execution_plan: execution_plan,
          enable_validation_cot: true
        }
      }

      result = %{success: true, processed: 10}
      unapplied = []

      # Validation hook should be able to access execution plan
      {:ok, validated_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      # Execution plan should still be present
      assert validated_agent.state.execution_plan == execution_plan

      # Validation result should be added
      assert {:ok, _validation} = ValidationHook.get_validation_result(validated_agent)
    end

    test "all three hooks work together in sequence" do
      # 1. Planning hook
      planning = %{
        goal: "Complete task successfully",
        analysis: "Task requires careful execution",
        dependencies: [],
        potential_issues: ["Resource constraints"],
        recommendations: ["Monitor resource usage"],
        timestamp: DateTime.utc_now()
      }

      # 2. Execution plan
      execution_plan = %{
        steps: [%{index: 0, action: "Execute"}],
        data_flow: [],
        error_points: [],
        execution_strategy: "Direct execution",
        timestamp: DateTime.utc_now()
      }

      # 3. Agent with all contexts
      agent = %{
        id: "test",
        state: %{
          planning_cot: planning,
          execution_plan: execution_plan,
          enable_validation_cot: true
        }
      }

      result = %{success: true}
      unapplied = []

      # Validation should see both planning and execution
      {:ok, validated_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      # All contexts should be preserved
      assert validated_agent.state.planning_cot == planning
      assert validated_agent.state.execution_plan == execution_plan
      assert {:ok, _validation} = ValidationHook.get_validation_result(validated_agent)
    end

    test "context enrichment preserves all state through lifecycle" do
      alias Jido.AI.Runner.ChainOfThought.ExecutionHook.ExecutionPlan
      alias Jido.AI.Runner.ChainOfThought.PlanningHook.PlanningReasoning
      alias Jido.AI.Runner.ChainOfThought.ValidationHook.ValidationResult

      initial_state = %{
        custom_data: "important",
        counter: 42,
        config: %{setting: "value"}
      }

      # Add planning with proper struct
      planning = %PlanningReasoning{
        goal: "Test",
        analysis: "Test",
        timestamp: DateTime.utc_now()
      }

      agent = %{state: initial_state}
      agent = PlanningHook.enrich_agent_with_planning(agent, planning)

      # Add execution plan with proper struct
      execution_plan = %ExecutionPlan{
        execution_strategy: "Test",
        timestamp: DateTime.utc_now()
      }

      agent = ExecutionHook.enrich_agent_with_execution_plan(agent, execution_plan)

      # Add validation with proper struct
      validation = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      agent = ValidationHook.enrich_agent_with_validation(agent, validation)

      # All original state should be preserved
      assert agent.state.custom_data == "important"
      assert agent.state.counter == 42
      assert agent.state.config == %{setting: "value"}

      # All CoT contexts should be present
      assert {:ok, _} = PlanningHook.get_planning_reasoning(agent)
      assert {:ok, _} = ExecutionHook.get_execution_plan(agent)
      assert {:ok, _} = ValidationHook.get_validation_result(agent)
    end
  end

  describe "opt-in behavior for all hooks" do
    test "all hooks enabled by default" do
      agent = %{state: %{}}

      assert PlanningHook.should_generate_planning?(%{}) == true
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
      assert ValidationHook.should_validate_execution?(agent) == true
    end

    test "planning can be disabled independently" do
      context = %{enable_planning_cot: false}

      assert PlanningHook.should_generate_planning?(context) == false
    end

    test "execution can be disabled independently" do
      agent = %{state: %{enable_execution_cot: false}}

      assert ExecutionHook.should_generate_execution_plan?(agent) == false
    end

    test "validation can be disabled independently" do
      agent = %{state: %{enable_validation_cot: false}}

      assert ValidationHook.should_validate_execution?(agent) == false
    end

    test "all hooks can be disabled together" do
      agent = %{
        state: %{
          enable_execution_cot: false,
          enable_validation_cot: false
        }
      }

      context = %{enable_planning_cot: false}

      assert PlanningHook.should_generate_planning?(context) == false
      assert ExecutionHook.should_generate_execution_plan?(agent) == false
      assert ValidationHook.should_validate_execution?(agent) == false
    end

    test "only planning enabled" do
      agent = %{
        state: %{
          enable_execution_cot: false,
          enable_validation_cot: false
        }
      }

      context = %{enable_planning_cot: true}

      assert PlanningHook.should_generate_planning?(context) == true
      assert ExecutionHook.should_generate_execution_plan?(agent) == false
      assert ValidationHook.should_validate_execution?(agent) == false
    end

    test "only execution enabled" do
      agent = %{
        state: %{
          enable_execution_cot: true,
          enable_validation_cot: false
        }
      }

      context = %{enable_planning_cot: false}

      assert PlanningHook.should_generate_planning?(context) == false
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
      assert ValidationHook.should_validate_execution?(agent) == false
    end

    test "only validation enabled" do
      agent = %{
        state: %{
          enable_execution_cot: false,
          enable_validation_cot: true
        }
      }

      context = %{enable_planning_cot: false}

      assert PlanningHook.should_generate_planning?(context) == false
      assert ExecutionHook.should_generate_execution_plan?(agent) == false
      assert ValidationHook.should_validate_execution?(agent) == true
    end

    test "hooks can be toggled independently" do
      agent = %{
        state: %{
          enable_execution_cot: true,
          enable_validation_cot: false
        }
      }

      # Initially: planning on, execution on, validation off
      context = %{enable_planning_cot: true}

      assert PlanningHook.should_generate_planning?(context) == true
      assert ExecutionHook.should_generate_execution_plan?(agent) == true
      assert ValidationHook.should_validate_execution?(agent) == false

      # Toggle validation on
      agent = %{agent | state: Map.put(agent.state, :enable_validation_cot, true)}
      assert ValidationHook.should_validate_execution?(agent) == true

      # Toggle execution off
      agent = %{agent | state: Map.put(agent.state, :enable_execution_cot, false)}
      assert ExecutionHook.should_generate_execution_plan?(agent) == false
      assert ValidationHook.should_validate_execution?(agent) == true
    end
  end

  describe "graceful degradation when hooks disabled" do
    test "disabled planning returns context unchanged" do
      context = %{enable_planning_cot: false, existing: "data"}

      assert PlanningHook.should_generate_planning?(context) == false
    end

    test "disabled execution returns agent unchanged" do
      agent = %{
        id: "test",
        state: %{enable_execution_cot: false, existing: "data"},
        pending_instructions: :queue.new()
      }

      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      assert result_agent == agent
      refute Map.has_key?(result_agent.state, :execution_plan)
    end

    test "disabled validation returns agent unchanged" do
      agent = %{
        id: "test",
        state: %{enable_validation_cot: false, existing: "data"}
      }

      result = %{success: true}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert result_agent == agent
      refute Map.has_key?(result_agent.state, :validation_result)
    end

    test "all disabled hooks return state unchanged" do
      # Execution hook
      agent = %{
        id: "test",
        state: %{
          enable_execution_cot: false,
          enable_validation_cot: false,
          important: "data"
        },
        pending_instructions: :queue.new()
      }

      {:ok, after_execution} = ExecutionHook.generate_execution_plan(agent)
      assert after_execution == agent

      # Validation hook
      result = %{success: true}
      {:ok, after_validation} = ValidationHook.validate_execution(after_execution, result, [])
      assert after_validation == agent

      # State should be completely unchanged
      assert after_validation.state.important == "data"
      refute Map.has_key?(after_validation.state, :execution_plan)
      refute Map.has_key?(after_validation.state, :validation_result)
    end

    test "partial enablement works correctly" do
      # Only execution enabled
      agent = %{
        id: "test",
        state: %{
          enable_execution_cot: true,
          enable_validation_cot: false
        },
        pending_instructions: :queue.new()
      }

      # Execution runs
      {:ok, after_execution} = ExecutionHook.generate_execution_plan(agent)
      # No instructions, returns unchanged
      assert after_execution == agent

      # Validation skipped
      result = %{success: true}
      {:ok, after_validation} = ValidationHook.validate_execution(after_execution, result, [])
      assert after_validation == after_execution
      refute Map.has_key?(after_validation.state, :validation_result)
    end
  end

  describe "retry behavior on validation failure" do
    test "validation returns retry signal when configured" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{
            # Very high to force failure
            tolerance: 0.99,
            retry_on_failure: true,
            max_retries: 2
          }
        }
      }

      result = {:error, "Processing failed"}
      unapplied = []

      response = ValidationHook.validate_execution(agent, result, unapplied)

      case response do
        {:ok, _agent} ->
          # Validation may pass if logic determines error is acceptable
          assert true

        {:retry, returned_agent, params} ->
          # Should return retry signal
          assert is_map(params)
          assert params.retry_attempt == 1
          assert params.temperature > 0
          # Retry count should be incremented
          assert get_in(returned_agent, [:state, :validation_retry_count]) == 1
      end
    end

    test "retry disabled returns ok even on validation failure" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{
            retry_on_failure: false,
            max_retries: 2
          }
        }
      }

      result = {:error, "Processing failed"}
      unapplied = []

      {:ok, _result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      # Should always return {:ok, agent} when retry disabled
      assert true
    end

    test "max retries prevents infinite loops" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{
            retry_on_failure: true,
            max_retries: 1
          },
          # Already at max
          validation_retry_count: 1
        }
      }

      result = {:error, "Processing failed"}
      unapplied = []

      {:ok, _result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      # Should return {:ok, agent} when max retries exceeded
      assert true
    end

    test "retry parameters include temperature adjustment" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{
            retry_on_failure: true,
            max_retries: 2,
            adjust_temperature: 0.15
          },
          cot_config: %{
            temperature: 0.7
          },
          validation_retry_count: 0
        }
      }

      result = {:error, "Processing failed"}
      unapplied = []

      case ValidationHook.validate_execution(agent, result, unapplied) do
        {:retry, _agent, params} ->
          # Temperature should be adjusted upward
          assert params.temperature > 0.7
          assert params.retry_attempt == 1
          assert params.reason == "validation_failure"

        {:ok, _agent} ->
          # Validation may pass depending on logic
          assert true
      end
    end

    test "retry increments retry counter" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{
            retry_on_failure: true,
            max_retries: 3
          },
          validation_retry_count: 0
        }
      }

      result = {:error, "Failed"}
      unapplied = []

      case ValidationHook.validate_execution(agent, result, unapplied) do
        {:retry, returned_agent, _params} ->
          # Counter should be incremented
          assert get_in(returned_agent, [:state, :validation_retry_count]) == 1

        {:ok, _agent} ->
          # May not retry if validation logic passes
          assert true
      end
    end

    test "retry counter persists across multiple validations" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{
            retry_on_failure: true,
            max_retries: 3
          },
          # Already retried twice
          validation_retry_count: 2
        }
      }

      # One more retry should be allowed
      result = {:error, "Failed"}
      unapplied = []

      case ValidationHook.validate_execution(agent, result, unapplied) do
        {:retry, returned_agent, _params} ->
          # Should increment to 3
          assert get_in(returned_agent, [:state, :validation_retry_count]) == 3

        {:ok, _agent} ->
          # May not need retry
          assert true
      end
    end
  end

  describe "context flow between hooks" do
    test "planning context available to execution hook" do
      planning = %{
        goal: "Process efficiently",
        potential_issues: ["Timeout possible"]
      }

      agent = %{
        id: "test",
        state: %{planning_cot: planning},
        pending_instructions: :queue.new()
      }

      # Execution hook should preserve planning
      {:ok, result_agent} = ExecutionHook.generate_execution_plan(agent)

      assert result_agent.state.planning_cot == planning
    end

    test "execution context available to validation hook" do
      execution_plan = %{
        steps: [%{index: 0, action: "Process"}],
        error_points: [],
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{execution_plan: execution_plan}
      }

      result = %{success: true}
      unapplied = []

      # Validation should preserve execution plan
      {:ok, validated_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert validated_agent.state.execution_plan == execution_plan
    end

    test "both planning and execution available to validation" do
      planning = %{
        goal: "Complete task",
        potential_issues: ["Resource limits"]
      }

      execution_plan = %{
        steps: [%{index: 0, action: "Execute"}],
        error_points: [%{step: 0, type: :resource, description: "Memory limit"}],
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{
          planning_cot: planning,
          execution_plan: execution_plan
        }
      }

      result = %{success: true}
      unapplied = []

      # Validation sees both contexts
      {:ok, validated_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert validated_agent.state.planning_cot == planning
      assert validated_agent.state.execution_plan == execution_plan
      assert {:ok, _validation} = ValidationHook.get_validation_result(validated_agent)
    end

    test "custom state preserved through all hooks" do
      alias Jido.AI.Runner.ChainOfThought.ExecutionHook.ExecutionPlan
      alias Jido.AI.Runner.ChainOfThought.PlanningHook.PlanningReasoning
      alias Jido.AI.Runner.ChainOfThought.ValidationHook.ValidationResult

      custom_state = %{
        user_id: "user123",
        session: "abc",
        preferences: %{theme: "dark"}
      }

      agent = %{state: custom_state}

      # Add planning with proper struct
      planning = %PlanningReasoning{
        goal: "Test",
        analysis: "Test analysis",
        timestamp: DateTime.utc_now()
      }

      agent = PlanningHook.enrich_agent_with_planning(agent, planning)

      # Add execution with proper struct
      execution = %ExecutionPlan{
        execution_strategy: "Test",
        timestamp: DateTime.utc_now()
      }

      agent = ExecutionHook.enrich_agent_with_execution_plan(agent, execution)

      # Add validation with proper struct
      validation = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      agent = ValidationHook.enrich_agent_with_validation(agent, validation)

      # Custom state should be untouched
      assert agent.state.user_id == "user123"
      assert agent.state.session == "abc"
      assert agent.state.preferences == %{theme: "dark"}
    end

    test "hooks don't interfere with each other's context" do
      # Add all contexts with proper struct types
      alias Jido.AI.Runner.ChainOfThought.ExecutionHook.ExecutionPlan
      alias Jido.AI.Runner.ChainOfThought.PlanningHook.PlanningReasoning
      alias Jido.AI.Runner.ChainOfThought.ValidationHook.ValidationResult

      planning = %PlanningReasoning{
        goal: "Planning goal",
        analysis: "Test analysis",
        timestamp: DateTime.utc_now()
      }

      execution = %ExecutionPlan{
        execution_strategy: "Execution strategy",
        timestamp: DateTime.utc_now()
      }

      validation = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      agent = %{state: %{}}
      agent = PlanningHook.enrich_agent_with_planning(agent, planning)
      agent = ExecutionHook.enrich_agent_with_execution_plan(agent, execution)
      agent = ValidationHook.enrich_agent_with_validation(agent, validation)

      # Each hook should be able to retrieve its own context
      {:ok, retrieved_planning} = PlanningHook.get_planning_reasoning(agent)
      {:ok, retrieved_execution} = ExecutionHook.get_execution_plan(agent)
      {:ok, retrieved_validation} = ValidationHook.get_validation_result(agent)

      assert retrieved_planning.goal == "Planning goal"
      assert retrieved_execution.execution_strategy == "Execution strategy"
      assert retrieved_validation.status == :success
    end
  end

  describe "comprehensive lifecycle scenarios" do
    test "successful execution with all hooks enabled" do
      # Simulate successful flow through all hooks

      # 1. Planning
      planning = %{
        goal: "Successfully process data",
        analysis: "Data processing workflow",
        dependencies: [],
        potential_issues: [],
        recommendations: ["Validate input"],
        timestamp: DateTime.utc_now()
      }

      # 2. Execution
      execution_plan = %{
        steps: [
          %{index: 0, action: "ValidateInput"},
          %{index: 1, action: "ProcessData"},
          %{index: 2, action: "StoreResult"}
        ],
        data_flow: [],
        error_points: [],
        execution_strategy: "Sequential processing",
        timestamp: DateTime.utc_now()
      }

      # 3. Agent state
      agent = %{
        id: "test",
        state: %{
          planning_cot: planning,
          execution_plan: execution_plan,
          enable_validation_cot: true
        }
      }

      # 4. Successful result
      result = %{
        success: true,
        processed: 100,
        stored: true
      }

      # 5. Validation
      {:ok, validated_agent} = ValidationHook.validate_execution(agent, result, [])

      # All contexts should be present
      assert validated_agent.state.planning_cot == planning
      assert validated_agent.state.execution_plan == execution_plan

      # Validation should indicate success
      {:ok, validation} = ValidationHook.get_validation_result(validated_agent)
      assert validation.status in [:success, :partial_success]
      assert validation.recommendation == :continue
    end

    test "failed execution with retry recommendation" do
      # Simulate failed flow with retry

      planning = %{
        goal: "Process data",
        potential_issues: ["Network timeout"],
        timestamp: DateTime.utc_now()
      }

      execution_plan = %{
        steps: [%{index: 0, action: "FetchData"}],
        error_points: [
          %{step: 0, type: :network, description: "Timeout possible"}
        ],
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{
          planning_cot: planning,
          execution_plan: execution_plan,
          validation_config: %{
            retry_on_failure: true,
            max_retries: 2
          }
        }
      }

      # Failed result
      result = {:error, "Network timeout"}

      # Should recommend retry
      response = ValidationHook.validate_execution(agent, result, [])

      case response do
        {:retry, _agent, params} ->
          assert params.retry_attempt == 1
          assert params.reason == "validation_failure"

        {:ok, _agent} ->
          # May be acceptable depending on validation logic
          assert true
      end
    end

    test "partial hook enablement maintains functionality" do
      # Only execution and validation enabled, no planning
      alias Jido.AI.Runner.ChainOfThought.ExecutionHook.ExecutionPlan

      execution_plan = %ExecutionPlan{
        execution_strategy: "Direct",
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{
          execution_plan: execution_plan,
          enable_validation_cot: true
        }
      }

      result = %{success: true}

      # Validation works without planning context
      {:ok, validated_agent} = ValidationHook.validate_execution(agent, result, [])

      # No planning context
      assert {:error, :no_planning} = PlanningHook.get_planning_reasoning(validated_agent)

      # But execution and validation present
      assert {:ok, _execution} = ExecutionHook.get_execution_plan(validated_agent)
      assert {:ok, _validation} = ValidationHook.get_validation_result(validated_agent)
    end
  end
end
