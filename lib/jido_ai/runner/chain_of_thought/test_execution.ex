defmodule Jido.AI.Runner.ChainOfThought.TestExecution do
  @moduledoc """
  Test execution integration for Chain-of-Thought reasoning.

  This module provides comprehensive test execution capabilities including:
  - Test suite management and generation
  - Sandboxed code execution
  - Test result analysis and failure categorization
  - Iterative code refinement based on test feedback

  ## Usage

      # Generate and execute tests
      {:ok, result} = TestExecution.execute_with_tests(
        code,
        test_suite: generated_tests,
        timeout: 5000
      )

      # Iterative refinement
      {:ok, refined_code} = TestExecution.iterative_refine(
        initial_code,
        test_suite: tests,
        max_iterations: 5
      )
  """

  alias Jido.AI.Runner.ChainOfThought.TestExecution.{
    ExecutionSandbox,
    IterativeRefiner,
    ResultAnalyzer,
    TestSuiteManager
  }

  @doc """
  Executes code with test suite and returns detailed results.

  ## Parameters

  - `code` - Code to execute
  - `opts` - Options:
    - `:test_suite` - Test suite to run (required)
    - `:timeout` - Execution timeout in ms (default: 30000)
    - `:framework` - Test framework to use (default: :ex_unit)

  ## Returns

  - `{:ok, result}` - Execution successful with results
  - `{:error, reason}` - Execution failed

  ## Examples

      {:ok, %{status: :pass, tests_passed: 5, tests_failed: 0}} =
        TestExecution.execute_with_tests(code, test_suite: tests)
  """
  @spec execute_with_tests(String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def execute_with_tests(code, opts) do
    test_suite = Keyword.fetch!(opts, :test_suite)
    timeout = Keyword.get(opts, :timeout, 30_000)
    framework = Keyword.get(opts, :framework, :ex_unit)

    with {:ok, test_file} <- TestSuiteManager.store_tests(test_suite, framework),
         {:ok, code_file} <- TestSuiteManager.store_code(code),
         {:ok, exec_result} <- ExecutionSandbox.execute(code_file, test_file, timeout: timeout) do
      ResultAnalyzer.analyze(exec_result)
    end
  end

  @doc """
  Iteratively refines code based on test execution feedback.

  ## Parameters

  - `code` - Initial code
  - `opts` - Options:
    - `:test_suite` - Test suite to validate against (required)
    - `:max_iterations` - Maximum refinement iterations (default: 5)
    - `:refinement_fn` - Custom refinement function
    - `:on_iteration` - Callback for each iteration

  ## Returns

  - `{:ok, refined_code}` - Refinement successful
  - `{:ok, refined_code, :partial}` - Partial success after max iterations
  - `{:error, reason}` - Refinement failed

  ## Examples

      {:ok, refined} = TestExecution.iterative_refine(
        initial_code,
        test_suite: tests,
        max_iterations: 3,
        on_iteration: fn iter, result ->
          IO.puts("Iteration \#{iter}: \#{trunc(result.pass_rate * 100)}% passed")
        end
      )
  """
  @spec iterative_refine(String.t(), keyword()) ::
          {:ok, String.t()} | {:ok, String.t(), :partial} | {:error, term()}
  def iterative_refine(code, opts) do
    IterativeRefiner.refine(code, opts)
  end

  @doc """
  Generates test suite for given code using CoT reasoning.

  ## Parameters

  - `code` - Code to generate tests for
  - `opts` - Options:
    - `:coverage` - Coverage level (:basic, :comprehensive)
    - `:framework` - Test framework (default: :ex_unit)

  ## Returns

  - `{:ok, test_suite}` - Tests generated successfully
  - `{:error, reason}` - Generation failed
  """
  @spec generate_tests(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_tests(code, opts \\ []) do
    TestSuiteManager.generate_tests(code, opts)
  end
end
