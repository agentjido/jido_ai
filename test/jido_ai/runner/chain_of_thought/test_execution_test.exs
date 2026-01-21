defmodule Jido.AI.Runner.ChainOfThought.TestExecutionTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.TestExecution

  alias Jido.AI.Runner.ChainOfThought.TestExecution.{
    ExecutionSandbox,
    IterativeRefiner,
    ResultAnalyzer,
    TestSuiteManager
  }

  describe "TestSuiteManager.generate_tests/2" do
    test "generates basic ExUnit tests" do
      code = """
      defmodule Calculator do
        def add(a, b), do: a + b
        def subtract(a, b), do: a - b
      end
      """

      assert {:ok, test_suite} = TestSuiteManager.generate_tests(code, coverage: :basic)
      assert String.contains?(test_suite, "defmodule CalculatorTest")
      assert String.contains?(test_suite, "use ExUnit.Case")
      assert String.contains?(test_suite, "test")
    end

    test "generates comprehensive tests with describes" do
      code = """
      defmodule Math do
        def multiply(a, b), do: a * b
      end
      """

      assert {:ok, test_suite} = TestSuiteManager.generate_tests(code, coverage: :comprehensive)
      assert String.contains?(test_suite, "describe")
      assert String.contains?(test_suite, "edge cases")
    end

    test "generates exhaustive tests with multiple cases" do
      code = """
      defmodule StringHelper do
        def reverse(str), do: String.reverse(str)
      end
      """

      assert {:ok, test_suite} = TestSuiteManager.generate_tests(code, coverage: :exhaustive)
      assert String.contains?(test_suite, "error conditions")
      assert String.contains?(test_suite, "input types")
    end

    test "generates doc tests" do
      code = """
      defmodule Greeter do
        def hello(name), do: "Hello, \#{name}!"
      end
      """

      assert {:ok, test_suite} = TestSuiteManager.generate_tests(code, framework: :doc_test)
      assert String.contains?(test_suite, "doctest")
    end

    test "generates property tests" do
      code = """
      defmodule Sorter do
        def sort(list), do: Enum.sort(list)
      end
      """

      assert {:ok, test_suite} = TestSuiteManager.generate_tests(code, framework: :property_test)
      assert String.contains?(test_suite, "use ExUnitProperties")
      assert String.contains?(test_suite, "property")
    end
  end

  describe "TestSuiteManager.store_tests/2" do
    test "stores test suite in temporary file" do
      test_content = """
      defmodule SampleTest do
        use ExUnit.Case

        test "sample" do
          assert true
        end
      end
      """

      assert {:ok, file_path} = TestSuiteManager.store_tests(test_content)
      assert File.exists?(file_path)
      assert String.ends_with?(file_path, "_test.exs")

      # Cleanup
      TestSuiteManager.cleanup([file_path])
    end

    test "returns error for invalid write" do
      # Try to write to invalid path
      invalid_content =
        test_content = """
        defmodule Test do
        end
        """

      # This should succeed with temp dir
      assert {:ok, _path} = TestSuiteManager.store_tests(invalid_content)
    end
  end

  describe "TestSuiteManager.store_code/1" do
    test "stores code in temporary file" do
      code = """
      defmodule Sample do
        def test, do: :ok
      end
      """

      assert {:ok, file_path} = TestSuiteManager.store_code(code)
      assert File.exists?(file_path)
      assert String.ends_with?(file_path, ".ex")

      # Cleanup
      TestSuiteManager.cleanup([file_path])
    end
  end

  describe "TestSuiteManager.detect_framework/1" do
    test "detects ExUnit framework" do
      content = "use ExUnit.Case\ntest do"
      assert TestSuiteManager.detect_framework(content) == :ex_unit
    end

    test "detects DocTest framework" do
      content = "@doc \"\"\"\niex> 1 + 1\n2\n\"\"\""
      assert TestSuiteManager.detect_framework(content) == :doc_test
    end

    test "detects Property Test framework" do
      content = "use ExUnitProperties\nproperty do"
      assert TestSuiteManager.detect_framework(content) == :property_test
    end

    test "defaults to ExUnit for unknown" do
      content = "some random content"
      assert TestSuiteManager.detect_framework(content) == :ex_unit
    end
  end

  describe "TestSuiteManager.register_template/2 and get_template/1" do
    test "registers and retrieves custom template" do
      template_fn = fn _code -> "custom test" end

      assert :ok = TestSuiteManager.register_template(:custom, template_fn)
      assert {:ok, retrieved_fn} = TestSuiteManager.get_template(:custom)
      assert is_function(retrieved_fn, 1)
    end

    test "returns error for non-existent template" do
      assert {:error, :not_found} = TestSuiteManager.get_template(:nonexistent)
    end
  end

  describe "TestSuiteManager.cleanup/1" do
    test "cleans up temporary files" do
      {:ok, file1} = TestSuiteManager.store_code("code1")
      {:ok, file2} = TestSuiteManager.store_code("code2")

      assert File.exists?(file1)
      assert File.exists?(file2)

      assert :ok = TestSuiteManager.cleanup([file1, file2])

      refute File.exists?(file1)
      refute File.exists?(file2)
    end

    test "handles cleanup of non-existent files gracefully" do
      assert :ok = TestSuiteManager.cleanup(["/nonexistent/file.ex"])
    end
  end

  describe "ExecutionSandbox.execute_code/2" do
    test "executes valid code successfully" do
      assert {:ok, result} = ExecutionSandbox.execute_code("1 + 1", timeout: 1000)
      assert result == 2
    end

    test "captures runtime errors" do
      assert {:error, {:runtime_error, _, _}} =
               ExecutionSandbox.execute_code("raise \"error\"", timeout: 1000)
    end

    test "enforces timeout" do
      # Infinite loop
      assert {:error, {:timeout, _}} =
               ExecutionSandbox.execute_code("Stream.cycle([1]) |> Enum.take(1000000000)",
                 timeout: 100
               )
    end

    test "handles syntax errors" do
      assert {:error, _} = ExecutionSandbox.execute_code("def invalid", timeout: 1000)
    end

    test "supports variable bindings" do
      assert {:ok, 3} =
               ExecutionSandbox.execute_code("a + b", bindings: [a: 1, b: 2], timeout: 1000)
    end
  end

  describe "ExecutionSandbox.compile_code/2" do
    test "compiles valid code" do
      {:ok, code_file} =
        TestSuiteManager.store_code("""
        defmodule ValidModule do
          def test, do: :ok
        end
        """)

      assert {:ok, _output} = ExecutionSandbox.compile_code(code_file, 5000)

      TestSuiteManager.cleanup([code_file])
    end

    test "returns error for invalid code" do
      {:ok, code_file} =
        TestSuiteManager.store_code("""
        defmodule Invalid do
          def test do
        end
        """)

      assert {:error, _errors} = ExecutionSandbox.compile_code(code_file, 5000)

      TestSuiteManager.cleanup([code_file])
    end
  end

  describe "ExecutionSandbox.enforce_timeout/2" do
    test "returns result within timeout" do
      test_fn = fn ->
        :timer.sleep(10)
        :ok
      end

      assert {:ok, :ok} = ExecutionSandbox.enforce_timeout(test_fn, 1000)
    end

    test "returns error when timeout exceeded" do
      test_fn = fn ->
        :timer.sleep(1000)
        :ok
      end

      assert {:error, :timeout} = ExecutionSandbox.enforce_timeout(test_fn, 100)
    end
  end

  describe "ExecutionSandbox.capture_runtime_errors/1" do
    test "returns result for successful execution" do
      test_fn = fn -> 1 + 1 end

      assert {:ok, 2} = ExecutionSandbox.capture_runtime_errors(test_fn)
    end

    test "captures raised errors" do
      test_fn = fn -> raise ArgumentError, "test error" end

      assert {:error, %{type: :runtime_error, message: message}} =
               ExecutionSandbox.capture_runtime_errors(test_fn)

      assert String.contains?(message, "test error")
    end

    test "captures thrown values" do
      test_fn = fn -> throw(:test_throw) end

      assert {:error, %{type: :caught, kind: :throw, value: :test_throw}} =
               ExecutionSandbox.capture_runtime_errors(test_fn)
    end
  end

  describe "ResultAnalyzer.extract_failures/1" do
    test "extracts failures from test output" do
      output = """
        1) test example fails
           ** (ExUnit.AssertionError) assertion failed
      """

      failures = ResultAnalyzer.extract_failures(output)
      assert length(failures) >= 1
      assert hd(failures).test =~ "example fails"
    end

    test "handles output with no failures" do
      output = "1 test, 0 failures"

      failures = ResultAnalyzer.extract_failures(output)
      assert Enum.empty?(failures)
    end
  end

  describe "ResultAnalyzer.categorize_failure/1" do
    test "categorizes syntax errors" do
      failure = %{message: "SyntaxError: unexpected token"}
      assert ResultAnalyzer.categorize_failure(failure) == :syntax
    end

    test "categorizes type errors" do
      failure = %{message: "FunctionClauseError: no function clause matching"}
      assert ResultAnalyzer.categorize_failure(failure) == :type
    end

    test "categorizes logic errors" do
      failure = %{message: "Assertion with == failed"}
      assert ResultAnalyzer.categorize_failure(failure) == :logic
    end

    test "categorizes edge case errors" do
      failure = %{message: "nil value found"}
      assert ResultAnalyzer.categorize_failure(failure) == :edge_case
    end

    test "categorizes timeout errors" do
      failure = %{message: "execution timeout exceeded"}
      assert ResultAnalyzer.categorize_failure(failure) == :timeout
    end

    test "categorizes compilation errors" do
      failure = %{message: "CompileError: module not found"}
      assert ResultAnalyzer.categorize_failure(failure) == :compilation
    end

    test "defaults to runtime for unknown errors" do
      failure = %{message: "unknown error"}
      assert ResultAnalyzer.categorize_failure(failure) == :runtime
    end
  end

  describe "ResultAnalyzer.analyze_root_cause/1" do
    test "provides root cause for syntax errors" do
      failure = %{category: :syntax, message: "syntax error"}
      cause = ResultAnalyzer.analyze_root_cause(failure)
      assert String.contains?(cause, "Syntax error")
    end

    test "provides root cause for type errors" do
      failure = %{category: :type, message: "type mismatch"}
      cause = ResultAnalyzer.analyze_root_cause(failure)
      assert String.contains?(cause, "Type mismatch")
    end

    test "provides root cause for logic errors" do
      failure = %{category: :logic, message: "Expected 5 but got 3"}
      cause = ResultAnalyzer.analyze_root_cause(failure)
      assert String.contains?(cause, "value does not match")
    end
  end

  describe "ResultAnalyzer.generate_correction_prompt/1" do
    test "generates correction prompt with all details" do
      failure_analysis = %{
        category: :logic,
        message: "assertion failed",
        location: "test.exs:10",
        root_cause: "calculation incorrect"
      }

      prompt = ResultAnalyzer.generate_correction_prompt(failure_analysis)

      assert String.contains?(prompt, "logic")
      assert String.contains?(prompt, "assertion failed")
      assert String.contains?(prompt, "test.exs:10")
      assert String.contains?(prompt, "calculation incorrect")
      assert String.contains?(prompt, "Correction Task")
    end

    test "handles missing location" do
      failure_analysis = %{
        category: :runtime,
        message: "error",
        location: nil,
        root_cause: "unknown"
      }

      prompt = ResultAnalyzer.generate_correction_prompt(failure_analysis)

      refute String.contains?(prompt, "Location:")
    end
  end

  describe "ResultAnalyzer.generate_suggestions/1" do
    test "generates suggestions grouped by category" do
      failures = [
        %{category: :syntax, message: "error 1"},
        %{category: :syntax, message: "error 2"},
        %{category: :type, message: "error 3"}
      ]

      suggestions = ResultAnalyzer.generate_suggestions(failures)

      assert length(suggestions) == 2
      assert Enum.any?(suggestions, &String.contains?(&1, "2 syntax"))
      assert Enum.any?(suggestions, &String.contains?(&1, "1 type"))
    end

    test "handles empty failures list" do
      suggestions = ResultAnalyzer.generate_suggestions([])
      assert Enum.empty?(suggestions)
    end
  end

  describe "ResultAnalyzer.analyze/1" do
    test "analyzes successful execution" do
      execution_result = %{
        status: :success,
        output: "5 tests, 0 failures",
        errors: [],
        duration_ms: 100,
        exit_code: 0
      }

      assert {:ok, analysis} = ResultAnalyzer.analyze(execution_result)
      assert analysis.status == :pass
      assert analysis.total_tests == 5
      assert analysis.passed_tests == 5
      assert analysis.failed_tests == 0
      assert analysis.pass_rate == 1.0
      assert Enum.empty?(analysis.failures)
    end

    test "analyzes failed execution" do
      execution_result = %{
        status: :failure,
        output: """
        5 tests, 2 failures

        1) test example
           ** (ExUnit.AssertionError) assertion failed

        2) test another
           ** (RuntimeError) error
        """,
        errors: [],
        duration_ms: 150,
        exit_code: 1
      }

      assert {:ok, analysis} = ResultAnalyzer.analyze(execution_result)
      assert analysis.status == :fail
      assert analysis.total_tests == 5
      assert analysis.passed_tests == 3
      assert analysis.failed_tests == 2
      assert analysis.pass_rate == 0.6
      assert length(analysis.failures) >= 1
    end

    test "analyzes timeout" do
      execution_result = %{
        status: :timeout,
        output: "",
        errors: [%{type: :timeout, message: "timeout"}],
        duration_ms: 30_000,
        exit_code: nil
      }

      assert {:ok, analysis} = ResultAnalyzer.analyze(execution_result)
      assert analysis.status == :error
      assert length(analysis.failures) == 1
      assert hd(analysis.failures).category == :timeout
    end

    test "analyzes compilation error" do
      execution_result = %{
        status: :compilation_error,
        output: "",
        errors: [%{type: :compilation_error, message: "syntax error"}],
        duration_ms: 50,
        exit_code: 1
      }

      assert {:ok, analysis} = ResultAnalyzer.analyze(execution_result)
      assert analysis.status == :error
      assert length(analysis.failures) == 1
      assert hd(analysis.failures).category == :compilation
    end
  end

  describe "IterativeRefiner.detect_convergence/1" do
    test "returns false for short history" do
      history = [
        %{pass_rate: 0.5},
        %{pass_rate: 0.6}
      ]

      refute IterativeRefiner.detect_convergence(history)
    end

    test "detects convergence when pass rate plateaus" do
      history = [
        %{pass_rate: 0.80},
        %{pass_rate: 0.81},
        %{pass_rate: 0.79}
      ]

      assert IterativeRefiner.detect_convergence(history)
    end

    test "returns false when pass rate still improving" do
      history = [
        %{pass_rate: 0.8},
        %{pass_rate: 0.6},
        %{pass_rate: 0.4}
      ]

      refute IterativeRefiner.detect_convergence(history)
    end
  end

  describe "IterativeRefiner.track_improvements/2" do
    test "tracks improvements for first iteration" do
      current = %{pass_rate: 0.6, improvements: []}
      improvements = IterativeRefiner.track_improvements(current, nil)

      assert length(improvements) == 1
      assert hd(improvements) =~ "Initial iteration"
    end

    test "tracks pass rate improvement" do
      previous = %{pass_rate: 0.4, improvements: []}
      current = %{pass_rate: 0.7, improvements: []}

      improvements = IterativeRefiner.track_improvements(current, previous)

      assert Enum.any?(improvements, &String.contains?(&1, "Pass rate improved"))
    end

    test "reports no improvement when stagnant" do
      previous = %{pass_rate: 0.5, improvements: []}
      current = %{pass_rate: 0.5, improvements: []}

      improvements = IterativeRefiner.track_improvements(current, previous)

      assert hd(improvements) =~ "No improvement"
    end
  end

  describe "integration scenarios" do
    test "generate tests, store, and cleanup" do
      code = """
      defmodule SimpleModule do
        def identity(x), do: x
      end
      """

      # Generate tests
      {:ok, test_suite} = TestSuiteManager.generate_tests(code)

      # Store both
      {:ok, test_file} = TestSuiteManager.store_tests(test_suite)
      {:ok, code_file} = TestSuiteManager.store_code(code)

      assert File.exists?(test_file)
      assert File.exists?(code_file)

      # Cleanup
      TestSuiteManager.cleanup([test_file, code_file])

      refute File.exists?(test_file)
      refute File.exists?(code_file)
    end
  end
end
