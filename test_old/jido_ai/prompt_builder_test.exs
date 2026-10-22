defmodule Jido.AI.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias Jido.AI.PromptBuilder

  describe "build/2" do
    test "returns message unchanged when sections list is empty" do
      assert PromptBuilder.build("Hello", []) == "Hello"
    end

    test "returns message unchanged when all sections are nil" do
      assert PromptBuilder.build("Hello", [
               {:memory_context, nil},
               {:known_facts, nil}
             ]) == "Hello"
    end

    test "returns message unchanged when all sections are empty strings" do
      assert PromptBuilder.build("Hello", [
               {:memory_context, ""},
               {:known_facts, "  "}
             ]) == "Hello"
    end

    test "wraps a single section in XML tags" do
      result = PromptBuilder.build("What is 2+2?", [{:memory_context, "User likes math"}])

      assert result ==
               "<memory_context>\nUser likes math\n</memory_context>\n\nWhat is 2+2?"
    end

    test "wraps multiple sections in order" do
      result =
        PromptBuilder.build("Hello", [
          {:memory_context, "memory stuff"},
          {:known_facts, "fact 1\nfact 2"},
          {:previous_errors, "Turn 1: error"}
        ])

      assert result ==
               "<memory_context>\nmemory stuff\n</memory_context>\n\n" <>
                 "<known_facts>\nfact 1\nfact 2\n</known_facts>\n\n" <>
                 "<previous_errors>\nTurn 1: error\n</previous_errors>\n\n" <>
                 "Hello"
    end

    test "skips nil sections in the middle" do
      result =
        PromptBuilder.build("Hello", [
          {:memory_context, "memories"},
          {:known_facts, nil},
          {:previous_errors, "errors"}
        ])

      assert result ==
               "<memory_context>\nmemories\n</memory_context>\n\n" <>
                 "<previous_errors>\nerrors\n</previous_errors>\n\n" <>
                 "Hello"
    end

    test "returns non-string messages as-is" do
      assert PromptBuilder.build(42, [{:memory_context, "stuff"}]) == 42
      assert PromptBuilder.build(nil, [{:memory_context, "stuff"}]) == nil
    end

    test "supports custom tag names" do
      result =
        PromptBuilder.build("query", [{:retrieved_documents, "doc content"}])

      assert result ==
               "<retrieved_documents>\ndoc content\n</retrieved_documents>\n\nquery"
    end
  end

  describe "wrap_xml/2" do
    test "wraps content in XML tags" do
      assert PromptBuilder.wrap_xml(:test_tag, "content") ==
               "<test_tag>\ncontent\n</test_tag>"
    end
  end
end
