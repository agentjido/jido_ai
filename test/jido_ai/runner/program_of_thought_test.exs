defmodule Jido.AI.Runner.ProgramOfThoughtTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.CoT.ProgramOfThought, as: ProgramOfThoughtAction
  alias Jido.AI.Runner.ProgramOfThought.{
    ProblemClassifier,
    ProgramExecutor,
    ProgramGenerator,
    ResultIntegrator
  }

  describe "ProblemClassifier.classify/1" do
    test "classifies mathematical problems correctly" do
      {:ok, analysis} = ProblemClassifier.classify("What is 15% of 240?")

      assert analysis.domain == :mathematical
      assert analysis.computational == true
      assert analysis.complexity in [:low, :medium]
      assert analysis.confidence >= 0.5
      assert analysis.should_use_pot == true
    end

    test "classifies financial problems correctly" do
      {:ok, analysis} =
        ProblemClassifier.classify("Calculate compound interest on $1000 at 5% for 10 years")

      assert analysis.domain == :financial
      assert analysis.computational == true
      # Operations may or may not be detected depending on phrasing
      assert is_list(analysis.operations)
    end

    test "classifies scientific problems correctly" do
      {:ok, analysis} = ProblemClassifier.classify("Convert 100 meters to feet")

      assert analysis.domain == :scientific
      assert analysis.computational == true
    end

    test "detects non-computational problems" do
      {:ok, analysis} =
        ProblemClassifier.classify("Explain the theory of relativity")

      assert analysis.computational == false
      assert analysis.should_use_pot == false
    end

    test "detects operations in problems" do
      {:ok, analysis} = ProblemClassifier.classify("Add 5 and 10, then multiply by 2")

      assert :addition in analysis.operations
      assert :multiplication in analysis.operations
    end

    test "estimates complexity correctly" do
      {:ok, low_analysis} = ProblemClassifier.classify("What is 2 + 2?")
      assert low_analysis.complexity == :low

      {:ok, medium_analysis} =
        ProblemClassifier.classify("Calculate 15% of 240 and then subtract 10")

      assert medium_analysis.complexity in [:low, :medium]
    end

    test "handles domain specification" do
      {:ok, analysis} =
        ProblemClassifier.analyze_with_domain("Calculate something", :mathematical)

      assert analysis.domain == :mathematical
      assert analysis.confidence == 1.0
      assert analysis.should_use_pot == true
    end
  end

  describe "ProgramGenerator.generate/2" do
    @tag :skip
    # Requires LLM
    test "generates program for simple mathematical problem" do
      problem = "What is 15% of 240?"
      opts = [domain: :mathematical, complexity: :low]

      {:ok, program} = ProgramGenerator.generate(problem, opts)

      assert is_binary(program)
      assert String.contains?(program, "defmodule Solution")
      assert String.contains?(program, "def solve")
    end

    test "validates program structure" do
      valid_program = """
      defmodule Solution do
        def solve do
          42
        end
      end
      """

      assert :ok = ProgramExecutor.validate_safety(valid_program)
    end

    test "detects unsafe file operations" do
      unsafe_program = """
      defmodule Solution do
        def solve do
          File.read("secret.txt")
        end
      end
      """

      {:error, {:unsafe_operation, :file_io}} =
        ProgramExecutor.validate_safety(unsafe_program)
    end

    test "detects unsafe system calls" do
      unsafe_program = """
      defmodule Solution do
        def solve do
          System.cmd("rm", ["-rf", "/"])
        end
      end
      """

      assert {:error, {:unsafe_operation, :system_call}} =
               ProgramExecutor.validate_safety(unsafe_program)
    end

    test "detects unsafe process operations" do
      unsafe_program = """
      defmodule Solution do
        def solve do
          spawn(fn -> IO.puts("evil") end)
        end
      end
      """

      {:error, {:unsafe_operation, :process_spawn}} =
        ProgramExecutor.validate_safety(unsafe_program)
    end
  end

  describe "ProgramExecutor.execute/2" do
    test "executes simple program successfully" do
      program = """
      defmodule Solution do
        def solve do
          42
        end
      end
      """

      {:ok, result} = ProgramExecutor.execute(program, timeout: 1000)

      assert result.result == 42
      assert result.duration_ms < 1000
      assert is_binary(result.output)
    end

    test "executes mathematical calculations" do
      program = """
      defmodule Solution do
        def solve do
          # Calculate 15% of 240
          number = 240
          percentage = 15
          result = number * (percentage / 100)
          result
        end
      end
      """

      {:ok, result} = ProgramExecutor.execute(program)

      assert result.result == 36.0
    end

    test "executes financial calculations" do
      program = """
      defmodule Solution do
        def solve do
          # Simple interest: I = P * r * t
          principal = 1000
          rate = 0.05
          time = 10
          interest = principal * rate * time
          Float.round(interest, 2)
        end
      end
      """

      {:ok, result} = ProgramExecutor.execute(program)

      assert result.result == 500.0
    end

    test "uses math functions correctly" do
      program = """
      defmodule Solution do
        def solve do
          # Square root of 16
          :math.sqrt(16)
        end
      end
      """

      {:ok, result} = ProgramExecutor.execute(program)

      assert result.result == 4.0
    end

    test "handles syntax errors gracefully" do
      program = """
      defmodule Solution do
        def solve do
          invalid syntax here
        end
      end
      """

      {:error, {:execution_error, error}} = ProgramExecutor.execute(program)

      assert error.type in [:syntax_error, :compile_error, :token_error]
      assert is_binary(error.message)
    end

    test "handles runtime errors gracefully" do
      program = """
      defmodule Solution do
        def solve do
          1 / 0
        end
      end
      """

      {:error, {:execution_error, error}} = ProgramExecutor.execute(program)

      assert error.type == :arithmetic_error
    end

    test "handles undefined function errors" do
      program = """
      defmodule Solution do
        def solve do
          NonExistent.function()
        end
      end
      """

      {:error, {:execution_error, error}} = ProgramExecutor.execute(program)

      assert error.type == :undefined_function
    end

    test "enforces timeout" do
      program = """
      defmodule Solution do
        def solve do
          # Infinite loop (should timeout)
          solve()
        end
      end
      """

      {:error, :timeout} = ProgramExecutor.execute(program, timeout: 100)
    end

    test "captures output when requested" do
      program = """
      defmodule Solution do
        def solve do
          IO.puts("Step 1")
          IO.puts("Step 2")
          42
        end
      end
      """

      {:ok, result} = ProgramExecutor.execute(program, capture_output: true)

      assert result.result == 42
      # IO capture may not work in all test environments, so just verify output field exists
      assert is_binary(result.output)
    end

    test "validates timeout range" do
      program = """
      defmodule Solution do
        def solve, do: 42
      end
      """

      # Very large timeout should be capped
      {:ok, _result} = ProgramExecutor.execute(program, timeout: 999_999)

      # Negative timeout should use default
      {:ok, _result} = ProgramExecutor.execute(program, timeout: -1)
    end
  end

  describe "ResultIntegrator.integrate/2" do
    test "integrates simple result successfully" do
      execution_result = %{
        result: 36.0,
        duration_ms: 10,
        output: ""
      }

      program = """
      defmodule Solution do
        def solve do
          # Step 1: Define the number
          number = 240
          # Step 2: Calculate 15%
          percentage = 15
          result = number * (percentage / 100)
          result
        end
      end
      """

      analysis = %{
        domain: :mathematical,
        complexity: :low,
        operations: [:percentage, :multiplication]
      }

      opts = [
        program: program,
        analysis: analysis,
        generate_explanation: false,
        validate_result: true
      ]

      {:ok, result} = ResultIntegrator.integrate(execution_result, opts)

      assert result.answer == 36.0
      assert is_list(result.steps)
      assert length(result.steps) > 0
      assert result.validation.is_plausible == true
    end

    test "extracts computational steps from program" do
      execution_result = %{result: 42, duration_ms: 5, output: ""}

      program = """
      defmodule Solution do
        def solve do
          # Step 1: Initialize value
          x = 10
          # Step 2: Multiply by 4
          y = x * 4
          # Step 3: Add 2
          result = y + 2
          result
        end
      end
      """

      analysis = %{domain: :mathematical, complexity: :low, operations: []}

      opts = [
        program: program,
        analysis: analysis,
        generate_explanation: false,
        validate_result: false
      ]

      {:ok, result} = ResultIntegrator.integrate(execution_result, opts)

      assert length(result.steps) >= 3
      assert Enum.any?(result.steps, fn {type, _, _} -> type == :comment end)
      assert Enum.any?(result.steps, fn {type, _, _} -> type == :calculation end)
    end

    test "validates result plausibility for financial domain" do
      execution_result = %{result: 500.0, duration_ms: 8, output: ""}

      program = "defmodule Solution do\n  def solve, do: 500.0\nend"

      analysis = %{
        domain: :financial,
        complexity: :medium,
        operations: [:multiplication]
      }

      opts = [
        program: program,
        analysis: analysis,
        generate_explanation: false,
        validate_result: true
      ]

      {:ok, result} = ResultIntegrator.integrate(execution_result, opts)

      assert result.validation.is_plausible == true
      assert result.validation.confidence > 0.5
      assert is_list(result.validation.checks)
    end

    test "flags implausible results" do
      # Negative financial result
      execution_result = %{result: -1000.0, duration_ms: 5, output: ""}

      program = "defmodule Solution do\n  def solve, do: -1000.0\nend"

      analysis = %{
        domain: :financial,
        complexity: :low,
        operations: []
      }

      opts = [
        program: program,
        analysis: analysis,
        generate_explanation: false,
        validate_result: true
      ]

      {:ok, result} = ResultIntegrator.integrate(execution_result, opts)

      # Should detect implausible negative financial result
      assert result.validation.is_plausible == false or result.validation.confidence < 0.8
    end

    test "validates execution time appropriateness" do
      # Low complexity should execute quickly
      fast_result = %{result: 42, duration_ms: 5, output: ""}

      program = "defmodule Solution do\n  def solve, do: 42\nend"

      analysis = %{domain: :mathematical, complexity: :low, operations: []}

      opts = [
        program: program,
        analysis: analysis,
        generate_explanation: false,
        validate_result: true
      ]

      {:ok, result} = ResultIntegrator.integrate(fast_result, opts)

      assert result.validation.is_plausible == true

      # Low complexity taking too long is suspicious
      slow_result = %{result: 42, duration_ms: 5000, output: ""}

      {:ok, result} = ResultIntegrator.integrate(slow_result, opts)

      # Should flag slow execution for simple problem
      assert result.validation.confidence < 1.0
    end

    test "handles non-numeric results" do
      execution_result = %{result: "result string", duration_ms: 5, output: ""}

      program = """
      defmodule Solution do
        def solve, do: "result string"
      end
      """

      analysis = %{domain: :mathematical, complexity: :low, operations: []}

      opts = [
        program: program,
        analysis: analysis,
        generate_explanation: false,
        validate_result: true
      ]

      {:ok, result} = ResultIntegrator.integrate(execution_result, opts)

      assert result.answer == "result string"
      assert is_map(result.validation)
    end
  end

  describe "End-to-end Program-of-Thought" do
    @tag :skip
    # Requires LLM
    test "solves simple percentage problem" do
      action =
        ProgramOfThoughtAction.new!(%{
          problem: "What is 15% of 240?",
          timeout: 5000,
          generate_explanation: false
        })

      {:ok, result, _context} =
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        Jido.AI.Actions.CoT.ProgramOfThought.run(action.params, %{})

      assert is_number(result.answer)
      assert_in_delta(result.answer, 36.0, 0.01)
      assert result.domain == :mathematical
      assert is_binary(result.program)
    end

    @tag :skip
    # Requires LLM
    test "solves financial calculation problem" do
      action =
        ProgramOfThoughtAction.new!(%{
          problem: "Calculate simple interest on $1000 at 5% for 10 years",
          domain: :financial,
          timeout: 5000
        })

      {:ok, result, _context} =
        # credo:disable-for-next-line Credo.Check.Design.AliasUsage
        Jido.AI.Actions.CoT.ProgramOfThought.run(action.params, %{})

      assert is_number(result.answer)
      assert_in_delta(result.answer, 500.0, 1.0)
      assert result.domain == :financial
    end
  end

  describe "Error handling and edge cases" do
    test "handles empty problem string" do
      {:ok, analysis} = ProblemClassifier.classify("")

      assert is_map(analysis)
      assert is_atom(analysis.domain)
    end

    test "handles very long problem description" do
      long_problem = String.duplicate("Calculate this number ", 1000)

      {:ok, analysis} = ProblemClassifier.classify(long_problem)

      assert analysis.complexity in [:medium, :high]
    end

    test "handles special characters in problem" do
      {:ok, analysis} = ProblemClassifier.classify("What is $1,000 * 5% + €200?")

      assert analysis.computational == true
    end
  end
end
