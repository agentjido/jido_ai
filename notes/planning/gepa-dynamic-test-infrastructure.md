# Plan: Dynamic Behavior-Based Test Infrastructure for GEPA

**Status**: Approved - Ready for Implementation
**Branch**: `fix/test-failures-post-reqllm-merge`
**Created**: 2025-10-22
**Estimated Time**: 5-8 hours

## Overview

Implement a behavior-based, dynamically-generated test system for GEPA that mocks the Model/LLM layer without requiring real API keys. This will fix all 51 GEPA test failures by intercepting calls at the model execution level.

## Problem Statement

After merging `feature/integrate_req_llm` into `feature/cot`, 51 GEPA tests are failing due to:
- Missing API keys (OPENAI_API_KEY not configured)
- Tests attempting real API calls instead of using mocks
- No existing mock infrastructure for ReqLLM/Model layer

**Current Failures**:
- 20 tests in `test/jido/runner/gepa/evaluator_test.exs`
- 31 tests in `test/jido/runner/gepa/evaluation_system_integration_test.exs`
- All failures: `Authentication error: API key not found`

## Solution Architecture

### 1. Define Model Test Behavior

**File**: `test/support/model_test_behaviour.ex`

Define a behavior that any testable model must implement:

```elixir
defmodule Jido.AI.Model.TestBehaviour do
  @moduledoc """
  Behavior for testable AI models in GEPA evaluations.

  This behavior defines the contract for mock models used in testing,
  allowing dynamic generation of model fixtures with configurable outcomes.
  """

  @callback chat_completion(model :: term(), prompt :: String.t()) ::
    {:ok, String.t()} | {:error, term()}

  @callback calculate_fitness(execution_result :: term()) :: float()

  @callback simulate_execution(model :: term(), opts :: keyword()) ::
    {:ok, map()} | {:error, term()}

  @callback with_failure(mock :: term(), failure_type :: atom()) :: term()

  @callback with_timeout(mock :: term()) :: term()
end
```

**Callbacks**:
- `chat_completion/2` - Return mock chat response for given prompt
- `calculate_fitness/1` - Calculate fitness score (0.0-1.0) for GEPA
- `simulate_execution/2` - Simulate full agent execution with controllable outcomes
- `with_failure/2` - Configure mock to return specific failures (:timeout, :error, :partial)
- `with_timeout/1` - Configure mock to simulate timeout scenario

### 2. Create Dynamic Test Fixtures Generator

**File**: `test/support/gepa_test_fixtures.ex`

Generate mock models at runtime with configurable behavior:

```elixir
defmodule Jido.Runner.GEPA.TestFixtures do
  @moduledoc """
  Dynamic test fixture generation for GEPA evaluations.

  Provides functions to generate mock models, scenarios, and test data
  for comprehensive GEPA testing without real API calls.
  """

  @doc """
  Generates a mock model for the specified provider.

  ## Options
  - `:scenario` - Test scenario (:success, :timeout, :failure, etc.)
  - `:fitness` - Specific fitness score (0.0-1.0)
  - `:latency` - Simulated response latency in ms
  - `:trajectory` - Custom trajectory data

  ## Examples

      generate_mock_model(:openai, scenario: :success)
      generate_mock_model(:anthropic, fitness: 0.85, latency: 100)
  """
  def generate_mock_model(provider, opts \\ [])

  @doc """
  Returns list of all test scenarios.
  """
  def test_scenarios() do
    [:success, :timeout, :failure, :partial, :high_fitness, :low_fitness, :error]
  end

  @doc """
  Builds a mock response for the given scenario.
  """
  def build_mock_response(scenario, context)

  @doc """
  Generates a valid trajectory for the given scenario.
  """
  def build_trajectory_for_scenario(scenario)

  @doc """
  Generates metrics data matching the scenario.
  """
  def build_metrics_for_scenario(scenario)
end
```

**Key Features**:
- Parameterized model generation (providers: `:openai`, `:anthropic`, `:local`)
- Scenario-based responses (success, error, timeout, partial)
- Configurable fitness scores
- Trajectory generation for valid test data
- Metrics generation matching scenarios

### 3. Create GEPA Test Helper Module

