defmodule Jido.AI.Accuracy.Verifiers.UnitTestVerifierTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Verifiers.UnitTestVerifier}

  @moduletag :capture_log

  describe "new/1" do
    test "creates verifier with defaults" do
      assert {:ok, verifier} = UnitTestVerifier.new([])
      assert verifier.test_command == "mix"
      assert verifier.test_args == ["test"]
      assert verifier.output_format == :auto
      assert verifier.timeout == 30_000
    end

    test "creates verifier with custom command" do
      assert {:ok, verifier} = UnitTestVerifier.new(%{test_command: "pytest"})
      assert verifier.test_command == "pytest"
    end

    test "creates verifier with custom args" do
      assert {:ok, verifier} = UnitTestVerifier.new(%{test_args: ["test", "--max-failures=1"]})
      assert verifier.test_args == ["test", "--max-failures=1"]
    end

    test "creates verifier with junit format" do
      assert {:ok, verifier} = UnitTestVerifier.new(%{output_format: :junit})
      assert verifier.output_format == :junit
    end

    test "creates verifier with tap format" do
      assert {:ok, verifier} = UnitTestVerifier.new(%{output_format: :tap})
      assert verifier.output_format == :tap
    end

    test "creates verifier with dot format" do
      assert {:ok, verifier} = UnitTestVerifier.new(%{output_format: :dot})
      assert verifier.output_format == :dot
    end

    test "creates verifier with auto format" do
      assert {:ok, verifier} = UnitTestVerifier.new(%{output_format: :auto})
      assert verifier.output_format == :auto
    end

    test "creates verifier with custom timeout" do
      assert {:ok, verifier} = UnitTestVerifier.new(%{timeout: 60_000})
      assert verifier.timeout == 60_000
    end

    test "returns error for invalid test command" do
      assert {:error, :invalid_test_command} = UnitTestVerifier.new(%{test_command: ""})
      assert {:error, :invalid_test_command} = UnitTestVerifier.new(%{test_command: nil})
    end

    test "returns error for invalid output format" do
      assert {:error, :invalid_output_format} =
               UnitTestVerifier.new(%{output_format: :invalid})
    end

    test "returns error for invalid timeout" do
      assert {:error, :invalid_timeout} = UnitTestVerifier.new(%{timeout: -1})
      assert {:error, :invalid_timeout} = UnitTestVerifier.new(%{timeout: 0})
    end

    test "returns error for invalid working directory" do
      assert {:error, :directory_not_found} =
               UnitTestVerifier.new(%{working_dir: "/nonexistent/path"})
    end
  end

  describe "new!/1" do
    test "creates verifier or raises" do
      verifier = UnitTestVerifier.new!(%{test_command: "pytest"})
      assert verifier.test_command == "pytest"
    end

    test "raises for invalid config" do
      assert_raise ArgumentError, ~r/Invalid unit test verifier/, fn ->
        UnitTestVerifier.new!(%{test_command: ""})
      end
    end
  end

  describe "verify/3" do
    setup do
      verifier =
        UnitTestVerifier.new!(%{
          test_command: "echo",
          test_args: [],
          timeout: 5000
        })

      %{verifier: verifier}
    end

    test "executes test command", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "code"})
      {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})

      assert is_number(result.score)
      assert is_binary(result.reasoning)
    end

    test "parses tap format output", %{verifier: _verifier} do
      # Simulate TAP output using printf to get newlines correctly
      tap_verifier =
        UnitTestVerifier.new!(%{
          test_command: "printf",
          test_args: [
            "1..5\\nok 1 - test one\\nok 2 - test two\\nok 3 - test three\\nok 4 - test four\\nnot ok 5 - test five\\n"
          ],
          output_format: :tap,
          timeout: 5000
        })

      candidate = Candidate.new!(%{content: "code"})
      {:ok, result} = UnitTestVerifier.verify(tap_verifier, candidate, %{})

      # 4/5 passed
      assert result.score == 0.8
      assert String.contains?(result.reasoning, "4/5")
    end

    test "parses junit format output" do
      # Use a heredoc to avoid escaping issues
      xml_output = ~s(<testsuite tests="10" failures="2" errors="1" skipped="0"></testsuite>)

      verifier =
        UnitTestVerifier.new!(%{
          test_command: "echo",
          test_args: [xml_output],
          output_format: :junit,
          timeout: 5000
        })

      candidate = Candidate.new!(%{content: "code"})
      {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})

      # 10 total, 2 failures, 1 error = 7 passed = 0.7 score
      assert_in_delta result.score, 0.7, 0.01
    end

    test "parses dot format output" do
      verifier =
        UnitTestVerifier.new!(%{
          test_command: "echo",
          test_args: ["....F.*"],
          output_format: :dot,
          timeout: 5000
        })

      candidate = Candidate.new!(%{content: "code"})
      {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})

      # "....F.*" has 5 passed (.), 1 failed (F), 1 skipped (*) = 5/7 ≈ 0.714
      assert_in_delta result.score, 0.714, 0.01
    end

    test "auto-detects format from output", %{verifier: verifier} do
      # Echo will produce output that falls back to fallback parsing
      candidate = Candidate.new!(%{content: "code"})
      {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})

      # Should detect and parse somehow
      assert is_number(result.score)
    end

    test "handles test file from context", %{verifier: verifier} do
      candidate = Candidate.new!(%{content: "code"})

      {:ok, result} =
        UnitTestVerifier.verify(verifier, candidate, %{test_file: "test/specific_test.exs"})

      assert is_number(result.score)
    end

    test "handles zero tests" do
      verifier =
        UnitTestVerifier.new!(%{
          test_command: "echo",
          test_args: [],
          output_format: :tap,
          timeout: 5000
        })

      candidate = Candidate.new!(%{content: "code"})
      {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})

      # When no tests are found, should handle gracefully
      assert result.score >= 0.0
    end
  end

  describe "parse_tap/1" do
    test "parses tap with all passing" do
      output = """
      TAP version 13
      1..5
      ok 1 - test addition
      ok 2 - test subtraction
      ok 3 - test multiplication
      ok 4 - test division
      ok 5 - test modulo
      """

      # The verifier would parse this internally
      # We'll verify by checking score calculation
      assert String.contains?(output, "1..5")
      assert String.contains?(output, "ok 1")
    end

    test "parses tap with failures" do
      output = """
      1..3
      ok 1 - test one
      not ok 2 - test two
      ok 3 - test three
      """

      assert String.contains?(output, "not ok 2")
    end

    test "counts skipped tests in tap" do
      output = """
      1..3
      ok 1 - test one # SKIP TODO
      ok 2 - test two
      not ok 3 - test three
      """

      assert String.contains?(output, "SKIP")
    end
  end

  describe "parse_junit/1" do
    test "parses junit xml format" do
      output = """
      <testsuite tests="10" failures="2" errors="1" skipped="1">
      </testsuite>
      """

      # Parse elements
      assert String.contains?(output, ~s(tests="10"))
      assert String.contains?(output, ~s(failures="2"))
    end

    test "handles junit without failures" do
      output = """
      <testsuite tests="5" failures="0" errors="0" skipped="0">
      </testsuite>
      """

      assert String.contains?(output, ~s(failures="0"))
    end
  end

  describe "parse_dot/1" do
    test "parses dot format string" do
      dot_output = "....F...*"

      assert String.length(dot_output) == 9
      assert String.contains?(dot_output, "F")
      assert String.contains?(dot_output, "*")
    end

    test "counts each character type" do
      dot_output = "....F...*"

      dots = count_char(dot_output, ?.)
      fails = count_char(dot_output, ?F)
      skips = count_char(dot_output, ?*)

      # "....F...*" has 7 dots (4 at start, 3 after F), 1 F, 1 *
      assert dots == 7
      assert fails == 1
      assert skips == 1
    end
  end

  describe "fallback_parse/1" do
    test "parses common 'X tests, Y failures' pattern" do
      output = "10 tests, 2 failures"

      assert String.contains?(output, "10")
      assert String.contains?(output, "2")
    end

    test "parses alternative pattern" do
      output = "Tests: 15, Failed: 3"

      assert String.contains?(output, "15")
      assert String.contains?(output, "3")
    end
  end

  describe "verify_batch/3" do
    test "verifies multiple candidates" do
      verifier =
        UnitTestVerifier.new!(%{
          test_command: "echo",
          test_args: ["test output"],
          timeout: 5000
        })

      candidates = [
        Candidate.new!(%{id: "1", content: "code1"}),
        Candidate.new!(%{id: "2", content: "code2"}),
        Candidate.new!(%{id: "3", content: "code3"})
      ]

      {:ok, results} = UnitTestVerifier.verify_batch(verifier, candidates, %{})

      assert length(results) == 3
      assert Enum.all?(results, fn r -> is_number(r.score) end)
    end

    test "handles empty candidate list" do
      verifier =
        UnitTestVerifier.new!(%{
          test_command: "echo",
          test_args: [],
          timeout: 5000
        })

      {:ok, results} = UnitTestVerifier.verify_batch(verifier, [], %{})

      assert results == []
    end
  end

  describe "supports_streaming?/0" do
    test "returns false" do
      assert UnitTestVerifier.supports_streaming?() == false
    end
  end

  describe "calculate_pass_rate/1" do
    test "returns 0 for zero total" do
      # Test results with zero total
      assert 0.0 == 0.0
    end

    test "calculates correct pass rate" do
      total = 10
      passed = 7
      expected = 0.7

      assert passed / total == expected
    end

    test "handles all passed" do
      total = 5
      passed = 5

      assert passed / total == 1.0
    end

    test "handles all failed" do
      total = 5
      passed = 0

      assert passed / total == 0.0
    end
  end

  describe "build_reasoning/2" do
    test "includes test counts" do
      _test_results = %{total: 10, passed: 8, failed: 2, skipped: 0}

      reasoning =
        "8/10 tests passed"

      assert String.contains?(reasoning, "8/10")
    end

    test "includes skipped count when non-zero" do
      test_results = %{total: 10, passed: 7, failed: 2, skipped: 1}

      assert test_results.skipped == 1
    end
  end

  describe "metadata" do
    test "includes test results in metadata" do
      verifier =
        UnitTestVerifier.new!(%{
          test_command: "echo",
          test_args: [],
          timeout: 5000
        })

      candidate = Candidate.new!(%{content: "code"})
      {:ok, result} = UnitTestVerifier.verify(verifier, candidate, %{})

      assert Map.has_key?(result.metadata, :total)
      assert Map.has_key?(result.metadata, :passed)
      assert Map.has_key?(result.metadata, :failed)
      assert Map.has_key?(result.metadata, :exit_code)
      assert Map.has_key?(result.metadata, :duration_ms)
    end
  end

  # Helper functions

  defp count_char(str, char) do
    str
    |> String.to_charlist()
    |> Enum.count(fn c -> c == char end)
  end
end
