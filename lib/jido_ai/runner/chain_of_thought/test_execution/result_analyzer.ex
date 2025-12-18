defmodule Jido.AI.Runner.ChainOfThought.TestExecution.ResultAnalyzer do
  @moduledoc """
  Analyzes test execution results and generates targeted correction guidance.

  Provides:
  - Test result parsing for failures, errors, and warnings
  - Failure categorization (syntax, type, logic, edge case)
  - Root cause analysis identifying likely error sources
  - Correction prompt generation with specific failure context
  """

  require Logger

  @type failure_category ::
          :syntax | :type | :logic | :edge_case | :runtime | :timeout | :compilation
  @type failure_analysis :: %{
          category: failure_category(),
          message: String.t(),
          location: String.t() | nil,
          root_cause: String.t(),
          correction_prompt: String.t()
        }

  @type analysis_result :: %{
          status: :pass | :fail | :error,
          total_tests: non_neg_integer(),
          passed_tests: non_neg_integer(),
          failed_tests: non_neg_integer(),
          failures: list(failure_analysis()),
          suggestions: list(String.t()),
          pass_rate: float()
        }

  @doc """
  Analyzes test execution result and provides detailed feedback.

  ## Parameters

  - `execution_result` - Result from ExecutionSandbox.execute/3

  ## Returns

  - `{:ok, analysis}` - Analysis completed successfully
  - `{:error, reason}` - Analysis failed

  ## Examples

      {:ok, analysis} = ResultAnalyzer.analyze(execution_result)
      # analysis.failures => list of categorized failures
      # analysis.suggestions => list of correction suggestions
  """
  @spec analyze(map()) :: {:ok, analysis_result()} | {:error, term()}
  def analyze(execution_result) do
    Logger.debug("Analyzing test execution result")

    case execution_result.status do
      :success ->
        analyze_success(execution_result)

      :failure ->
        analyze_failures(execution_result)

      :timeout ->
        analyze_timeout(execution_result)

      :compilation_error ->
        analyze_compilation_error(execution_result)
    end
  end

  @doc """
  Extracts failure information from test output.

  ## Parameters

  - `output` - Test execution output string

  ## Returns

  List of failure maps
  """
  @spec extract_failures(String.t()) :: list(map())
  def extract_failures(output) do
    output
    |> String.split("\n")
    |> Enum.reduce({[], nil}, fn line, {failures, current_test} ->
      cond do
        # Match test start
        String.match?(line, ~r/^\s*\d+\) test /) ->
          test_name = extract_test_name(line)
          {failures, test_name}

        # Match failure/error markers
        String.contains?(line, ["** (", "Assertion with"]) and current_test ->
          failure = %{
            test: current_test,
            message: String.trim(line),
            line_number: extract_line_number(line)
          }

          {[failure | failures], current_test}

        true ->
          {failures, current_test}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  @doc """
  Categorizes failure based on error message and context.

  ## Parameters

  - `failure` - Failure map with message and context

  ## Returns

  Failure category atom
  """
  @spec categorize_failure(map()) :: failure_category()
  def categorize_failure(failure) do
    message = Map.get(failure, :message, "")

    cond do
      String.contains?(message, ["CompileError", "compile error"]) ->
        :compilation

      String.contains?(message, ["SyntaxError", "syntax error", "unexpected token"]) ->
        :syntax

      String.contains?(message, ["type", "TypeError", "FunctionClauseError", "bad argument"]) ->
        :type

      String.contains?(message, ["Assertion", "assert", "Expected", "but got"]) ->
        :logic

      String.contains?(message, ["nil", "undefined", "not found", "does not exist"]) ->
        :edge_case

      String.contains?(message, ["timeout", "exceeded", "too long"]) ->
        :timeout

      true ->
        :runtime
    end
  end

  @doc """
  Performs root cause analysis on failure.

  ## Parameters

  - `failure` - Failure map with categorization

  ## Returns

  Root cause description string
  """
  @spec analyze_root_cause(map()) :: String.t()
  def analyze_root_cause(failure) do
    category = Map.get(failure, :category, :runtime)
    message = Map.get(failure, :message, "")

    case category do
      :syntax ->
        "Syntax error in code structure. Check for missing/extra brackets, parentheses, or keywords."

      :type ->
        "Type mismatch or incorrect function clause. Verify function signatures and argument types."

      :logic ->
        extract_logic_root_cause(message)

      :edge_case ->
        "Edge case not handled. Code may not account for nil, empty collections, or boundary values."

      :runtime ->
        "Runtime error during execution. Check for invalid operations or missing dependencies."

      :timeout ->
        "Execution exceeded timeout. Code may have infinite loop or be too slow."

      :compilation ->
        "Code failed to compile. Check for syntax errors, undefined modules, or missing dependencies."
    end
  end

  @doc """
  Generates correction prompt based on failure analysis.

  ## Parameters

  - `failure_analysis` - Analyzed failure with root cause

  ## Returns

  Correction prompt string for CoT reasoning
  """
  @spec generate_correction_prompt(failure_analysis()) :: String.t()
  def generate_correction_prompt(failure_analysis) do
    """
    ## Test Failure Correction Required

    **Category:** #{failure_analysis.category}
    **Error:** #{failure_analysis.message}
    #{if failure_analysis.location, do: "**Location:** #{failure_analysis.location}\n", else: ""}
    **Root Cause:** #{failure_analysis.root_cause}

    ### Correction Task

    Please analyze the failure above and generate corrected code that:
    1. Addresses the root cause identified
    2. Passes the failing test case
    3. Maintains functionality of passing tests
    4. Follows best practices for #{failure_analysis.category} issues

    Think step-by-step about:
    - What is causing this specific failure?
    - What changes are needed to fix it?
    - Are there related issues that should be addressed?
    - How can we prevent similar failures?
    """
  end

  @doc """
  Generates correction suggestions for all failures.

  ## Parameters

  - `failures` - List of analyzed failures

  ## Returns

  List of correction suggestion strings
  """
  @spec generate_suggestions(list(failure_analysis())) :: list(String.t())
  def generate_suggestions(failures) do
    failures
    |> Enum.group_by(& &1.category)
    |> Enum.map(fn {category, category_failures} ->
      count = length(category_failures)
      generate_category_suggestion(category, count)
    end)
  end

  # Private functions

  defp analyze_success(execution_result) do
    output = execution_result.output
    {total, passed} = parse_test_counts(output)

    analysis = %{
      status: :pass,
      total_tests: total,
      passed_tests: passed,
      failed_tests: 0,
      failures: [],
      suggestions: ["All tests passing! Code meets requirements."],
      pass_rate: 1.0
    }

    {:ok, analysis}
  end

  defp analyze_failures(execution_result) do
    output = execution_result.output
    {total, passed} = parse_test_counts(output)
    failed = total - passed

    failures = extract_failures(output)
    analyzed_failures = Enum.map(failures, &analyze_failure/1)
    suggestions = generate_suggestions(analyzed_failures)

    analysis = %{
      status: :fail,
      total_tests: total,
      passed_tests: passed,
      failed_tests: failed,
      failures: analyzed_failures,
      suggestions: suggestions,
      pass_rate: if(total > 0, do: passed / total, else: 0.0)
    }

    {:ok, analysis}
  end

  defp analyze_timeout(_execution_result) do
    analysis = %{
      status: :error,
      total_tests: 0,
      passed_tests: 0,
      failed_tests: 0,
      failures: [
        %{
          category: :timeout,
          message: "Test execution exceeded timeout",
          location: nil,
          root_cause: "Execution exceeded timeout. Code may have infinite loop or be too slow.",
          correction_prompt:
            generate_correction_prompt(%{
              category: :timeout,
              message: "Execution timeout",
              location: nil,
              root_cause: "Code execution exceeded time limit"
            })
        }
      ],
      suggestions: [
        "Optimize code to reduce execution time",
        "Check for infinite loops or recursive calls without base cases",
        "Consider using more efficient algorithms or data structures"
      ],
      pass_rate: 0.0
    }

    {:ok, analysis}
  end

  defp analyze_compilation_error(execution_result) do
    errors = execution_result.errors

    analyzed_errors =
      Enum.map(errors, fn error ->
        %{
          category: :compilation,
          message: error.message,
          location: nil,
          root_cause: "Code failed to compile",
          correction_prompt:
            generate_correction_prompt(%{
              category: :compilation,
              message: error.message,
              location: nil,
              root_cause: "Compilation error prevents execution"
            })
        }
      end)

    analysis = %{
      status: :error,
      total_tests: 0,
      passed_tests: 0,
      failed_tests: 0,
      failures: analyzed_errors,
      suggestions: [
        "Fix compilation errors before running tests",
        "Check for syntax errors and undefined modules",
        "Ensure all dependencies are available"
      ],
      pass_rate: 0.0
    }

    {:ok, analysis}
  end

  defp analyze_failure(failure) do
    category = categorize_failure(failure)
    root_cause = analyze_root_cause(%{category: category, message: failure.message})

    failure_analysis = %{
      category: category,
      message: failure.message,
      location: failure[:line_number],
      root_cause: root_cause
    }

    Map.put(failure_analysis, :correction_prompt, generate_correction_prompt(failure_analysis))
  end

  defp parse_test_counts(output) do
    case Regex.run(~r/(\d+) tests?, (\d+) failures?/, output) do
      [_, total_str, failures_str] ->
        total = String.to_integer(total_str)
        failed = String.to_integer(failures_str)
        {total, total - failed}

      _ ->
        {0, 0}
    end
  end

  defp extract_test_name(line) do
    case Regex.run(~r/\d+\) test (.+)/, line) do
      [_, test_name] -> String.trim(test_name)
      _ -> "unknown test"
    end
  end

  defp extract_line_number(line) do
    case Regex.run(~r/:(\d+)/, line) do
      [_, line_num] -> line_num
      _ -> nil
    end
  end

  defp extract_logic_root_cause(message) do
    cond do
      String.contains?(message, "Expected") ->
        "Assertion failed: actual value does not match expected value. Verify calculation logic."

      String.contains?(message, "left") and String.contains?(message, "right") ->
        "Comparison assertion failed. Check equality or comparison logic."

      true ->
        "Logic error in implementation. Verify algorithm correctness and test expectations."
    end
  end

  defp generate_category_suggestion(:syntax, count) do
    "Fix #{count} syntax error(s): Review code structure, brackets, and keywords"
  end

  defp generate_category_suggestion(:type, count) do
    "Fix #{count} type error(s): Verify function signatures and argument types"
  end

  defp generate_category_suggestion(:logic, count) do
    "Fix #{count} logic error(s): Review algorithm implementation and test expectations"
  end

  defp generate_category_suggestion(:edge_case, count) do
    "Fix #{count} edge case error(s): Handle nil, empty values, and boundary conditions"
  end

  defp generate_category_suggestion(:runtime, count) do
    "Fix #{count} runtime error(s): Review error messages and stack traces"
  end

  defp generate_category_suggestion(:timeout, count) do
    "Fix #{count} timeout error(s): Optimize code performance and check for infinite loops"
  end

  defp generate_category_suggestion(:compilation, count) do
    "Fix #{count} compilation error(s): Resolve syntax and module issues"
  end
end
