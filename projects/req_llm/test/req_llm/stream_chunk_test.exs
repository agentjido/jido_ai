defmodule ReqLLM.StreamChunkTest do
  use ExUnit.Case, async: true

  alias ReqLLM.StreamChunk

  describe "text/2" do
    test "creates content chunk with text" do
      chunk = StreamChunk.text("Hello")

      assert chunk.type == :content
      assert chunk.text == "Hello"
      assert chunk.metadata == %{}
      assert is_nil(chunk.name)
      assert is_nil(chunk.arguments)
    end

    test "creates content chunk with metadata" do
      metadata = %{token_count: 5, position: 1}
      chunk = StreamChunk.text("Hello world", metadata)

      assert chunk.type == :content
      assert chunk.text == "Hello world"
      assert chunk.metadata == metadata
    end

    test "handles empty and unicode text" do
      empty_chunk = StreamChunk.text("")
      unicode_chunk = StreamChunk.text("こんにちは 🌍")

      assert empty_chunk.text == ""
      assert unicode_chunk.text == "こんにちは 🌍"
    end
  end

  describe "thinking/2" do
    test "creates thinking chunk with reasoning text" do
      chunk = StreamChunk.thinking("Let me consider this...")

      assert chunk.type == :thinking
      assert chunk.text == "Let me consider this..."
      assert chunk.metadata == %{}
      assert is_nil(chunk.name)
      assert is_nil(chunk.arguments)
    end

    test "creates thinking chunk with metadata" do
      metadata = %{reasoning_step: 1, confidence: 0.8}
      chunk = StreamChunk.thinking("First, I need to...", metadata)

      assert chunk.type == :thinking
      assert chunk.text == "First, I need to..."
      assert chunk.metadata == metadata
    end

    test "handles multiline thinking content" do
      content = """
      Let me think about this step by step:
      1. First consideration
      2. Second point
      """

      chunk = StreamChunk.thinking(content)
      assert chunk.text == content
    end
  end

  describe "tool_call/3" do
    test "creates tool call chunk with name and arguments" do
      args = %{city: "New York", unit: "celsius"}
      chunk = StreamChunk.tool_call("get_weather", args)

      assert chunk.type == :tool_call
      assert chunk.name == "get_weather"
      assert chunk.arguments == args
      assert chunk.metadata == %{}
      assert is_nil(chunk.text)
    end

    test "creates tool call chunk with metadata" do
      args = %{query: "Elixir programming"}
      metadata = %{call_id: "123", partial: true}
      chunk = StreamChunk.tool_call("search_web", args, metadata)

      assert chunk.type == :tool_call
      assert chunk.name == "search_web"
      assert chunk.arguments == args
      assert chunk.metadata == metadata
    end

    test "handles empty arguments map" do
      chunk = StreamChunk.tool_call("no_args_function", %{})

      assert chunk.name == "no_args_function"
      assert chunk.arguments == %{}
    end

    test "handles complex nested arguments" do
      args = %{
        filters: %{
          location: ["US", "CA"],
          date_range: %{start: "2024-01-01", end: "2024-12-31"}
        },
        limit: 10
      }

      chunk = StreamChunk.tool_call("complex_search", args)
      assert chunk.arguments == args
    end
  end

  describe "meta/2" do
    test "creates metadata chunk" do
      data = %{finish_reason: "stop", model: "claude-3"}
      chunk = StreamChunk.meta(data)

      assert chunk.type == :meta
      assert chunk.metadata == data
      assert is_nil(chunk.text)
      assert is_nil(chunk.name)
      assert is_nil(chunk.arguments)
    end

    test "merges extra metadata" do
      base_data = %{finish_reason: "stop"}
      extra_data = %{tokens_used: 42, duration_ms: 150}
      chunk = StreamChunk.meta(base_data, extra_data)

      expected = Map.merge(base_data, extra_data)
      assert chunk.metadata == expected
    end

    test "handles usage statistics" do
      usage_data = %{
        usage: %{
          input_tokens: 100,
          output_tokens: 50,
          total_tokens: 150
        },
        finish_reason: "stop"
      }

      chunk = StreamChunk.meta(usage_data)
      assert chunk.metadata == usage_data
    end

    test "extra metadata overrides base data on conflicts" do
      base = %{priority: "low", status: "pending"}
      extra = %{priority: "high"}
      chunk = StreamChunk.meta(base, extra)

      assert chunk.metadata.priority == "high"
      assert chunk.metadata.status == "pending"
    end
  end

  describe "validate/1" do
    test "validates content chunks successfully" do
      valid_chunk = StreamChunk.text("Valid content")
      assert {:ok, ^valid_chunk} = StreamChunk.validate(valid_chunk)
    end

    test "validates thinking chunks successfully" do
      valid_chunk = StreamChunk.thinking("Valid reasoning")
      assert {:ok, ^valid_chunk} = StreamChunk.validate(valid_chunk)
    end

    test "validates tool call chunks successfully" do
      valid_chunk = StreamChunk.tool_call("func_name", %{arg: "value"})
      assert {:ok, ^valid_chunk} = StreamChunk.validate(valid_chunk)
    end

    test "validates meta chunks successfully" do
      valid_chunk = StreamChunk.meta(%{finish_reason: "stop"})
      assert {:ok, ^valid_chunk} = StreamChunk.validate(valid_chunk)
    end

    test "rejects content chunks with nil text" do
      invalid_chunk = %StreamChunk{type: :content, text: nil}

      assert {:error, "Content chunks must have non-nil text"} =
               StreamChunk.validate(invalid_chunk)
    end

    test "rejects thinking chunks with nil text" do
      invalid_chunk = %StreamChunk{type: :thinking, text: nil}

      assert {:error, "Thinking chunks must have non-nil text"} =
               StreamChunk.validate(invalid_chunk)
    end

    test "rejects tool call chunks with missing name or arguments" do
      invalid_chunk_name = %StreamChunk{type: :tool_call, name: nil, arguments: %{}}
      invalid_chunk_args = %StreamChunk{type: :tool_call, name: "func", arguments: nil}

      assert {:error, "Tool call chunks must have non-nil name and arguments"} =
               StreamChunk.validate(invalid_chunk_name)

      assert {:error, "Tool call chunks must have non-nil name and arguments"} =
               StreamChunk.validate(invalid_chunk_args)
    end

    test "rejects meta chunks with nil metadata" do
      invalid_chunk = %StreamChunk{type: :meta, metadata: nil}
      assert {:error, "Meta chunks must have metadata map"} = StreamChunk.validate(invalid_chunk)
    end

    test "rejects chunks with unknown type" do
      invalid_chunk = %StreamChunk{type: :unknown}
      assert {:error, "Unknown chunk type: :unknown"} = StreamChunk.validate(invalid_chunk)
    end
  end

  describe "struct behavior" do
    test "enforces required type field" do
      assert_raise ArgumentError, fn ->
        struct!(StreamChunk, %{text: "missing type"})
      end
    end

    test "provides default empty metadata map" do
      chunk = struct!(StreamChunk, %{type: :content, text: "test"})
      assert chunk.metadata == %{}
    end

    test "allows field access via pattern matching" do
      chunk = StreamChunk.text("test content", %{id: 123})

      assert %StreamChunk{type: :content, text: text, metadata: %{id: id}} = chunk
      assert text == "test content"
      assert id == 123
    end
  end

  describe "edge cases and boundary conditions" do
    setup do
      %{
        empty_text: "",
        long_text: String.duplicate("a", 10_000),
        unicode_text: "🚀 Testing with émojis and ñ special chars",
        whitespace_text: "   \n\t  ",
        empty_metadata: %{},
        nested_metadata: %{level1: %{level2: %{value: "deep"}}}
      }
    end

    test "handles edge case text content", %{
      empty_text: empty,
      long_text: long,
      unicode_text: unicode,
      whitespace_text: whitespace
    } do
      empty_chunk = StreamChunk.text(empty)
      long_chunk = StreamChunk.text(long)
      unicode_chunk = StreamChunk.text(unicode)
      whitespace_chunk = StreamChunk.text(whitespace)

      assert empty_chunk.text == empty
      assert long_chunk.text == long
      assert unicode_chunk.text == unicode
      assert whitespace_chunk.text == whitespace

      # All should validate successfully
      assert {:ok, _} = StreamChunk.validate(empty_chunk)
      assert {:ok, _} = StreamChunk.validate(long_chunk)
      assert {:ok, _} = StreamChunk.validate(unicode_chunk)
      assert {:ok, _} = StreamChunk.validate(whitespace_chunk)
    end

    test "handles complex metadata structures", %{nested_metadata: nested} do
      chunk = StreamChunk.text("test", nested)
      assert get_in(chunk.metadata, [:level1, :level2, :value]) == "deep"
    end

    test "preserves metadata types and structures" do
      metadata = %{
        boolean_flag: true,
        number_value: 42.5,
        list_data: [1, 2, 3],
        atom_key: :some_atom,
        datetime: ~N[2024-01-01 12:00:00]
      }

      chunk = StreamChunk.meta(metadata)
      assert chunk.metadata == metadata
    end

    test "handles tool calls with various argument types" do
      args = %{
        string: "test",
        integer: 42,
        float: 3.14,
        boolean: true,
        list: [1, 2, 3],
        map: %{nested: "value"},
        atom: :key,
        nil_value: nil
      }

      chunk = StreamChunk.tool_call("multi_type_tool", args)
      assert chunk.arguments == args
      assert {:ok, _} = StreamChunk.validate(chunk)
    end
  end
end
