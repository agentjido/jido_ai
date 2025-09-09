defmodule ReqLLM.Test.Assertions do
  @moduledoc """
  Specialized assertion helpers for capability test results.
  
  Provides focused assertion functions for different types of capability verification
  results to reduce repetition and improve test readability.
  """
  
  import ExUnit.Assertions
  
  @doc """
  Asserts that a reasoning capability result has the expected structure and values.
  """
  def assert_reasoning_result(%{} = data) do
    # Required fields for reasoning results
    required_fields = [:model_id, :content_length, :reasoning_length, :content_preview, :has_reasoning_tokens]
    
    for field <- required_fields do
      assert Map.has_key?(data, field), "Missing required field: #{field}"
    end
    
    # Type validations
    assert is_binary(data.model_id), "model_id should be a string"
    assert is_integer(data.content_length), "content_length should be an integer"
    assert is_integer(data.reasoning_length), "reasoning_length should be an integer"
    assert is_binary(data.content_preview), "content_preview should be a string"
    assert is_boolean(data.has_reasoning_tokens), "has_reasoning_tokens should be a boolean"
    
    # Content validation
    assert data.content_length >= 0, "content_length should be non-negative"
    assert data.reasoning_length >= 0, "reasoning_length should be non-negative"
    assert String.length(data.content_preview) <= 100, "content_preview should be truncated to 100 chars"
    
    # Reasoning-specific validations
    if data.has_reasoning_tokens do
      assert data.reasoning_length > 0, "reasoning_length should be > 0 when has_reasoning_tokens is true"
      assert is_binary(data.reasoning_preview), "reasoning_preview should be present when has_reasoning_tokens is true"
    else
      assert data.reasoning_length == 0, "reasoning_length should be 0 when has_reasoning_tokens is false"
    end
    
    data
  end
  
  @doc """
  Asserts that a tool calling capability result has the expected structure and values.
  """
  def assert_tool_calling_result(%{} = data) do
    # Required fields for tool calling results
    required_fields = [:model_id, :tool_calls_count, :first_tool_name, :first_tool_args]
    
    for field <- required_fields do
      assert Map.has_key?(data, field), "Missing required field: #{field}"
    end
    
    # Type validations
    assert is_binary(data.model_id), "model_id should be a string"
    assert is_integer(data.tool_calls_count), "tool_calls_count should be an integer"
    assert is_binary(data.first_tool_name), "first_tool_name should be a string"
    assert is_map(data.first_tool_args), "first_tool_args should be a map"
    
    # Content validation
    assert data.tool_calls_count > 0, "tool_calls_count should be positive"
    assert String.length(data.first_tool_name) > 0, "first_tool_name should not be empty"
    
    data
  end
  
  @doc """
  Asserts that a stream text capability result has the expected structure and values.
  """
  def assert_stream_result(%{} = data) do
    # Required fields for stream results
    required_fields = [:model_id, :chunks_received, :text_chunks_received, :response_length, :response_preview]
    
    for field <- required_fields do
      assert Map.has_key?(data, field), "Missing required field: #{field}"
    end
    
    # Type validations
    assert is_binary(data.model_id), "model_id should be a string"
    assert is_integer(data.chunks_received), "chunks_received should be an integer"
    assert is_integer(data.text_chunks_received), "text_chunks_received should be an integer"
    assert is_integer(data.response_length), "response_length should be an integer"
    assert is_binary(data.response_preview), "response_preview should be a string"
    
    # Content validation
    assert data.chunks_received >= 0, "chunks_received should be non-negative"
    assert data.text_chunks_received >= 0, "text_chunks_received should be non-negative"
    assert data.response_length >= 0, "response_length should be non-negative"
    assert String.length(data.response_preview) <= 50, "response_preview should be truncated to 50 chars"
    
    # Stream-specific validations
    assert data.text_chunks_received <= data.chunks_received, 
           "text_chunks_received should not exceed total chunks_received"
    
    data
  end
  
  @doc """
  Asserts that a generate text capability result has the expected structure and values.
  """
  def assert_generate_text_result(%{} = data) do
    # Required fields for generate text results
    required_fields = [:model_id, :response_length, :response_preview]
    
    for field <- required_fields do
      assert Map.has_key?(data, field), "Missing required field: #{field}"
    end
    
    # Type validations
    assert is_binary(data.model_id), "model_id should be a string"
    assert is_integer(data.response_length), "response_length should be an integer"
    assert is_binary(data.response_preview), "response_preview should be a string"
    
    # Content validation  
    assert data.response_length >= 0, "response_length should be non-negative"
    assert String.length(data.response_preview) <= 50, "response_preview should be truncated to 50 chars"
    
    data
  end
  
  @doc """
  Asserts that a capability result matches the expected format (either success or error).
  
  Handles both tuple format ({:ok, data} / {:error, reason}) and struct format (ReqLLM.Capability.Result).
  """
  def assert_capability_result({:ok, data}, :passed, _capability) do
    assert is_map(data), "Success result should contain a map of data"
    assert Map.has_key?(data, :model_id), "Success result should have model_id field"
    data
  end
  
  def assert_capability_result({:error, reason}, :failed, _capability) do
    assert is_binary(reason), "Error result should contain a string reason"
    assert String.length(reason) > 0, "Error reason should not be empty"
    reason
  end
  
  def assert_capability_result(%ReqLLM.Capability.Result{status: :passed} = result, :passed, capability) do
    assert result.capability == capability, "Expected capability #{capability}, got #{result.capability}"
    assert is_map(result.details), "Result details should be a map"
    result.details
  end
  
  def assert_capability_result(%ReqLLM.Capability.Result{status: :failed} = result, :failed, capability) do
    assert result.capability == capability, "Expected capability #{capability}, got #{result.capability}"
    assert Map.has_key?(result.details, :error), "Failed result should have error in details"
    result.details.error
  end
  
  def assert_capability_result(result, expected_status, capability) do
    flunk("Expected #{expected_status} result for #{capability}, got: #{inspect(result)}")
  end
  
  @doc """
  Asserts that a list of results contains the expected number of passed/failed results.
  
  ## Examples
  
      assert_result_counts(results, passed: 3, failed: 1)
      assert_result_counts(results, total: 4)
  """
  def assert_result_counts(results, expected_counts) do
    actual_total = length(results)
    actual_passed = Enum.count(results, &(&1.status == :passed))
    actual_failed = Enum.count(results, &(&1.status == :failed))
    
    if expected_total = expected_counts[:total] do
      assert actual_total == expected_total,
             "Expected #{expected_total} total results, got #{actual_total}"
    end
    
    if expected_passed = expected_counts[:passed] do
      assert actual_passed == expected_passed,
             "Expected #{expected_passed} passed results, got #{actual_passed}"
    end
    
    if expected_failed = expected_counts[:failed] do
      assert actual_failed == expected_failed,
             "Expected #{expected_failed} failed results, got #{actual_failed}"
    end
    
    results
  end
end
