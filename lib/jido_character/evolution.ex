defmodule Jido.Character.Evolution do
  use TypedEctoSchema
  import Ecto.Changeset

  alias Jido.Character.Evolution.{TemporalState, GrowthSystem, History}

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    embeds_one(:temporal_state, TemporalState, on_replace: :update)
    embeds_one(:growth_system, GrowthSystem, on_replace: :update)
    embeds_many(:history, History)
  end

  def changeset(evolution, attrs) do
    evolution
    |> cast(attrs, [])
    |> cast_embed(:temporal_state)
    |> cast_embed(:growth_system)
    |> cast_embed(:history)
  end

  def increment_age(character) do
    temporal_state = character.evolution.temporal_state
    now = DateTime.utc_now()
    new_age = temporal_state.age + 1

    history_event = %{
      event_type: "age_increment",
      description: "Character aged from #{temporal_state.age} to #{new_age}",
      timestamp: now,
      previous_state: %{age: temporal_state.age},
      new_state: %{age: new_age},
      metadata: %{amount: 1}
    }

    attrs = %{
      temporal_state: %{
        age: new_age,
        maturity: temporal_state.maturity,
        stage: temporal_state.stage,
        last_evolved_at: now
      },
      history: character.evolution.history ++ [history_event]
    }

    changeset(character.evolution, attrs)
  end

  def increase_maturity(character, amount) when is_float(amount) and amount > 0 do
    temporal_state = character.evolution.temporal_state
    now = DateTime.utc_now()
    new_maturity = min(temporal_state.maturity + amount, 1.0)

    history_event = %{
      event_type: "maturity_increase",
      description:
        "Character maturity increased from #{temporal_state.maturity} to #{new_maturity}",
      timestamp: now,
      previous_state: %{maturity: temporal_state.maturity},
      new_state: %{maturity: new_maturity},
      metadata: %{amount: amount}
    }

    {stage_event, new_stage} = check_stage_transition(temporal_state, new_maturity)

    history_events = if stage_event, do: [history_event, stage_event], else: [history_event]

    attrs = %{
      temporal_state: %{
        age: temporal_state.age,
        maturity: new_maturity,
        stage: new_stage || temporal_state.stage,
        last_evolved_at: now
      },
      history: character.evolution.history ++ history_events
    }

    changeset(character.evolution, attrs)
  end

  def apply_decay(character) do
    temporal_state = character.evolution.temporal_state
    growth_system = character.evolution.growth_system
    now = DateTime.utc_now()
    decay_amount = growth_system.decay_rate || 0.1
    new_maturity = max(temporal_state.maturity - decay_amount, 0.0)

    history_event = %{
      event_type: "maturity_decay",
      description:
        "Character maturity decayed from #{temporal_state.maturity} to #{new_maturity}",
      timestamp: now,
      previous_state: %{maturity: temporal_state.maturity},
      new_state: %{maturity: new_maturity},
      metadata: %{amount: decay_amount}
    }

    {stage_event, new_stage} = check_stage_transition(temporal_state, new_maturity)

    history_events = if stage_event, do: [history_event, stage_event], else: [history_event]

    attrs = %{
      temporal_state: %{
        age: temporal_state.age,
        maturity: new_maturity,
        stage: new_stage || temporal_state.stage,
        last_evolved_at: now
      },
      history: character.evolution.history ++ history_events
    }

    changeset(character.evolution, attrs)
  end

  def calculate_cognitive_growth(character) do
    cognitive = character.cognitive
    knowledge_score = calculate_knowledge_score(cognitive.knowledge)
    memory_score = calculate_memory_score(cognitive.memories)
    emotional_score = calculate_emotional_score(cognitive.emotional)

    total_growth = (knowledge_score + memory_score + emotional_score) / 3.0

    factor_weights = %{
      knowledge: knowledge_score / 3.0,
      memory: memory_score / 3.0,
      emotional: emotional_score / 3.0
    }

    {total_growth, factor_weights}
  end

  def apply_cognitive_growth(character) do
    {growth_amount, factor_weights} = calculate_cognitive_growth(character)
    temporal_state = character.evolution.temporal_state
    now = DateTime.utc_now()

    # Apply growth amount directly without any scaling
    new_maturity = min(temporal_state.maturity + growth_amount, 1.0)

    history_event = %{
      event_type: "cognitive_growth",
      description: "Character maturity increased through cognitive growth",
      timestamp: now,
      previous_state: %{maturity: temporal_state.maturity},
      new_state: %{maturity: new_maturity},
      metadata: %{
        amount: growth_amount,
        factor_weights: factor_weights
      }
    }

    {stage_event, new_stage} = check_stage_transition(temporal_state, new_maturity)

    history_events = if stage_event, do: [history_event, stage_event], else: [history_event]

    attrs = %{
      temporal_state: %{
        age: temporal_state.age,
        maturity: new_maturity,
        stage: new_stage || temporal_state.stage,
        last_evolved_at: now
      },
      history: character.evolution.history ++ history_events
    }

    changeset(character.evolution, attrs)
  end

  defp calculate_knowledge_score(knowledge) when is_list(knowledge) do
    total_confidence = Enum.reduce(knowledge, 0.0, fn k, acc -> acc + (k.confidence || 0.75) end)
    knowledge_count = length(knowledge)
    if knowledge_count > 0, do: total_confidence / knowledge_count, else: 0.0
  end

  defp calculate_memory_score(memories) when is_list(memories) do
    memory_count = length(memories)
    # Scale memory score based on count, max out at 20 memories
    (memory_count / 20.0) |> min(1.0)
  end

  defp calculate_emotional_score(emotional) do
    emotional.intensity
  end

  defp check_stage_transition(current_state, new_maturity) do
    current_stage = current_state.stage

    new_stage =
      cond do
        new_maturity >= 0.8 -> "mature"
        new_maturity >= 0.4 -> "growing"
        true -> "initial"
      end

    if new_stage != current_stage do
      {create_stage_event(current_stage, new_stage), new_stage}
    else
      {nil, current_stage}
    end
  end

  defp create_stage_event(previous_stage, new_stage) do
    %{
      event_type: "stage_transition",
      description: "Character evolved from #{previous_stage} to #{new_stage}",
      timestamp: DateTime.utc_now(),
      previous_state: %{stage: previous_stage},
      new_state: %{stage: new_stage},
      metadata: %{
        from_stage: previous_stage,
        to_stage: new_stage
      }
    }
  end
end
