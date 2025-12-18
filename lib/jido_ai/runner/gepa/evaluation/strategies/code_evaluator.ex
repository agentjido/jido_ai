defmodule Jido.AI.Runner.GEPA.Evaluation.Strategies.CodeEvaluator do
  @moduledoc """
  Code generation task evaluator for GEPA.

  Evaluates prompts for code generation tasks by:
  1. Generating code using the LLM
  2. Validating syntax (if applicable)
  3. Running test cases (if provided)
  4. Calculating code-specific metrics

  ## Task Configuration

      task: %{
        type: :code_generation,
        language: :elixir,  # :elixir, :python, :javascript, etc.
        problem: "Write a function to calculate fibonacci",
        test_cases: [
          %{input: 0, expected: 0},
          %{input: 5, expected: 5},
          %{input: 10, expected: 55}
        ],
        starter_code: "def fibonacci(n):",  # optional
        timeout: 30_000  # optional, default 30s
      }

  ## Evaluation Process

  1. **Code Generation**: Use LLM with prompt to generate code
  2. **Syntax Validation**: Parse code to check for syntax errors
  3. **Test Execution**: Run provided test cases (if any)
  4. **Metric Calculation**:
     - Functionality: test_passed / total_tests
     - Syntax validity: boolean
     - Quality: based on trajectory and response
     - Fitness: weighted combination

  ## Metrics

  - **functionality**: Ratio of passing tests (0-1)
  - **syntax_valid**: Code parses without errors (boolean)
  - **test_coverage**: Number of tests run
  - **execution_time**: Time taken for tests (ms)
  - **fitness**: Overall score incorporating all metrics
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Evaluation.Validators.CodeValidator
  alias Jido.AI.Runner.GEPA.Evaluator

  @type task_config :: map()
  @type prompt :: String.t()
  @type test_case :: %{input: term(), expected: term()}
  @type evaluation_result :: Evaluator.EvaluationResult.t()

  @doc """
  Evaluates a prompt for code generation tasks.

  Generates code using the LLM, validates syntax, runs tests, and calculates
  code-specific fitness metrics.

  ## Examples

      CodeEvaluator.evaluate_prompt(
        "def fibonacci(n):",
        task: %{
          type: :code_generation,
          language: :python,
          test_cases: [%{input: 5, expected: 5}]
        }
      )
  """
  @spec evaluate_prompt(prompt(), keyword()) :: {:ok, evaluation_result()} | {:error, term()}
  def evaluate_prompt(prompt, opts) when is_binary(prompt) and is_list(opts) do
    task = Keyword.get(opts, :task, %{})

    Logger.debug(
      "Code evaluation starting (language: #{task[:language]}, tests: #{length(task[:test_cases] || [])})"
    )

    # First, do generic evaluation to get LLM response
    case Evaluator.evaluate_prompt(prompt, opts) do
      {:ok, generic_result} ->
        # Extract generated code from response
        generated_code = extract_code_from_result(generic_result)

        # Perform code-specific evaluation
        code_metrics = evaluate_code(generated_code, task)

        # Combine generic and code-specific metrics
        enhanced_result = enhance_result_with_code_metrics(generic_result, code_metrics)

        Logger.debug(
          "Code evaluation complete (functionality: #{code_metrics.functionality}, syntax_valid: #{code_metrics.syntax_valid})"
        )

        {:ok, enhanced_result}

      {:error, reason} = error ->
        Logger.warning("Code evaluation failed during generation: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Evaluates multiple prompts in batch for code generation tasks.
  """
  @spec evaluate_batch(list(prompt()), keyword()) :: list(evaluation_result())
  def evaluate_batch(prompts, opts) when is_list(prompts) and is_list(opts) do
    Logger.info("Batch code evaluation for #{length(prompts)} prompts")

    # Use generic batch evaluation, then enhance each result
    generic_results = Evaluator.evaluate_batch(prompts, opts)
    task = Keyword.get(opts, :task, %{})

    Enum.map(generic_results, fn result ->
      if is_nil(result.error) do
        generated_code = extract_code_from_result(result)
        code_metrics = evaluate_code(generated_code, task)
        enhance_result_with_code_metrics(result, code_metrics)
      else
        # Keep error results as-is
        result
      end
    end)
  end

  # Private Functions

  @doc false
  @spec extract_code_from_result(evaluation_result()) :: String.t()
  defp extract_code_from_result(%Evaluator.EvaluationResult{} = result) do
    # Try to extract code from response data
    # The trajectory should have the agent's response
    cond do
      # Check if trajectory has response data
      result.trajectory && result.trajectory.metadata[:response] ->
        extract_code_from_text(result.trajectory.metadata[:response])

      # Check metrics for response data
      result.metrics[:response_data] ->
        extract_code_from_text(result.metrics[:response_data])

      # Fallback to empty code
      true ->
        Logger.warning("Could not extract code from evaluation result")
        ""
    end
  end

  @doc false
  @spec extract_code_from_text(term()) :: String.t()
  defp extract_code_from_text(text) when is_binary(text) do
    # Try to extract code from markdown code blocks
    case Regex.run(~r/```(?:\w+)?\n(.*?)\n```/s, text) do
      [_, code] -> String.trim(code)
      # No code blocks, use entire text
      nil -> text
    end
  end

  defp extract_code_from_text(data) when is_map(data) do
    # Try to find code in map data
    cond do
      Map.has_key?(data, :code) -> to_string(data.code)
      Map.has_key?(data, :content) -> extract_code_from_text(data.content)
      Map.has_key?(data, :message) -> extract_code_from_text(data.message)
      true -> ""
    end
  end

  defp extract_code_from_text(_), do: ""

  @doc false
  @spec evaluate_code(String.t(), task_config()) :: map()
  defp evaluate_code(code, task) do
    start_time = System.monotonic_time(:millisecond)

    # Validate syntax
    syntax_result = validate_syntax(code, task[:language])

    # Run tests if provided
    test_result =
      if task[:test_cases] && length(task[:test_cases]) > 0 do
        run_test_cases(code, task[:test_cases], task)
      else
        %{tests_passed: 0, tests_total: 0, functionality: 1.0}
      end

    execution_time = System.monotonic_time(:millisecond) - start_time

    %{
      syntax_valid: syntax_result.valid,
      syntax_errors: syntax_result.errors,
      tests_passed: test_result.tests_passed,
      tests_total: test_result.tests_total,
      functionality: test_result.functionality,
      execution_time: execution_time,
      generated_code: code
    }
  end

  @doc false
  @spec validate_syntax(String.t(), atom() | nil) :: %{valid: boolean(), errors: list()}
  defp validate_syntax(code, language) do
    case language do
      :elixir ->
        CodeValidator.validate_elixir_syntax(code)

      :python ->
        # credo:disable-for-next-line Credo.Check.Design.TagTODO
        # TODO: Implement Python syntax validation
        %{valid: true, errors: []}

      :javascript ->
        # credo:disable-for-next-line Credo.Check.Design.TagTODO
        # TODO: Implement JavaScript syntax validation
        %{valid: true, errors: []}

      _ ->
        # Unknown language, skip syntax validation
        %{valid: true, errors: []}
    end
  end

  @doc false
  @spec run_test_cases(String.t(), list(test_case()), task_config()) :: map()
  defp run_test_cases(_code, test_cases, _task) when test_cases == [] do
    %{tests_passed: 0, tests_total: 0, functionality: 1.0}
  end

  defp run_test_cases(code, test_cases, task) do
    # For now, use simple heuristic evaluation
    # credo:disable-for-next-line Credo.Check.Design.TagTODO
    # TODO: Implement actual code execution and testing in future phase
    # This would require sandboxed execution environment

    Logger.debug(
      "Test execution not yet implemented, using heuristic evaluation for #{length(test_cases)} tests"
    )

    # Heuristic: Check if code contains expected patterns
    # This is a placeholder until we have safe code execution
    functionality = calculate_heuristic_functionality(code, test_cases, task)

    %{
      tests_passed: 0,
      tests_total: length(test_cases),
      functionality: functionality
    }
  end

  @doc false
  @spec calculate_heuristic_functionality(String.t(), list(test_case()), task_config()) :: float()
  defp calculate_heuristic_functionality(code, test_cases, task) do
    # Simple heuristic: Check if code contains problem-related keywords
    # More sophisticated: Check code structure, function definitions, etc.

    cond do
      # Code is empty
      String.trim(code) == "" ->
        0.0

      # Code has syntax (validated elsewhere)
      # Give partial credit for valid code structure
      String.length(code) > 10 ->
        base_score = 0.5

        # Check for function definition keywords
        has_function =
          case task[:language] do
            :elixir -> String.contains?(code, "def ")
            :python -> String.contains?(code, "def ")
            :javascript -> String.contains?(code, "function") || String.contains?(code, "=>")
            _ -> true
          end

        function_score = if has_function, do: 0.25, else: 0.0

        # Check if test case values appear in code (very rough heuristic)
        test_values_present =
          Enum.any?(test_cases, fn tc ->
            String.contains?(code, to_string(tc.expected)) ||
              String.contains?(code, to_string(tc.input))
          end)

        test_score = if test_values_present, do: 0.25, else: 0.0

        min(base_score + function_score + test_score, 1.0)

      # Very short code, likely incomplete
      true ->
        0.2
    end
  end

  @doc false
  @spec enhance_result_with_code_metrics(evaluation_result(), map()) :: evaluation_result()
  defp enhance_result_with_code_metrics(%Evaluator.EvaluationResult{} = result, code_metrics) do
    # Calculate enhanced fitness that incorporates code metrics
    enhanced_fitness = calculate_code_fitness(result.fitness, code_metrics)

    # Merge code metrics into result
    enhanced_metrics =
      Map.merge(result.metrics, %{
        code: %{
          syntax_valid: code_metrics.syntax_valid,
          functionality: code_metrics.functionality,
          tests_passed: code_metrics.tests_passed,
          tests_total: code_metrics.tests_total,
          execution_time: code_metrics.execution_time
        }
      })

    %{result | fitness: enhanced_fitness, metrics: enhanced_metrics}
  end

  @doc false
  @spec calculate_code_fitness(float() | nil, map()) :: float()
  defp calculate_code_fitness(generic_fitness, code_metrics) do
    # Weight code-specific metrics more heavily
    # 50% functionality, 30% generic, 20% syntax
    functionality_weight = 0.5
    generic_weight = 0.3
    syntax_weight = 0.2

    functionality_score = code_metrics.functionality
    syntax_score = if code_metrics.syntax_valid, do: 1.0, else: 0.0
    generic_score = generic_fitness || 0.5

    functionality_weight * functionality_score +
      generic_weight * generic_score +
      syntax_weight * syntax_score
  end
end
