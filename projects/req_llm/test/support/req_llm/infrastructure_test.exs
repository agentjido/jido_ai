defmodule ReqLLM.Test.InfrastructureTest do
  @moduledoc """
  Test to verify the test support infrastructure works correctly.
  """
  
  use ReqLLM.Test.CapabilityCase

  test "fixtures create valid result structures" do
    # Test passed result
    result = passed_result(:test_capability, %{extra: "data"})
    assert_capability_result(result, :passed, :test_capability)
    assert result.details.test == "success"
    assert result.details.extra == "data"

    # Test failed result  
    result = failed_result(:failing_capability, "custom error")
    assert_capability_result(result, :failed, :failing_capability)
    assert result.details.error == "custom error"
  end

  test "capability stubs work correctly" do
    model = test_model("test", "stub-model")
    
    # Test passing capability
    {:ok, data} = FastPassingCapability.verify(model, [])
    assert data.test == "success"

    # Test failing capability
    {:error, reason} = FastFailingCapability.verify(model, [])
    assert reason == "test failure"

    # Test conditional capability
    model_with_tools = test_model_with_capabilities([:tool_calling])
    assert ConditionalCapability.advertised?(model_with_tools) == true
    
    model_without_tools = test_model_with_capabilities([])
    assert ConditionalCapability.advertised?(model_without_tools) == false
  end

  test "test case provides helpful setup" do
    # Verify we have access to all the imports and aliases
    model = test_model("openai", "gpt-4")
    assert model.provider == :openai
    assert model.model == "gpt-4"

    results = mixed_results(2, 1)
    assert_results_summary(results, passed: 2, failed: 1)
  end

  test "capability case setup works" do
    # Test the setup helper
    setup_data = setup_capability_test()
    assert setup_data.test_model.provider == :test
    assert length(setup_data.passing_capabilities) > 0
    assert length(setup_data.failing_capabilities) > 0
  end

  test "run capability scenario helper works" do
    model = test_model("test", "scenario-model")
    results = run_capability_scenario(model, [:fast_passing, :fast_failing])
    
    assert length(results) == 2
    assert_results_summary(results, passed: 1, failed: 1)
    
    # Test with options
    results = run_capability_scenario(model, [:fast_failing, :fast_passing], fail_fast: true)
    assert length(results) == 1  # Should stop after first failure
  end
end
