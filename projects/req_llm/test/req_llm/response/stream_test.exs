defmodule ReqLLM.Response.StreamTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Response.Stream

  describe "parse_events/1" do
    test "parses OpenAI delta events with content only" do
      events = [
        %{data: ~s({"choices":[{"delta":{"content":"Hello"}}]})},
        %{data: ~s({"choices":[{"delta":{"content":" world"}}]})},
        %{data: "[DONE]"}
      ]

      assert ["Hello", " world"] = Stream.parse_events(events)
    end

    test "parses OpenAI delta events with reasoning only" do
      events = [
        %{data: ~s({"choices":[{"delta":{"reasoning":"I should"}}]})},
        %{data: ~s({"choices":[{"delta":{"reasoning":" be helpful"}}]})},
        %{data: "[DONE]"}
      ]

      assert ["🧠 I should", "🧠  be helpful"] = Stream.parse_events(events)
    end

    test "parses OpenAI delta events with reasoning and content" do
      events = [
        %{data: ~s({"choices":[{"delta":{"reasoning":"User greeted me"}}]})},
        %{data: ~s({"choices":[{"delta":{"content":"Hello"}}]})},
        %{data: ~s({"choices":[{"delta":{"content":" world"}}]})},
        %{data: "[DONE]"}
      ]

      assert ["🧠 User greeted me", "Hello", " world"] = Stream.parse_events(events)
    end

    test "parses OpenAI delta events with mixed reasoning and content" do
      events = [
        %{data: ~s({"choices":[{"delta":{"reasoning":"Thinking","content":"Hello"}}]})},
        %{data: "[DONE]"}
      ]

      assert ["🧠 Thinking\nHello"] = Stream.parse_events(events)
    end

    test "parses Anthropic content_block_delta events with text" do
      events = [
        %{data: ~s({"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}})},
        %{data: ~s({"type":"content_block_delta","delta":{"type":"text_delta","text":" world"}})},
        %{data: "[DONE]"}
      ]

      assert ["Hello", " world"] = Stream.parse_events(events)
    end

    test "parses Anthropic content_block_delta events with thinking" do
      events = [
        %{
          data:
            ~s({"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"User greeted"}})
        },
        %{data: ~s({"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}})},
        %{data: "[DONE]"}
      ]

      assert ["🧠 User greeted", "Hello"] = Stream.parse_events(events)
    end

    test "ignores empty deltas" do
      events = [
        %{data: ~s({"choices":[{"delta":{}}]})},
        %{data: ~s({"choices":[{"delta":{"content":"Hello"}}]})},
        %{data: "[DONE]"}
      ]

      assert ["Hello"] = Stream.parse_events(events)
    end

    test "ignores invalid JSON events" do
      events = [
        %{data: "invalid json"},
        %{data: ~s({"choices":[{"delta":{"content":"Hello"}}]})},
        %{data: "[DONE]"}
      ]

      assert ["Hello"] = Stream.parse_events(events)
    end

    test "ignores unknown event types" do
      events = [
        %{data: ~s({"unknown": "event"})},
        %{data: ~s({"choices":[{"delta":{"content":"Hello"}}]})},
        %{data: "[DONE]"}
      ]

      assert ["Hello"] = Stream.parse_events(events)
    end

    test "handles empty events list" do
      assert [] = Stream.parse_events([])
    end
  end
end