**File**: `test/support/gepa_test_helper.ex`

Provides utilities for setting up mocked GEPA tests:

```elixir
defmodule Jido.Runner.GEPA.TestHelper do
  @moduledoc """
  Helper functions for GEPA evaluation tests.

  Provides setup, assertions, and utilities for testing GEPA
  evaluations with mocked models.
  """

  import Mimic

  @doc """
  Sets up a mock model in the test context.

  ## Examples

      setup do
        setup_mock_model(:openai, scenario: :success)
      end
  """
  def setup_mock_model(provider, opts \\ [])

  @doc """
  Wraps test execution with a mocked evaluator.
  """
  def with_mock_evaluator(config, test_fn)

  @doc """
  Custom assertions for GEPA evaluation results.
  """
  def assert_evaluation_result(result, expectations)

  @doc """
  Verifies trajectory structure and content.
  """
  def assert_valid_trajectory(trajectory)

  @doc """
  Verifies metrics structure and ranges.
  """
  def assert_valid_metrics(metrics)
end
```

**Integration with Mimic**:
- Stub `Jido.AI.Actions.Internal.ChatResponse.run/2`
- Stub `Jido.AI.Actions.ReqLlm.ChatCompletion.run/2`
- Stub `Jido.Agent.Server.start_link/1` to use mock models
- Clean setup/teardown for each test

### 4. Implement Dynamic Test Generation Macros

**File**: `test/support/gepa_test_case.ex`

Macro-based test generation for running tests across multiple model types:

```elixir
defmodule Jido.Runner.GEPA.TestCase do
  @moduledoc """
  Test case template for GEPA evaluations.

  Provides macros for generating tests across multiple model providers
  and scenarios dynamically.
  """

  defmacro __using__(_opts) do
    quote do
      import Jido.Runner.GEPA.TestFixtures
      import Jido.Runner.GEPA.TestHelper
      import Jido.Runner.GEPA.TestCase
    end
  end

  @doc """
  Generates test cases for each specified model provider.

  ## Examples

      test_with_models "evaluates successfully", [:openai, :anthropic] do
        {:ok, result} = Evaluator.evaluate_prompt("test", task: %{type: :reasoning})
        assert result.error == nil
      end

      # Generates 2 tests:
      # - "evaluates successfully (openai)"
      # - "evaluates successfully (anthropic)"
  """
  defmacro test_with_models(description, providers, do: block)

  @doc """
  Generates test cases for each scenario.

  ## Examples

      test_with_scenarios "handles scenario", [:success, :timeout, :failure] do |scenario|
        # Test with specific scenario
      end
  """
  defmacro test_with_scenarios(description, scenarios, do: block)
end
```

### 5. Refactor GEPA Tests

**Files to Modify**:
- `test/jido/runner/gepa/evaluator_test.exs` (20 tests)
- `test/jido/runner/gepa/evaluation_system_integration_test.exs` (31 tests)

**Changes**:
- Add `use Jido.Runner.GEPA.TestCase` to test modules
- Replace real model initialization with `setup_mock_model`
- Use `test_with_models` macro for parameterized tests
- Remove hardcoded provider configuration (`:openai`, `gpt-4`)
- Add scenario-based test cases (success, failure, timeout)
- Use helper assertions (`assert_evaluation_result`, etc.)

**Example Transformation**:

```elixir
# BEFORE
test "evaluates a single prompt successfully" do
  prompt = "Think step by step"
  task = %{type: :reasoning, prompt: "What is 2+2?"}

  {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

  assert %EvaluationResult{} = result
  assert result.prompt == prompt
  assert is_float(result.fitness)
  assert result.fitness >= 0.0
  assert result.fitness <= 1.0
end

# AFTER
test_with_models "evaluates a single prompt successfully", [:openai, :anthropic, :local] do
  prompt = "Think step by step"
  task = %{type: :reasoning, prompt: "What is 2+2?"}

  {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

  assert_evaluation_result(result, %{
    prompt: prompt,
    fitness_range: {0.0, 1.0},
    error: nil
  })
end
```

## Implementation Steps

### Stage 1: Foundation (1-2 hours)

