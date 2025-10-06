defmodule Jido.AI.ReqLlmBridge.ResponseAggregatorTest do
  use ExUnit.Case, async: true

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge.ResponseAggregator

  describe "aggregate_response/2" do
    test "aggregates simple response without tools" do
      response = %{
        content: "This is a simple response",
        usage: %{prompt_tokens: 10, completion_tokens: 15, total_tokens: 25}
      }

      context = %{
        conversation_id: "conv_123",
        processing_start_time: System.monotonic_time(:millisecond) - 100
      }

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "This is a simple response"
      assert aggregated.tool_calls == []
      assert aggregated.tool_results == []
      assert aggregated.usage.total_tokens == 25
      assert aggregated.conversation_id == "conv_123"
      assert aggregated.finished == true
      assert is_map(aggregated.metadata)
      assert aggregated.metadata.processing_time_ms >= 0
    end

    test "aggregates response with tool calls and results" do
      tool_calls = [
        %{
          id: "call_1",
          function: %{name: "get_weather", arguments: %{location: "Paris"}}
        }
      ]

      tool_results = [
        %{
          tool_call_id: "call_1",
          role: "tool",
          name: "get_weather",
          content: ~s({"temperature": 22, "condition": "sunny"})
        }
      ]

      response = %{
        content: "Let me check the weather for you.",
        tool_calls: tool_calls,
        tool_results: tool_results,
        usage: %{total_tokens: 75}
      }

      context = %{conversation_id: "conv_456"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "Let me check the weather for you."
      assert length(aggregated.tool_calls) == 1
      assert length(aggregated.tool_results) == 1
      assert aggregated.tool_calls == tool_calls
      assert aggregated.tool_results == tool_results
      assert aggregated.conversation_id == "conv_456"
      assert aggregated.finished == true
    end

    test "handles empty content gracefully" do
      response = %{
        content: "",
        usage: %{total_tokens: 10}
      }

      context = %{conversation_id: "conv_empty"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "I don't have any response to provide."
      assert aggregated.finished == true
    end

    test "handles response with only tool results" do
      tool_results = [
        %{
          tool_call_id: "call_1",
          name: "calculator",
          content: ~s({"result": 42})
        }
      ]

      response = %{
        content: "",
        tool_results: tool_results,
        usage: %{total_tokens: 30}
      }

      context = %{conversation_id: "conv_tools_only"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert String.contains?(aggregated.content, "Here are the results")
      assert String.contains?(aggregated.content, "calculator")
      assert aggregated.tool_results == tool_results
    end

    test "determines finished status based on tool call completion" do
      # Test case where we have tool calls but no matching results (not finished)
      incomplete_response = %{
        content: "Working on it...",
        tool_calls: [%{id: "call_1", function: %{name: "tool"}}],
        # No results for the call
        tool_results: [],
        usage: %{total_tokens: 20}
      }

      context = %{conversation_id: "conv_incomplete"}

      assert {:ok, aggregated} =
               ResponseAggregator.aggregate_response(incomplete_response, context)

      assert aggregated.finished == false

      # Test case where tool calls have matching results (finished)
      complete_response = %{
        content: "Done!",
        tool_calls: [%{id: "call_1", function: %{name: "tool"}}],
        tool_results: [%{tool_call_id: "call_1", content: "result"}],
        usage: %{total_tokens: 25}
      }

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(complete_response, context)
      assert aggregated.finished == true
    end

    test "builds comprehensive metadata" do
      response = %{
        content: "Response with metadata",
        tool_calls: [%{id: "call_1"}],
        tool_results: [
          %{tool_call_id: "call_1", content: "success"},
          %{tool_call_id: "call_2", content: "error", error: true}
        ],
        usage: %{total_tokens: 50}
      }

      start_time = System.monotonic_time(:millisecond)

      context = %{
        conversation_id: "conv_metadata",
        processing_start_time: start_time
      }

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      metadata = aggregated.metadata
      assert metadata.processing_time_ms >= 0
      assert metadata.tools_executed == 2
      assert metadata.has_tool_calls == true
      assert metadata.response_type == :content_with_tools
      assert Map.has_key?(metadata, :tool_errors)
      assert length(metadata.tool_errors) == 1
    end
  end

  describe "aggregate_streaming_response/2" do
    test "aggregates streaming chunks with content only" do
      stream_chunks = [
        %{content: "This "},
        %{content: "is a "},
        %{content: "streaming "},
        %{content: "response."},
        %{usage: %{prompt_tokens: 15, completion_tokens: 10, total_tokens: 25}}
      ]

      context = %{conversation_id: "conv_stream"}

      assert {:ok, aggregated} =
               ResponseAggregator.aggregate_streaming_response(stream_chunks, context)

      assert aggregated.content == "This is a streaming response."
      assert aggregated.usage.total_tokens == 25
      assert aggregated.conversation_id == "conv_stream"
      assert aggregated.finished == true
    end

    test "aggregates streaming chunks with tool calls" do
      stream_chunks = [
        %{content: "Let me help you with that."},
        %{tool_calls: [%{id: "stream_call", function: %{name: "helper"}}]},
        %{usage: %{total_tokens: 40}}
      ]

      context = %{conversation_id: "conv_stream_tools"}

      assert {:ok, aggregated} =
               ResponseAggregator.aggregate_streaming_response(stream_chunks, context)

      assert aggregated.content == "Let me help you with that."
      assert length(aggregated.tool_calls) == 1
      assert aggregated.tool_calls == [%{id: "stream_call", function: %{name: "helper"}}]
    end

    test "handles empty streaming chunks" do
      stream_chunks = []
      context = %{conversation_id: "conv_empty_stream"}

      assert {:ok, aggregated} =
               ResponseAggregator.aggregate_streaming_response(stream_chunks, context)

      assert aggregated.content == "I don't have any response to provide."
      assert aggregated.tool_calls == []
      assert aggregated.finished == true
    end

    test "merges usage statistics correctly" do
      stream_chunks = [
        %{content: "Part 1", usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}},
        %{content: " Part 2", usage: %{prompt_tokens: 0, completion_tokens: 8, total_tokens: 8}},
        %{usage: %{prompt_tokens: 5, completion_tokens: 2, total_tokens: 7}}
      ]

      context = %{conversation_id: "conv_usage_merge"}

      assert {:ok, aggregated} =
               ResponseAggregator.aggregate_streaming_response(stream_chunks, context)

      assert aggregated.content == "Part 1 Part 2"
      assert aggregated.usage.prompt_tokens == 15
      assert aggregated.usage.completion_tokens == 15
      assert aggregated.usage.total_tokens == 30
    end

    test "handles malformed streaming chunks gracefully" do
      stream_chunks = [
        %{content: "Good chunk"},
        # Bad chunk
        nil,
        # Missing expected fields
        %{malformed: true},
        %{content: " Another good chunk"}
      ]

      context = %{conversation_id: "conv_malformed"}

      assert {:ok, aggregated} =
               ResponseAggregator.aggregate_streaming_response(stream_chunks, context)

      # Should still process the good chunks
      assert String.contains?(aggregated.content, "Good chunk")
      assert String.contains?(aggregated.content, "Another good chunk")
    end
  end

  describe "format_for_user/2" do
    test "formats simple response" do
      response = %{
        content: "This is a simple response",
        tool_calls: [],
        tool_results: [],
        usage: %{total_tokens: 20},
        conversation_id: "conv_123",
        finished: true,
        metadata: %{processing_time_ms: 150, tools_executed: 0}
      }

      formatted = ResponseAggregator.format_for_user(response)
      assert formatted == "This is a simple response"
    end

    test "formats response with integrated tool results" do
      response = %{
        content: "The weather information is",
        tool_calls: [%{id: "call_1"}],
        tool_results: [
          %{
            tool_call_id: "call_1",
            name: "get_weather",
            content: ~s({"temperature": 22, "condition": "sunny"})
          }
        ],
        usage: %{total_tokens: 50},
        conversation_id: "conv_456",
        finished: true,
        metadata: %{processing_time_ms: 200, tools_executed: 1}
      }

      formatted = ResponseAggregator.format_for_user(response, %{tool_result_style: :integrated})

      assert String.contains?(formatted, "The weather information is")
      assert String.contains?(formatted, "tool result")
    end

    test "formats response with appended tool results" do
      response = %{
        content: "Here's what I found:",
        tool_calls: [],
        tool_results: [
          %{
            tool_call_id: "call_1",
            name: "search_tool",
            content: ~s({"results": ["item1", "item2"]})
          }
        ],
        usage: %{total_tokens: 75},
        conversation_id: "conv_789",
        finished: true,
        metadata: %{processing_time_ms: 300, tools_executed: 1}
      }

      formatted = ResponseAggregator.format_for_user(response, %{tool_result_style: :appended})

      assert String.contains?(formatted, "Here's what I found:")
      assert String.contains?(formatted, "Tool Results:")
      assert String.contains?(formatted, "search_tool")
    end

    test "includes metadata when requested" do
      response = %{
        content: "Response with metadata",
        tool_calls: [],
        tool_results: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_meta",
        finished: true,
        metadata: %{processing_time_ms: 500, tools_executed: 0}
      }

      formatted = ResponseAggregator.format_for_user(response, %{include_metadata: true})

      assert String.contains?(formatted, "Response with metadata")
      assert String.contains?(formatted, "Response Metadata:")
      assert String.contains?(formatted, "Processing time: 500ms")
      assert String.contains?(formatted, "Tokens used: 30")
    end

    test "handles tool-only responses" do
      response = %{
        content: "",
        tool_calls: [],
        tool_results: [
          %{
            tool_call_id: "call_1",
            name: "calculator",
            content: ~s({"result": 42, "operation": "add"})
          }
        ],
        usage: %{total_tokens: 25},
        conversation_id: "conv_tools_only",
        finished: true,
        metadata: %{processing_time_ms: 100, tools_executed: 1}
      }

      formatted = ResponseAggregator.format_for_user(response)

      assert String.contains?(formatted, "Here are the results")
      assert String.contains?(formatted, "calculator")
    end

    test "handles tool results with errors" do
      response = %{
        content: "I tried to help but encountered an issue",
        tool_calls: [],
        tool_results: [
          %{
            tool_call_id: "call_1",
            name: "broken_tool",
            content: ~s({"error": true, "message": "Tool failed"}),
            error: true
          }
        ],
        usage: %{total_tokens: 40},
        conversation_id: "conv_error",
        finished: true,
        metadata: %{processing_time_ms: 200, tools_executed: 1}
      }

      # Tool errors should not be included in user-facing format
      formatted = ResponseAggregator.format_for_user(response)
      assert formatted == "I tried to help but encountered an issue"
    end
  end

  describe "extract_metrics/1" do
    test "extracts comprehensive metrics from response" do
      response = %{
        content: "Response with metrics",
        tool_calls: [%{id: "call_1"}, %{id: "call_2"}],
        tool_results: [
          %{tool_call_id: "call_1", content: "success"},
          %{tool_call_id: "call_2", content: "error", error: true}
        ],
        usage: %{prompt_tokens: 25, completion_tokens: 35, total_tokens: 60},
        conversation_id: "conv_metrics",
        finished: true,
        metadata: %{
          processing_time_ms: 1500,
          tools_executed: 2,
          has_tool_calls: true
        }
      }

      metrics = ResponseAggregator.extract_metrics(response)

      assert metrics.processing_time_ms == 1500
      assert metrics.total_tokens == 60
      assert metrics.prompt_tokens == 25
      assert metrics.completion_tokens == 35
      assert metrics.tools_executed == 2
      assert metrics.tools_successful == 1
      assert metrics.tools_failed == 1
      assert metrics.tool_success_rate == 50.0
      assert metrics.conversation_id == "conv_metrics"
      assert metrics.finished == true
    end

    test "handles response without tools" do
      response = %{
        content: "Simple response",
        tool_calls: [],
        tool_results: [],
        usage: %{total_tokens: 20},
        conversation_id: "conv_simple",
        finished: true,
        metadata: %{processing_time_ms: 100}
      }

      metrics = ResponseAggregator.extract_metrics(response)

      assert metrics.tools_executed == 0
      assert metrics.tools_successful == 0
      assert metrics.tools_failed == 0
      assert metrics.tool_success_rate == 0.0
      assert metrics.total_tokens == 20
    end

    test "calculates success rate correctly" do
      # All successful
      all_success_response = %{
        content: "All good",
        tool_calls: [],
        tool_results: [
          %{content: "success 1"},
          %{content: "success 2"},
          %{content: "success 3"}
        ],
        usage: %{total_tokens: 50},
        conversation_id: "conv_all_success",
        finished: true,
        metadata: %{processing_time_ms: 200}
      }

      metrics = ResponseAggregator.extract_metrics(all_success_response)
      assert metrics.tool_success_rate == 100.0

      # All failed
      all_failed_response = %{
        content: "All failed",
        tool_calls: [],
        tool_results: [
          %{content: "error", error: true},
          %{content: "error", error: true}
        ],
        usage: %{total_tokens: 30},
        conversation_id: "conv_all_failed",
        finished: true,
        metadata: %{processing_time_ms: 150}
      }

      metrics = ResponseAggregator.extract_metrics(all_failed_response)
      assert metrics.tool_success_rate == 0.0
    end
  end

  describe "content extraction and formatting" do
    test "extracts text from structured content" do
      response = %{
        content: [
          %{type: "text", text: "Hello "},
          %{type: "text", text: "world!"}
        ],
        usage: %{total_tokens: 15}
      }

      context = %{conversation_id: "conv_structured"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)
      assert aggregated.content == "Hello world!"
    end

    test "handles mixed content types gracefully" do
      response = %{
        content: [
          %{type: "text", text: "Text part "},
          %{type: "unknown", data: "should be ignored"},
          "Raw string part"
        ],
        usage: %{total_tokens: 20}
      }

      context = %{conversation_id: "conv_mixed"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)
      assert String.contains?(aggregated.content, "Text part")
      assert String.contains?(aggregated.content, "Raw string part")
    end

    test "formats structured tool results correctly" do
      tool_result = %{
        tool_call_id: "call_1",
        name: "weather_api",
        content: ~s({
          "temperature": 22,
          "condition": "sunny",
          "humidity": 65,
          "location": "Paris"
        })
      }

      response = %{
        content: "",
        tool_results: [tool_result],
        usage: %{total_tokens: 30}
      }

      context = %{conversation_id: "conv_structured_tools"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Should format the JSON nicely in the content
      assert String.contains?(aggregated.content, "weather_api")
    end

    test "handles non-JSON tool results gracefully" do
      tool_result = %{
        tool_call_id: "call_1",
        name: "simple_tool",
        content: "Plain text result"
      }

      response = %{
        content: "",
        tool_results: [tool_result],
        usage: %{total_tokens: 25}
      }

      context = %{conversation_id: "conv_plain_tools"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert String.contains?(aggregated.content, "simple_tool")
      assert String.contains?(aggregated.content, "Plain text result")
    end
  end

  describe "error handling" do
    test "handles aggregation errors gracefully" do
      # Simulate a response that causes an error during processing
      bad_response = %{
        content: "Normal content",
        tool_results: [
          %{
            # This might cause an error
            tool_call_id: nil,
            name: nil,
            content: nil
          }
        ]
      }

      context = %{conversation_id: "conv_error"}

      # Should still return an error tuple rather than crashing
      result = ResponseAggregator.aggregate_response(bad_response, context)

      case result do
        # If it handles gracefully
        {:ok, _aggregated} -> :ok
        # Expected error format
        {:error, {:aggregation_failed, _error}} -> :ok
        other -> flunk("Unexpected result: #{inspect(other)}")
      end
    end

    test "handles missing usage information" do
      response = %{
        content: "Response without usage"
        # No usage field
      }

      context = %{conversation_id: "conv_no_usage"}

      assert {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Should provide default usage values
      assert aggregated.usage.prompt_tokens == 0
      assert aggregated.usage.completion_tokens == 0
      assert aggregated.usage.total_tokens == 0
    end

    test "handles malformed context gracefully" do
      response = %{
        content: "Test response",
        usage: %{total_tokens: 10}
      }

      # Context missing required fields
      malformed_context =
        %{
          # Missing conversation_id
        }

      # Should handle gracefully or provide sensible defaults
      result = ResponseAggregator.aggregate_response(response, malformed_context)

      case result do
        {:ok, aggregated} ->
          # Should have some conversation_id, even if nil or default
          assert Map.has_key?(aggregated, :conversation_id)

        # Acceptable to error on malformed input
        {:error, _} ->
          :ok
      end
    end
  end
end
