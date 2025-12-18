defmodule Jido.AI.Runner.ChainOfThought.TestExecution.IterativeRefiner do
  @moduledoc """
  Iterative code generation and refinement using test execution feedback.

  Implements:
  - Generate-test-refine loop with failure-driven correction
  - Convergence detection when all tests pass
  - Incremental improvement tracking across iterations
  - Integration with self-correction mechanisms
  """

  require Logger

  alias Jido.AI.Runner.ChainOfThought.TestExecution.{
    ExecutionSandbox,
    ResultAnalyzer,
    TestSuiteManager
  }

  @default_max_iterations 5
  # 100% pass rate required
  @default_pass_threshold 1.0
  # 95% pass rate for partial success
  @convergence_threshold 0.95

  @type refinement_result :: %{
          code: String.t(),
          iteration: non_neg_integer(),
          pass_rate: float(),
          improvements: list(String.t())
        }

  @doc """
  Iteratively refines code based on test execution feedback.

  ## Parameters

  - `initial_code` - Starting code to refine
  - `opts` - Options:
    - `:test_suite` - Test suite to validate against (required)
    - `:max_iterations` - Maximum refinement iterations (default: 5)
    - `:pass_threshold` - Required pass rate to succeed (default: 1.0)
    - `:refinement_fn` - Custom refinement function
    - `:on_iteration` - Callback for each iteration

  ## Returns

  - `{:ok, refined_code}` - All tests passing
  - `{:ok, refined_code, :partial}` - Partial success (high pass rate but not 100%)
  - `{:error, reason}` - Refinement failed

  ## Examples

      {:ok, refined} = IterativeRefiner.refine(
        initial_code,
        test_suite: tests,
        max_iterations: 5,
        on_iteration: fn iter, result ->
          IO.puts("Iteration \#{iter}: \#{result.pass_rate * 100}% passing")
        end
      )
  """
  @spec refine(String.t(), keyword()) ::
          {:ok, String.t()} | {:ok, String.t(), :partial} | {:error, term()}
  def refine(initial_code, opts) do
    test_suite = Keyword.fetch!(opts, :test_suite)
    max_iterations = Keyword.get(opts, :max_iterations, @default_max_iterations)
    pass_threshold = Keyword.get(opts, :pass_threshold, @default_pass_threshold)
    refinement_fn = Keyword.get(opts, :refinement_fn)
    on_iteration = Keyword.get(opts, :on_iteration)

    Logger.info("Starting iterative refinement (max #{max_iterations} iterations)")

    do_refine(
      initial_code,
      test_suite,
      max_iterations,
      pass_threshold,
      refinement_fn,
      on_iteration,
      1,
      []
    )
  end

  @doc """
  Executes single refinement iteration.

  ## Parameters

  - `code` - Current code
  - `test_suite` - Test suite
  - `previous_analysis` - Analysis from previous iteration

  ## Returns

  - `{:ok, refined_code, analysis}` - Refinement successful
  - `{:error, reason}` - Refinement failed
  """
  @spec refine_iteration(String.t(), String.t(), map() | nil) ::
          {:ok, String.t(), map()} | {:error, term()}
  def refine_iteration(code, test_suite, previous_analysis \\ nil) do
    # Execute tests
    with {:ok, test_file} <- TestSuiteManager.store_tests(test_suite),
         {:ok, code_file} <- TestSuiteManager.store_code(code),
         {:ok, exec_result} <- ExecutionSandbox.execute(code_file, test_file),
         {:ok, analysis} <- ResultAnalyzer.analyze(exec_result) do
      # Clean up temp files
      TestSuiteManager.cleanup([test_file, code_file])

      if analysis.pass_rate >= 1.0 do
        # All tests passing, no refinement needed
        {:ok, code, analysis}
      else
        # Generate corrections based on failures
        corrected_code = apply_corrections(code, analysis, previous_analysis)
        {:ok, corrected_code, analysis}
      end
    end
  end

  @doc """
  Detects convergence when pass rate stops improving.

  ## Parameters

  - `history` - List of previous iteration results

  ## Returns

  Boolean indicating if convergence detected
  """
  @spec detect_convergence(list(refinement_result())) :: boolean()
  def detect_convergence(history) when length(history) < 3, do: false

  def detect_convergence(history) do
    # Check if pass rate has plateaued over last 3 iterations
    last_three = Enum.take(history, 3)
    pass_rates = Enum.map(last_three, & &1.pass_rate)

    max_rate = Enum.max(pass_rates)
    min_rate = Enum.min(pass_rates)

    # Convergence if variance is very small
    max_rate - min_rate < 0.05
  end

  @doc """
  Tracks incremental improvements across iterations.

  ## Parameters

  - `current_result` - Current iteration result
  - `previous_result` - Previous iteration result

  ## Returns

  List of improvement descriptions
  """
  @spec track_improvements(refinement_result(), refinement_result() | nil) :: list(String.t())
  def track_improvements(current_result, nil) do
    ["Initial iteration: #{trunc(current_result.pass_rate * 100)}% tests passing"]
  end

  def track_improvements(current_result, previous_result) do
    improvements = []

    # Pass rate improvement
    rate_delta = current_result.pass_rate - previous_result.pass_rate

    improvements =
      if rate_delta > 0 do
        ["Pass rate improved by #{trunc(rate_delta * 100)}%"] ++ improvements
      else
        improvements
      end

    # Failure category improvements
    improvements =
      if length(current_result.improvements) > 0 do
        current_result.improvements ++ improvements
      else
        improvements
      end

    if Enum.empty?(improvements) do
      ["No improvement in this iteration"]
    else
      improvements
    end
  end

  # Private functions

  defp do_refine(
         _code,
         _test_suite,
         max_iter,
         _threshold,
         _refine_fn,
         _callback,
         iteration,
         _history
       )
       when iteration > max_iter do
    Logger.warning("Max iterations (#{max_iter}) reached without achieving pass threshold")
    {:error, :max_iterations_exceeded}
  end

  defp do_refine(code, test_suite, max_iter, threshold, refine_fn, callback, iteration, history) do
    Logger.debug("Refinement iteration #{iteration}/#{max_iter}")

    previous_analysis = if Enum.empty?(history), do: nil, else: List.first(history).analysis

    case refine_iteration(code, test_suite, previous_analysis) do
      {:ok, refined_code, analysis} ->
        pass_rate = analysis.pass_rate

        # Build iteration result
        improvements =
          if Enum.empty?(history) do
            []
          else
            compare_analyses(analysis, List.first(history).analysis)
          end

        iteration_result = %{
          code: refined_code,
          iteration: iteration,
          pass_rate: pass_rate,
          improvements: improvements,
          analysis: analysis
        }

        # Invoke callback if provided
        if callback, do: callback.(iteration, iteration_result)

        new_history = [iteration_result | history]

        cond do
          # Success: all tests passing
          pass_rate >= threshold ->
            Logger.info(
              "Refinement succeeded at iteration #{iteration}: #{trunc(pass_rate * 100)}% tests passing"
            )

            {:ok, refined_code}

          # Partial success: high pass rate at convergence
          pass_rate >= @convergence_threshold and detect_convergence(new_history) ->
            Logger.info(
              "Refinement converged at iteration #{iteration}: #{trunc(pass_rate * 100)}% tests passing"
            )

            {:ok, refined_code, :partial}

          # Continue refining
          true ->
            # Apply custom refinement if provided
            next_code =
              if refine_fn do
                refine_fn.(refined_code, analysis)
              else
                refined_code
              end

            do_refine(
              next_code,
              test_suite,
              max_iter,
              threshold,
              refine_fn,
              callback,
              iteration + 1,
              new_history
            )
        end

      {:error, reason} ->
        Logger.error("Refinement failed at iteration #{iteration}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp apply_corrections(code, analysis, _previous_analysis) do
    # Generate correction based on failure analysis
    # In a real implementation, this would use LLM to generate corrected code

    if Enum.empty?(analysis.failures) do
      code
    else
      # Extract correction prompts
      first_failure = List.first(analysis.failures)
      correction_prompt = first_failure.correction_prompt

      Logger.debug("Applying corrections based on: #{first_failure.category}")

      # For now, return original code with comment indicating needed fix
      # In production, this would call LLM with correction_prompt
      """
      # Correction needed: #{first_failure.root_cause}
      # #{correction_prompt}

      #{code}
      """
    end
  end

  defp compare_analyses(current, previous) do
    improvements = []

    # Compare failure counts by category
    current_failures = Enum.group_by(current.failures, & &1.category)
    previous_failures = Enum.group_by(previous.failures, & &1.category)

    # Find categories that improved
    Enum.reduce(previous_failures, improvements, fn {category, prev_fails}, acc ->
      curr_count = length(Map.get(current_failures, category, []))
      prev_count = length(prev_fails)

      if curr_count < prev_count do
        ["Fixed #{prev_count - curr_count} #{category} error(s)" | acc]
      else
        acc
      end
    end)
  end
end
