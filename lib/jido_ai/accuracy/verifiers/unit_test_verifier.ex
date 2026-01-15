defmodule Jido.AI.Accuracy.Verifiers.UnitTestVerifier do
  @moduledoc """
  Verifier that runs unit tests to validate code correctness.

  This verifier executes test suites and scores candidates based on
  test pass rate. Useful for:
  - Verifying generated code against test requirements
  - Regression testing during code evolution
  - Quality assessment for code candidates
  - TDD (Test-Driven Development) workflows

  ## Test Output Formats

  The verifier supports multiple test output formats:

  ### JUnit XML Format

  Standard XML format used by Java, pytest, and many others:

      verifier = UnitTestVerifier.new!(%{
        test_command: "pytest",
        test_args: ["--junitxml=results.xml"],
        output_format: :junit
      })

  ### TAP (Test Anything Protocol)

  Human-readable format used by Perl, Elixir, and others:

      verifier = UnitTestVerifier.new!(%{
        test_command: "mix test",
        output_format: :tap
      })

  ### Dot Format

  Simple pass/fail indicators:

      verifier = UnitTestVerifier.new!(%{
        test_command: "mix test",
        output_format: :dot
      })

  ### Auto Detection

  Automatically detects format from test output:

      verifier = UnitTestVerifier.new!(%{
        test_command: "pytest",
        output_format: :auto
      })

  ## Usage

      # Create verifier for Elixir tests
      verifier = UnitTestVerifier.new!(%{
        test_command: "mix",
        test_args: ["test", "--max-failures=1"],
        output_format: :tap
      })

      # Verify a candidate (tests should already exist)
      candidate = Candidate.new!(%{
        content: "def add(a, b), do: a + b"
      })

      {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{
        test_file: "test/math_test.exs"
      })

      # Check result
      result.score  # => 1.0 (all tests passed)
      result.reasoning  # => "5/5 tests passed"

  ## Score Calculation

  Score is calculated as: `passed_tests / total_tests`

  - `1.0` - All tests passed
  - `0.5` - Half of tests passed
  - `0.0` - No tests passed or test execution failed

  ## Test Result Parsing

  ### JUnit Format

  ```xml
  <testsuite tests="10" failures="2" errors="1" skipped="0">
    ...
  </testsuite>
  ```

  ### TAP Format

  ```
  1..5
  ok 1 - test addition
  not ok 2 - test subtraction
  ...
  ```

  ### Dot Format

  ```
  ....F...*
  ```

  Each character represents a test:
  - `.` - Passed
  - `F` - Failed
  - `*` - Skipped

  ## Configuration

  ### Test Commands

  Common test commands by language:
  - Elixir: `mix test`
  - Python: `pytest` or `python -m unittest`
  - JavaScript: `npm test` or `jest`
  - Ruby: `rspec` or `ruby -Itest`

  ### Working Directory

  Set the working directory for test execution:

      verifier = UnitTestVerifier.new!(%{
        test_command: "pytest",
        working_dir: "/path/to/project"
      })

  ### Environment Variables

  Pass environment variables to tests:

      verifier = UnitTestVerifier.new!(%{
        test_command: "pytest",
        environment: %{"TEST_ENV" => "ci"}
      })

  ## Security Considerations

  - Tests run in a subprocess with timeout protection
  - Working directory is validated before execution
  - Environment variables are sanitized
  - Consider sandboxing for untrusted code

  """

  @behaviour Jido.AI.Accuracy.Verifier

  alias Jido.AI.Accuracy.{Candidate, VerificationResult, ToolExecutor}

  @type output_format :: :junit | :tap | :dot | :auto
  @type t :: %__MODULE__{
          test_command: String.t(),
          test_args: [String.t()],
          test_pattern: String.t() | nil,
          output_format: output_format(),
          working_dir: String.t() | nil,
          environment: %{optional(String.t()) => String.t()},
          timeout: pos_integer()
        }

  defstruct test_command: "mix",
            test_args: ["test"],
            test_pattern: nil,
            output_format: :auto,
            working_dir: nil,
            environment: %{},
            timeout: 30_000

  @doc """
  Creates a new unit test verifier from the given attributes.

  ## Options

  - `:test_command` - Command to run tests (default: "mix")
  - `:test_args` - Arguments for test command (default: ["test"])
  - `:test_pattern` - Pattern for test file selection
  - `:output_format` - Output format (:junit, :tap, :dot, :auto, default: :auto)
  - `:working_dir` - Working directory for tests
  - `:environment` - Environment variables for tests
  - `:timeout` - Test execution timeout in ms (default: 30000)

  ## Returns

  - `{:ok, verifier}` - Success
  - `:error, reason}` - Validation failed

  ## Examples

      iex> UnitTestVerifier.new(%{test_command: "pytest"})
      {:ok, %UnitTestVerifier{test_command: "pytest"}}

      iex> UnitTestVerifier.new(%{output_format: :junit})
      {:ok, %UnitTestVerifier{output_format: :junit}}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    verifier = struct(__MODULE__, opts)

    with :ok <- validate_test_command(verifier.test_command),
         :ok <- validate_output_format(verifier.output_format),
         :ok <- validate_timeout(verifier.timeout),
         :ok <- validate_working_dir(verifier.working_dir) do
      {:ok, verifier}
    end
  end

  @doc """
  Creates a new unit test verifier, raising on error.

  ## Examples

      iex> UnitTestVerifier.new!(%{test_command: "pytest"})
      %UnitTestVerifier{test_command: "pytest"}

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) or is_map(opts) do
    case new(opts) do
      {:ok, verifier} -> verifier
      {:error, reason} -> raise ArgumentError, "Invalid unit test verifier: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Verifies a candidate by running unit tests.

  Executes the configured test command and parses the output to
  calculate a score based on test pass rate.

  ## Examples

      iex> verifier = UnitTestVerifier.new!(%{})
      iex> candidate = Candidate.new!(%{content: "code"})
      iex> {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})
      iex> result.score >= 0.0
      true

  """
  @spec verify(t(), Candidate.t(), map()) :: {:ok, VerificationResult.t()} | {:error, term()}
  def verify(%__MODULE__{} = verifier, %Candidate{} = candidate, context) do
    command = build_test_command(verifier, context)

    opts = [
      timeout: verifier.timeout,
      cd: verifier.working_dir,
      env: verifier.environment
    ]

    case ToolExecutor.run_command(verifier.test_command, command, opts) do
      {:ok, result} ->
        test_results = parse_test_output(result, verifier.output_format)

        score = calculate_pass_rate(test_results)
        reasoning = build_reasoning(test_results, result)

        verification_result = %VerificationResult{
          candidate_id: candidate.id,
          score: score,
          confidence: calculate_confidence(test_results),
          reasoning: reasoning,
          metadata:
            Map.merge(test_results, %{
              exit_code: result.exit_code,
              stdout: result.stdout,
              stderr: result.stderr,
              timed_out: result.timed_out,
              duration_ms: result.duration_ms
            })
        }

        {:ok, verification_result}

      {:error, reason} ->
        {:ok, error_result(candidate, reason)}
    end
  end

  @impl true
  @doc """
  Verifies multiple candidates in batch.

  Note: This runs the full test suite for each candidate.
  For efficiency, consider running tests once and comparing
  all candidates against the expected results.

  ## Examples

      iex> verifier = UnitTestVerifier.new!(%{})
      iex> candidates = [Candidate.new!(%{id: "1", content: "code"})]
      iex> {:ok, results} = UnitTestVerifier.verify_batch(verifier, candidates, %{})
      iex> length(results)
      1

  """
  @spec verify_batch(t(), [Candidate.t()], map()) :: {:ok, [VerificationResult.t()]} | {:error, term()}
  def verify_batch(%__MODULE__{} = verifier, candidates, context) when is_list(candidates) do
    results =
      Enum.map(candidates, fn candidate ->
        case verify(verifier, candidate, context) do
          {:ok, result} -> result
          {:error, _reason} -> error_result(candidate, :test_execution_failed)
        end
      end)

    {:ok, results}
  end

  @impl true
  @doc """
  Unit test verifier does not support streaming.

  """
  @spec supports_streaming?() :: false
  def supports_streaming?, do: false

  # Private functions

  defp build_test_command(verifier, context) do
    base_args = verifier.test_args

    # Add test pattern if specified
    pattern_args =
      if verifier.test_pattern do
        ["--pattern", verifier.test_pattern]
      else
        []
      end

    # Add test file from context if specified
    context_args =
      if test_file = Map.get(context, :test_file) do
        [test_file]
      else
        []
      end

    base_args ++ pattern_args ++ context_args
  end

  defp parse_test_output(result, format) do
    output = ToolExecutor.capture_output(result)

    case format do
      :auto -> detect_and_parse(output)
      :junit -> parse_junit(output)
      :tap -> parse_tap(output)
      :dot -> parse_dot(output)
    end
  end

  defp detect_and_parse(output) do
    cond do
      String.contains?(output, "<testsuite") -> parse_junit(output)
      String.contains?(output, "TAP version") or String.contains?(output, "1..") -> parse_tap(output)
      Regex.match?(~r/^[\.F\*]+$/m, output) -> parse_dot(output)
      true -> fallback_parse(output)
    end
  end

  defp parse_junit(output) do
    # Try to extract test counts from JUnit XML
    case Regex.run(~r/<testsuite[^>]*tests="(\d+)"[^>]*failures="(\d+)"[^>]*errors="(\d+)"/, output) do
      [_, total_str, failures_str, errors_str] ->
        total = String.to_integer(total_str)
        failures = String.to_integer(failures_str)
        errors = String.to_integer(errors_str)
        passed = total - failures - errors

        %{
          total: total,
          passed: passed,
          failed: failures + errors,
          skipped: 0,
          format: :junit
        }

      _ ->
        fallback_parse(output)
    end
  end

  defp parse_tap(output) do
    # Parse TAP format
    # "1..5" header indicates total tests
    total =
      case Regex.run(~r/^1\.\.(\d+)/m, output) do
        [_, n] -> String.to_integer(n)
        nil -> nil
      end

    # Count "ok" and "not ok" lines
    lines = String.split(output, "\n")

    {passed, failed} =
      Enum.reduce(lines, {0, 0}, fn line, {pass, fail} ->
        cond do
          Regex.match?(~r/^ok\s+\d+/, line) -> {pass + 1, fail}
          Regex.match?(~r/^not ok\s+\d+/, line) -> {pass, fail + 1}
          true -> {pass, fail}
        end
      end)

    total = total || passed + failed
    skipped = count_skipped_tap(lines)

    %{
      total: total,
      passed: passed,
      failed: failed,
      skipped: skipped,
      format: :tap
    }
  end

  defp count_skipped_tap(lines) do
    Enum.count(lines, fn line ->
      Regex.match?(~r/^ok\s+\d+.*# TODO|# SKIP/i, line) or
        Regex.match?(~r/^not ok\s+\d+.*# SKIP/i, line)
    end)
  end

  defp parse_dot(output) do
    # Parse dot format (....F.*)
    lines = String.split(output, "\n")

    dots =
      Enum.find_value(lines, fn line ->
        if Regex.match?(~r/^[\.F\*]+$/, String.trim(line)) do
          String.trim(line)
        end
      end)

    if dots do
      chars = String.to_charlist(dots)

      {passed, failed, skipped} =
        Enum.reduce(chars, {0, 0, 0}, fn char, {pass, fail, skip} ->
          case char do
            ?. -> {pass + 1, fail, skip}
            ?F -> {pass, fail + 1, skip}
            ?* -> {pass, fail, skip + 1}
            _ -> {pass, fail, skip}
          end
        end)

      total = passed + failed + skipped

      %{
        total: total,
        passed: passed,
        failed: failed,
        skipped: skipped,
        format: :dot
      }
    else
      fallback_parse(output)
    end
  end

  defp fallback_parse(output) do
    # Try to find common patterns in test output
    # "X tests, Y failures, Z errors"
    case Regex.run(~r/(\d+)\s+tests?,\s*(\d+)\s+failures?/i, output) do
      [_, total_str, failures_str] ->
        total = String.to_integer(total_str)
        failures = String.to_integer(failures_str)

        %{
          total: total,
          passed: total - failures,
          failed: failures,
          skipped: 0,
          format: :fallback
        }

      _ ->
        # Last resort: look for "passed/failed" mentions
        passed = count_occurrences(output, ~r/passed|passing|success/i)
        failed = count_occurrences(output, ~r/failed|failing|failure/i)

        total = passed + failed

        if total > 0 do
          %{
            total: total,
            passed: passed,
            failed: failed,
            skipped: 0,
            format: :fallback
          }
        else
          # Couldn't parse - check exit code
          %{
            total: 1,
            passed: 0,
            failed: 1,
            skipped: 0,
            format: :exit_code_only
          }
        end
    end
  end

  defp count_occurrences(text, regex) do
    regex
    |> Regex.scan(text)
    |> length()
  end

  defp calculate_pass_rate(%{total: 0}), do: 0.0
  defp calculate_pass_rate(%{total: total, passed: passed}), do: passed / total

  defp calculate_confidence(%{total: 0}), do: 0.0
  defp calculate_confidence(%{total: total, failed: 0}), do: 1.0
  defp calculate_confidence(%{total: total, failed: failed}), do: (total - failed) / total

  defp build_reasoning(test_results, exec_result) do
    base =
      if test_results.total > 0 do
        "#{test_results.passed}/#{test_results.total} tests passed"
      else
        "No test results found"
      end

    base =
      if test_results.skipped > 0 do
        "#{base}, #{test_results.skipped} skipped"
      else
        base
      end

    if exec_result.timed_out do
      "#{base} (timed out)"
    else
      base
    end
  end

  defp error_result(candidate, reason) do
    %VerificationResult{
      candidate_id: candidate.id,
      score: 0.0,
      confidence: 0.0,
      reasoning: "Test execution failed: #{format_error(reason)}",
      metadata: %{error: reason}
    }
  end

  # Validation

  defp validate_test_command(cmd) when is_binary(cmd) and cmd != "", do: :ok
  defp validate_test_command(_), do: {:error, :invalid_test_command}

  defp validate_output_format(format) when format in [:junit, :tap, :dot, :auto], do: :ok
  defp validate_output_format(_), do: {:error, :invalid_output_format}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp validate_working_dir(nil), do: :ok

  defp validate_working_dir(path) when is_binary(path) do
    if File.dir?(path), do: :ok, else: {:error, :directory_not_found}
  end

  defp validate_working_dir(_), do: {:error, :invalid_directory}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
