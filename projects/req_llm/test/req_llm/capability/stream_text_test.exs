defmodule ReqLLM.Capability.StreamTextTest do
  @moduledoc """
  Unit tests for ReqLLM.Capability.StreamText capability verification.

  Tests the StreamText capability module's interface compliance and streaming behavior.
  Note: These tests avoid making real API calls by mocking at the appropriate level.
  """

  use ReqLLM.Test.CapabilityCase

  alias ReqLLM.Capability.StreamText
  alias ReqLLM.StreamChunk



  describe "advertised?/1" do
    test "returns true for all provider types" do
      test_providers = [
        {:openai, "gpt-4"},
        {:anthropic, "claude-3-sonnet"},
        {:fake_provider, "fake-model"},
        {:custom, "custom-model"}
      ]

      for {provider, model_name} <- test_providers do
        model = test_model(to_string(provider), model_name)

        assert StreamText.advertised?(model) == true,
               "Expected advertised?(#{provider}:#{model_name}) to be true"
      end
    end
  end

  describe "verify/2" do
    test "successful verification with content chunks" do
      test_scenarios = [
        {"Simple content stream", ["Hello", " world", "!"], 3, 3, 12, "Hello world!"},
        {"Single chunk", ["Complete response"], 1, 1, 17, "Complete response"},
        {"Unicode content", ["Hello", " 👋", " world"], 3, 3, 13, "Hello 👋 world"},
        {"Content with whitespace", ["  Hello  ", "  world  "], 2, 2, 18, "  Hello    world  "},
        {"Empty chunks mixed", ["Hello", "", " world"], 3, 3, 11, "Hello world"},
        {"Long response truncation", [String.duplicate("text ", 20)], 1, 1, 100,
         String.slice(String.duplicate("text ", 20), 0, 50)}
      ]

      for {description, chunk_texts, expected_total_chunks, expected_content_chunks,
           expected_length, expected_preview} <- test_scenarios do
        model = test_model("openai", "gpt-4")

        # Create a stream with content chunks
        chunks = Enum.map(chunk_texts, &StreamChunk.text/1)
        stream = Stream.map(chunks, & &1)

        Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
          {:ok, stream}
        end)

        result = StreamText.verify(model, [])

        assert {:ok, response_data} = result, "Test '#{description}' should pass"
        assert response_data.model_id == "openai:gpt-4"

        assert response_data.chunks_received == expected_total_chunks,
               "Total chunks mismatch for '#{description}'"

        assert response_data.text_chunks_received == expected_content_chunks,
               "Content chunks mismatch for '#{description}'"

        assert response_data.response_length == expected_length,
               "Length mismatch for '#{description}'"

        assert response_data.response_preview == expected_preview,
               "Preview mismatch for '#{description}'"
      end
    end

    test "successful verification with mixed chunk types" do
      model = test_model("anthropic", "claude-3-sonnet")

      # Create stream with different chunk types
      chunks = [
        StreamChunk.text("Hello"),
        StreamChunk.thinking("Let me think..."),
        StreamChunk.text(" world"),
        StreamChunk.tool_call("get_weather", %{city: "NYC"}),
        StreamChunk.text("!"),
        StreamChunk.meta(%{finish_reason: "stop"})
      ]

      stream = Stream.map(chunks, & &1)

      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:ok, stream}
      end)

      result = StreamText.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.model_id == "anthropic:claude-3-sonnet"
      assert response_data.chunks_received == 6
      # Only :content chunks count
      assert response_data.text_chunks_received == 3
      # "Hello world!"
      assert response_data.response_length == 12
      assert response_data.response_preview == "Hello world!"
    end

    test "handles stream chunk limit (100 chunks)" do
      model = test_model("openai", "gpt-4")

      # Create an infinite stream that would exceed 100 chunks
      infinite_chunks =
        Stream.repeatedly(fn -> StreamChunk.text("chunk ") end) |> Stream.take(200)

      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:ok, infinite_chunks}
      end)

      result = StreamText.verify(model, [])

      assert {:ok, response_data} = result
      # Should be limited to 100 chunks
      assert response_data.chunks_received == 100
      assert response_data.text_chunks_received == 100
      # 100 * "chunk " = 600 chars
      assert response_data.response_length == 600

      assert response_data.response_preview ==
               String.slice(String.duplicate("chunk ", 100), 0, 50)
    end



    test "handles error cases appropriately" do
      error_scenarios = [
        {"Empty stream", [], "No chunks received from stream"},
        {"Only non-content chunks",
         [
           StreamChunk.thinking("thinking..."),
           StreamChunk.tool_call("func", %{}),
           StreamChunk.meta(%{finish_reason: "stop"})
         ], "Empty streamed response"},
        {"Only empty text chunks",
         [
           StreamChunk.text(""),
           StreamChunk.text("   "),
           StreamChunk.text("\n\t"),
           StreamChunk.text("   "),
           StreamChunk.text("\n"),
           StreamChunk.text("\t  ")
         ], "Empty streamed response"},
        {"Only nil text chunks",
         [
           %StreamChunk{type: :content, text: nil},
           %StreamChunk{type: :content, text: nil}
         ], "Empty streamed response"}
      ]

      for {description, chunks, expected_error} <- error_scenarios do
        model = test_model("openai", "gpt-4")

        stream = Stream.map(chunks, & &1)

        Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
          {:ok, stream}
        end)

        result = StreamText.verify(model, [])
        assert {:error, ^expected_error} = result, "Error case '#{description}' failed"
      end
    end

    test "handles stream_text! API errors" do
      model = test_model("openai", "gpt-4")

      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:error, "Network timeout"}
      end)

      result = StreamText.verify(model, [])
      assert {:error, "Network timeout"} = result
    end



    test "filters nil text from content chunks" do
      model = test_model("openai", "gpt-4")

      chunks = [
        StreamChunk.text("Hello"),
        # Nil text should be filtered
        %StreamChunk{type: :content, text: nil},
        StreamChunk.text(" world"),
        # Nil text should be filtered
        %StreamChunk{type: :content, text: nil}
      ]

      stream = Stream.map(chunks, & &1)

      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:ok, stream}
      end)

      result = StreamText.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.chunks_received == 4
      # Only non-nil content chunks
      assert response_data.text_chunks_received == 2
      # "Hello world"
      assert response_data.response_length == 11
      assert response_data.response_preview == "Hello world"
    end
  end

  timeout_tests(StreamText, :stream_text!)
  model_id_tests(StreamText, :stream_text!)
  behaviour_tests(StreamText)

  describe "verify/2 result format" do
    test "returns proper stream result structure" do
      model = test_model("openai", "gpt-4")

      # Test success format
      chunks = [StreamChunk.text("Test response")]
      stream = Stream.map(chunks, & &1)

      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:ok, stream}
      end)

      result = StreamText.verify(model, [])
      assert {:ok, data} = result
      assert_stream_result(data)

      # Test error format
      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:error, "Network error"}
      end)

      result = StreamText.verify(model, [])
      assert_capability_result(result, :failed, :stream_text)
    end

    test "verify/2 handles non-Stream responses gracefully" do
      model = test_model("openai", "gpt-4")

      # Test non-stream response (should not happen in practice but good to test)
      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:ok, "not a stream"}
      end)

      # This should raise a case clause error since stream_text! should always return a Stream
      assert_raise(CaseClauseError, fn ->
        StreamText.verify(model, [])
      end)
    end
  end

  describe "stream processing edge cases" do
    test "handles stream with duplicate content" do
      model = test_model("openai", "gpt-4")

      chunks = [
        StreamChunk.text("Hello"),
        # Duplicate
        StreamChunk.text("Hello"),
        StreamChunk.text(" world")
      ]

      stream = Stream.map(chunks, & &1)

      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:ok, stream}
      end)

      result = StreamText.verify(model, [])

      assert {:ok, response_data} = result
      # "HelloHello world"
      assert response_data.response_length == 16
      assert response_data.response_preview == "HelloHello world"
    end

    test "handles very long individual chunks" do
      model = test_model("openai", "gpt-4")

      # Single chunk that's very long
      long_text = String.duplicate("Very long text chunk. ", 50)
      chunks = [StreamChunk.text(long_text)]
      stream = Stream.map(chunks, & &1)

      Mimic.stub(ReqLLM, :stream_text!, fn _model, _message, _opts ->
        {:ok, stream}
      end)

      result = StreamText.verify(model, [])

      assert {:ok, response_data} = result
      assert response_data.chunks_received == 1
      assert response_data.text_chunks_received == 1
      assert response_data.response_length == String.length(long_text)
      # Preview should be truncated to 50 chars
      assert response_data.response_preview == String.slice(long_text, 0, 50)
      assert String.length(response_data.response_preview) == 50
    end


  end
end
