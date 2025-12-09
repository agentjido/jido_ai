defmodule Jido.AI.Runner.GEPA.TestHelper do
  @moduledoc """
  Helper functions for GEPA evaluation tests.

  Provides setup, assertions, and utilities for testing GEPA
  evaluations with mocked models. Integrates with Mimic for
  stubbing AI model calls and agent execution.

  ## Usage

      defmodule MyGEPATest do
        use ExUnit.Case
        import Jido.AI.Runner.GEPA.TestHelper

        setup do
          setup_mock_model(:openai, scenario: :success)
        end

        test "evaluation works" do
          {:ok, result} = Evaluator.evaluate_prompt("test", task: %{type: :reasoning})
          assert_evaluation_result(result, %{error: nil})
        end
      end
  """

  import Mimic
  import ExUnit.Assertions

  alias Jido.AI.Runner.GEPA.Evaluator.EvaluationResult
  alias Jido.AI.Runner.GEPA.TestFixtures
  alias Jido.AI.Runner.GEPA.Trajectory
  alias Jido.Signal.ID, as: SignalID

  @doc """
  Sets up a mock model in the test context.

  This function configures Mimic stubs for AI actions and agent execution
  to use mock responses instead of real API calls.

  ## Parameters
  - `provider` - Provider atom (`:openai`, `:anthropic`, `:local`)
  - `opts` - Configuration options (passed to `TestFixtures.generate_mock_model/2`)

  ## Returns
  - `{:ok, context}` map with `:mock_model` key

  ## Examples

      setup do
        setup_mock_model(:openai, scenario: :success)
      end

      setup do
        setup_mock_model(:anthropic, fitness: 0.9, latency: 50)
      end
  """
  def setup_mock_model(provider, opts \\ []) do
    mock = TestFixtures.generate_mock_model(provider, opts)

    # Stub Server.call to return mock Signal responses
    stub(Jido.Agent.Server, :call, fn _agent_pid, signal, _timeout ->
      # Check if this is a chat/AI response signal
      if chat_signal?(signal) do
        # Simulate latency
        if mock.latency > 0 do
          Process.sleep(mock.latency)
        end

        # Extract prompt from signal data for proper response
        prompt = extract_prompt_from_signal(signal)

        # Return response based on scenario
        case mock.scenario do
          :timeout ->
            {:error, :timeout}

          :error ->
            {:error, %{reason: :llm_error, details: "Mock LLM error"}}

          :agent_crash ->
            {:error, :agent_crashed}

          :failure ->
            {:error, :evaluation_failed}

          _ ->
            # Build a proper Signal response with prompt context
            {:ok, build_mock_signal(mock, prompt)}
        end
      else
        # For non-chat signals, return a simple success response
        # This prevents issues with concurrent agent lifecycle management
        {:ok,
         %Jido.Signal{
           id: SignalID.generate!(),
           type: "jido.agent.internal.ok",
           source: "/mock/agent",
           data: %{status: :ok}
         }}
      end
    end)

    {:ok, %{mock_model: mock}}
  end

  @doc """
  Wraps test execution with a mocked evaluator configuration.

  ## Parameters
  - `config` - Configuration map with `:provider` and `:opts` keys
  - `test_fn` - Test function to execute with mocked setup

  ## Examples

      with_mock_evaluator(%{provider: :openai, opts: [scenario: :success]}, fn ->
        # Test code here
      end)
  """
  def with_mock_evaluator(config, test_fn) do
    {:ok, _context} = setup_mock_model(config.provider, config.opts)
    test_fn.()
  end

  @doc """
  Custom assertions for GEPA evaluation results.

  Validates that an evaluation result meets expected criteria.

  ## Parameters
  - `result` - The `EvaluationResult` struct to validate
  - `expectations` - Map of expected values

  ## Supported Expectations
  - `:prompt` - Expected prompt string
  - `:fitness_range` - Tuple `{min, max}` for fitness bounds
  - `:fitness` - Exact fitness value
  - `:error` - Expected error (or `nil` for no error)
  - `:success` - Expected success boolean in metrics
  - `:min_duration` - Minimum duration in milliseconds
  - `:max_duration` - Maximum duration in milliseconds

  ## Examples

      assert_evaluation_result(result, %{
        prompt: "test prompt",
        fitness_range: {0.0, 1.0},
        error: nil,
        success: true
      })
  """
  def assert_evaluation_result(%EvaluationResult{} = result, expectations) do
    # Validate it's an EvaluationResult struct
    assert %EvaluationResult{} = result

    # Check prompt if specified
    if prompt = expectations[:prompt] do
      assert result.prompt == prompt, "Expected prompt '#{prompt}', got '#{result.prompt}'"
    end

    # Check fitness range if specified
    case expectations[:fitness_range] do
      {min, max} when is_number(min) and is_number(max) ->
        if result.fitness do
          assert result.fitness >= min,
                 "Fitness #{result.fitness} below minimum #{min}"

          assert result.fitness <= max,
                 "Fitness #{result.fitness} above maximum #{max}"
        end

      _ ->
        :ok
    end

    # Check exact fitness if specified
    if fitness = expectations[:fitness] do
      assert result.fitness == fitness,
             "Expected fitness #{fitness}, got #{result.fitness}"
    end

    # Check error if specified
    if Map.has_key?(expectations, :error) do
      expected_error = expectations[:error]

      assert result.error == expected_error,
             "Expected error #{inspect(expected_error)}, got #{inspect(result.error)}"
    end

    # Check success in metrics if specified
    if Map.has_key?(expectations, :success) do
      expected_success = expectations[:success]

      assert result.metrics.success == expected_success,
             "Expected success #{expected_success}, got #{result.metrics.success}"
    end

    # Check duration bounds if specified
    if min_duration = expectations[:min_duration] do
      assert result.metrics.duration_ms >= min_duration,
             "Duration #{result.metrics.duration_ms}ms below minimum #{min_duration}ms"
    end

    if max_duration = expectations[:max_duration] do
      assert result.metrics.duration_ms <= max_duration,
             "Duration #{result.metrics.duration_ms}ms above maximum #{max_duration}ms"
    end

    result
  end

  @doc """
  Verifies trajectory structure and content.

  ## Parameters
  - `trajectory` - The trajectory to validate

  ## Examples

      assert_valid_trajectory(result.trajectory)
  """
  def assert_valid_trajectory(trajectory) when is_map(trajectory) do
    # Trajectory can be a Trajectory struct or a map
    assert is_map(trajectory), "Trajectory must be a map"

    # Check for essential trajectory fields
    # The exact structure depends on Trajectory implementation
    # This is a basic validation
    assert Map.has_key?(trajectory, :steps) or Map.has_key?(trajectory, :id) or
             Map.has_key?(trajectory, :metadata),
           "Trajectory must have steps, id, or metadata"

    trajectory
  end

  def assert_valid_trajectory(nil) do
    flunk("Trajectory is nil")
  end

  @doc """
  Verifies metrics structure and ranges.

  ## Parameters
  - `metrics` - The metrics map to validate

  ## Examples

      assert_valid_metrics(result.metrics)
  """
  def assert_valid_metrics(metrics) when is_map(metrics) do
    assert Map.has_key?(metrics, :duration_ms), "Metrics must include duration_ms"
    assert Map.has_key?(metrics, :success), "Metrics must include success flag"

    assert is_integer(metrics.duration_ms), "duration_ms must be an integer"
    assert metrics.duration_ms >= 0, "duration_ms must be non-negative"

    assert is_boolean(metrics.success), "success must be a boolean"

    metrics
  end

  def assert_valid_metrics(nil) do
    flunk("Metrics is nil")
  end

  @doc """
  Asserts that a batch of evaluation results are all valid.

  ## Parameters
  - `results` - List of evaluation results
  - `expectations` - Optional expectations to apply to all results

  ## Examples

      assert_batch_results(results, %{error: nil})
  """
  def assert_batch_results(results, expectations \\ %{}) when is_list(results) do
    assert length(results) > 0, "Results list is empty"

    Enum.each(results, fn result ->
      assert %EvaluationResult{} = result
      assert_evaluation_result(result, expectations)
    end)

    results
  end

  @doc """
  Asserts that results are ordered correctly (if order matters).

  ## Parameters
  - `results` - List of evaluation results
  - `expected_prompts` - List of expected prompts in order

  ## Examples

      assert_results_ordered(results, ["prompt 1", "prompt 2", "prompt 3"])
  """
  def assert_results_ordered(results, expected_prompts) do
    actual_prompts = Enum.map(results, & &1.prompt)

    assert actual_prompts == expected_prompts,
           "Results not in expected order. Expected: #{inspect(expected_prompts)}, Got: #{inspect(actual_prompts)}"

    results
  end

  # Private helpers

  defp extract_prompt(params) when is_map(params) do
    cond do
      Map.has_key?(params, :prompt) ->
        case params.prompt do
          %{messages: [%{content: content} | _]} -> content
          %{messages: messages} when is_list(messages) -> inspect(messages)
          prompt when is_binary(prompt) -> prompt
          _ -> "unknown prompt"
        end

      Map.has_key?(params, :messages) ->
        case params.messages do
          [%{content: content} | _] -> content
          _ -> "unknown prompt"
        end

      true ->
        "unknown prompt"
    end
  end

  defp extract_prompt(_), do: "unknown prompt"

  # Check if a signal is a chat/AI response signal that should be mocked
  defp chat_signal?(%{type: type}) when is_binary(type) do
    String.contains?(type, "chat") or String.contains?(type, "ai")
  end

  defp chat_signal?(%Jido.Signal{type: type}) when is_binary(type) do
    String.contains?(type, "chat") or String.contains?(type, "ai")
  end

  defp chat_signal?(_), do: false

  # Extract prompt from the signal being sent to the agent
  defp extract_prompt_from_signal(%{data: data}) when is_map(data) do
    cond do
      # Check if data has a prompt field directly
      Map.has_key?(data, :prompt) && is_binary(data.prompt) ->
        data.prompt

      # Check if data has instructions with a prompt
      Map.has_key?(data, :instructions) && is_list(data.instructions) ->
        case List.first(data.instructions) do
          %{prompt: prompt} when is_binary(prompt) -> prompt
          _ -> "test prompt"
        end

      # Default fallback
      true ->
        "test prompt"
    end
  end

  defp extract_prompt_from_signal(_), do: "test prompt"

  # Build a mock Signal response for Server.call
  defp build_mock_signal(mock, prompt) do
    %Jido.Signal{
      id: SignalID.generate!(),
      type: "jido.agent.out.instruction.result",
      source: "/mock/agent",
      data: %{
        content: "Mock response for: #{prompt}",
        role: :assistant,
        metadata: %{
          model: mock.model_name,
          provider: mock.provider,
          fitness: mock.fitness,
          prompt: prompt
        }
      },
      time: DateTime.to_iso8601(DateTime.utc_now()),
      datacontenttype: "application/json"
    }
  end
end
