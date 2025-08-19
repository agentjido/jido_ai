defmodule Jido.Eval.Sample.SingleTurnTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jido.Eval.Sample.SingleTurn
  alias Jido.AI.Message

  doctest SingleTurn

  describe "new/1" do
    test "creates a valid single-turn sample" do
      attrs = %{
        user_input: "Hello",
        response: "Hi there!",
        tags: %{"category" => "greeting"}
      }

      assert {:ok, sample} = SingleTurn.new(attrs)
      assert sample.user_input == "Hello"
      assert sample.response == "Hi there!"
      assert sample.tags == %{"category" => "greeting"}
    end

    test "creates a sample with Message structs" do
      user_msg = %Message{role: :user, content: "Hello"}
      response_msg = %Message{role: :assistant, content: "Hi!"}

      attrs = %{user_input: user_msg, response: response_msg}

      assert {:ok, sample} = SingleTurn.new(attrs)
      assert sample.user_input == user_msg
      assert sample.response == response_msg
    end

    test "rejects sample without user_input or response" do
      attrs = %{id: "test"}

      assert {:error, reason} = SingleTurn.new(attrs)
      assert reason == "Sample must have either user_input or response"
    end

    test "accepts sample with only user_input" do
      attrs = %{user_input: "Hello"}
      assert {:ok, _sample} = SingleTurn.new(attrs)
    end

    test "accepts sample with only response" do
      attrs = %{response: "Hello"}
      assert {:ok, _sample} = SingleTurn.new(attrs)
    end
  end

  describe "validate/1" do
    test "validates sample with user_input" do
      sample = %SingleTurn{user_input: "Hello"}
      assert :ok = SingleTurn.validate(sample)
    end

    test "validates sample with response" do
      sample = %SingleTurn{response: "Hello"}
      assert :ok = SingleTurn.validate(sample)
    end

    test "rejects empty sample" do
      sample = %SingleTurn{}
      assert {:error, _reason} = SingleTurn.validate(sample)
    end
  end

  describe "to_messages/1" do
    test "converts string user_input to Message" do
      sample = %SingleTurn{user_input: "Hello"}
      converted = SingleTurn.to_messages(sample)

      assert %Message{role: :user, content: "Hello"} = converted.user_input
    end

    test "converts string response to Message" do
      sample = %SingleTurn{response: "Hi there!"}
      converted = SingleTurn.to_messages(sample)

      assert %Message{role: :assistant, content: "Hi there!"} = converted.response
    end

    test "leaves Message structs unchanged" do
      user_msg = %Message{role: :user, content: "Hello"}
      sample = %SingleTurn{user_input: user_msg}
      converted = SingleTurn.to_messages(sample)

      assert converted.user_input == user_msg
    end

    test "handles nil values" do
      sample = %SingleTurn{user_input: nil}
      converted = SingleTurn.to_messages(sample)

      assert converted.user_input == nil
    end
  end

  describe "to_strings/1" do
    test "converts Message user_input to string" do
      user_msg = %Message{role: :user, content: "Hello"}
      sample = %SingleTurn{user_input: user_msg}
      converted = SingleTurn.to_strings(sample)

      assert converted.user_input == "Hello"
    end

    test "converts Message response to string" do
      response_msg = %Message{role: :assistant, content: "Hi!"}
      sample = %SingleTurn{response: response_msg}
      converted = SingleTurn.to_strings(sample)

      assert converted.response == "Hi!"
    end

    test "leaves string values unchanged" do
      sample = %SingleTurn{user_input: "Hello"}
      converted = SingleTurn.to_strings(sample)

      assert converted.user_input == "Hello"
    end

    test "handles nil values" do
      sample = %SingleTurn{response: nil}
      converted = SingleTurn.to_strings(sample)

      assert converted.response == nil
    end
  end

  describe "to_map/1 and from_map/1" do
    test "round-trip conversion preserves data" do
      original = %SingleTurn{
        id: "test_001",
        user_input: "What is AI?",
        retrieved_contexts: ["context1", "context2"],
        reference_contexts: ["ref1"],
        response: "AI is artificial intelligence",
        multi_responses: ["AI is...", "Artificial intelligence is..."],
        reference: "AI stands for artificial intelligence",
        rubrics: %{"accuracy" => "high", "relevance" => "good"},
        tags: %{"category" => "general", "difficulty" => "easy"}
      }

      map = SingleTurn.to_map(original)
      assert {:ok, restored} = SingleTurn.from_map(map)

      assert restored.id == original.id
      assert restored.user_input == original.user_input
      assert restored.retrieved_contexts == original.retrieved_contexts
      assert restored.reference_contexts == original.reference_contexts
      assert restored.response == original.response
      assert restored.multi_responses == original.multi_responses
      assert restored.reference == original.reference
      assert restored.rubrics == original.rubrics
      assert restored.tags == original.tags
    end

    test "to_map excludes nil fields" do
      sample = %SingleTurn{
        id: "test",
        user_input: "Hello",
        response: nil,
        reference: nil
      }

      map = SingleTurn.to_map(sample)

      refute Map.has_key?(map, :response)
      refute Map.has_key?(map, :reference)
      assert map.id == "test"
      assert map.user_input == "Hello"
      # tags should always be present (empty map)
      assert Map.has_key?(map, :tags)
    end

    test "from_map handles string keys" do
      map = %{
        "id" => "test",
        "user_input" => "Hello",
        "tags" => %{"key" => "value"}
      }

      assert {:ok, sample} = SingleTurn.from_map(map)
      assert sample.id == "test"
      assert sample.user_input == "Hello"
      assert sample.tags == %{"key" => "value"}
    end

    test "from_map converts message maps to structs" do
      map = %{
        user_input: %{role: :user, content: "Hello"},
        response: %{role: :assistant, content: "Hi!"}
      }

      assert {:ok, sample} = SingleTurn.from_map(map)
      assert %Message{role: :user, content: "Hello"} = sample.user_input
      assert %Message{role: :assistant, content: "Hi!"} = sample.response
    end

    test "from_map handles invalid data" do
      map = %{}

      assert {:error, _reason} = SingleTurn.from_map(map)
    end
  end

  describe "property tests" do
    property "round-trip serialization preserves valid samples" do
      check all(
              id <- string(:alphanumeric, min_length: 1, max_length: 50),
              user_input <- string(:printable, min_length: 1, max_length: 200),
              response <- string(:printable, min_length: 1, max_length: 200),
              max_runs: 100
            ) do
        original = %SingleTurn{
          id: id,
          user_input: user_input,
          response: response,
          tags: %{"test" => "property"}
        }

        map = SingleTurn.to_map(original)
        assert {:ok, restored} = SingleTurn.from_map(map)

        assert restored.id == original.id
        assert restored.user_input == original.user_input
        assert restored.response == original.response
        assert restored.tags == original.tags
      end
    end

    property "samples with either user_input or response are valid" do
      check all(
              has_input <- boolean(),
              has_response <- boolean(),
              input <- string(:printable, min_length: 1, max_length: 100),
              response <- string(:printable, min_length: 1, max_length: 100),
              max_runs: 50
            ) do
        # Ensure at least one field is present
        {user_input, response_field} =
          case {has_input, has_response} do
            # Force at least user_input
            {false, false} -> {input, nil}
            {true, false} -> {input, nil}
            {false, true} -> {nil, response}
            {true, true} -> {input, response}
          end

        attrs = %{user_input: user_input, response: response_field}
        assert {:ok, sample} = SingleTurn.new(attrs)
        assert :ok = SingleTurn.validate(sample)
      end
    end
  end

  describe "edge cases" do
    test "handles very long strings" do
      long_string = String.duplicate("a", 10_000)

      attrs = %{user_input: long_string}
      assert {:ok, sample} = SingleTurn.new(attrs)
      assert sample.user_input == long_string
    end

    test "handles unicode content" do
      unicode_input = "Hello 世界 🌍"
      attrs = %{user_input: unicode_input}

      assert {:ok, sample} = SingleTurn.new(attrs)
      assert sample.user_input == unicode_input
    end

    test "handles empty tags map" do
      attrs = %{user_input: "Hello", tags: %{}}
      assert {:ok, sample} = SingleTurn.new(attrs)
      assert sample.tags == %{}
    end

    test "handles large context lists" do
      large_contexts = Enum.map(1..1000, &"context_#{&1}")

      attrs = %{
        user_input: "Hello",
        retrieved_contexts: large_contexts
      }

      assert {:ok, sample} = SingleTurn.new(attrs)
      assert length(sample.retrieved_contexts) == 1000
    end
  end
end
