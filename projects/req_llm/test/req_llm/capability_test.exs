defmodule ReqLLM.CapabilityTest do
  @moduledoc """
  Consolidated tests for ReqLLM.Capability module and capability discovery system.

  Focuses on capability discovery mechanism and basic verification workflow
  without requiring network calls or actual AI model interactions.
  """

  use ReqLLM.Test.CapabilityCase
  import ReqLLM.Test.Macros

  setup [:setup_capability_test]

  describe "discover_capabilities/2" do
    test "when discovering capabilities with various filters then returns expected results", %{test_model: model} do
      # Test cases: [filter_opts, expected_capability_count_range, description]
      test_cases = [
        [[], 1..10, "discovers all advertised capabilities"],
        [[only: [:generate_text]], 1..1, "filters to single capability with atom list"],
        [[only: "generate_text,stream_text"], 2..2, "filters with comma-separated string"],
        [[only: [:nonexistent_capability]], 0..0, "returns no capabilities for invalid filter"],
        [[only: [:generate_text, :invalid_capability]], 1..1, "ignores invalid capability names"]
      ]

      for [opts, expected_range, description] <- test_cases do
        case Capability.discover_capabilities(model, opts) do
          {:ok, capabilities} ->
            assert length(capabilities) in expected_range,
              "#{description}: expected #{inspect(expected_range)}, got #{length(capabilities)}"
            
            # Validate all returned items are proper capability modules
            for cap <- capabilities do
              assert is_atom(cap)
              assert function_exported?(cap, :id, 0)
              assert function_exported?(cap, :advertised?, 1)
              assert function_exported?(cap, :verify, 2)
            end

          {:error, reason} when expected_range == 0..0 ->
            assert reason =~ "No capabilities to verify"

          result ->
            flunk("Unexpected result for #{description}: #{inspect(result)}")
        end
      end
    end
  end

  describe "run_checks/3" do
    test "when executing capability checks then returns structured results", %{test_model: model} do
      # Test scenarios: [capability_types, opts, expected_behavior]
      scenarios = [
        [[:fast_passing, :fast_failing], [], "executes all checks and measures latency"],
        [[:fast_failing, :fast_passing], [fail_fast: true], "stops early on first failure"],
        [[:slow], [], "measures latency for timed operations"]
      ]

      for [capability_types, opts, description] <- scenarios do
        results = run_capability_scenario(model, capability_types, opts)

        if opts[:fail_fast] && :fast_failing in capability_types do
          assert length(results) == 1, "#{description}: should stop after first failure"
          assert hd(results).status == :failed
        else
          assert length(results) == length(capability_types), "#{description}: should run all checks"
        end

        # Validate all results structure
        for result <- results do
          assert_struct(result, ReqLLM.Capability.Result)
          assert result.model == "test:capability-model"
          assert result.capability in [:fast_passing, :fast_failing, :slow_capability]
          assert is_integer(result.latency_ms) and result.latency_ms >= 0
          assert result.status in [:passed, :failed]
        end
      end
    end
  end

  describe "verify/2 integration" do
    test "when all capabilities pass then returns :ok" do
      model = test_model("openai", "gpt-4")
      stub_model_metadata_success(model)
      stub_reporter_dispatch()
      stub_capability_success(ReqLLM.Capability.GenerateText)

      result = Capability.verify("openai:gpt-4", only: [:generate_text])
      assert result == :ok
    end

    test "when first fails with fail_fast then returns error with one result" do
      model = test_model("openai", "gpt-4")
      stub_model_metadata_success(model)
      stub_capability_failure(ReqLLM.Capability.GenerateText)
      
      ReqLLM.Capability.Reporter
      |> stub(:dispatch, fn results, _opts ->
        assert length(results) == 1
        assert hd(results).status == :failed
        :ok
      end)

      result = Capability.verify("openai:gpt-4", fail_fast: true, only: [:generate_text])
      assert result == :error
    end

    test "when mixed pass/fail without fail_fast then returns error with all results" do
      model = test_model("openai", "gpt-4")  
      stub_model_metadata_success(model)
      stub_capability_success(ReqLLM.Capability.GenerateText)
      stub_capability_failure(ReqLLM.Capability.StreamText)

      ReqLLM.Capability.Reporter
      |> stub(:dispatch, fn results, _opts ->
        assert length(results) == 2
        passed = Enum.count(results, &(&1.status == :passed))
        failed = Enum.count(results, &(&1.status == :failed)) 
        assert passed == 1 and failed == 1
        :ok
      end)

      result = Capability.verify("openai:gpt-4", only: [:generate_text, :stream_text])
      assert result == :error
    end

    test "when model metadata error surfaces then returns error" do
      ReqLLM.Model 
      |> stub(:with_metadata, fn _model_id -> {:error, "Invalid provider: nonexistent"} end)

      log_output = capture_log(fn ->
        result = Capability.verify("nonexistent:model", [])
        assert result == :error
      end)

      assert log_output =~ "Invalid provider: nonexistent"
    end

    test "when timeout option provided then propagates to capability verify" do
      model = test_model("openai", "gpt-4")
      stub_model_metadata_success(model)
      stub_reporter_dispatch()

      ReqLLM.Capability.GenerateText
      |> stub(:advertised?, fn _model -> true end)
      |> stub(:verify, fn _model, opts ->
        assert Keyword.get(opts, :timeout) == 30_000
        {:ok, %{response: "Test"}}
      end)

      result = Capability.verify("openai:gpt-4", timeout: 30_000, only: [:generate_text])
      assert result == :ok
    end
  end

  # Helper functions for test setup

  defp stub_model_metadata_success(model) do
    ReqLLM.Model |> stub(:with_metadata, fn _model_id -> {:ok, model} end)
  end

  defp stub_reporter_dispatch do
    ReqLLM.Capability.Reporter |> stub(:dispatch, fn _results, _opts -> :ok end)
  end

  defp stub_capability_success(capability_module) do
    capability_module
    |> stub(:advertised?, fn _model -> true end)
    |> stub(:verify, fn _model, _opts -> {:ok, %{response: "Test success"}} end)
  end

  defp stub_capability_failure(capability_module) do
    capability_module
    |> stub(:advertised?, fn _model -> true end)
    |> stub(:verify, fn _model, _opts -> {:error, "Test failure"} end)
  end
end