**Goal**: Establish core behavior and fixture infrastructure

1. **Create `ModelTestBehaviour`** (30 min)
   - Define callbacks for chat completion, fitness, execution
   - Document behavior contract
   - Add type specs

2. **Create `GepaTestFixtures` skeleton** (30 min)
   - Implement `generate_mock_model/2` basic version
   - Implement `test_scenarios/0`
   - Add module documentation

3. **Set up `GepaTestHelper`** (30 min)
   - Implement `setup_mock_model/2`
   - Configure Mimic stubs for ChatResponse
   - Add basic assertions

4. **Write validation test** (30 min)
   - Create simple test using new infrastructure
   - Verify mock injection works
   - Confirm no real API calls made

**Validation**: Single test passes using mock model, no API calls

### Stage 2: Dynamic Generation (2-3 hours)

**Goal**: Complete fixture generation and macro system

5. **Implement `generate_mock_model/2`** (1 hour)
   - Handle all provider types
   - Implement scenario configuration
   - Add fitness customization
   - Generate trajectory data

6. **Create scenario generation** (30 min)
   - Implement `build_mock_response/2`
   - Implement `build_trajectory_for_scenario/1`
   - Implement `build_metrics_for_scenario/1`

7. **Build trajectory generators** (30 min)
   - Success trajectory with steps
   - Timeout trajectory (incomplete)
   - Failure trajectory with errors
   - Partial trajectory

8. **Implement `test_with_models` macro** (1 hour)
   - Parse macro arguments
   - Generate test cases dynamically
   - Support provider-specific configuration
   - Add test name suffixing

**Validation**: Macro generates tests correctly, all scenarios work

### Stage 3: Test Migration (2-3 hours)

**Goal**: Update all GEPA tests to use new infrastructure

9. **Refactor `evaluator_test.exs`** (1-1.5 hours)
   - Add `use Jido.Runner.GEPA.TestCase`
   - Update setup blocks
   - Convert 20 tests to use mocks
   - Replace assertions with helpers

10. **Refactor `evaluation_system_integration_test.exs`** (1-1.5 hours)
    - Add `use Jido.Runner.GEPA.TestCase`
    - Update complex integration tests
    - Convert 31 tests to use mocks
    - Ensure batch operations work

11. **Add scenario-based tests** (30 min)
    - Add explicit timeout tests
    - Add explicit failure tests
    - Add edge case tests

12. **Verify zero failures** (30 min)
    - Run full GEPA test suite
    - Fix any issues
    - Confirm all 51 tests pass

**Validation**: All 51 GEPA tests pass, run in < 5 seconds

### Stage 4: Documentation & Cleanup (30 min)

**Goal**: Document system and finalize implementation

13. **Document test behavior system** (15 min)
    - Add comprehensive module docs
    - Add usage examples
    - Document patterns and best practices

14. **Create examples** (10 min)
    - Add example test file
    - Show common patterns
    - Document troubleshooting

15. **Update planning documents** (5 min)
    - Mark GEPA test fixes complete
    - Update feature planning doc
    - Add to completion summary

**Validation**: Documentation complete, ready for commit

## Detailed File Changes

### New Files

#### `test/support/model_test_behaviour.ex`

```elixir
defmodule Jido.AI.Model.TestBehaviour do
  @moduledoc """
  Behavior for testable AI models in GEPA evaluations.
  """

  @callback chat_completion(model :: term(), prompt :: String.t()) ::
    {:ok, String.t()} | {:error, term()}

  @callback calculate_fitness(execution_result :: term()) :: float()

  @callback simulate_execution(model :: term(), opts :: keyword()) ::
    {:ok, map()} | {:error, term()}

  @callback with_failure(mock :: term(), failure_type :: atom()) :: term()

  @callback with_timeout(mock :: term()) :: term()
end
```

#### `test/support/gepa_test_fixtures.ex`

