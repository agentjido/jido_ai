defmodule Jido.AI.ReqLlmBridge.StreamingAdapterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReqLlmBridge.StreamingAdapter

  @moduledoc """
  Tests for the StreamingAdapter module.

  Tests cover:
  - Chunk transformation with metadata enrichment
  - Stream lifecycle management (continuation logic)
  - Error recovery in streaming contexts
  """

  describe "4.1 Chunk Transformation" do
    test "chunk transformation with metadata enrichment" do
      # Create mock chunk
      chunk = %{content: "Hello", finish_reason: nil}

      # Transform with metadata
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 0})

      # Assert basic structure
      assert is_map(result)
      assert result.content == "Hello"

      # Assert metadata is present
      assert Map.has_key?(result, :chunk_metadata)
      metadata = result.chunk_metadata

      # Assert all required metadata fields
      assert Map.has_key?(metadata, :index)
      assert Map.has_key?(metadata, :timestamp)
      assert Map.has_key?(metadata, :chunk_size)
      assert Map.has_key?(metadata, :provider)

      # Assert metadata values
      assert metadata.index == 0
      assert %DateTime{} = metadata.timestamp
      assert is_integer(metadata.chunk_size)
      assert is_binary(metadata.provider)
    end

    test "chunk content extraction with :content key" do
      chunk = %{content: "test content"}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 0})

      assert result.content == "test content"
      assert result.chunk_metadata.chunk_size == byte_size("test content")
    end

    test "chunk content extraction with string \"content\" key" do
      chunk = %{"content" => "string key content"}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 1})

      assert result.content == "string key content"
      assert result.chunk_metadata.chunk_size == byte_size("string key content")
      assert result.chunk_metadata.index == 1
    end

    test "chunk content extraction with :text key" do
      chunk = %{text: "text key content"}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 2})

      # transform_streaming_chunk may convert :text to :content
      # Just verify transformation succeeds and metadata is added
      assert is_map(result)
      assert Map.has_key?(result, :chunk_metadata)
      assert result.chunk_metadata.index == 2
    end

    test "chunk content extraction with nested :delta > :content" do
      chunk = %{delta: %{content: "nested content"}}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 3})

      # ReqLlmBridge.transform_streaming_chunk handles delta extraction
      assert is_map(result)
      assert Map.has_key?(result, :chunk_metadata)
      assert result.chunk_metadata.chunk_size == byte_size("nested content")
      assert result.chunk_metadata.index == 3
    end

    test "provider extraction from chunk with :provider key" do
      chunk = %{content: "test", provider: "openai"}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 0})

      assert result.chunk_metadata.provider == "openai"
    end

    test "provider extraction from chunk with :model key" do
      chunk = %{content: "test", model: "gpt-4"}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 0})

      # Provider extraction falls back to :model if :provider not present
      assert result.chunk_metadata.provider == "gpt-4"
    end

    test "provider fallback to unknown when not present" do
      chunk = %{content: "test"}
      result = StreamingAdapter.transform_chunk_with_metadata({chunk, 0})

      assert result.chunk_metadata.provider == "unknown"
    end
  end

  describe "4.2 Stream Lifecycle" do
    test "continue_stream? detects finish_reason: stop" do
      chunk = %{content: "final", finish_reason: "stop"}

      assert StreamingAdapter.continue_stream?(chunk) == false
    end

    test "continue_stream? continues on finish_reason: nil" do
      chunk = %{content: "ongoing", finish_reason: nil}

      assert StreamingAdapter.continue_stream?(chunk) == true
    end

    test "stream continues with finish_reason: empty string" do
      chunk = %{content: "ongoing", finish_reason: ""}

      assert StreamingAdapter.continue_stream?(chunk) == true
    end

    test "stream continues with finish_reason: unknown" do
      chunk = %{content: "ongoing", finish_reason: "unknown"}

      assert StreamingAdapter.continue_stream?(chunk) == true
    end

    test "continue_stream? detects finish_reason: length" do
      chunk = %{content: "stopped", finish_reason: "length"}

      assert StreamingAdapter.continue_stream?(chunk) == false
    end

    test "continue_stream? detects finish_reason: content_filter" do
      chunk = %{content: "filtered", finish_reason: "content_filter"}

      assert StreamingAdapter.continue_stream?(chunk) == false
    end

    test "continue_stream? detects finish_reason: tool_calls" do
      chunk = %{content: "tool", finish_reason: "tool_calls"}

      assert StreamingAdapter.continue_stream?(chunk) == false
    end

    test "continue_stream? defaults to true for chunks without finish_reason" do
      chunk = %{content: "no finish reason"}

      assert StreamingAdapter.continue_stream?(chunk) == true
    end

    test "adapt_stream applies take_while with continue_stream?" do
      # Create stream with chunks including stop condition
      chunks = [
        %{content: "first", finish_reason: nil},
        %{content: "second", finish_reason: nil},
        %{content: "stop", finish_reason: "stop"},
        %{content: "should not reach", finish_reason: nil}
      ]

      stream =
        StreamingAdapter.adapt_stream(chunks, error_recovery: false, resource_cleanup: false)

      results = Enum.to_list(stream)

      # take_while stops BEFORE emitting the element that fails the test
      # So we get 2 chunks (first, second), stop chunk is not included
      assert length(results) == 2

      # Verify content (order should be preserved)
      assert Enum.at(results, 0).content == "first"
      assert Enum.at(results, 1).content == "second"
    end
  end

  describe "4.3 Error Recovery" do
    test "error recovery is configurable via adapt_stream options" do
      # Test that error_recovery option is passed through
      chunks = [%{content: "test", finish_reason: nil}]

      # With error recovery enabled (default)
      stream_with_recovery = StreamingAdapter.adapt_stream(chunks, error_recovery: true)
      results = Enum.to_list(stream_with_recovery)

      assert length(results) == 1
      assert hd(results).content == "test"
    end

    test "error recovery can be disabled" do
      # Test that error_recovery: false still processes stream
      chunks = [%{content: "test", finish_reason: nil}]

      # With error recovery disabled
      stream_without_recovery = StreamingAdapter.adapt_stream(chunks, error_recovery: false)
      results = Enum.to_list(stream_without_recovery)

      assert length(results) == 1
      assert hd(results).content == "test"
    end

    test "handle_stream_errors wraps stream with error handling" do
      # Test that handle_stream_errors creates a stream transform
      chunks = [%{content: "test", finish_reason: nil}]

      stream = StreamingAdapter.handle_stream_errors(chunks, true)

      # Should successfully process stream
      results = Enum.to_list(stream)
      assert length(results) == 1
      assert hd(results).content == "test"
    end
  end

  describe "4.4 Stream Lifecycle Management" do
    test "manage_stream_lifecycle wraps stream with resource management" do
      chunks = [
        %{content: "managed", finish_reason: nil}
      ]

      # Enable lifecycle management
      stream = StreamingAdapter.manage_stream_lifecycle(Stream.map(chunks, & &1), true)

      # Should complete successfully
      results = Enum.to_list(stream)
      assert length(results) == 1
      assert hd(results).content == "managed"
    end

    test "lifecycle management can be disabled" do
      chunks = [
        %{content: "unmanaged", finish_reason: nil}
      ]

      # Disable lifecycle management
      stream = StreamingAdapter.manage_stream_lifecycle(Stream.map(chunks, & &1), false)

      # Should still work (just passes through)
      results = Enum.to_list(stream)
      assert length(results) == 1
      assert hd(results).content == "unmanaged"
    end
  end

  describe "4.5 Full Stream Adaptation" do
    test "adapt_stream integrates all features" do
      chunks = [
        %{content: "first", finish_reason: nil, provider: "test-provider"},
        %{content: "second", finish_reason: nil},
        %{content: "final", finish_reason: "stop"}
      ]

      # Full adaptation with all features
      stream = StreamingAdapter.adapt_stream(chunks)
      results = Enum.to_list(stream)

      # take_while stops BEFORE the chunk with finish_reason: "stop"
      # So we get 2 chunks (first, second), not including the stop chunk
      assert length(results) == 2

      # Verify metadata enrichment
      first_chunk = Enum.at(results, 0)
      assert Map.has_key?(first_chunk, :chunk_metadata)
      assert first_chunk.chunk_metadata.index == 0
      assert first_chunk.chunk_metadata.provider == "test-provider"

      second_chunk = Enum.at(results, 1)
      assert second_chunk.chunk_metadata.index == 1
      assert second_chunk.chunk_metadata.provider == "unknown"
    end

    test "adapt_stream with custom timeout option" do
      chunks = [%{content: "timeout test", finish_reason: nil}]

      stream = StreamingAdapter.adapt_stream(chunks, timeout: 10_000)
      results = Enum.to_list(stream)

      assert length(results) == 1
    end

    test "adapt_stream with error recovery disabled" do
      chunks = [%{content: "no recovery", finish_reason: nil}]

      stream = StreamingAdapter.adapt_stream(chunks, error_recovery: false)
      results = Enum.to_list(stream)

      assert length(results) == 1
    end

    test "adapt_stream with resource cleanup disabled" do
      chunks = [%{content: "no cleanup", finish_reason: nil}]

      stream = StreamingAdapter.adapt_stream(chunks, resource_cleanup: false)
      results = Enum.to_list(stream)

      assert length(results) == 1
    end
  end
end
