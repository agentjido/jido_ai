defmodule ReqLLM.Test.CapabilityCase do
  @moduledoc """
  ExUnit case template for ReqLLM capability testing.

  Provides a standardized test environment with all necessary imports,
  test helpers, and setup for testing capability modules and verification workflows.

  ## Usage

      defmodule MyCapabilityTest do
        use ReqLLM.Test.CapabilityCase

        test "capability verification works" do
          model = fake_model("openai", "gpt-4")
          result = passed_result(:test_capability)
          
          assert_capability_result(result, :passed, :test_capability)
        end
      end

  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Core ExUnit functionality
      use ExUnit.Case, async: true
      use Mimic

      # ReqLLM test support modules  
      import ReqLLM.Test.Fixtures
      import ReqLLM.Test.Assertions
      import ReqLLM.Test.CapabilityHelpers
      alias ReqLLM.Test.CapabilityStubs

      # Core ReqLLM modules commonly used in tests
      alias ReqLLM.{Model, Message, Capability}
      alias ReqLLM.Capability.Result
      alias ReqLLM.TestHelpers.Capability, as: TestHelpers

      # ExUnit utilities for capture and logging
      import ExUnit.CaptureLog
      import ExUnit.CaptureIO

      # Import helper functions from CapabilityCase
      import ReqLLM.Test.CapabilityCase,
        only: [
          setup_capability_test: 0,
          setup_capability_test: 1,
          run_capability_scenario: 2,
          run_capability_scenario: 3,
          test_model_with_capabilities: 1,
          test_model_with_capabilities: 2,
          discover_and_filter: 1,
          discover_and_filter: 2,
          assert_results_summary: 2
        ]

      # Convenient aliases for stub capabilities
      alias ReqLLM.Test.CapabilityStubs.{
        FastPassingCapability,
        FastFailingCapability,
        SlowCapability,
        ConditionalCapability,
        ThrowingCapability,
        TimeoutCapability,
        ConfigurableCapability
      }
    end
  end

  setup do
    # Start Req.Test for HTTP mocking in all capability tests
    ReqLLM.TestHelpers.Capability.start_req_test(self())
    :ok
  end

  @doc """
  Provides common setup for capability verification tests.

  Sets up Req.Test, stubs common providers, and provides helper functions
  for capability testing scenarios.
  """
  def setup_capability_test(context \\ %{}) do
    # Additional setup can be added here for specific test patterns
    Map.merge(context, %{
      test_model: ReqLLM.Test.Fixtures.test_model("test", "capability-model"),
      passing_capabilities: ReqLLM.Test.CapabilityStubs.passing_capabilities(),
      failing_capabilities: ReqLLM.Test.CapabilityStubs.failing_capabilities()
    })
  end

  @doc """
  Helper to create a standard test scenario for capability verification.

  ## Examples

      setup [:setup_capability_test]

      test "runs capability checks", %{test_model: model} do
        results = run_capability_scenario(model, [:fast_passing, :fast_failing])
        assert length(results) == 2
      end

  """
  def run_capability_scenario(model, capability_types, opts \\ []) do
    capabilities =
      capability_types
      |> Enum.map(&get_capability_module/1)
      |> Enum.reject(&is_nil/1)

    ReqLLM.Capability.run_checks(capabilities, model, opts)
  end

  # Map capability type atoms to their corresponding stub modules
  defp get_capability_module(:fast_passing), do: ReqLLM.Test.CapabilityStubs.FastPassingCapability
  defp get_capability_module(:fast_failing), do: ReqLLM.Test.CapabilityStubs.FastFailingCapability
  defp get_capability_module(:slow), do: ReqLLM.Test.CapabilityStubs.SlowCapability
  defp get_capability_module(:conditional), do: ReqLLM.Test.CapabilityStubs.ConditionalCapability
  defp get_capability_module(:throwing), do: ReqLLM.Test.CapabilityStubs.ThrowingCapability
  defp get_capability_module(:timeout), do: ReqLLM.Test.CapabilityStubs.TimeoutCapability

  defp get_capability_module(:configurable),
    do: ReqLLM.Test.CapabilityStubs.ConfigurableCapability

  defp get_capability_module(_), do: nil

  @doc """
  Convenience function for creating test models with specific capability configurations.

  ## Examples

      test "conditional capability" do
        model = test_model_with_capabilities([:tool_calling])
        assert ConditionalCapability.advertised?(model)
      end

  """
  def test_model_with_capabilities(capability_list, opts \\ []) do
    capabilities = %{
      tool_call?: :tool_calling in capability_list,
      reasoning?: :reasoning in capability_list,
      supports_temperature?: :temperature in capability_list || true
    }

    ReqLLM.Test.Fixtures.test_model(
      Keyword.get(opts, :provider, "test"),
      Keyword.get(opts, :model, "test-model"),
      Keyword.put(opts, :capabilities, capabilities)
    )
  end

  @doc """
  Helper for testing capability discovery with filtering.

  ## Examples

      test "capability filtering" do
        model = test_model_with_capabilities([:tool_calling])
        capabilities = discover_and_filter(model, only: [:generate_text])
        assert length(capabilities) <= 1
      end

  """
  def discover_and_filter(model, opts \\ []) do
    case ReqLLM.Capability.discover_capabilities(model, opts) do
      {:ok, capabilities} -> capabilities
      {:error, _reason} -> []
    end
  end

  @doc """
  Convenience function for asserting capability results in bulk.

  ## Examples

      test "multiple results" do
        results = [
          passed_result(:capability_1),
          failed_result(:capability_2, "error")
        ]
        
        assert_results_summary(results, passed: 1, failed: 1)
      end

  """
  def assert_results_summary(results, expected_counts) do
    ReqLLM.Test.Assertions.assert_result_counts(results, expected_counts)

    # Additional validations
    for result <- results do
      assert %ReqLLM.Capability.Result{} = result
      assert result.status in [:passed, :failed]
      assert is_atom(result.capability)

      # Details can be a map (for passed results) or string (for simple failed results)
      case result.status do
        :passed -> assert is_map(result.details)
        :failed -> assert is_map(result.details) or is_binary(result.details)
      end
    end

    results
  end
end
