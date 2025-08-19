defmodule Jido.Character.Cognitive do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:memories, :knowledge, :emotional]}
  typed_embedded_schema do
    embeds_many(:memories, Jido.Character.Cognitive.Memory, on_replace: :delete)
    embeds_many(:knowledge, Jido.Character.Cognitive.Knowledge, on_replace: :delete)
    embeds_one(:emotional, Jido.Character.Cognitive.Emotional, on_replace: :update)
  end

  def changeset(cognitive, attrs) when is_map(attrs) do
    cognitive
    |> cast(attrs, [])
    |> cast_embed(:memories)
    |> cast_embed(:knowledge)
    |> cast_embed(:emotional)
  end

  def add_memory(cognitive, description) do
    memory = %{
      description: description,
      timestamp: DateTime.utc_now()
    }

    changeset(cognitive, %{
      memories: [memory | Enum.map(cognitive.memories || [], &Map.from_struct/1)]
    })
  end

  def add_knowledge(cognitive, fact, source \\ nil, confidence \\ 0.75) do
    knowledge = %{
      fact: fact,
      source: source,
      confidence: confidence
    }

    changeset(cognitive, %{
      knowledge: [knowledge | Enum.map(cognitive.knowledge || [], &Map.from_struct/1)]
    })
  end

  def update_emotional(cognitive, mood, intensity \\ 0.5) do
    changeset(cognitive, %{
      emotional: %{
        mood: mood,
        intensity: intensity
      }
    })
  end

  def find_memories_by_pattern(cognitive, pattern) do
    Enum.filter(cognitive.memories || [], &String.contains?(&1.description, pattern))
  end

  def find_knowledge_by_pattern(cognitive, pattern) do
    Enum.filter(cognitive.knowledge || [], &String.contains?(&1.fact, pattern))
  end

  def get_current_mood(cognitive) do
    case cognitive.emotional do
      nil -> nil
      emotional -> {emotional.mood, emotional.intensity}
    end
  end
end