```elixir
defmodule Jido.Runner.GEPA.TestFixtures do
  @moduledoc """
  Dynamic test fixture generation for GEPA evaluations.
  """

  alias Jido.Runner.GEPA.Trajectory
  alias Jido.Runner.GEPA.Metrics

  def generate_mock_model(provider, opts \\ []) do
    scenario = Keyword.get(opts, :scenario, :success)
    fitness = Keyword.get(opts, :fitness, calculate_default_fitness(scenario))
    latency = Keyword.get(opts, :latency, 100)

    %{
      provider: provider,
      scenario: scenario,
      fitness: fitness,
      latency: latency,
      response_fn: build_response_fn(scenario),
      trajectory: build_trajectory_for_scenario(scenario),
      metrics: build_metrics_for_scenario(scenario)
    }
  end

  def test_scenarios do
    [:success, :timeout, :failure, :partial, :high_fitness, :low_fitness, :error]
  end

  def build_mock_response(scenario, context) do
    case scenario do
      :success -> {:ok, "Mock successful response for: #{context.prompt}"}
      :timeout -> {:error, :timeout}
      :failure -> {:error, :evaluation_failed}
      :partial -> {:ok, "Partial response"}
      :error -> {:error, :llm_error}
      _ -> {:ok, "Mock response"}
    end
  end

  def build_trajectory_for_scenario(scenario) do
    base_trajectory = Trajectory.new(metadata: %{scenario: scenario})

    case scenario do
      :success -> add_success_steps(base_trajectory)
      :timeout -> add_timeout_steps(base_trajectory)
      :failure -> add_failure_steps(base_trajectory)
      :partial -> add_partial_steps(base_trajectory)
      _ -> base_trajectory
    end
  end

  def build_metrics_for_scenario(scenario) do
    base_metrics = %{duration_ms: 100, success: false}

    case scenario do
      :success -> %{base_metrics | success: true}
      :timeout -> %{base_metrics | timeout: true}
      :failure -> %{base_metrics | error: true}
      _ -> base_metrics
    end
  end

  # Private helpers

  defp calculate_default_fitness(scenario) do
    case scenario do
      :success -> 0.85
      :high_fitness -> 0.95
      :low_fitness -> 0.3
      :partial -> 0.5
      _ -> 0.0
    end
  end

  defp build_response_fn(scenario) do
    fn prompt -> build_mock_response(scenario, %{prompt: prompt}) end
  end

  defp add_success_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(:reasoning, "Analyzing prompt")
    |> Trajectory.add_step(:action, "Executing task")
    |> Trajectory.add_step(:observation, "Task completed successfully")
  end

  defp add_timeout_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(:reasoning, "Starting analysis")
    |> Trajectory.add_step(:action, "Long running operation")
    # Incomplete - simulates timeout
  end

  defp add_failure_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(:reasoning, "Attempting task")
    |> Trajectory.add_step(:action, "Operation failed", %{error: true})
  end

  defp add_partial_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(:reasoning, "Partial analysis")
    |> Trajectory.add_step(:action, "Incomplete execution")
  end
end
```

#### `test/support/gepa_test_helper.ex`

```elixir
defmodule Jido.Runner.GEPA.TestHelper do
  @moduledoc """
  Helper functions for GEPA evaluation tests.
  """

  import Mimic
  import ExUnit.Assertions

  alias Jido.Runner.GEPA.TestFixtures
  alias Jido.Runner.GEPA.Evaluator.EvaluationResult

  def setup_mock_model(provider, opts \\ []) do
    mock = TestFixtures.generate_mock_model(provider, opts)

    # Stub ChatResponse to return mock responses
    stub(Jido.AI.Actions.Internal.ChatResponse, :run, fn _params, _context ->
      Process.sleep(mock.latency)

      case mock.scenario do
        :timeout -> {:error, :timeout}
        :error -> {:error, :llm_error}
        _ -> {:ok, %{content: "Mock response", metadata: %{}}}
      end
    end)

    # Stub Agent.Server.start_link to use mock configuration
    stub(Jido.Agent.Server, :start_link, fn _opts ->
      {:ok, spawn(fn -> receive do _ -> :ok end end)}
    end)

    {:ok, %{mock_model: mock}}
  end

  def with_mock_evaluator(config, test_fn) do
    setup_mock_model(config.provider, config.opts)
    test_fn.()
  end

  def assert_evaluation_result(result, expectations) do
    assert %EvaluationResult{} = result

    if prompt = expectations[:prompt] do
      assert result.prompt == prompt
    end

    if {min, max} = expectations[:fitness_range] do
      if result.fitness do
        assert result.fitness >= min
        assert result.fitness <= max
      end
    end

    if error = expectations[:error] do
      assert result.error == error
    end

    if success = expectations[:success] do
      assert result.metrics.success == success
    end
  end

  def assert_valid_trajectory(trajectory) do
    assert is_map(trajectory)
    assert Map.has_key?(trajectory, :steps) or Map.has_key?(trajectory, :id)
  end

  def assert_valid_metrics(metrics) do
    assert is_map(metrics)
    assert Map.has_key?(metrics, :duration_ms)
    assert Map.has_key?(metrics, :success)
    assert is_integer(metrics.duration_ms)
    assert is_boolean(metrics.success)
  end
end
```

