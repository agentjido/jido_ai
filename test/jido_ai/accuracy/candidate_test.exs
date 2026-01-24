defmodule Jido.AI.Accuracy.CandidateTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Candidate

  describe "new/1" do
    test "creates valid candidate with content only" do
      assert {:ok, candidate} = Candidate.new(%{content: "The answer is 42"})

      assert is_binary(candidate.id)
      assert String.starts_with?(candidate.id, "candidate_")
      assert candidate.content == "The answer is 42"
      assert candidate.score == nil
      assert candidate.reasoning == nil
      assert candidate.tokens_used == nil
      assert candidate.model == nil
      assert candidate.timestamp != nil
      assert candidate.metadata == %{}
    end

    test "creates valid candidate with all fields" do
      assert {:ok, candidate} =
               Candidate.new(%{
                 content: "The answer is 42",
                 reasoning: "Let me calculate step by step...",
                 score: 0.95,
                 tokens_used: 150,
                 model: "anthropic:claude-haiku-4-5",
                 metadata: %{temperature: 0.7}
               })

      assert candidate.content == "The answer is 42"
      assert candidate.reasoning == "Let me calculate step by step..."
      assert candidate.score == 0.95
      assert candidate.tokens_used == 150
      assert candidate.model == "anthropic:claude-haiku-4-5"
      assert candidate.metadata == %{temperature: 0.7}
    end

    test "auto-generates UUID when id not provided" do
      assert {:ok, c1} = Candidate.new(%{content: "A"})
      assert {:ok, c2} = Candidate.new(%{content: "B"})

      assert c1.id != c2.id
      assert String.starts_with?(c1.id, "candidate_")
      assert String.starts_with?(c2.id, "candidate_")
    end

    test "uses provided id when given" do
      assert {:ok, candidate} = Candidate.new(%{content: "Test", id: "custom_id_123"})
      assert candidate.id == "custom_id_123"
    end

    test "auto-generates timestamp when not provided" do
      assert {:ok, candidate} = Candidate.new(%{content: "Test"})

      assert %DateTime{} = candidate.timestamp
      assert DateTime.compare(candidate.timestamp, DateTime.utc_now()) in [:lt, :eq]
    end

    test "uses provided timestamp when given" do
      timestamp = DateTime.utc_now() |> DateTime.add(-3600)

      assert {:ok, candidate} = Candidate.new(%{content: "Test", timestamp: timestamp})
      assert DateTime.compare(candidate.timestamp, timestamp) == :eq
    end

    test "uses empty map as default metadata" do
      assert {:ok, candidate} = Candidate.new(%{content: "Test"})
      assert candidate.metadata == %{}
    end

    test "accepts custom metadata" do
      metadata = %{temperature: 0.7, top_p: 0.9}

      assert {:ok, candidate} = Candidate.new(%{content: "Test", metadata: metadata})
      assert candidate.metadata == metadata
    end
  end

  describe "new!/1" do
    test "returns candidate when valid" do
      candidate = Candidate.new!(%{content: "Test"})
      assert candidate.content == "Test"
    end

    test "raises when not a map" do
      assert_raise ArgumentError, ~r/Invalid candidate/, fn ->
        Candidate.new!(nil)
      end
    end
  end

  describe "update_score/2" do
    test "updates score and returns updated struct" do
      {:ok, candidate} = Candidate.new(%{content: "Test"})

      updated = Candidate.update_score(candidate, 0.85)

      assert updated.score == 0.85
      assert updated.content == "Test"
      assert updated.id == candidate.id
    end

    test "replaces existing score" do
      {:ok, candidate} = Candidate.new(%{content: "Test", score: 0.5})

      updated = Candidate.update_score(candidate, 0.9)

      assert updated.score == 0.9
    end

    test "accepts negative scores" do
      {:ok, candidate} = Candidate.new(%{content: "Test"})

      updated = Candidate.update_score(candidate, -0.5)

      assert updated.score == -0.5
    end

    test "accepts zero score" do
      {:ok, candidate} = Candidate.new(%{content: "Test"})

      updated = Candidate.update_score(candidate, 0)

      assert updated.score == 0
    end
  end

  describe "to_map/1" do
    test "serializes candidate to map with string keys" do
      {:ok, candidate} = Candidate.new(%{content: "Test"})

      map = Candidate.to_map(candidate)

      assert is_map(map)
      assert map["content"] == "Test"
      assert is_binary(map["id"])
      assert is_binary(map["timestamp"])
    end

    test "serializes all fields" do
      timestamp = DateTime.utc_now()

      {:ok, candidate} =
        Candidate.new(%{
          content: "Answer",
          reasoning: "Because...",
          score: 0.9,
          tokens_used: 100,
          model: "test:model",
          timestamp: timestamp,
          metadata: %{key: "value"}
        })

      map = Candidate.to_map(candidate)

      assert map["content"] == "Answer"
      assert map["reasoning"] == "Because..."
      assert map["score"] == 0.9
      assert map["tokens_used"] == 100
      assert map["model"] == "test:model"
      assert map["timestamp"] == DateTime.to_iso8601(timestamp)
      assert map["metadata"] == %{key: "value"}
    end

    test "handles nil fields correctly" do
      {:ok, candidate} = Candidate.new(%{content: "Test"})

      map = Candidate.to_map(candidate)

      assert map["reasoning"] == nil
      assert map["score"] == nil
      assert map["tokens_used"] == nil
      assert map["model"] == nil
    end
  end

  describe "from_map/1" do
    test "deserializes map with string keys to candidate" do
      map = %{
        "content" => "Hello",
        "id" => "test_123",
        "timestamp" => "2024-01-01T00:00:00Z"
      }

      assert {:ok, candidate} = Candidate.from_map(map)
      assert candidate.content == "Hello"
      assert candidate.id == "test_123"
    end

    test "deserializes map with atom keys" do
      map = %{
        content: "Hello",
        id: "test_456"
      }

      assert {:ok, candidate} = Candidate.from_map(map)
      assert candidate.content == "Hello"
      assert candidate.id == "test_456"
    end

    test "deserializes all fields" do
      map = %{
        "content" => "Answer",
        "reasoning" => "Because...",
        "score" => 0.9,
        "tokens_used" => 100,
        "model" => "test:model",
        "id" => "test_789",
        "metadata" => %{key: "value"}
      }

      assert {:ok, candidate} = Candidate.from_map(map)

      assert candidate.content == "Answer"
      assert candidate.reasoning == "Because..."
      assert candidate.score == 0.9
      assert candidate.tokens_used == 100
      assert candidate.model == "test:model"
      assert candidate.id == "test_789"
      assert candidate.metadata == %{key: "value"}
    end

    test "handles invalid timestamp gracefully" do
      map = %{
        "content" => "Test",
        "timestamp" => "not-a-timestamp"
      }

      assert {:ok, candidate} = Candidate.from_map(map)
      assert candidate.timestamp == nil
    end

    test "handles empty string timestamp" do
      map = %{
        "content" => "Test",
        "timestamp" => ""
      }

      assert {:ok, candidate} = Candidate.from_map(map)
      assert candidate.timestamp == nil
    end

    test "handles nil timestamp" do
      map = %{
        "content" => "Test",
        "timestamp" => nil
      }

      assert {:ok, candidate} = Candidate.from_map(map)
      assert candidate.timestamp == nil
    end

    test "returns error for invalid map" do
      assert {:error, :invalid_map} = Candidate.from_map("not a map")
      assert {:error, :invalid_map} = Candidate.from_map(123)
    end
  end

  describe "from_map!/1" do
    test "returns candidate when map is valid" do
      map = %{"content" => "Test"}

      candidate = Candidate.from_map!(map)
      assert candidate.content == "Test"
    end

    test "raises when map is invalid" do
      assert_raise ArgumentError, ~r/Invalid candidate map/, fn ->
        Candidate.from_map!("not a map")
      end
    end
  end

  describe "serialization round-trip" do
    test "to_map and from_map are inverses" do
      {:ok, original} =
        Candidate.new(%{
          content: "Full answer",
          reasoning: "Step by step",
          score: 0.95,
          tokens_used: 200,
          model: "test:model",
          metadata: %{temp: 0.8}
        })

      map = Candidate.to_map(original)
      assert {:ok, restored} = Candidate.from_map(map)

      assert restored.content == original.content
      assert restored.reasoning == original.reasoning
      assert restored.score == original.score
      assert restored.tokens_used == original.tokens_used
      assert restored.model == original.model
      assert restored.id == original.id
      assert restored.metadata == original.metadata
    end

    test "round-trip with minimal fields" do
      {:ok, original} = Candidate.new(%{content: "Simple"})

      map = Candidate.to_map(original)
      assert {:ok, restored} = Candidate.from_map(map)

      assert restored.content == original.content
      assert restored.id == original.id
    end
  end

  describe "timestamp handling" do
    test "timestamp is serialized to ISO8601 string" do
      timestamp = DateTime.from_unix!(1_700_000_000)

      {:ok, candidate} = Candidate.new(%{content: "Test", timestamp: timestamp})

      map = Candidate.to_map(candidate)
      assert map["timestamp"] == DateTime.to_iso8601(timestamp)
    end

    test "ISO8601 string is deserialized to DateTime" do
      map = %{
        "content" => "Test",
        "timestamp" => "2023-11-14T22:13:20Z"
      }

      assert {:ok, candidate} = Candidate.from_map(map)

      assert %DateTime{} = candidate.timestamp
      assert DateTime.to_iso8601(candidate.timestamp) == "2023-11-14T22:13:20Z"
    end
  end
end
