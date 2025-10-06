defmodule JidoTest.AI.ReqLLMStreamingTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge
  alias Jido.AI.ReqLlmBridge.StreamingAdapter

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we might need to mock
    Mimic.copy(StreamingAdapter)
    :ok
  end

  describe "convert_streaming_response/2" do
    test "uses basic transformation when enhanced is false" do
      # Create a mock stream of ReqLLM chunks
      mock_stream = [
        %{content: "Hello", finish_reason: nil, role: "assistant"},
        %{content: " world", finish_reason: nil, role: "assistant"},
        %{content: "!", finish_reason: "stop", role: "assistant"}
      ]

      result_stream = ReqLlmBridge.convert_streaming_response(mock_stream, enhanced: false)

      # Convert to list to verify transformation
      result_list = Enum.to_list(result_stream)

      assert length(result_list) == 3

      # Verify first chunk transformation
      first_chunk = Enum.at(result_list, 0)
      assert first_chunk.content == "Hello"
      assert first_chunk.finish_reason == nil
      assert first_chunk.delta.content == "Hello"
      assert first_chunk.delta.role == "assistant"

      # Verify last chunk with finish_reason
      last_chunk = Enum.at(result_list, 2)
      assert last_chunk.content == "!"
      assert last_chunk.finish_reason == "stop"
    end

    test "uses enhanced streaming adapter when enhanced is true" do
      mock_stream = [%{content: "test", role: "assistant"}]
      opts = [enhanced: true, provider: :openai]

      expect(StreamingAdapter, :adapt_stream, fn stream, passed_opts ->
        assert Enum.to_list(stream) == [%{content: "test", role: "assistant"}]
        assert passed_opts == opts
        ["enhanced_result"]
      end)

      result_stream = ReqLlmBridge.convert_streaming_response(mock_stream, opts)
      result_list = Enum.to_list(result_stream)

      assert result_list == ["enhanced_result"]
    end

    test "defaults to basic transformation when no opts provided" do
      mock_stream = [%{content: "default test", role: "assistant"}]

      result_stream = ReqLlmBridge.convert_streaming_response(mock_stream)
      result_list = Enum.to_list(result_stream)

      assert length(result_list) == 1
      first_chunk = Enum.at(result_list, 0)
      assert first_chunk.content == "default test"
      assert first_chunk.delta.role == "assistant"
    end

    test "handles empty stream correctly" do
      mock_stream = []

      result_stream = ReqLlmBridge.convert_streaming_response(mock_stream, enhanced: false)
      result_list = Enum.to_list(result_stream)

      assert result_list == []
    end

    test "preserves stream lazy evaluation" do
      # Create a lazy stream that would be infinite if fully evaluated
      mock_stream = Stream.repeatedly(fn -> %{content: "infinite", role: "assistant"} end)

      result_stream = ReqLlmBridge.convert_streaming_response(mock_stream, enhanced: false)

      # Take only first 3 items to verify laziness is preserved
      result_list = result_stream |> Enum.take(3)

      assert length(result_list) == 3
      assert Enum.all?(result_list, fn chunk -> chunk.content == "infinite" end)
    end
  end

  describe "transform_streaming_chunk/1" do
    test "transforms basic ReqLLM chunk with content" do
      chunk = %{
        content: "Hello there!",
        finish_reason: nil,
        role: "assistant"
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      expected = %{
        content: "Hello there!",
        finish_reason: nil,
        usage: nil,
        tool_calls: [],
        delta: %{
          content: "Hello there!",
          role: "assistant"
        }
      }

      assert result == expected
    end

    test "transforms chunk with finish_reason" do
      chunk = %{
        content: "Complete response.",
        finish_reason: "stop",
        role: "assistant"
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      assert result.content == "Complete response."
      assert result.finish_reason == "stop"
      assert result.delta.content == "Complete response."
      assert result.delta.role == "assistant"
    end

    test "handles chunk with usage information" do
      chunk = %{
        content: "Response with usage",
        usage: %{
          prompt_tokens: 10,
          completion_tokens: 5,
          total_tokens: 15
        },
        role: "assistant"
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      assert result.content == "Response with usage"

      assert result.usage == %{
               prompt_tokens: 10,
               completion_tokens: 5,
               total_tokens: 15
             }
    end

    test "handles chunk with tool calls" do
      chunk = %{
        content: "",
        tool_calls: [
          %{
            id: "call_123",
            type: "function",
            function: %{name: "add", arguments: "{\"a\": 1, \"b\": 2}"}
          }
        ],
        role: "assistant"
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      assert result.content == ""

      assert result.tool_calls == [
               %{
                 id: "call_123",
                 type: "function",
                 function: %{name: "add", arguments: "{\"a\": 1, \"b\": 2}"}
               }
             ]
    end

    test "handles chunk with string keys" do
      chunk = %{
        "content" => "String keys test",
        "finish_reason" => "length",
        "role" => "assistant",
        "usage" => %{"prompt_tokens" => 8}
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      assert result.content == "String keys test"
      assert result.finish_reason == "length"
      assert result.delta.role == "assistant"
      assert result.usage == %{"prompt_tokens" => 8}
    end

    test "handles chunk with mixed atom and string keys" do
      chunk = %{
        "content" => "Mixed keys",
        "finish_reason" => "stop",
        "role" => "assistant",
        "tool_calls" => []
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      assert result.content == "Mixed keys"
      assert result.finish_reason == "stop"
      assert result.delta.role == "assistant"
      assert result.tool_calls == []
    end

    test "handles chunk with missing content" do
      chunk = %{
        finish_reason: "stop",
        role: "assistant"
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      # Should handle gracefully with nil or empty content
      assert result.content == nil or result.content == ""
      assert result.finish_reason == "stop"
      assert result.delta.role == "assistant"
    end

    test "handles chunk with missing role" do
      chunk = %{
        content: "No role specified",
        finish_reason: nil
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      assert result.content == "No role specified"
      # Default role
      assert result.delta.role == "assistant"
    end

    test "handles empty chunk" do
      chunk = %{}

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      expected = %{
        content: nil,
        finish_reason: nil,
        usage: nil,
        tool_calls: [],
        delta: %{
          content: nil,
          role: "assistant"
        }
      }

      assert result == expected
    end

    test "handles chunk with nested delta content" do
      chunk = %{
        delta: %{content: "Delta content", role: "user"},
        finish_reason: nil
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)

      # Should extract content from delta if main content is missing
      assert result.delta.role == "user"
    end
  end

  describe "get_chunk_content/1 (via transform_streaming_chunk)" do
    test "extracts content from direct content field" do
      chunk = %{content: "Direct content"}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.content == "Direct content"
    end

    test "extracts content from string key" do
      chunk = %{"content" => "String key content"}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.content == "String key content"
    end

    test "extracts content from delta.content when main content is nil" do
      chunk = %{delta: %{content: "Delta content"}}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.content == "Delta content"
    end

    test "prefers main content over delta content" do
      chunk = %{
        content: "Main content",
        delta: %{content: "Delta content"}
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.content == "Main content"
    end

    test "handles nil content gracefully" do
      chunk = %{content: nil}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.content == nil
    end
  end

  describe "convert_usage/1 (via transform_streaming_chunk)" do
    test "preserves usage map as-is" do
      chunk = %{
        content: "test",
        usage: %{prompt_tokens: 5, completion_tokens: 3, total_tokens: 8}
      }

      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.usage == %{prompt_tokens: 5, completion_tokens: 3, total_tokens: 8}
    end

    test "handles nil usage" do
      chunk = %{content: "test", usage: nil}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.usage == nil
    end

    test "handles missing usage field" do
      chunk = %{content: "test"}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.usage == nil
    end
  end

  describe "convert_tool_calls/1 (via transform_streaming_chunk)" do
    test "preserves tool_calls list as-is" do
      tool_calls = [
        %{id: "call_1", type: "function", function: %{name: "test"}},
        %{id: "call_2", type: "function", function: %{name: "test2"}}
      ]

      chunk = %{content: "test", tool_calls: tool_calls}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.tool_calls == tool_calls
    end

    test "returns empty list for nil tool_calls" do
      chunk = %{content: "test", tool_calls: nil}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.tool_calls == []
    end

    test "returns empty list for missing tool_calls field" do
      chunk = %{content: "test"}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.tool_calls == []
    end

    test "handles empty tool_calls list" do
      chunk = %{content: "test", tool_calls: []}
      result = ReqLlmBridge.transform_streaming_chunk(chunk)
      assert result.tool_calls == []
    end
  end

  describe "map_streaming_error/1" do
    test "maps stream error to Jido AI format" do
      error = {:error, %{reason: "stream_error", message: "Connection lost"}}
      result = ReqLlmBridge.map_streaming_error(error)

      assert {:error, mapped_error} = result
      assert is_map(mapped_error)
    end

    test "maps timeout error" do
      error = {:error, :timeout}
      result = ReqLlmBridge.map_streaming_error(error)

      assert {:error, _mapped_error} = result
    end

    test "maps rate limit error" do
      error = {:error, %{code: 429, message: "Rate limit exceeded"}}
      result = ReqLlmBridge.map_streaming_error(error)

      assert {:error, _mapped_error} = result
    end

    test "handles unknown streaming errors" do
      error = {:error, "Unknown streaming error"}
      result = ReqLlmBridge.map_streaming_error(error)

      assert {:error, _mapped_error} = result
    end
  end

  describe "integration scenarios" do
    test "full streaming workflow with multiple chunks" do
      # Simulate a complete streaming response
      reqllm_chunks = [
        %{content: "The", role: "assistant", finish_reason: nil},
        %{content: " weather", role: "assistant", finish_reason: nil},
        %{content: " is", role: "assistant", finish_reason: nil},
        %{content: " nice", role: "assistant", finish_reason: nil},
        %{
          content: " today",
          role: "assistant",
          finish_reason: "stop",
          usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
        }
      ]

      # Convert using the streaming response function
      converted_stream = ReqLlmBridge.convert_streaming_response(reqllm_chunks, enhanced: false)
      result_chunks = Enum.to_list(converted_stream)

      assert length(result_chunks) == 5

      # Verify all chunks have expected structure
      Enum.each(result_chunks, fn chunk ->
        assert Map.has_key?(chunk, :content)
        assert Map.has_key?(chunk, :delta)
        assert Map.has_key?(chunk, :tool_calls)
        assert chunk.delta.role == "assistant"
      end)

      # Verify content accumulation
      contents = Enum.map(result_chunks, & &1.content)
      assert contents == ["The", " weather", " is", " nice", " today"]

      # Verify final chunk has usage and finish_reason
      final_chunk = List.last(result_chunks)
      assert final_chunk.finish_reason == "stop"
      assert final_chunk.usage.total_tokens == 15
    end

    test "streaming with tool calls throughout" do
      reqllm_chunks = [
        %{content: "I'll help", role: "assistant", finish_reason: nil},
        %{
          content: "",
          role: "assistant",
          finish_reason: "tool_calls",
          tool_calls: [%{id: "call_1", type: "function", function: %{name: "calculate"}}]
        },
        %{content: "The result is 42", role: "assistant", finish_reason: "stop"}
      ]

      converted_stream = ReqLlmBridge.convert_streaming_response(reqllm_chunks, enhanced: false)
      result_chunks = Enum.to_list(converted_stream)

      assert length(result_chunks) == 3

      # First chunk: normal content
      assert Enum.at(result_chunks, 0).content == "I'll help"
      assert Enum.at(result_chunks, 0).tool_calls == []

      # Second chunk: tool call
      assert Enum.at(result_chunks, 1).content == ""
      assert Enum.at(result_chunks, 1).finish_reason == "tool_calls"
      assert length(Enum.at(result_chunks, 1).tool_calls) == 1

      # Third chunk: final response
      assert Enum.at(result_chunks, 2).content == "The result is 42"
      assert Enum.at(result_chunks, 2).finish_reason == "stop"
    end

    test "streaming with mixed content formats" do
      # Mix of atom keys, string keys, and different content structures
      reqllm_chunks = [
        %{content: "Start", role: "assistant"},
        %{"content" => " middle", "role" => "assistant"},
        %{delta: %{content: " end"}, role: "assistant", finish_reason: "stop"}
      ]

      converted_stream = ReqLlmBridge.convert_streaming_response(reqllm_chunks, enhanced: false)
      result_chunks = Enum.to_list(converted_stream)

      contents = Enum.map(result_chunks, & &1.content)
      assert contents == ["Start", " middle", " end"]

      # All should have consistent structure
      Enum.each(result_chunks, fn chunk ->
        assert chunk.delta.role == "assistant"
        assert is_list(chunk.tool_calls)
      end)
    end

    test "error handling in streaming context" do
      # Test streaming error mapping
      stream_errors = [
        {:error, %{reason: "stream_error", message: "Connection lost"}},
        {:error, :timeout},
        {:error, %{code: 429, message: "Rate limit"}}
      ]

      Enum.each(stream_errors, fn error ->
        result = ReqLlmBridge.map_streaming_error(error)
        assert {:error, _mapped} = result
      end)
    end
  end

  describe "performance and memory" do
    test "handles large streams efficiently" do
      # Create a large stream
      large_stream =
        Stream.map(1..1000, fn i ->
          %{
            content: "Chunk #{i}",
            role: "assistant",
            finish_reason: if(i == 1000, do: "stop", else: nil)
          }
        end)

      # Convert and measure that it processes without consuming excessive memory
      converted_stream = ReqLlmBridge.convert_streaming_response(large_stream, enhanced: false)

      # Take only first and last few to verify lazy processing
      first_10 = converted_stream |> Enum.take(10)
      assert length(first_10) == 10
      assert Enum.at(first_10, 0).content == "Chunk 1"
      assert Enum.at(first_10, 9).content == "Chunk 10"

      # Verify structure is maintained
      Enum.each(first_10, fn chunk ->
        assert Map.has_key?(chunk, :content)
        assert Map.has_key?(chunk, :delta)
        assert chunk.delta.role == "assistant"
      end)
    end

    test "preserves stream characteristics" do
      # Verify that converted stream maintains stream properties
      original_stream = Stream.map(1..5, fn i -> %{content: "Item #{i}", role: "assistant"} end)
      converted_stream = ReqLlmBridge.convert_streaming_response(original_stream, enhanced: false)

      # Should still be a stream
      assert Enumerable.impl_for(converted_stream) != nil

      # Should be able to process in chunks
      first_3 = converted_stream |> Enum.take(3)
      assert length(first_3) == 3

      # Should be able to filter/transform further
      filtered =
        converted_stream
        |> Stream.filter(fn chunk ->
          String.contains?(chunk.content, "2") or String.contains?(chunk.content, "4")
        end)
        |> Enum.to_list()

      assert length(filtered) == 2
    end
  end
end
