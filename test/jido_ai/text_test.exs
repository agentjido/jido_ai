defmodule Jido.AI.TurnTextTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Turn

  describe "extract_text/1" do
    test "returns binary strings unchanged" do
      assert Turn.extract_text("hello world") == "hello world"
      assert Turn.extract_text("") == ""
    end

    test "returns empty string for nil" do
      assert Turn.extract_text(nil) == ""
    end

    test "extracts from standard ReqLLM response shape" do
      response = %{message: %{content: "Hello from LLM"}}
      assert Turn.extract_text(response) == "Hello from LLM"
    end

    test "extracts from response with content blocks" do
      response = %{
        message: %{
          content: [
            %{type: :text, text: "Part 1"},
            %{type: :text, text: "Part 2"}
          ]
        }
      }

      assert Turn.extract_text(response) == "Part 1\nPart 2"
    end

    test "filters non-text blocks" do
      response = %{
        message: %{
          content: [
            %{type: :text, text: "Text content"},
            %{type: :tool_use, id: "123", name: "test"},
            %{type: :text, text: "more text"}
          ]
        }
      }

      assert Turn.extract_text(response) == "Text content\nmore text"
    end

    test "handles string type in content blocks" do
      response = %{
        message: %{
          content: [
            %{type: "text", text: "String type"}
          ]
        }
      }

      assert Turn.extract_text(response) == "String type"
    end

    test "extracts from OpenAI-style response shape" do
      response = %{
        choices: [
          %{message: %{content: "OpenAI response"}}
        ]
      }

      assert Turn.extract_text(response) == "OpenAI response"
    end

    test "handles OpenAI response with content blocks" do
      response = %{
        choices: [
          %{
            message: %{
              content: [
                %{type: :text, text: "Block 1"},
                %{type: :text, text: "Block 2"}
              ]
            }
          }
        ]
      }

      assert Turn.extract_text(response) == "Block 1\nBlock 2"
    end

    test "handles nil content in message" do
      response = %{message: %{content: nil}}
      assert Turn.extract_text(response) == ""
    end

    test "handles empty content list" do
      response = %{message: %{content: []}}
      assert Turn.extract_text(response) == ""
    end

    test "returns empty string for unknown map shapes" do
      assert Turn.extract_text(%{foo: "bar"}) == ""
      assert Turn.extract_text(%{other: %{stuff: "here"}}) == ""
    end

    test "handles iodata lists" do
      assert Turn.extract_text(["hello", " ", "world"]) == "hello world"
      assert Turn.extract_text([?h, ?i]) == "hi"
      assert Turn.extract_text([["nested"], " ", "list"]) == "nested list"
    end

    test "returns empty string for non-matching values" do
      assert Turn.extract_text(123) == ""
      assert Turn.extract_text(:atom) == ""
      assert Turn.extract_text({:tuple}) == ""
    end

    test "extracts from map with direct content key" do
      response = %{content: "Direct content"}
      assert Turn.extract_text(response) == "Direct content"
    end
  end

  describe "extract_from_content/1" do
    test "returns binary strings unchanged" do
      assert Turn.extract_from_content("hello") == "hello"
    end

    test "returns empty string for nil" do
      assert Turn.extract_from_content(nil) == ""
    end

    test "extracts text from content blocks" do
      content = [
        %{type: :text, text: "First"},
        %{type: :text, text: "Second"}
      ]

      assert Turn.extract_from_content(content) == "First\nSecond"
    end

    test "handles iodata" do
      assert Turn.extract_from_content(["a", "b", "c"]) == "abc"
    end

    test "returns empty string for unknown values" do
      assert Turn.extract_from_content(123) == ""
      assert Turn.extract_from_content(:atom) == ""
    end
  end
end
