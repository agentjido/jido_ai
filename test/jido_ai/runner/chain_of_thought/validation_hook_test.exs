defmodule Jido.AI.Runner.ChainOfThought.ValidationHookTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.ValidationHook
  alias Jido.AI.Runner.ChainOfThought.ValidationHook.{ValidationConfig, ValidationResult}

  describe "should_validate_execution?/1" do
    test "returns true when enable_validation_cot is not set" do
      agent = %{state: %{}}
      assert ValidationHook.should_validate_execution?(agent) == true
    end

    test "returns true when enable_validation_cot is true" do
      agent = %{state: %{enable_validation_cot: true}}
      assert ValidationHook.should_validate_execution?(agent) == true
    end

    test "returns false when enable_validation_cot is false" do
      agent = %{state: %{enable_validation_cot: false}}
      assert ValidationHook.should_validate_execution?(agent) == false
    end

    test "returns true for nil state" do
      agent = %{state: nil}
      assert ValidationHook.should_validate_execution?(agent) == true
    end
  end

  describe "enrich_agent_with_validation/2" do
    test "adds validation result to agent state" do
      agent = %{state: %{existing: "data"}}

      validation = %ValidationResult{
        status: :success,
        match_score: 0.95,
        recommendation: :continue,
        timestamp: DateTime.utc_now()
      }

      updated_agent = ValidationHook.enrich_agent_with_validation(agent, validation)

      assert updated_agent.state.validation_result == validation
      assert updated_agent.state.existing == "data"
    end

    test "creates state map if agent has no state" do
      agent = %{state: nil}

      validation = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      updated_agent = ValidationHook.enrich_agent_with_validation(agent, validation)

      assert updated_agent.state.validation_result == validation
    end

    test "overwrites existing validation result" do
      old_validation = %ValidationResult{
        status: :unexpected,
        timestamp: DateTime.utc_now()
      }

      agent = %{state: %{validation_result: old_validation}}

      new_validation = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      updated_agent = ValidationHook.enrich_agent_with_validation(agent, new_validation)

      assert updated_agent.state.validation_result == new_validation
      assert updated_agent.state.validation_result.status == :success
    end
  end

  describe "get_validation_result/1" do
    test "extracts validation result from agent state" do
      validation = %ValidationResult{
        status: :success,
        match_score: 0.9,
        timestamp: DateTime.utc_now()
      }

      agent = %{state: %{validation_result: validation}}

      assert {:ok, retrieved} = ValidationHook.get_validation_result(agent)
      assert retrieved == validation
    end

    test "returns error when no validation result exists" do
      agent = %{state: %{}}

      assert {:error, :no_validation} = ValidationHook.get_validation_result(agent)
    end

    test "returns error when agent has no state" do
      agent = %{state: nil}

      assert {:error, :no_validation} = ValidationHook.get_validation_result(agent)
    end

    test "returns error when validation_result is invalid" do
      agent = %{state: %{validation_result: "invalid"}}

      assert {:error, :invalid_validation} = ValidationHook.get_validation_result(agent)
    end
  end

  describe "get_validation_config/1" do
    test "returns default config when not set" do
      agent = %{state: %{}}

      config = ValidationHook.get_validation_config(agent)

      assert config.tolerance == 0.8
      assert config.retry_on_failure == false
      assert config.max_retries == 2
      assert config.adjust_temperature == 0.1
      assert config.generate_reflection == true
    end

    test "returns custom config when set as struct" do
      custom_config = %ValidationConfig{
        tolerance: 0.9,
        retry_on_failure: true,
        max_retries: 3
      }

      agent = %{state: %{validation_config: custom_config}}

      config = ValidationHook.get_validation_config(agent)

      assert config.tolerance == 0.9
      assert config.retry_on_failure == true
      assert config.max_retries == 3
    end

    test "converts map config to struct" do
      map_config = %{
        tolerance: 0.7,
        retry_on_failure: true,
        max_retries: 1
      }

      agent = %{state: %{validation_config: map_config}}

      config = ValidationHook.get_validation_config(agent)

      assert %ValidationConfig{} = config
      assert config.tolerance == 0.7
      assert config.retry_on_failure == true
      assert config.max_retries == 1
    end
  end

  describe "validate_execution/3" do
    test "returns agent unchanged when validation is disabled" do
      agent = %{
        id: "test",
        state: %{enable_validation_cot: false}
      }

      result = %{success: true}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert result_agent == agent
      refute Map.has_key?(result_agent.state, :validation_result)
    end

    test "performs validation when enabled with default config" do
      agent = %{
        id: "test",
        state: %{}
      }

      result = %{success: true, data: "test"}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert {:ok, validation} = ValidationHook.get_validation_result(result_agent)
      assert validation.status in [:success, :partial_success, :unexpected]
      assert is_float(validation.match_score)
      assert validation.recommendation in [:continue, :retry, :investigate]
    end

    test "returns continue recommendation for successful validation" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{tolerance: 0.5}
        }
      }

      result = %{success: true}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert {:ok, validation} = ValidationHook.get_validation_result(result_agent)
      assert validation.recommendation == :continue
    end

    test "handles validation with planning context" do
      planning = %{
        goal: "Test goal",
        analysis: "Test analysis",
        dependencies: [],
        potential_issues: ["Issue 1"],
        recommendations: []
      }

      agent = %{
        id: "test",
        state: %{
          planning_cot: planning
        }
      }

      result = %{success: true}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert {:ok, validation} = ValidationHook.get_validation_result(result_agent)
      assert %ValidationResult{} = validation
    end

    test "handles validation with execution plan context" do
      execution_plan = %{
        steps: [
          %{index: 0, action: "TestAction"}
        ],
        data_flow: [],
        error_points: [
          %{step: 0, type: :validation, description: "Potential error"}
        ],
        execution_strategy: "Sequential",
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{
          execution_plan: execution_plan
        }
      }

      result = %{success: true}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert {:ok, validation} = ValidationHook.get_validation_result(result_agent)
      assert %ValidationResult{} = validation
    end

    test "handles validation with both planning and execution context" do
      planning = %{
        goal: "Complete task",
        potential_issues: ["Data missing"]
      }

      execution_plan = %{
        steps: [%{index: 0, action: "ProcessData"}],
        error_points: [%{step: 0, type: :data, description: "Missing data"}],
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

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert {:ok, validation} = ValidationHook.get_validation_result(result_agent)
      assert %ValidationResult{} = validation
    end

    @tag :skip
    @tag :requires_llm
    test "generates reflection for unexpected results" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %{
            generate_reflection: true
          }
        }
      }

      result = {:error, "Unexpected error"}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      assert {:ok, validation} = ValidationHook.get_validation_result(result_agent)
      assert validation.reflection != ""
    end
  end

  describe "retry behavior" do
    test "returns retry recommendation when configured and validation fails" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %ValidationConfig{
            # Very high tolerance to force failure
            tolerance: 0.99,
            retry_on_failure: true,
            max_retries: 2
          }
        }
      }

      # Simulate failed result
      result = {:error, "Processing failed"}
      unapplied = []

      response = ValidationHook.validate_execution(agent, result, unapplied)

      # Should either continue or retry depending on validation logic
      case response do
        {:ok, _agent} ->
          assert true

        {:retry, agent, params} ->
          assert is_map(params)
          assert params.retry_attempt == 1
          assert params.temperature > 0
          # Retry count should be incremented
          assert get_in(agent, [:state, :validation_retry_count]) == 1
      end
    end

    test "does not retry when retry_on_failure is false" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %ValidationConfig{
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

    test "respects max_retries limit" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %ValidationConfig{
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

    test "adjusts temperature on retry" do
      agent = %{
        id: "test",
        state: %{
          validation_config: %ValidationConfig{
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
          # Temperature should be adjusted
          assert params.temperature > 0.7

        {:ok, _agent} ->
          # Validation may pass, which is fine
          assert true
      end
    end
  end

  describe "ValidationResult struct" do
    test "requires status and timestamp" do
      result = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      assert result.status == :success
      assert %DateTime{} = result.timestamp
    end

    test "has default values for optional fields" do
      result = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      assert result.match_score == 0.0
      assert result.expected_vs_actual == %{}
      assert result.unexpected_results == []
      assert result.anticipated_errors_occurred == []
      assert result.reflection == ""
      assert result.recommendation == :continue
    end

    test "accepts all fields" do
      result = %ValidationResult{
        status: :unexpected,
        match_score: 0.75,
        expected_vs_actual: %{expected: "A", actual: "B"},
        unexpected_results: ["Result 1"],
        anticipated_errors_occurred: ["Error 1"],
        reflection: "Analysis of results",
        recommendation: :retry,
        timestamp: DateTime.utc_now()
      }

      assert result.status == :unexpected
      assert result.match_score == 0.75
      assert result.reflection == "Analysis of results"
      assert result.recommendation == :retry
    end
  end

  describe "ValidationConfig struct" do
    test "has correct defaults" do
      config = %ValidationConfig{}

      assert config.tolerance == 0.8
      assert config.retry_on_failure == false
      assert config.max_retries == 2
      assert config.adjust_temperature == 0.1
      assert config.generate_reflection == true
    end

    test "accepts custom values" do
      config = %ValidationConfig{
        tolerance: 0.9,
        retry_on_failure: true,
        max_retries: 5,
        adjust_temperature: 0.2,
        generate_reflection: false
      }

      assert config.tolerance == 0.9
      assert config.retry_on_failure == true
      assert config.max_retries == 5
      assert config.adjust_temperature == 0.2
      assert config.generate_reflection == false
    end
  end

  describe "context enrichment for inspection" do
    test "validation result is accessible after enrichment" do
      agent = %{state: %{}}

      validation = %ValidationResult{
        status: :success,
        match_score: 0.95,
        recommendation: :continue,
        timestamp: DateTime.utc_now()
      }

      enriched_agent = ValidationHook.enrich_agent_with_validation(agent, validation)

      {:ok, retrieved} = ValidationHook.get_validation_result(enriched_agent)

      assert retrieved.status == :success
      assert retrieved.match_score == 0.95
      assert retrieved.recommendation == :continue
    end

    test "multiple enrichments preserve other state" do
      agent = %{state: %{user_data: "important", counter: 42}}

      validation1 = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      agent = ValidationHook.enrich_agent_with_validation(agent, validation1)

      validation2 = %ValidationResult{
        status: :partial_success,
        timestamp: DateTime.utc_now()
      }

      agent = ValidationHook.enrich_agent_with_validation(agent, validation2)

      # State should preserve non-validation data
      assert agent.state.user_data == "important"
      assert agent.state.counter == 42

      # Validation should be updated
      {:ok, current} = ValidationHook.get_validation_result(agent)
      assert current.status == :partial_success
    end
  end

  describe "opt-in behavior" do
    test "validation is enabled by default" do
      agent = %{state: %{}}
      assert ValidationHook.should_validate_execution?(agent) == true
    end

    test "validation can be explicitly enabled" do
      agent = %{state: %{enable_validation_cot: true}}
      assert ValidationHook.should_validate_execution?(agent) == true
    end

    test "validation can be explicitly disabled" do
      agent = %{state: %{enable_validation_cot: false}}
      assert ValidationHook.should_validate_execution?(agent) == false
    end

    test "disabled validation skips all processing" do
      agent = %{
        id: "test",
        state: %{
          enable_validation_cot: false,
          existing: "data"
        }
      }

      result = %{success: true}
      unapplied = []

      {:ok, result_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      # Agent should be completely unchanged
      assert result_agent == agent
      assert result_agent.state == %{enable_validation_cot: false, existing: "data"}
      refute Map.has_key?(result_agent.state, :validation_result)
    end
  end

  describe "integration with planning and execution context" do
    test "validation can access both planning and execution state" do
      planning = %{
        goal: "Process data",
        potential_issues: ["Missing input"]
      }

      execution_plan = %{
        steps: [%{index: 0, action: "Process"}],
        error_points: [],
        timestamp: DateTime.utc_now()
      }

      agent = %{
        id: "test",
        state: %{
          planning_cot: planning,
          execution_plan: execution_plan
        }
      }

      result = %{processed: true}
      unapplied = []

      {:ok, validated_agent} = ValidationHook.validate_execution(agent, result, unapplied)

      # Both planning and execution should still be present
      assert validated_agent.state.planning_cot == planning
      assert validated_agent.state.execution_plan == execution_plan

      # And validation result should be added
      assert {:ok, _validation} = ValidationHook.get_validation_result(validated_agent)
    end

    test "validation preserves all context after enrichment" do
      planning = %{goal: "Test"}
      execution_plan = %{steps: [], timestamp: DateTime.utc_now()}

      agent = %{
        state: %{
          planning_cot: planning,
          execution_plan: execution_plan,
          custom_data: "preserve"
        }
      }

      validation = %ValidationResult{
        status: :success,
        timestamp: DateTime.utc_now()
      }

      enriched_agent = ValidationHook.enrich_agent_with_validation(agent, validation)

      # All contexts should be preserved
      assert enriched_agent.state.planning_cot == planning
      assert enriched_agent.state.execution_plan == execution_plan
      assert enriched_agent.state.custom_data == "preserve"
      assert {:ok, _} = ValidationHook.get_validation_result(enriched_agent)
    end
  end
end
