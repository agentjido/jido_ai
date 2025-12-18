defmodule Jido.AI.Runner.GEPA.TestFixtures do
  @moduledoc """
  Dynamic test fixture generation for GEPA evaluations.

  Provides functions to generate mock models, scenarios, and test data
  for comprehensive GEPA testing without real API calls.

  ## Usage

      # Generate a mock model for testing
      mock = generate_mock_model(:openai, scenario: :success)

      # Get all available test scenarios
      scenarios = test_scenarios()

      # Build a mock response for a scenario
      response = build_mock_response(:success, %{prompt: "test"})

      # Generate trajectory data for testing
      trajectory = build_trajectory_for_scenario(:success)
  """

  alias Jido.AI.Runner.GEPA.Trajectory

  @doc """
  Generates a mock model for the specified provider.

  ## Parameters
  - `provider` - Provider atom (`:openai`, `:anthropic`, `:local`)
  - `opts` - Configuration options

  ## Options
  - `:scenario` - Test scenario (default: `:success`)
  - `:fitness` - Specific fitness score (0.0-1.0)
  - `:latency` - Simulated response latency in ms (default: 100)
  - `:trajectory` - Custom trajectory data
  - `:metrics` - Custom metrics data

  ## Examples

      generate_mock_model(:openai, scenario: :success)
      generate_mock_model(:anthropic, fitness: 0.85, latency: 50)
      generate_mock_model(:local, scenario: :timeout)
  """
  def generate_mock_model(provider, opts \\ []) do
    scenario = Keyword.get(opts, :scenario, :success)
    fitness = Keyword.get(opts, :fitness, calculate_default_fitness(scenario))
    latency = Keyword.get(opts, :latency, 100)
    trajectory = Keyword.get(opts, :trajectory, build_trajectory_for_scenario(scenario))
    metrics = Keyword.get(opts, :metrics, build_metrics_for_scenario(scenario))

    %{
      provider: provider,
      scenario: scenario,
      fitness: fitness,
      latency: latency,
      response_fn: build_response_fn(scenario),
      trajectory: trajectory,
      metrics: metrics,
      model_name: get_model_name(provider)
    }
  end

  @doc """
  Returns list of all available test scenarios.

  ## Returns
  List of scenario atoms that can be used with `generate_mock_model/2`
  """
  def test_scenarios do
    [
      :success,
      :timeout,
      :failure,
      :partial,
      :high_fitness,
      :low_fitness,
      :error,
      :agent_crash
    ]
  end

  @doc """
  Builds a mock response for the given scenario.

  ## Parameters
  - `scenario` - The test scenario
  - `context` - Context map with request details (e.g., `%{prompt: "..."}`)

  ## Returns
  - `{:ok, response}` for successful scenarios
  - `{:error, reason}` for failure scenarios
  """
  def build_mock_response(scenario, context) do
    prompt = Map.get(context, :prompt, "test prompt")

    case scenario do
      :success ->
        {:ok,
         %{
           content: "Mock successful response for: #{prompt}",
           role: :assistant,
           metadata: %{model: "mock-model", tokens: 50}
         }}

      :high_fitness ->
        {:ok,
         %{
           content: "Excellent response with high-quality reasoning: #{prompt}",
           role: :assistant,
           metadata: %{model: "mock-model", tokens: 100, quality: :high}
         }}

      :low_fitness ->
        {:ok,
         %{
           content: "Poor quality response",
           role: :assistant,
           metadata: %{model: "mock-model", tokens: 10, quality: :low}
         }}

      :partial ->
        {:ok,
         %{
           content: "Partial response (incomplete)",
           role: :assistant,
           metadata: %{model: "mock-model", tokens: 25, complete: false}
         }}

      :timeout ->
        {:error, :timeout}

      :failure ->
        {:error, :evaluation_failed}

      :error ->
        {:error, %{reason: :llm_error, details: "Mock LLM error"}}

      :agent_crash ->
        {:error, :agent_crashed}

      _ ->
        {:ok,
         %{
           content: "Mock response",
           role: :assistant,
           metadata: %{model: "mock-model"}
         }}
    end
  end

  @doc """
  Generates a valid trajectory for the given scenario.

  ## Parameters
  - `scenario` - The test scenario

  ## Returns
  A `Trajectory.t()` struct populated with appropriate steps and metadata
  """
  def build_trajectory_for_scenario(scenario) do
    base_trajectory =
      Trajectory.new(
        metadata: %{
          scenario: scenario,
          test_fixture: true,
          created_at: DateTime.utc_now()
        }
      )

    case scenario do
      :success -> add_success_steps(base_trajectory)
      :high_fitness -> add_high_quality_steps(base_trajectory)
      :low_fitness -> add_low_quality_steps(base_trajectory)
      :timeout -> add_timeout_steps(base_trajectory)
      :failure -> add_failure_steps(base_trajectory)
      :partial -> add_partial_steps(base_trajectory)
      :error -> add_error_steps(base_trajectory)
      :agent_crash -> add_crash_steps(base_trajectory)
      _ -> base_trajectory
    end
  end

  @doc """
  Generates metrics data matching the scenario.

  ## Parameters
  - `scenario` - The test scenario

  ## Returns
  A map with metrics appropriate for the scenario
  """
  def build_metrics_for_scenario(scenario) do
    base_metrics = %{
      duration_ms: 100,
      success: false,
      timeout: false,
      error: false
    }

    case scenario do
      :success ->
        %{base_metrics | success: true, duration_ms: 150}

      :high_fitness ->
        Map.merge(base_metrics, %{success: true, duration_ms: 120, quality_score: 0.95})

      :low_fitness ->
        Map.merge(base_metrics, %{success: true, duration_ms: 80, quality_score: 0.3})

      :timeout ->
        %{base_metrics | timeout: true, duration_ms: 30_000}

      :failure ->
        %{base_metrics | error: true, duration_ms: 200}

      :partial ->
        Map.merge(base_metrics, %{success: false, duration_ms: 500, partial: true})

      :error ->
        %{base_metrics | error: true, duration_ms: 50}

      :agent_crash ->
        Map.merge(base_metrics, %{error: true, duration_ms: 10, crash: true})

      _ ->
        base_metrics
    end
  end

  # Private helper functions

  defp calculate_default_fitness(scenario) do
    case scenario do
      :success -> 0.85
      :high_fitness -> 0.95
      :low_fitness -> 0.3
      :partial -> 0.5
      :failure -> 0.0
      :error -> 0.0
      :timeout -> nil
      :agent_crash -> nil
      _ -> 0.5
    end
  end

  defp build_response_fn(scenario) do
    fn prompt -> build_mock_response(scenario, %{prompt: prompt}) end
  end

  defp get_model_name(provider) do
    case provider do
      :openai -> "gpt-4"
      :anthropic -> "claude-3-5-sonnet"
      :local -> "llama-3"
      _ -> "mock-model"
    end
  end

  # Trajectory step builders

  defp add_success_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Analyzing prompt and planning approach",
      metadata: %{confidence: 0.9}
    )
    |> Trajectory.add_step(
      type: :action,
      content: "Executing task with optimal strategy",
      metadata: %{tool: "executor"}
    )
    |> Trajectory.add_step(
      type: :observation,
      content: "Task completed successfully",
      metadata: %{success: true}
    )
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Verified results meet all criteria",
      metadata: %{validation: :passed}
    )
    |> Trajectory.complete(outcome: :success)
  end

  defp add_high_quality_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Comprehensive analysis with detailed breakdown",
      metadata: %{depth: :high, confidence: 0.95}
    )
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Identified optimal approach with trade-off analysis",
      metadata: %{alternatives_considered: 3}
    )
    |> Trajectory.add_step(
      type: :action,
      content: "Executing with validated strategy",
      metadata: %{quality: :high}
    )
    |> Trajectory.add_step(
      type: :observation,
      content: "Excellent results with all criteria exceeded",
      metadata: %{success: true, quality: :excellent}
    )
    |> Trajectory.complete(outcome: :success)
  end

  defp add_low_quality_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Basic analysis",
      metadata: %{confidence: 0.4}
    )
    |> Trajectory.add_step(
      type: :action,
      content: "Simple execution",
      metadata: %{quality: :low}
    )
    |> Trajectory.add_step(
      type: :observation,
      content: "Minimal results",
      metadata: %{success: true, quality: :poor}
    )
    |> Trajectory.complete(outcome: :success)
  end

  defp add_timeout_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Starting analysis",
      metadata: %{step: 1}
    )
    |> Trajectory.add_step(
      type: :action,
      content: "Long running operation initiated",
      metadata: %{expected_duration: :long}
    )
    # Incomplete - simulates timeout
    |> Map.put(:outcome, :timeout)
  end

  defp add_failure_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Attempting task analysis",
      metadata: %{step: 1}
    )
    |> Trajectory.add_step(
      type: :action,
      content: "Operation failed",
      metadata: %{error: true, reason: :execution_error}
    )
    |> Trajectory.add_step(
      type: :observation,
      content: "Failure detected",
      metadata: %{success: false, error: true}
    )
    |> Trajectory.complete(outcome: :failure)
  end

  defp add_partial_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Partial analysis completed",
      metadata: %{complete: false}
    )
    |> Trajectory.add_step(
      type: :action,
      content: "Incomplete execution",
      metadata: %{progress: 0.6}
    )
    # Missing final steps
    |> Map.put(:outcome, :partial)
  end

  defp add_error_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Started processing",
      metadata: %{step: 1}
    )
    |> Trajectory.add_step(
      type: :action,
      content: "Error encountered",
      metadata: %{error: true, type: :llm_error}
    )
    |> Trajectory.complete(outcome: :error)
  end

  defp add_crash_steps(trajectory) do
    trajectory
    |> Trajectory.add_step(
      type: :reasoning,
      content: "Initial step",
      metadata: %{step: 1}
    )
    # Abrupt termination - no completion steps
    |> Map.put(:outcome, :error)
    |> Map.put(:error, :agent_crashed)
  end
end
