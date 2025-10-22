defmodule Jido.AI.ReqLlmBridge.ResponseAggregatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReqLlmBridge.ResponseAggregator

  doctest Jido.AI.ReqLlmBridge.ResponseAggregator

  @moduledoc """
  Tests for the ResponseAggregator module.

  Tests cover:
  - Content aggregation and normalization
  - Tool result integration
  - Usage statistics extraction and merging
  - Response formatting for users
  - Metrics extraction
  """

  describe "6.1 Content Aggregation" do
    test "extracting base content from response with :content key" do
      response = %{content: "Hello from the LLM"}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "Hello from the LLM"
    end

    test "extracting base content from response with string key" do
      response = %{"content" => "Response with string key"}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "Response with string key"
    end

    test "extracting content from content array" do
      response = %{
        content: [
          %{type: "text", text: "Hello"},
          %{type: "text", text: " world"}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "Hello world"
    end

    test "normalizing content arrays to strings" do
      response = %{
        content: [
          %{type: "text", text: "Part 1"},
          %{type: "image", data: "base64..."},
          %{type: "text", text: " Part 2"}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Non-text items are skipped
      assert aggregated.content == "Part 1 Part 2"
    end

    test "handling empty string content" do
      response = %{content: ""}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "I don't have any response to provide."
    end

    test "handling empty array content" do
      response = %{content: []}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content == "I don't have any response to provide."
    end
  end

  describe "6.2 Tool Result Integration" do
    test "extracting tool calls from response" do
      response = %{
        content: "Let me check that",
        tool_calls: [
          %{id: "call_1", function: %{name: "get_weather", arguments: "{}"}}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert length(aggregated.tool_calls) == 1
      assert Enum.at(aggregated.tool_calls, 0).id == "call_1"
    end

    test "extracting tool results from response" do
      response = %{
        content: "The weather is sunny",
        tool_results: [
          %{
            tool_call_id: "call_1",
            name: "get_weather",
            content: ~s({"temperature": 22, "condition": "sunny"})
          }
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert length(aggregated.tool_results) == 1
      assert Enum.at(aggregated.tool_results, 0).tool_call_id == "call_1"
    end

    test "integrating tool results into content with integrated style" do
      response = %{
        content: "The weather is",
        tool_results: [
          %{
            tool_call_id: "call_1",
            name: "get_weather",
            content: ~s({"temperature": 22, "condition": "sunny"})
          }
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      formatted =
        ResponseAggregator.format_for_user(aggregated, %{tool_result_style: :integrated})

      # Tool result should be integrated into narrative
      assert formatted =~ "The weather is"
      assert formatted =~ "Based on the tool result"
    end
  end

  describe "6.3 Usage Statistics" do
    test "extracting usage stats from response" do
      response = %{
        content: "Response",
        usage: %{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30}
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.usage.prompt_tokens == 10
      assert aggregated.usage.completion_tokens == 20
      assert aggregated.usage.total_tokens == 30
    end

    test "merging usage stats from streaming chunks" do
      chunks = [
        %{content: "Hello", usage: %{prompt_tokens: 5, completion_tokens: 3, total_tokens: 8}},
        %{content: " world", usage: %{prompt_tokens: 0, completion_tokens: 5, total_tokens: 5}},
        %{content: "!", usage: %{prompt_tokens: 0, completion_tokens: 2, total_tokens: 2}}
      ]

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_streaming_response(chunks, context)

      assert aggregated.usage.prompt_tokens == 5
      assert aggregated.usage.completion_tokens == 10
      assert aggregated.usage.total_tokens == 15
    end

    test "handling missing usage stats defaults to zero" do
      response = %{content: "Response without usage"}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.usage.prompt_tokens == 0
      assert aggregated.usage.completion_tokens == 0
      assert aggregated.usage.total_tokens == 0
    end
  end

  describe "6.4 Response Formatting" do
    test "formatting response with integrated tool result style" do
      aggregated = %{
        content: "The current temperature is",
        tool_results: [
          %{content: ~s({"temperature": 22}), error: false}
        ],
        tool_calls: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 100}
      }

      formatted =
        ResponseAggregator.format_for_user(aggregated, %{tool_result_style: :integrated})

      assert formatted =~ "The current temperature is"
      assert formatted =~ "Based on the tool result"
    end

    test "formatting response with appended tool result style" do
      aggregated = %{
        content: "Here is the information",
        tool_results: [
          %{content: "Tool result data", name: "my_tool", error: false}
        ],
        tool_calls: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 100}
      }

      formatted = ResponseAggregator.format_for_user(aggregated, %{tool_result_style: :appended})

      assert formatted =~ "Here is the information"
      assert formatted =~ "---"
      assert formatted =~ "Tool Results:"
    end

    test "formatting with metadata included" do
      aggregated = %{
        content: "Response content",
        tool_results: [],
        tool_calls: [],
        usage: %{prompt_tokens: 10, completion_tokens: 20, total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 150, tools_executed: 2}
      }

      formatted = ResponseAggregator.format_for_user(aggregated, %{include_metadata: true})

      assert formatted =~ "Response content"
      assert formatted =~ "Response Metadata:"
      assert formatted =~ "Processing time: 150ms"
      assert formatted =~ "Tokens used: 30"
      assert formatted =~ "Tools executed: 2"
    end

    test "formatting without metadata by default" do
      aggregated = %{
        content: "Response content",
        tool_results: [],
        tool_calls: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 150}
      }

      formatted = ResponseAggregator.format_for_user(aggregated, %{})

      assert formatted == "Response content"
      refute formatted =~ "Response Metadata:"
    end
  end

  describe "6.5 Metrics Extraction" do
    test "extracting processing time metrics" do
      aggregated = %{
        content: "Response",
        tool_results: [],
        tool_calls: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 250}
      }

      metrics = ResponseAggregator.extract_metrics(aggregated)

      assert metrics.processing_time_ms == 250
    end

    test "extracting tool execution statistics" do
      aggregated = %{
        content: "Response",
        tool_results: [
          %{tool_call_id: "call_1", content: "result1", error: false},
          %{tool_call_id: "call_2", content: "result2", error: false},
          %{tool_call_id: "call_3", content: "error", error: true}
        ],
        tool_calls: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 100, tools_executed: 3}
      }

      metrics = ResponseAggregator.extract_metrics(aggregated)

      assert metrics.tools_executed == 3
      assert metrics.tools_successful == 2
      assert metrics.tools_failed == 1
    end

    test "calculating tool success rate" do
      aggregated = %{
        content: "Response",
        tool_results: [
          %{content: "result1", error: false},
          %{content: "result2", error: false},
          %{content: "result3", error: false},
          %{content: "error", error: true}
        ],
        tool_calls: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 100}
      }

      metrics = ResponseAggregator.extract_metrics(aggregated)

      assert metrics.tool_success_rate == 75.0
      assert metrics.tools_executed == 4
      assert metrics.tools_successful == 3
      assert metrics.tools_failed == 1
    end

    test "calculating success rate with zero tools" do
      aggregated = %{
        content: "Response",
        tool_results: [],
        tool_calls: [],
        usage: %{total_tokens: 30},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 100}
      }

      metrics = ResponseAggregator.extract_metrics(aggregated)

      assert metrics.tool_success_rate == 0.0
      assert metrics.tools_executed == 0
      assert metrics.tools_successful == 0
      assert metrics.tools_failed == 0
    end

    test "extracting token usage metrics" do
      aggregated = %{
        content: "Response",
        tool_results: [],
        tool_calls: [],
        usage: %{prompt_tokens: 15, completion_tokens: 25, total_tokens: 40},
        conversation_id: "conv_1",
        finished: true,
        metadata: %{processing_time_ms: 100}
      }

      metrics = ResponseAggregator.extract_metrics(aggregated)

      assert metrics.total_tokens == 40
      assert metrics.prompt_tokens == 15
      assert metrics.completion_tokens == 25
    end
  end

  describe "6.6 Streaming Response Aggregation" do
    test "aggregating streaming chunks with content accumulation" do
      chunks = [
        %{content: "Hello"},
        %{content: " there"},
        %{content: " world"}
      ]

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_streaming_response(chunks, context)

      assert aggregated.content == "Hello there world"
      assert aggregated.finished == true
    end

    test "aggregating streaming chunks with tool calls" do
      chunks = [
        %{content: "Let me check", tool_calls: [%{id: "call_1", function: %{name: "tool1"}}]},
        %{content: " that", tool_calls: []},
        %{content: ".", tool_calls: [%{id: "call_1", function: %{name: "tool1"}}]}
      ]

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_streaming_response(chunks, context)

      assert aggregated.content == "Let me check that."
      # Duplicate tool calls should be deduplicated
      assert length(aggregated.tool_calls) == 1
    end

    test "handling nil chunks in streaming" do
      chunks = [
        %{content: "Hello"},
        nil,
        %{content: " world"},
        nil
      ]

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_streaming_response(chunks, context)

      assert aggregated.content == "Hello world"
    end
  end

  describe "6.7 Response Metadata" do
    test "metadata includes processing time" do
      response = %{content: "Response"}
      start_time = System.monotonic_time(:millisecond)
      context = %{conversation_id: "conv_1", options: %{}, processing_start_time: start_time}

      # Simulate some processing time
      Process.sleep(10)

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.metadata.processing_time_ms >= 10
    end

    test "metadata includes tool execution count" do
      response = %{
        content: "Response",
        tool_results: [
          %{content: "result1"},
          %{content: "result2"}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.metadata.tools_executed == 2
    end

    test "metadata includes response type" do
      response = %{
        content: "Response",
        tool_results: [%{content: "result"}]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.metadata.response_type == :content_with_tools
    end

    test "metadata detects content_only response" do
      response = %{content: "Just text"}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.metadata.response_type == :content_only
    end

    test "metadata detects tools_only response" do
      response = %{
        content: "",
        tool_results: [%{content: "result"}]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.metadata.response_type == :tools_only
    end

    test "metadata detects empty response" do
      response = %{content: ""}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.metadata.response_type == :empty
    end
  end

  describe "6.8 Finished Status Detection" do
    test "response is finished when all tool calls have results" do
      response = %{
        content: "Done",
        tool_calls: [%{id: "call_1"}],
        tool_results: [%{tool_call_id: "call_1", content: "result"}]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.finished == true
    end

    test "response is not finished when tool calls are pending" do
      response = %{
        content: "Working on it",
        tool_calls: [%{id: "call_1"}, %{id: "call_2"}],
        tool_results: [%{tool_call_id: "call_1", content: "result"}]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.finished == false
    end

    test "response is finished when no tool calls present" do
      response = %{content: "Simple response"}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.finished == true
    end
  end

  describe "6.9 Error Handling" do
    test "aggregate_response handles malformed input gracefully" do
      # Test with invalid data that might cause issues
      response = %{content: nil}
      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert is_binary(aggregated.content)
    end

    test "tool errors are included in metadata" do
      response = %{
        content: "Response",
        tool_results: [
          %{tool_call_id: "call_1", content: "result", error: false},
          %{tool_call_id: "call_2", content: "failed", error: true, reason: "timeout"}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert Map.has_key?(aggregated.metadata, :tool_errors)
      assert length(aggregated.metadata.tool_errors) == 1
    end

    test "tool errors are sanitized in metadata" do
      response = %{
        content: "Response",
        tool_results: [
          %{
            tool_call_id: "call_1",
            content: "failed",
            error: true,
            password: "secret123"
          }
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      # Password should be redacted in error metadata
      error = Enum.at(aggregated.metadata.tool_errors, 0)
      assert error.password == "[REDACTED]"
    end
  end

  describe "6.10 Tool-Only Response Formatting" do
    test "formatting response with only tool results" do
      response = %{
        content: "",
        tool_results: [
          %{name: "calculator", content: ~s({"result": 42})}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content =~ "Here are the results:"
    end

    test "formatting tool-only response with multiple results" do
      response = %{
        content: "",
        tool_results: [
          %{name: "tool1", content: ~s({"value": "result1"})},
          %{name: "tool2", content: ~s({"value": "result2"})}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content =~ "Here are the results:"
    end

    test "formatting tool-only response with all errors" do
      response = %{
        content: "",
        tool_results: [
          %{name: "tool1", content: "error", error: true}
        ]
      }

      context = %{conversation_id: "conv_1", options: %{}}

      {:ok, aggregated} = ResponseAggregator.aggregate_response(response, context)

      assert aggregated.content =~ "encountered errors"
    end
  end
end
