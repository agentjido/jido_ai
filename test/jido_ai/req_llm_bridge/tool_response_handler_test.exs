defmodule Jido.AI.ReqLlmBridge.ToolResponseHandlerTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge.{
    ConversationManager,
    ResponseAggregator,
    ToolExecutor,
    ToolResponseHandler
  }

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ToolExecutor)
    Mimic.copy(ResponseAggregator)
    Mimic.copy(ConversationManager)

    # Mock Action for testing
    defmodule TestAction do
      use Jido.Action,
        name: "test_action",
        description: "A test action",
        schema: [
          message: [type: :string, required: true, doc: "Test message"]
        ]

      @impl true
      def run(params, _context) do
        {:ok, %{response: "Hello #{params.message}"}}
      end
    end

    {:ok, %{test_action: TestAction}}
  end

  describe "process_llm_response/3" do
    test "processes response without tool calls" do
      llm_response = %{
        content: "This is a simple response without tools",
        usage: %{prompt_tokens: 10, completion_tokens: 15, total_tokens: 25}
      }

      context = %{conversation_id: "conv_123", timeout: 30_000}

      expect(ResponseAggregator, :aggregate_response, fn response, ^context ->
        assert response == llm_response

        {:ok,
         %{
           content: "This is a simple response without tools",
           tool_calls: [],
           tool_results: [],
           usage: %{total_tokens: 25},
           conversation_id: "conv_123",
           finished: true
         }}
      end)

      assert {:ok, aggregated} =
               ToolResponseHandler.process_llm_response(
                 llm_response,
                 "conv_123",
                 %{timeout: 30_000}
               )

      assert aggregated.content == "This is a simple response without tools"
      assert aggregated.tool_calls == []
    end

    test "processes response with tool calls and executes them", %{test_action: action} do
      tool_calls = [
        %{
          id: "call_1",
          function: %{
            name: "test_action",
            arguments: %{"message" => "world"}
          }
        }
      ]

      llm_response = %{
        content: "I'll use a tool to help you.",
        tool_calls: tool_calls,
        usage: %{total_tokens: 50}
      }

      context = %{conversation_id: "conv_456", timeout: 30_000}

      # Mock finding the tool
      expect(ConversationManager, :find_tool_by_name, fn "conv_456", "test_action" ->
        {:ok, %{action_module: action}}
      end)

      # Mock tool execution
      expect(ToolExecutor, :execute_tool, fn ^action, %{"message" => "world"}, %{}, 30_000 ->
        {:ok, %{response: "Hello world"}}
      end)

      # Mock response aggregation
      _expected_response = %{
        content: "I'll use a tool to help you.",
        tool_calls: tool_calls,
        tool_results: [
          %{
            tool_call_id: "call_1",
            role: "tool",
            name: "test_action",
            content: ~s({"response":"Hello world"})
          }
        ],
        has_tool_calls: true
      }

      expect(ResponseAggregator, :aggregate_response, fn response, ^context ->
        assert response.content == "I'll use a tool to help you."
        assert length(response.tool_results) == 1

        {:ok,
         %{
           content: "I'll use a tool to help you.",
           tool_calls: tool_calls,
           tool_results: response.tool_results,
           conversation_id: "conv_456",
           finished: true
         }}
      end)

      assert {:ok, result} =
               ToolResponseHandler.process_llm_response(
                 llm_response,
                 "conv_456",
                 %{timeout: 30_000}
               )

      assert result.conversation_id == "conv_456"
      assert length(result.tool_calls) == 1
    end

    test "handles tool execution errors gracefully", %{test_action: action} do
      tool_calls = [
        %{
          id: "call_error",
          function: %{
            name: "test_action",
            arguments: %{"invalid" => "params"}
          }
        }
      ]

      llm_response = %{
        content: "Let me try to help.",
        tool_calls: tool_calls
      }

      context = %{conversation_id: "conv_error", timeout: 30_000}

      expect(ConversationManager, :find_tool_by_name, fn "conv_error", "test_action" ->
        {:ok, %{action_module: action}}
      end)

      expect(ToolExecutor, :execute_tool, fn ^action, %{"invalid" => "params"}, %{}, 30_000 ->
        {:error, %{type: "parameter_validation_error", message: "Missing required parameter"}}
      end)

      expect(ResponseAggregator, :aggregate_response, fn response, ^context ->
        # Should continue with partial results
        assert response.has_tool_calls == true

        {:ok,
         %{
           content: "Let me try to help.",
           tool_calls: tool_calls,
           tool_results: [],
           tool_execution_errors: [%{type: "parameter_validation_error"}],
           conversation_id: "conv_error",
           finished: true
         }}
      end)

      assert {:ok, result} =
               ToolResponseHandler.process_llm_response(
                 llm_response,
                 "conv_error",
                 %{timeout: 30_000}
               )

      assert result.conversation_id == "conv_error"
    end

    test "handles response processing errors" do
      llm_response = %{content: "Test response"}
      context = %{conversation_id: "conv_fail"}

      expect(ResponseAggregator, :aggregate_response, fn _response, ^context ->
        {:error, "Aggregation failed"}
      end)

      assert {:error, {:response_processing_failed, "Aggregation failed"}} =
               ToolResponseHandler.process_llm_response(llm_response, "conv_fail", %{})
    end
  end

  describe "process_streaming_response/3" do
    test "processes streaming response chunks" do
      stream_chunks = [
        %{content: "This is "},
        %{content: "a streaming "},
        %{content: "response."},
        %{usage: %{total_tokens: 30}}
      ]

      context = %{conversation_id: "conv_stream", timeout: 30_000}

      expect(ResponseAggregator, :aggregate_response, fn response, ^context ->
        assert response.content == "This is a streaming response."

        {:ok,
         %{
           content: "This is a streaming response.",
           tool_calls: [],
           tool_results: [],
           conversation_id: "conv_stream",
           finished: true
         }}
      end)

      assert {:ok, result} =
               ToolResponseHandler.process_streaming_response(
                 stream_chunks,
                 "conv_stream",
                 %{timeout: 30_000}
               )

      assert result.content == "This is a streaming response."
    end

    test "processes streaming response with tool calls", %{test_action: action} do
      stream_chunks = [
        %{content: "Let me check that for you."},
        %{
          tool_calls: [
            %{
              id: "stream_call",
              function: %{name: "test_action", arguments: %{"message" => "streaming"}}
            }
          ]
        }
      ]

      context = %{conversation_id: "conv_stream_tools", timeout: 30_000}

      expect(ConversationManager, :find_tool_by_name, fn "conv_stream_tools", "test_action" ->
        {:ok, %{action_module: action}}
      end)

      expect(ToolExecutor, :execute_tool, fn ^action, %{"message" => "streaming"}, %{}, 30_000 ->
        {:ok, %{response: "Hello streaming"}}
      end)

      expect(ResponseAggregator, :aggregate_response, fn response, ^context ->
        assert response.content == "Let me check that for you."
        assert length(response.tool_results) == 1

        {:ok,
         %{
           content: "Let me check that for you.",
           tool_calls: [%{id: "stream_call"}],
           tool_results: response.tool_results,
           conversation_id: "conv_stream_tools",
           finished: true
         }}
      end)

      assert {:ok, result} =
               ToolResponseHandler.process_streaming_response(
                 stream_chunks,
                 "conv_stream_tools",
                 %{timeout: 30_000}
               )

      assert result.conversation_id == "conv_stream_tools"
    end

    test "handles streaming processing errors" do
      # Simulate a stream that causes an error
      error_stream = [
        %{content: "This will fail"},
        # This will cause an error in processing
        nil
      ]

      _context = %{conversation_id: "conv_stream_error"}

      assert {:error, {:streaming_processing_failed, _error}} =
               ToolResponseHandler.process_streaming_response(
                 error_stream,
                 "conv_stream_error",
                 %{}
               )
    end
  end

  describe "execute_tool_calls/2" do
    test "executes multiple tool calls concurrently", %{test_action: action} do
      tool_calls = [
        %{
          id: "call_1",
          function: %{name: "test_action", arguments: %{"message" => "first"}}
        },
        %{
          id: "call_2",
          function: %{name: "test_action", arguments: %{"message" => "second"}}
        }
      ]

      context = %{
        conversation_id: "conv_multi",
        timeout: 30_000,
        max_tool_calls: 5,
        context: %{}
      }

      expect(ConversationManager, :find_tool_by_name, 2, fn "conv_multi", "test_action" ->
        {:ok, %{action_module: action}}
      end)

      expect(ToolExecutor, :execute_tool, 2, fn ^action, params, %{}, 30_000 ->
        case params do
          %{"message" => "first"} ->
            {:ok, %{response: "Hello first"}}

          %{"message" => "second"} ->
            {:ok, %{response: "Hello second"}}
        end
      end)

      assert {:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)

      assert length(results) == 2

      assert Enum.all?(results, fn result ->
               result.role == "tool" and result.name == "test_action"
             end)
    end

    test "handles tool not found error" do
      tool_calls = [
        %{
          id: "missing_call",
          function: %{name: "missing_tool", arguments: %{}}
        }
      ]

      context = %{
        conversation_id: "conv_missing",
        timeout: 30_000,
        context: %{}
      }

      expect(ConversationManager, :find_tool_by_name, fn "conv_missing", "missing_tool" ->
        {:error, :not_found}
      end)

      assert {:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)

      # Should return error result for the tool call
      assert length(results) == 1
      result = hd(results)
      assert result.error == true
      assert result.tool_call_id == "missing_call"
    end

    test "handles malformed tool arguments" do
      tool_calls = [
        %{
          id: "malformed_call",
          function: %{name: "test_action", arguments: "invalid json"}
        }
      ]

      context = %{
        conversation_id: "conv_malformed",
        timeout: 30_000,
        context: %{}
      }

      expect(ConversationManager, :find_tool_by_name, fn "conv_malformed", "test_action" ->
        {:ok, %{action_module: TestAction}}
      end)

      assert {:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)

      # Should handle the JSON parsing error gracefully
      assert length(results) == 1
      result = hd(results)
      assert result.tool_call_id == "malformed_call"
      assert result.error == true
    end

    test "respects max_tool_calls limit" do
      # Create 10 tool calls but limit to 3
      tool_calls =
        Enum.map(1..10, fn i ->
          %{
            id: "call_#{i}",
            function: %{name: "test_action", arguments: %{"message" => "call #{i}"}}
          }
        end)

      context = %{
        conversation_id: "conv_limit",
        timeout: 30_000,
        max_tool_calls: 3,
        context: %{}
      }

      expect(ConversationManager, :find_tool_by_name, 3, fn "conv_limit", "test_action" ->
        {:ok, %{action_module: TestAction}}
      end)

      expect(ToolExecutor, :execute_tool, 3, fn TestAction, _params, %{}, 30_000 ->
        {:ok, %{response: "limited response"}}
      end)

      assert {:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)

      # Should only execute 3 tools despite 10 being requested
      assert length(results) == 3
    end

    test "handles tool execution timeouts" do
      tool_calls = [
        %{
          id: "timeout_call",
          function: %{name: "test_action", arguments: %{"message" => "timeout"}}
        }
      ]

      context = %{
        conversation_id: "conv_timeout",
        # Very short timeout
        timeout: 100,
        context: %{}
      }

      expect(ConversationManager, :find_tool_by_name, fn "conv_timeout", "test_action" ->
        {:ok, %{action_module: TestAction}}
      end)

      expect(ToolExecutor, :execute_tool, fn TestAction, _params, %{}, 100 ->
        # Simulate a timeout scenario
        Process.sleep(200)
        {:ok, %{response: "should not reach here"}}
      end)

      assert {:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)

      # Should handle timeout gracefully
      assert length(results) == 1
      result = hd(results)

      # The result should indicate either timeout or error
      assert result.tool_call_id == "timeout_call"
    end
  end

  describe "error handling and edge cases" do
    test "handles empty tool calls list" do
      context = %{conversation_id: "conv_empty", timeout: 30_000}

      assert {:ok, []} = ToolResponseHandler.execute_tool_calls([], context)
    end

    test "handles response with mixed content types" do
      # Response with both string and structured content
      mixed_response = %{
        content: [
          %{type: "text", text: "Here's some text: "},
          %{type: "text", text: "More text here."}
        ],
        usage: %{total_tokens: 20}
      }

      context = %{conversation_id: "conv_mixed"}

      expect(ResponseAggregator, :aggregate_response, fn response, ^context ->
        assert is_binary(response.content)

        {:ok,
         %{
           content: response.content,
           conversation_id: "conv_mixed",
           finished: true
         }}
      end)

      assert {:ok, result} =
               ToolResponseHandler.process_llm_response(
                 mixed_response,
                 "conv_mixed",
                 %{}
               )

      assert is_binary(result.content)
    end

    test "handles malformed streaming chunks gracefully" do
      malformed_stream = [
        %{content: "Good chunk"},
        # Missing expected fields
        %{malformed: true},
        %{content: "Another good chunk"}
      ]

      context = %{conversation_id: "conv_malformed_stream"}

      expect(ResponseAggregator, :aggregate_response, fn response, ^context ->
        # Should still process the good chunks
        assert String.contains?(response.content, "Good chunk")

        {:ok,
         %{
           content: response.content,
           conversation_id: "conv_malformed_stream",
           finished: true
         }}
      end)

      assert {:ok, result} =
               ToolResponseHandler.process_streaming_response(
                 malformed_stream,
                 "conv_malformed_stream",
                 %{}
               )

      assert result.conversation_id == "conv_malformed_stream"
    end
  end

  describe "concurrent tool execution" do
    test "handles concurrent tool calls safely", %{test_action: action} do
      # Create multiple tool calls that should execute concurrently
      tool_calls =
        Enum.map(1..5, fn i ->
          %{
            id: "concurrent_call_#{i}",
            function: %{name: "test_action", arguments: %{"message" => "concurrent #{i}"}}
          }
        end)

      context = %{
        conversation_id: "conv_concurrent",
        timeout: 30_000,
        context: %{}
      }

      expect(ConversationManager, :find_tool_by_name, 5, fn "conv_concurrent", "test_action" ->
        {:ok, %{action_module: action}}
      end)

      expect(ToolExecutor, :execute_tool, 5, fn ^action, params, %{}, 30_000 ->
        # Add small delay to test concurrency
        Process.sleep(50)
        message = params["message"]
        {:ok, %{response: "Hello #{message}"}}
      end)

      start_time = System.monotonic_time(:millisecond)

      assert {:ok, results} = ToolResponseHandler.execute_tool_calls(tool_calls, context)

      end_time = System.monotonic_time(:millisecond)
      execution_time = end_time - start_time

      # With concurrency, 5 tools with 50ms each should complete in less than 250ms
      # (much less than 250ms if truly concurrent)
      assert execution_time < 200

      assert length(results) == 5

      assert Enum.all?(results, fn result ->
               String.contains?(result.content, "concurrent")
             end)
    end
  end
end