#### `test/support/gepa_test_case.ex`

```elixir
defmodule Jido.Runner.GEPA.TestCase do
  @moduledoc """
  Test case template for GEPA evaluations.
  """

  defmacro __using__(_opts) do
    quote do
      import Jido.Runner.GEPA.TestFixtures
      import Jido.Runner.GEPA.TestHelper
      import Jido.Runner.GEPA.TestCase
    end
  end

  defmacro test_with_models(description, providers, do: block) do
    for provider <- providers do
      test_name = "#{description} (#{provider})"

      quote do
        test unquote(test_name) do
          setup_mock_model(unquote(provider), scenario: :success)
          unquote(block)
        end
      end
    end
  end

  defmacro test_with_scenarios(description, scenarios, do: block) do
    for scenario <- scenarios do
      test_name = "#{description} (#{scenario})"

      quote do
        test unquote(test_name) do
          setup_mock_model(:openai, scenario: unquote(scenario))
          var!(scenario) = unquote(scenario)
          unquote(block)
        end
      end
    end
  end
end
```

### Modified Files

#### `test/jido/runner/gepa/evaluator_test.exs`

```elixir
defmodule Jido.Runner.GEPA.EvaluatorTest do
  use ExUnit.Case, async: true
  use Jido.Runner.GEPA.TestCase  # NEW!

  alias Jido.Runner.GEPA.Evaluator
  alias Jido.Runner.GEPA.Evaluator.EvaluationResult

  # NEW: Setup mock model for all tests
  setup do
    setup_mock_model(:openai, scenario: :success)
  end

  describe "evaluate_prompt/2" do
    # UPDATED: Use test_with_models macro
    test_with_models "evaluates a single prompt successfully", [:openai, :anthropic] do
      prompt = "Think step by step and solve the problem"
      task = %{type: :reasoning, prompt: "What is 2+2?"}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # UPDATED: Use helper assertions
      assert_evaluation_result(result, %{
        prompt: prompt,
        fitness_range: {0.0, 1.0},
        error: nil,
        success: true
      })
    end

    # ... other tests updated similarly
  end
end
```

## Benefits

### 1. **Zero Real API Calls**
- All tests use mocks
- No authentication required
- No API quota consumption
- No network dependencies

### 2. **Fast Execution**
- No network latency
- Tests run in milliseconds
- Full suite < 5 seconds
- Parallel execution safe

### 3. **Deterministic**
- Controlled outcomes
- Reproducible results
- No flaky tests
- Predictable timing

### 4. **Extensible**
- Easy to add new scenarios
- Simple to add new providers
- Flexible configuration
- Reusable components

### 5. **Maintainable**
- Single source of truth for mocks
- Centralized behavior definition
- Clear separation of concerns
- Well-documented patterns

### 6. **Comprehensive**
- Can test edge cases reliably
- Timeout scenarios controllable
- Failure modes testable
- Integration test support

## Success Criteria

- ✅ All 51 GEPA tests pass
- ✅ No real API calls made during tests
- ✅ Tests run in < 5 seconds total
- ✅ Zero test failures in full suite
- ✅ Easy to add new test scenarios
- ✅ Clear documentation for adding tests
- ✅ Mock behavior matches real API structure
- ✅ Integration tests work with mocks
- ✅ Concurrent tests don't interfere
- ✅ Cleanup happens properly

