defmodule Jido.Character.CognitiveTest do
  use ExUnit.Case, async: true
  alias Jido.Character.Cognitive
  alias Jido.Character.Cognitive.{Memory, Knowledge, Emotional}

  describe "cognitive operations" do
    setup do
      cognitive = %Cognitive{
        memories: [
          %Memory{
            description: "first test memory",
            timestamp: DateTime.utc_now(),
            importance: 0.8,
            tags: ["test", "memory"]
          }
        ],
        knowledge: [
          %Knowledge{
            fact: "testing is important",
            source: "experience",
            confidence: 0.9,
            category: "software",
            learned_at: DateTime.utc_now()
          }
        ],
        emotional: %Emotional{
          mood: "curious",
          intensity: 0.7,
          last_changed_at: DateTime.utc_now(),
          secondary_moods: ["excited"]
        }
      }

      {:ok, cognitive: cognitive}
    end

    test "validates memory", %{cognitive: cognitive} do
      changeset =
        Cognitive.add_memory(cognitive, "new test memory")

      assert changeset.valid?
      [new_memory | _] = changeset.changes.memories
      assert new_memory.changes.description == "new test memory"
      assert %DateTime{} = new_memory.changes.timestamp
    end

    test "rejects invalid memory importance", %{cognitive: _cognitive} do
      changeset =
        Memory.changeset(%Memory{}, %{
          description: "test memory",
          importance: 2.0
        })

      refute changeset.valid?
      assert {"must be less than or equal to %{number}", _} = changeset.errors[:importance]
    end

    test "validates knowledge", %{cognitive: cognitive} do
      changeset =
        Cognitive.add_knowledge(cognitive, "new fact", "testing", 0.8)

      assert changeset.valid?
      [new_knowledge | _] = changeset.changes.knowledge
      assert new_knowledge.changes.fact == "new fact"
      assert new_knowledge.changes.source == "testing"
      assert new_knowledge.changes.confidence == 0.8
    end

    test "rejects invalid knowledge confidence", %{cognitive: _cognitive} do
      changeset =
        Knowledge.changeset(%Knowledge{}, %{
          fact: "test fact",
          confidence: -0.1
        })

      refute changeset.valid?
      assert {"must be greater than or equal to %{number}", _} = changeset.errors[:confidence]
    end

    test "validates emotional state", %{cognitive: cognitive} do
      changeset =
        Cognitive.update_emotional(cognitive, "happy", 0.9)

      assert changeset.valid?
      assert changeset.changes.emotional.changes.mood == "happy"
      assert changeset.changes.emotional.changes.intensity == 0.9
      assert %DateTime{} = changeset.changes.emotional.changes.last_changed_at
    end

    test "rejects invalid mood", %{cognitive: _cognitive} do
      changeset =
        Emotional.changeset(%Emotional{}, %{
          mood: "invalid_mood",
          intensity: 0.5
        })

      refute changeset.valid?
      assert {"is invalid", _} = changeset.errors[:mood]
    end

    test "finds memories by pattern", %{cognitive: cognitive} do
      memories = Cognitive.find_memories_by_pattern(cognitive, "test")
      assert length(memories) == 1
      [memory] = memories
      assert memory.description == "first test memory"
    end

    test "finds knowledge by pattern", %{cognitive: cognitive} do
      knowledge = Cognitive.find_knowledge_by_pattern(cognitive, "testing")
      assert length(knowledge) == 1
      [fact] = knowledge
      assert fact.fact == "testing is important"
    end

    test "gets current mood", %{cognitive: cognitive} do
      assert {"curious", 0.7} = Cognitive.get_current_mood(cognitive)
    end

    test "validates secondary moods", %{cognitive: _cognitive} do
      changeset =
        Emotional.changeset(%Emotional{}, %{
          mood: "happy",
          intensity: 0.5,
          secondary_moods: ["calm", "content"]
        })

      assert changeset.valid?
      assert changeset.changes.secondary_moods == ["calm", "content"]
    end

    test "rejects invalid secondary moods", %{cognitive: _cognitive} do
      changeset =
        Emotional.changeset(%Emotional{}, %{
          mood: "happy",
          intensity: 0.5,
          secondary_moods: ["invalid_mood"]
        })

      refute changeset.valid?
      assert {"contains invalid moods", []} = changeset.errors[:secondary_moods]
    end
  end
end
