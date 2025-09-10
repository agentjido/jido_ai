defmodule ReqLLM.Capability.ReporterTest do
  @moduledoc """
  Unit tests for ReqLLM.Capability.Reporter output formatting.

  Tests the Reporter module's dispatch logic and output formatting functions
  without requiring network calls. Uses ExUnit.CaptureIO to verify output.
  """

  use ReqLLM.Test.CapabilityCase

  alias ReqLLM.Capability.Reporter

  describe "dispatch/2" do
    test "handles all format options correctly" do
      test_cases = [
        {nil, :pretty},
        {:pretty, :pretty},
        {:json, :json},
        {:debug, :debug},
        {:unknown, :pretty}
      ]

      for {input_format, expected_format} <- test_cases do
        results = [passed_result(:generate_text)]

        output = capture_output(results, format: input_format)

        case expected_format do
          :pretty ->
            assert output =~ "✓"
            assert output =~ "generate_text"

          :json ->
            json_data = Jason.decode!(output)
            assert json_data["status"] == "passed"

          :debug ->
            assert output =~ "✓"
            assert output =~ "generate_text"
        end
      end
    end
  end

  describe "pretty format output" do
    test "displays correct icon and color per status" do
      results = [
        passed_result(:generate_text),
        failed_result(:tool_calling, "Schema error")
      ]

      output = capture_pretty(results)

      # Green checkmark for passed
      assert output =~ "\e[32m✓\e[0m"
      # Red X for failed
      assert output =~ "\e[31m✗\e[0m"
    end

    test "formats timing edge cases correctly" do
      results = [
        passed_result(:test1) |> with_timing(0),
        passed_result(:test2) |> with_timing(999),
        passed_result(:test3) |> with_timing(1000)
      ]

      output = capture_pretty(results)

      assert output =~ "(0ms)"
      assert output =~ "(999ms)"
      assert output =~ "(1.0s)"
    end

    test "displays results in reverse order" do
      results = [
        passed_result(:first),
        passed_result(:second),
        passed_result(:third)
      ]

      output = capture_pretty(results)
      lines = String.split(String.trim(output), "\n")

      assert Enum.at(lines, 0) =~ "third"
      assert Enum.at(lines, 1) =~ "second"
      assert Enum.at(lines, 2) =~ "first"
    end
  end

  describe "debug format output" do
    test "shows error details for failed results only" do
      results = [
        passed_result(:generate_text),
        failed_result(:tool_calling, "Schema validation failed")
      ]

      output = capture_debug(results)

      assert output =~ "✓"
      assert output =~ "✗"
      assert output =~ "Error: %{error: \"Schema validation failed\"}"
      refute output =~ "Success details"
    end
  end

  describe "json format output" do
    test "outputs valid JSON for each result" do
      results = [
        passed_result(:generate_text),
        failed_result(:tool_calling, "Error details")
      ]

      output = capture_json(results)
      lines = String.split(String.trim(output), "\n")

      assert length(lines) == 2

      # Results should be reversed
      first_json = Jason.decode!(Enum.at(lines, 0))
      second_json = Jason.decode!(Enum.at(lines, 1))

      assert first_json["capability"] == "tool_calling"
      assert first_json["status"] == "failed"
      assert second_json["capability"] == "generate_text"
      assert second_json["status"] == "passed"
    end
  end

  # Shared test utilities

  defp capture_output(results, opts) do
    capture_io(fn -> Reporter.dispatch(results, opts) end)
  end

  defp capture_pretty(results) do
    capture_io(fn -> Reporter.output_pretty(results) end)
  end

  defp capture_debug(results) do
    capture_io(fn -> Reporter.output_debug(results) end)
  end

  defp capture_json(results) do
    capture_io(fn -> Reporter.output_json(results) end)
  end

  defp with_timing(result, latency_ms) do
    %{result | latency_ms: latency_ms}
  end
end
