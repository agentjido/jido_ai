defmodule ReqLLM.Collections.EnumerableTest do
  use ExUnit.Case, async: true

  import ReqLLM.Test.Factory

  alias ReqLLM.{Message, Messages, ContentPart}

  # Parameterized helper for testing Enum behavior across different collections
  defp assert_enum_behaviour(collection, expected_items, context \\ %{}) do
    # Basic protocol operations
    assert Enum.count(collection) == length(expected_items)
    assert Enum.to_list(collection) == expected_items

    # Member operations
    if expected_items != [] do
      first_item = hd(expected_items)
      assert Enum.member?(collection, first_item)

      # Test with item that shouldn't exist based on context
      non_member = context[:non_member] || create_non_member(first_item)
      refute Enum.member?(collection, non_member)
    end

    # Transformation operations
    mapped = Enum.map(collection, &extract_key(&1, context[:map_key] || :default))
    assert length(mapped) == length(expected_items)

    # Filtering operations
    if context[:filter_predicate] do
      filtered = Enum.filter(collection, context[:filter_predicate])
      expected_filtered = Enum.filter(expected_items, context[:filter_predicate])
      assert filtered == expected_filtered
    end

    # Reduction operations
    count = Enum.reduce(collection, 0, fn _, acc -> acc + 1 end)
    assert count == length(expected_items)

    # Slicing operations
    if length(expected_items) > 1 do
      slice_count = min(2, length(expected_items))
      sliced = Enum.slice(collection, 0, slice_count)
      expected_slice = Enum.slice(expected_items, 0, slice_count)
      assert sliced == expected_slice
    end

    # Search operations
    if expected_items != [] && context[:find_predicate] do
      found = Enum.find(collection, context[:find_predicate])
      expected_found = Enum.find(expected_items, context[:find_predicate])
      assert found == expected_found
    end
  end

  # Helper to create non-member items for testing
  defp create_non_member(%Message{}), do: user_msg("Non-existent message")
  defp create_non_member(%ContentPart{}), do: text_part("Non-existent part")
  defp create_non_member(item) when is_binary(item), do: "Non-existent string"
  defp create_non_member(_), do: :non_existent

  # Helper to extract keys for mapping tests
  defp extract_key(%Message{role: role}, :role), do: role
  defp extract_key(%Message{content: content}, :content), do: content
  defp extract_key(%ContentPart{type: type}, :type), do: type
  defp extract_key(item, :default) when is_binary(item), do: String.upcase(item)
  defp extract_key(item, :default), do: item

  describe "Message Enumerable - String Content" do
    test "comprehensive enum behavior with string content" do
      message = user_msg("Hello world")
      expected_items = ["Hello world"]

      context = %{
        non_member: "Other text",
        map_key: :default,
        filter_predicate: &String.contains?(&1, "Hello"),
        find_predicate: &String.contains?(&1, "world")
      }

      assert_enum_behaviour(message, expected_items, context)
    end

    test "empty string handling" do
      # Note: Factory doesn't create empty messages as they're invalid
      # This tests the enumerable behavior conceptually
      message = %Message{role: :user, content: "X"}

      # Test map with empty result
      result = Enum.map(message, fn _ -> "" end)
      assert result == [""]

      # Test filter that returns empty
      result = Enum.filter(message, fn _ -> false end)
      assert result == []
    end

    test "stream compatibility" do
      message = user_msg("Hello world")

      # Test that Message works with Stream operations
      result =
        message
        |> Enum.map(&String.upcase/1)
        |> Enum.filter(&String.contains?(&1, "HELLO"))

      assert result == ["HELLO WORLD"]
    end
  end

  describe "Message Enumerable - List Content" do
    setup do
      content_parts = [
        text_part("Hello"),
        image_part("https://example.com/image.png"),
        text_part("World")
      ]

      message = user_msg(content_parts)
      {:ok, message: message, content_parts: content_parts}
    end

    test "comprehensive enum behavior with content parts", %{
      message: message,
      content_parts: content_parts
    } do
      context = %{
        non_member: text_part("Non-existent"),
        map_key: :type,
        filter_predicate: &(&1.type == :text),
        find_predicate: &(&1.type == :image_url)
      }

      assert_enum_behaviour(message, content_parts, context)
    end

    test "complex content part operations", %{message: message} do
      # Test complex reduction
      text_length =
        Enum.reduce(message, 0, fn part, acc ->
          case part do
            %{type: :text, text: text} -> acc + String.length(text)
            _ -> acc
          end
        end)

      # "Hello" + "World"
      assert text_length == 10

      # Test with_index
      indexed = Enum.with_index(message)
      assert length(indexed) == 3
      assert {%ContentPart{type: :text}, 0} = hd(indexed)

      # Test zip operations
      types = Enum.map(message, & &1.type)
      zipped = Enum.zip(message, types)
      assert length(zipped) == 3
    end
  end

  describe "Messages Collection Enumerable" do
    setup do
      messages = [
        system_msg("You are a helpful assistant"),
        user_msg("Hello!"),
        assistant_msg("Hi there!"),
        user_msg("How are you?")
      ]

      collection = Messages.new(messages)
      {:ok, collection: collection, messages: messages}
    end

    test "comprehensive enum behavior", %{collection: collection, messages: messages} do
      context = %{
        non_member: user_msg("Non-existent message"),
        map_key: :role,
        filter_predicate: &(&1.role == :user),
        find_predicate: &(&1.role == :assistant)
      }

      assert_enum_behaviour(collection, messages, context)
    end

    test "advanced collection operations", %{collection: collection} do
      # Test grouping by role
      grouped = Enum.group_by(collection, & &1.role)
      assert Map.has_key?(grouped, :system)
      assert Map.has_key?(grouped, :user)
      assert Map.has_key?(grouped, :assistant)
      assert length(grouped[:user]) == 2

      # Test sorting by content length
      sorted = Enum.sort_by(collection, &String.length(&1.content))
      contents = Enum.map(sorted, & &1.content)

      # Should be sorted by length: "Hello!", "Hi there!", "How are you?", "You are..."
      assert String.length(hd(contents)) <= String.length(List.last(contents))

      # Test chunk operations
      chunks = Enum.chunk_every(collection, 2)
      assert length(chunks) == 2
      assert length(hd(chunks)) == 2
    end

    test "nested enumeration patterns", %{collection: collection} do
      # Test flat mapping over message content
      all_content =
        Enum.flat_map(collection, fn message ->
          case message.content do
            content when is_binary(content) -> [content]
            content when is_list(content) -> Enum.map(content, &(&1.text || ""))
          end
        end)

      assert length(all_content) == 4
      assert "Hello!" in all_content
    end

    test "empty collection behavior" do
      empty_collection = Messages.new([])
      assert_enum_behaviour(empty_collection, [])

      # Test operations on empty collection
      assert Enum.empty?(empty_collection)
      assert Enum.map(empty_collection, & &1.role) == []
      assert Enum.filter(empty_collection, fn _ -> true end) == []
      assert Enum.reduce(empty_collection, 0, fn _, acc -> acc + 1 end) == 0
    end
  end

  describe "Messages Collection - Collectable Protocol" do
    test "into/1 creates Messages collection" do
      messages = [user_msg("Hello"), assistant_msg("Hi")]

      # Test collecting into Messages
      result = Enum.into(messages, Messages.new([]))
      assert %Messages{} = result
      assert Enum.to_list(result) == messages
    end

    test "collecting with transformation" do
      strings = ["Hello", "Hi", "How are you?"]

      # Collect strings into Messages by transforming them
      result =
        strings
        |> Stream.with_index()
        |> Enum.into(Messages.new([]), fn {content, index} ->
          role = if rem(index, 2) == 0, do: :user, else: :assistant
          %Message{role: role, content: content, metadata: %{}}
        end)

      assert %Messages{} = result
      assert Enum.count(result) == 3

      roles = Enum.map(result, & &1.role)
      assert roles == [:user, :assistant, :user]
    end

    test "collecting from other enumerables" do
      # Test collecting from various enumerable sources
      range_messages =
        1..3
        |> Enum.into(Messages.new([]), fn i ->
          user_msg("Message #{i}")
        end)

      assert Enum.count(range_messages) == 3
      contents = Enum.map(range_messages, & &1.content)
      assert contents == ["Message 1", "Message 2", "Message 3"]
    end

    test "collecting with filtering" do
      all_messages = [
        user_msg("Hello"),
        system_msg("System message"),
        user_msg("World"),
        assistant_msg("Assistant message")
      ]

      # Collect only user messages
      user_only =
        all_messages
        |> Stream.filter(&(&1.role == :user))
        |> Enum.into(Messages.new([]))

      assert Enum.count(user_only) == 2
      assert Enum.all?(user_only, &(&1.role == :user))
    end
  end

  describe "Complex Usage Patterns" do
    test "chaining enumerable operations across Message and Messages" do
      # Create a message with multiple content parts
      multimodal_message =
        user_msg([
          text_part("Analyze this:"),
          image_part("https://example.com/chart.png"),
          text_part("What do you see?")
        ])

      # Create a messages collection
      collection =
        Messages.new([
          system_msg("You are an image analyzer"),
          multimodal_message,
          assistant_msg("I can analyze images for you")
        ])

      # Complex chaining: find messages with images and extract text content
      text_from_image_messages =
        collection
        |> Enum.filter(fn message ->
          case message.content do
            content when is_list(content) ->
              Enum.any?(content, &(&1.type == :image_url))

            _ ->
              false
          end
        end)
        |> Enum.flat_map(fn message ->
          message.content
          |> Enum.filter(&(&1.type == :text))
          |> Enum.map(& &1.text)
        end)

      assert text_from_image_messages == ["Analyze this:", "What do you see?"]
    end

    test "stream processing for large collections" do
      # Create a large collection for stream processing
      large_messages = Enum.map(1..1000, &user_msg("Message #{&1}"))
      collection = Messages.new(large_messages)

      # Use streams for memory-efficient processing
      result =
        collection
        |> Stream.filter(&String.contains?(&1.content, "10"))
        |> Stream.map(&String.length(&1.content))
        |> Enum.sum()

      # Should process messages containing "10" efficiently
      assert result > 0
    end

    test "protocol integration with third-party enumerables" do
      # Test that our collections work with other Enum-compatible libraries
      messages = [user_msg("A"), user_msg("B"), user_msg("C")]
      collection = Messages.new(messages)

      # Test with Range
      indexed_messages = Enum.zip(collection, 1..3)
      assert length(indexed_messages) == 3

      # Test comprehensions
      content_lengths = for message <- collection, do: String.length(message.content)
      assert content_lengths == [1, 1, 1]
    end
  end

  describe "Enumerable Protocol Edge Cases" do
    test "handles halt and suspend in reduce" do
      collection = Messages.new([user_msg("A"), user_msg("B"), user_msg("C")])

      # Test early halt
      {:halted, result} =
        Enumerable.reduce(collection, {:halt, []}, fn item, acc ->
          {:cont, [item | acc]}
        end)

      assert result == []

      # Test suspend (should be supported by our implementation)
      {:suspended, acc, continuation} =
        Enumerable.reduce(collection, {:suspend, []}, fn item, acc ->
          {:cont, [item | acc]}
        end)

      assert acc == []
      assert is_function(continuation)
    end

    test "slice implementation with various ranges" do
      messages = [
        user_msg("First"),
        assistant_msg("Second"),
        user_msg("Third"),
        assistant_msg("Fourth")
      ]

      collection = Messages.new(messages)

      # Test various slice operations
      assert Enum.slice(collection, 1, 2) == Enum.slice(messages, 1, 2)
      assert Enum.slice(collection, -2, 2) == Enum.slice(messages, -2, 2)
      assert Enum.slice(collection, 0..1) == Enum.slice(messages, 0..1)
      assert Enum.slice(collection, 1..-1//1) == Enum.slice(messages, 1..-1//1)
    end
  end
end
