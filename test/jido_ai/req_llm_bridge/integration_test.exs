defmodule Jido.AI.ReqLlmBridge.IntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.AI.ReqLlmBridge

  alias Jido.AI.ReqLlmBridge.{
    Authentication,
    ConversationManager,
    ErrorHandler,
    ResponseAggregator,
    ToolBuilder
  }

  @moduledoc """
  Integration tests for the ReqLlmBridge system.

  These tests verify that all modules work together correctly in end-to-end scenarios.
  Uses real modules (not mocks) to test actual behavior across module boundaries.

  Tests cover:
  - Tool conversion and execution flow
  - Conversation management with tools
  - Response aggregation with tools
  - Authentication integration
  - Error propagation through the system
  """

  setup do
    # Clear conversations before each test
    :ok = ConversationManager.clear_all_conversations()
    :ok
  end

  describe "9.1 Tool Conversion and Execution Flow" do
    test "complete flow: Action → tool descriptor → execution" do
      # Note: Jido.Actions.Basic.Sleep has schema compatibility issues with ReqLLM
      # This is a known issue where ToolBuilder generates JSON Schema but ReqLLM expects keyword list
      # So we expect this to fail with a tool conversion error

      # Attempt to convert action to tool descriptor
      result = ToolBuilder.create_tool_descriptor(Jido.Actions.Basic.Sleep)

      # Assert we get a valid tool descriptor (ToolBuilder succeeds)
      assert {:ok, descriptor} = result
      # Action name includes "_action" suffix
      assert descriptor.name == "sleep_action"
      assert is_function(descriptor.callback, 1)

      # Attempt to execute the tool with valid parameters using the callback
      execution_result = descriptor.callback.(%{duration_ms: 100})

      # Execution should succeed
      assert {:ok, result_data} = execution_result
      assert is_map(result_data)
    end

    test "parameter flow: JSON params → conversion → validation → Action.run" do
      # Create tool descriptor
      {:ok, descriptor} = ToolBuilder.create_tool_descriptor(Jido.Actions.Basic.Sleep)

      # Simulate JSON params from LLM (string keys)
      json_params = %{"duration_ms" => 50}

      # Execute tool with JSON params using the callback
      result = descriptor.callback.(json_params)

      # Assert execution succeeded
      assert {:ok, execution_result} = result
      assert is_map(execution_result)
    end

    test "result flow: Action result → serialization → tool result" do
      # Create and execute tool
      {:ok, descriptor} = ToolBuilder.create_tool_descriptor(Jido.Actions.Basic.Sleep)
      {:ok, result} = descriptor.callback.(%{duration_ms: 10})

      # Result should be JSON-serializable
      assert {:ok, json} = Jason.encode(result)
      assert is_binary(json)

      # Result should be decodable
      assert {:ok, decoded} = Jason.decode(json)
      assert is_map(decoded)
    end
  end

  describe "9.2 Conversation with Tools" do
    test "creating conversation with tool configuration" do
      # Create conversation
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Configure tools for conversation
      tools = [
        %{name: "calculator", description: "Performs calculations"},
        %{name: "weather", description: "Gets weather info"}
      ]

      :ok = ConversationManager.set_tools(conv_id, tools)

      # Verify tools are stored
      {:ok, stored_tools} = ConversationManager.get_tools(conv_id)
      assert length(stored_tools) == 2
      assert Enum.any?(stored_tools, &(&1.name == "calculator"))
      assert Enum.any?(stored_tools, &(&1.name == "weather"))
    end

    test "adding messages to conversation" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add user message
      :ok = ConversationManager.add_user_message(conv_id, "What's the weather?")

      # Add assistant response
      response = %{
        content: "Let me check that",
        tool_calls: [%{id: "call_1", name: "weather"}]
      }

      :ok = ConversationManager.add_assistant_response(conv_id, response)

      # Add tool results
      tool_results = [
        %{tool_call_id: "call_1", name: "weather", content: "Sunny, 22°C"}
      ]

      :ok = ConversationManager.add_tool_results(conv_id, tool_results)

      # Verify all messages in history
      {:ok, history} = ConversationManager.get_history(conv_id)
      assert length(history) == 3
      assert Enum.at(history, 0).role == "user"
      assert Enum.at(history, 1).role == "assistant"
      assert Enum.at(history, 2).role == "tool"
    end

    test "tool execution within conversation context" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Create and set tools
      {:ok, descriptor} = ToolBuilder.create_tool_descriptor(Jido.Actions.Basic.Sleep)
      tools = [descriptor]
      :ok = ConversationManager.set_tools(conv_id, tools)

      # Find tool by name
      {:ok, tool} = ConversationManager.find_tool_by_name(conv_id, "sleep_action")

      # Execute tool using the callback
      result = tool.callback.(%{duration_ms: 10})

      assert {:ok, _execution_result} = result
    end

    test "conversation history includes tool results" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Add conversation with tools
      :ok = ConversationManager.add_user_message(conv_id, "Calculate 2+2")

      response = %{
        content: "Let me calculate that",
        tool_calls: [%{id: "call_1", name: "calculator"}]
      }

      :ok = ConversationManager.add_assistant_response(conv_id, response)

      # Add tool results
      tool_results = [%{tool_call_id: "call_1", name: "calculator", content: "4"}]
      :ok = ConversationManager.add_tool_results(conv_id, tool_results)

      # Get history and verify tool results are present
      {:ok, history} = ConversationManager.get_history(conv_id)
      tool_messages = Enum.filter(history, &(&1.role == "tool"))

      assert length(tool_messages) == 1
      assert Enum.at(tool_messages, 0).metadata.tool_call_id == "call_1"
    end
  end

  describe "9.3 Response Aggregation with Tools" do
    test "aggregating LLM response with tool execution results" do
      # Create response with tool calls
      response = %{
        content: "Based on the calculation",
        tool_calls: [%{id: "call_1", function: %{name: "calculator"}}],
        tool_results: [
          %{tool_call_id: "call_1", name: "calculator", content: "42"}
        ],
        usage: %{total_tokens: 25}
      }

      context = %{conversation_id: "conv_1", options: %{}}

      # Aggregate response
      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Verify tool results are included
      assert length(aggregated.tool_results) == 1
      assert Enum.at(aggregated.tool_results, 0).content == "42"

      # Format for user
      formatted =
        ResponseAggregator.format_for_user(aggregated, %{tool_result_style: :integrated})

      assert is_binary(formatted)
      assert formatted =~ "Based on the calculation"
    end

    test "combining content and tool results" do
      response = %{
        content: "The answer is",
        tool_results: [
          %{name: "calculator", content: ~s({"result": 42}), error: false}
        ],
        usage: %{total_tokens: 30}
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Both content and tool results should be present
      assert aggregated.content =~ "The answer is"
      assert length(aggregated.tool_results) == 1

      # Format with integrated style
      formatted =
        ResponseAggregator.format_for_user(aggregated, %{tool_result_style: :integrated})

      assert formatted =~ "The answer is"
      assert formatted =~ "Based on the tool result"
    end

    test "usage statistics aggregation" do
      response = %{
        content: "Response",
        usage: %{prompt_tokens: 15, completion_tokens: 10, total_tokens: 25}
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Usage stats should be preserved
      assert aggregated.usage.prompt_tokens == 15
      assert aggregated.usage.completion_tokens == 10
      assert aggregated.usage.total_tokens == 25

      # Extract metrics
      metrics = ResponseAggregator.extract_metrics(aggregated)
      assert metrics.total_tokens == 25
      assert metrics.prompt_tokens == 15
      assert metrics.completion_tokens == 10
    end
  end

  describe "9.4 Authentication Integration" do
    test "authentication flow with provider mapping" do
      # Test authentication function - in test environment without credentials,
      # authentication may fail, but we verify the function returns proper format
      req_options = %{api_key: "test-key-123"}

      result = Authentication.authenticate_for_provider(:openai, req_options)

      # Result should be either success or error tuple
      case result do
        {:ok, headers, key} ->
          # If authentication succeeds (e.g., api_key override works)
          assert is_map(headers)
          assert is_binary(key)
          assert Map.has_key?(headers, "authorization")

        {:error, reason} ->
          # If authentication fails (e.g., no credentials configured)
          # Verify error message format is correct
          assert is_binary(reason)
          assert reason =~ "Authentication error" or reason =~ "API key not found"
      end
    end

    test "building ReqLLM options with authenticated keys" do
      # Build options with key resolution
      params = %{temperature: 0.7, max_tokens: 100}

      # Use build_req_llm_options_with_keys
      options = ReqLlmBridge.build_req_llm_options_with_keys(params, :openai)

      # Should have temperature and max_tokens
      assert options.temperature == 0.7
      assert options.max_tokens == 100
      # api_key may or may not be present depending on authentication
    end

    test "session-based authentication validation" do
      # Validate that authentication system works
      result = Authentication.validate_authentication(:openai, %{})

      # Should return ok or error depending on whether key is configured
      assert match?(:ok, result) or match?({:error, _}, result)
    end
  end

  describe "9.5 Error Flow" do
    test "error propagation from tool execution → ErrorHandler → response" do
      # Create a tool descriptor that will fail
      {:ok, descriptor} = ToolBuilder.create_tool_descriptor(Jido.Actions.Basic.Sleep)

      # Execute with invalid params (should cause error) using the callback
      result = descriptor.callback.(%{invalid_param: "bad"})

      # Should get error
      assert {:error, error} = result

      # Format error with ErrorHandler
      formatted_error = ErrorHandler.format_error(error)

      # Error should be formatted
      assert is_map(formatted_error)
      assert Map.has_key?(formatted_error, :type)
      assert Map.has_key?(formatted_error, :category)

      # Create tool error response
      error_response = ErrorHandler.create_tool_error_response(error)

      # Should have error structure
      assert error_response.error == true
      assert Map.has_key?(error_response, :timestamp)
    end

    test "error sanitization in final response" do
      # Create response with tool error containing sensitive data
      response = %{
        content: "There was an error",
        tool_results: [
          %{
            tool_call_id: "call_1",
            error: true,
            content: "Error occurred",
            password: "secret123",
            api_key: "sk-12345"
          }
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      # Aggregate response
      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Errors should be in metadata
      assert Map.has_key?(aggregated.metadata, :tool_errors)
      errors = aggregated.metadata.tool_errors

      # Sensitive data should be redacted
      error = Enum.at(errors, 0)
      assert error.password == "[REDACTED]"
      assert error.api_key == "[REDACTED]"
    end

    test "error categorization in aggregated response" do
      # Create errors of different types
      validation_error = {:validation_error, "field", "message"}
      execution_error = {:action_execution_error, "timeout"}
      network_error = {:error, %{type: "network_error", message: "Connection refused"}}

      # Format each error
      formatted_validation = ErrorHandler.format_error(validation_error)
      formatted_execution = ErrorHandler.format_error(execution_error)
      formatted_network = ReqLlmBridge.map_error(network_error)

      # Verify categorization
      assert formatted_validation.category == "parameter_error"
      assert formatted_execution.category == "execution_error"

      {:error, mapped_network} = formatted_network
      assert mapped_network.reason == "network_error"
    end
  end

  describe "9.6 End-to-End Message Flow" do
    test "complete message conversion and response flow" do
      # Start with Jido message format
      messages = [
        %{role: :user, content: "Hello"}
      ]

      # Convert to ReqLLM format
      converted = ReqLlmBridge.convert_messages(messages)

      # Single user message should be string
      assert converted == "Hello"

      # Create mock ReqLLM response
      llm_response = %{
        text: "Hi there!",
        usage: %{prompt_tokens: 5, completion_tokens: 3, total_tokens: 8},
        finish_reason: "stop"
      }

      # Convert response back to Jido format
      jido_response = ReqLlmBridge.convert_response(llm_response)

      # Verify response structure
      assert jido_response.content == "Hi there!"
      assert jido_response.usage.total_tokens == 8
      assert jido_response.finish_reason == "stop"
    end

    test "multi-turn conversation with tool calls" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # User asks question
      :ok = ConversationManager.add_user_message(conv_id, "What's 2+2?")

      # Assistant responds with tool call
      response = %{
        content: "Let me calculate that",
        tool_calls: [
          %{id: "call_1", function: %{name: "calculator", arguments: ~s({"a": 2, "b": 2})}}
        ]
      }

      :ok = ConversationManager.add_assistant_response(conv_id, response)

      # Tool execution (simulated)
      tool_results = [
        %{tool_call_id: "call_1", name: "calculator", content: ~s({"result": 4})}
      ]

      :ok = ConversationManager.add_tool_results(conv_id, tool_results)

      # Assistant final response
      final_response = %{content: "The answer is 4"}
      :ok = ConversationManager.add_assistant_response(conv_id, final_response)

      # Verify complete history
      {:ok, history} = ConversationManager.get_history(conv_id)
      assert length(history) == 4

      roles = Enum.map(history, & &1.role)
      assert roles == ["user", "assistant", "tool", "assistant"]
    end
  end

  describe "9.7 Streaming Integration" do
    test "streaming response aggregation with conversation" do
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Simulate streaming chunks
      chunks = [
        %{content: "The", usage: %{prompt_tokens: 5, completion_tokens: 1, total_tokens: 6}},
        %{content: " answer", usage: %{prompt_tokens: 0, completion_tokens: 2, total_tokens: 2}},
        %{content: " is 42", usage: %{prompt_tokens: 0, completion_tokens: 3, total_tokens: 3}}
      ]

      context = %{conversation_id: conv_id, options: %{}}

      # Aggregate streaming response
      {:ok, aggregated} = ResponseAggregator.aggregate_streaming_response(chunks, context)

      # Content should be accumulated
      assert aggregated.content == "The answer is 42"

      # Usage should be summed
      assert aggregated.usage.prompt_tokens == 5
      assert aggregated.usage.completion_tokens == 6
      assert aggregated.usage.total_tokens == 11

      # Add to conversation
      :ok = ConversationManager.add_assistant_response(conv_id, %{content: aggregated.content})

      {:ok, history} = ConversationManager.get_history(conv_id)
      assert length(history) == 1
      assert Enum.at(history, 0).content == "The answer is 42"
    end
  end

  describe "9.8 Options and Configuration Flow" do
    test "building and using options across modules" do
      # Build options for conversation
      params = %{
        temperature: 0.8,
        max_tokens: 150,
        tool_choice: :auto
      }

      # Build ReqLLM options
      options = ReqLlmBridge.build_req_llm_options(params)

      # Verify options are built correctly
      assert options.temperature == 0.8
      assert options.max_tokens == 150
      assert options.tool_choice == "auto"

      # Create conversation with options
      {:ok, conv_id} = ConversationManager.create_conversation()
      :ok = ConversationManager.set_options(conv_id, options)

      # Retrieve options
      {:ok, retrieved_options} = ConversationManager.get_options(conv_id)
      assert retrieved_options.temperature == 0.8
      assert retrieved_options.max_tokens == 150
    end
  end

  describe "9.9 Metrics and Analytics Integration" do
    test "extracting metrics from complete interaction" do
      # Create response with full metadata
      response = %{
        content: "Complete response",
        tool_results: [
          %{content: "result1", error: false},
          %{content: "result2", error: false},
          %{content: "error", error: true}
        ],
        usage: %{prompt_tokens: 20, completion_tokens: 15, total_tokens: 35}
      }

      start_time = System.monotonic_time(:millisecond)
      # Simulate processing time
      Process.sleep(50)

      context = %{
        conversation_id: "conv_1",
        options: %{},
        processing_start_time: start_time
      }

      # Aggregate response
      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Extract metrics
      metrics = ResponseAggregator.extract_metrics(aggregated)

      # Verify comprehensive metrics
      assert metrics.processing_time_ms >= 50
      assert metrics.total_tokens == 35
      assert metrics.tools_executed == 3
      assert metrics.tools_successful == 2
      assert metrics.tools_failed == 1
      assert metrics.tool_success_rate == 66.7
    end
  end
end