## Timeline

**Total Estimated Time**: 5-8 hours

- **Stage 1: Foundation** - 1-2 hours
  - Model behavior definition
  - Basic fixtures
  - Mock setup
  - Validation test

- **Stage 2: Dynamic Generation** - 2-3 hours
  - Complete fixture generation
  - Scenario system
  - Trajectory/metrics builders
  - Test generation macros

- **Stage 3: Test Migration** - 2-3 hours
  - Update evaluator tests (20)
  - Update integration tests (31)
  - Add scenario tests
  - Verify all pass

- **Stage 4: Documentation** - 30 minutes
  - Module documentation
  - Usage examples
  - Planning updates

## Risks & Mitigations

### Risk 1: Mocks Don't Match Real Behavior
**Impact**: High
**Probability**: Medium
**Mitigation**:
- Base mock responses on actual API response structures
- Validate mock structure against real responses
- Create separate integration test suite for real API validation
- Document differences between mock and real behavior

### Risk 2: Over-Abstraction Makes Tests Hard to Understand
**Impact**: Medium
**Probability**: Medium
**Mitigation**:
- Keep behavior simple and focused
- Provide clear examples in documentation
- Use descriptive names for functions and scenarios
- Add inline comments explaining complex logic

### Risk 3: Breaking Changes to Model Interface
**Impact**: Low
**Probability**: Low
**Mitigation**:
- Centralized behavior definition makes updates easy
- Single place to update when interface changes
- Type specs catch interface mismatches
- Tests will fail fast on breaking changes

### Risk 4: Macro Complexity
**Impact**: Low
**Probability**: Low
**Mitigation**:
- Keep macros simple and focused
- Provide both macro and non-macro alternatives
- Document macro expansion behavior
- Test macro generation explicitly

## Future Enhancements

### 1. Property-Based Testing
- Integrate StreamData for property tests
- Generate random valid inputs
- Test invariants across scenarios
- Discover edge cases automatically

### 2. Performance Benchmarking
- Add performance scenario fixtures
- Measure evaluation throughput
- Test under load conditions
- Benchmark different parallelism levels

### 3. Provider-Specific Quirks
- Mock rate limiting behavior
- Mock token limit handling
- Mock provider-specific errors
- Test retry logic

### 4. Chaos Testing
- Random failure injection
- Network instability simulation
- Timeout variation
- Resource constraint simulation

### 5. Snapshot Testing
- Capture and compare responses
- Detect regression in outputs
- Visual diff for trajectories
- Version response fixtures

## Implementation Checklist

### Stage 1: Foundation
- [ ] Create `test/support/model_test_behaviour.ex`
- [ ] Create `test/support/gepa_test_fixtures.ex` skeleton
- [ ] Create `test/support/gepa_test_helper.ex`
- [ ] Write validation test
- [ ] Verify mock injection works

### Stage 2: Dynamic Generation
- [ ] Implement `generate_mock_model/2` fully
- [ ] Implement scenario generation
- [ ] Build trajectory generators
- [ ] Build metrics generators
- [ ] Implement `test_with_models` macro
- [ ] Implement `test_with_scenarios` macro

### Stage 3: Test Migration
- [ ] Update `evaluator_test.exs` (20 tests)
- [ ] Update `evaluation_system_integration_test.exs` (31 tests)
- [ ] Add timeout scenario tests
- [ ] Add failure scenario tests
- [ ] Add edge case tests
- [ ] Run full GEPA test suite
- [ ] Verify zero failures

### Stage 4: Documentation
- [ ] Add module documentation
- [ ] Create usage examples
- [ ] Document common patterns
- [ ] Add troubleshooting guide
- [ ] Update planning documents

### Final Verification
- [ ] All 51 GEPA tests pass
- [ ] Tests run in < 5 seconds
- [ ] No API calls made
- [ ] Full test suite passes
- [ ] Documentation complete
- [ ] Ready for commit

## Notes

- This approach is specific to GEPA tests only
- The 1 Program of Thought test failure will be fixed separately
- Mock infrastructure is reusable for other test suites
- Consider extracting to shared test utilities for other modules
- Performance scenarios may need real API validation separately
