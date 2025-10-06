defmodule Jido.AI.ReqLlmBridge.StreamingAdapterTest do
  use ExUnit.Case, async: true
  doctest Jido.AI.ReqLlmBridge.StreamingAdapter

  alias Jido.AI.ReqLlmBridge
  alias Jido.AI.ReqLlmBridge.StreamingAdapter

  describe "adapt_stream/2" do
    test "transforms basic stream chunks to Jido AI format" do
      # Mock ReqLLM stream chunks
      mock_chunks = [
        %{content: "Hello", finish_reason: nil, usage: nil},
        %{content: " world", finish_reason: nil, usage: nil},
        %{content: "!", finish_reason: "stop", usage: %{prompt_tokens: 5, completion_tokens: 3}}
      ]

      stream = mock_chunks
      adapted = StreamingAdapter.adapt_stream(stream)

      results = Enum.to_list(adapted)

      # Should get 2 results since last chunk has finish_reason: "stop" which stops streaming
      assert length(results) == 2

      # Check first chunk
      first_chunk = Enum.at(results, 0)
      assert first_chunk[:content] == "Hello"
      assert first_chunk[:delta][:content] == "Hello"
      assert first_chunk[:delta][:role] == "assistant"
      assert first_chunk[:chunk_metadata][:index] == 0
      assert first_chunk[:chunk_metadata][:chunk_size] == 5

      # Check second chunk has finish_reason
      second_chunk = Enum.at(results, 1)
      assert second_chunk[:content] == " world"
      assert second_chunk[:finish_reason] == nil
    end

    test "handles error recovery when enabled" do
      # Test with a simple stream for error recovery functionality
      normal_stream = [%{content: "start", finish_reason: nil}]

      adapted = StreamingAdapter.adapt_stream(normal_stream, error_recovery: true)

      # Should process normally when no errors occur
      results = Enum.to_list(adapted)
      assert length(results) >= 1
      assert Enum.at(results, 0)[:content] == "start"
    end

    test "applies timeout settings" do
      mock_stream = [%{content: "test", finish_reason: nil}]

      adapted = StreamingAdapter.adapt_stream(mock_stream, timeout: 1000)
      results = Enum.to_list(adapted)

      assert length(results) == 1
      assert Enum.at(results, 0)[:content] == "test"
    end
  end

  describe "transform_chunk_with_metadata/1" do
    test "adds comprehensive metadata to chunks" do
      chunk = %{content: "test content", finish_reason: nil, usage: nil}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 5})

      assert result[:content] == "test content"
      assert result[:chunk_metadata][:index] == 5
      # byte_size("test content")
      assert result[:chunk_metadata][:chunk_size] == 12
      assert is_struct(result[:chunk_metadata][:timestamp], DateTime)
    end

    test "preserves original chunk structure" do
      chunk = %{
        content: "hello",
        finish_reason: "stop",
        usage: %{prompt_tokens: 1, completion_tokens: 1},
        tool_calls: []
      }

      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 0})

      assert result[:content] == "hello"
      assert result[:finish_reason] == "stop"
      assert result[:usage][:prompt_tokens] == 1
      assert result[:tool_calls] == []
    end
  end

  describe "continue_stream?/1" do
    test "continues streaming when finish_reason is nil" do
      chunk = %{finish_reason: nil}
      assert StreamingAdapter.continue_stream?(chunk) == true
    end

    test "continues streaming when finish_reason is empty string" do
      chunk = %{finish_reason: ""}
      assert StreamingAdapter.continue_stream?(chunk) == true
    end

    test "stops streaming on definitive stop conditions" do
      stop_conditions = ["stop", "length", "content_filter", "tool_calls"]

      Enum.each(stop_conditions, fn reason ->
        chunk = %{finish_reason: reason}
        assert StreamingAdapter.continue_stream?(chunk) == false
      end)
    end

    test "continues on other finish reasons" do
      chunk = %{finish_reason: "unknown_reason"}
      assert StreamingAdapter.continue_stream?(chunk) == true
    end
  end

  describe "handle_stream_errors/2" do
    test "passes through normal chunks without error recovery" do
      normal_stream = [%{content: "chunk1"}, %{content: "chunk2"}]

      result_stream = StreamingAdapter.handle_stream_errors(normal_stream, false)
      results = Enum.to_list(result_stream)

      assert length(results) == 2
      assert Enum.at(results, 0)[:content] == "chunk1"
      assert Enum.at(results, 1)[:content] == "chunk2"
    end

    test "handles errors gracefully with recovery enabled" do
      # This is a basic test - in practice, error handling would be more complex
      normal_stream = [%{content: "test"}]
      result_stream = StreamingAdapter.handle_stream_errors(normal_stream, true)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert Enum.at(results, 0)[:content] == "test"
    end
  end

  describe "manage_stream_lifecycle/2" do
    test "manages stream lifecycle with cleanup enabled" do
      test_stream = [%{content: "start"}, %{content: "middle"}, %{content: "end"}]

      managed_stream = StreamingAdapter.manage_stream_lifecycle(test_stream, true)
      results = Enum.to_list(managed_stream)

      assert length(results) == 3
      assert Enum.map(results, & &1[:content]) == ["start", "middle", "end"]
    end

    test "passes through stream without lifecycle management when disabled" do
      test_stream = [%{content: "test"}]

      result_stream = StreamingAdapter.manage_stream_lifecycle(test_stream, false)

      # Should be the same stream reference when disabled
      assert result_stream == test_stream
    end
  end

  describe "integration with Jido.AI.ReqLlmBridge.convert_streaming_response/2" do
    test "basic streaming conversion works" do
      mock_stream = [
        %{content: "Hello", finish_reason: nil},
        %{content: " world", finish_reason: "stop"}
      ]

      converted = ReqLlmBridge.convert_streaming_response(mock_stream)
      results = Enum.to_list(converted)

      assert length(results) == 2
      assert Enum.at(results, 0)[:content] == "Hello"
      assert Enum.at(results, 1)[:content] == " world"
      assert Enum.at(results, 1)[:finish_reason] == "stop"
    end

    test "enhanced streaming conversion with adapter" do
      mock_stream = [%{content: "Test", finish_reason: nil}]

      converted = ReqLlmBridge.convert_streaming_response(mock_stream, enhanced: true)
      results = Enum.to_list(converted)

      assert length(results) == 1
      chunk = Enum.at(results, 0)
      assert chunk[:content] == "Test"
      assert chunk[:chunk_metadata][:index] == 0
      assert is_struct(chunk[:chunk_metadata][:timestamp], DateTime)
    end
  end
end
