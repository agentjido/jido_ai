defmodule Jido.Character.EvolutionTest do
  use ExUnit.Case, async: true
  alias Jido.Character.Evolution

  describe "evolution operations" do
    setup do
      temporal_state = %{
        age: 0,
        maturity: 0.7,
        stage: "growing",
        last_evolved_at: DateTime.utc_now()
      }

      growth_system = %{
        decay_rate: 0.1,
        growth_rate: 0.1,
        rules: %{
          "maturity_thresholds" => %{
            "initial" => 0.0,
            "growing" => 0.4,
            "mature" => 0.8
          }
        }
      }

      cognitive = %{
        memories: [
          %{description: "Memory 1", timestamp: DateTime.utc_now()},
          %{description: "Memory 2", timestamp: DateTime.utc_now()}
        ],
        knowledge: [
          %{fact: "Fact 1", source: "Source 1", confidence: 0.8},
          %{fact: "Fact 2", source: "Source 2", confidence: 0.9}
        ],
        emotional: %{
          mood: "happy",
          intensity: 0.7
        }
      }

      character = %{
        evolution: %Evolution{
          temporal_state: temporal_state,
          growth_system: growth_system,
          history: []
        },
        cognitive: cognitive
      }

      {:ok, character: character}
    end

    test "increment_age increases age and logs event", %{character: character} do
      changeset = Evolution.increment_age(character)
      assert changeset.changes.temporal_state.changes.age == 1
      assert length(changeset.changes.history) == 1
      [event] = changeset.changes.history
      assert event.changes.event_type == "age_increment"
      assert event.changes.metadata.amount == 1
    end

    test "increase_maturity adds maturity and logs event", %{character: character} do
      changeset = Evolution.increase_maturity(character, 0.2)
      assert_in_delta changeset.changes.temporal_state.changes.maturity, 0.9, 0.0001
      assert length(changeset.changes.history) == 2
      [event, _stage_event] = changeset.changes.history
      assert event.changes.event_type == "maturity_increase"
      assert event.changes.metadata.amount == 0.2
    end

    test "increase_maturity caps at 1.0", %{character: character} do
      changeset = Evolution.increase_maturity(character, 0.5)
      assert changeset.changes.temporal_state.changes.maturity == 1.0
    end

    test "apply_decay reduces maturity and logs event", %{character: character} do
      changeset = Evolution.apply_decay(character)
      assert changeset.changes.temporal_state.changes.maturity == 0.6
      assert length(changeset.changes.history) == 1
      [event] = changeset.changes.history
      assert event.changes.event_type == "maturity_decay"
      assert event.changes.metadata.amount == 0.1
    end

    test "apply_decay floors at 0.0", %{character: character} do
      character = put_in(character.evolution.temporal_state.maturity, 0.05)
      changeset = Evolution.apply_decay(character)
      assert changeset.changes.temporal_state.changes.maturity == 0.0
    end

    test "stage transitions occur at correct thresholds", %{character: character} do
      # Test transition to mature
      changeset = Evolution.increase_maturity(character, 0.2)
      assert changeset.changes.temporal_state.changes.stage == "mature"
      assert length(changeset.changes.history) == 2
      [_growth_event, stage_event] = changeset.changes.history
      assert stage_event.changes.event_type == "stage_transition"
      assert stage_event.changes.metadata.from_stage == "growing"
      assert stage_event.changes.metadata.to_stage == "mature"

      # Test regression to initial
      character = put_in(character.evolution.temporal_state.maturity, 0.3)
      changeset = Evolution.apply_decay(character)
      assert changeset.changes.temporal_state.changes.stage == "initial"
      assert length(changeset.changes.history) == 2
      [_decay_event, stage_event] = changeset.changes.history
      assert stage_event.changes.event_type == "stage_transition"
      assert stage_event.changes.metadata.from_stage == "growing"
      assert stage_event.changes.metadata.to_stage == "initial"
    end

    test "stage can regress through decay", %{character: character} do
      character = put_in(character.evolution.temporal_state.maturity, 0.45)
      changeset = Evolution.apply_decay(character)
      assert changeset.changes.temporal_state.changes.stage == "initial"
      assert length(changeset.changes.history) == 2
      [_decay_event, stage_event] = changeset.changes.history
      assert stage_event.changes.event_type == "stage_transition"
      assert stage_event.changes.metadata.from_stage == "growing"
      assert stage_event.changes.metadata.to_stage == "initial"
    end

    test "calculates cognitive growth correctly", %{character: character} do
      {growth_amount, factor_weights} = Evolution.calculate_cognitive_growth(character)

      # With 2 memories (2/20 = 0.1), 2 knowledge items (avg confidence 0.85),
      # and emotional intensity 0.7, we expect:
      # total_growth = (0.85 + 0.1 + 0.7) / 3 = 0.55
      assert_in_delta growth_amount, 0.55, 0.01

      # Each factor should contribute 1/3 of its score to the total
      # 0.85/3
      assert_in_delta factor_weights.knowledge, 0.283, 0.01
      # 0.1/3
      assert_in_delta factor_weights.memory, 0.033, 0.01
      # 0.7/3
      assert_in_delta factor_weights.emotional, 0.233, 0.01
    end

    test "applies cognitive growth and logs events", %{character: character} do
      changeset = Evolution.apply_cognitive_growth(character)

      # Check that maturity increased by the expected amount (capped at 1.0)
      new_maturity = changeset.changes.temporal_state.changes.maturity
      assert new_maturity == 1.0

      # Check that the event was logged correctly with the full growth amount
      assert length(changeset.changes.history) == 2
      [growth_event, _stage_event] = changeset.changes.history
      assert growth_event.changes.event_type == "cognitive_growth"
      assert_in_delta growth_event.changes.metadata.amount, 0.55, 0.01

      # Verify factor weights in metadata
      weights = growth_event.changes.metadata.factor_weights
      assert_in_delta weights.knowledge, 0.283, 0.01
      assert_in_delta weights.memory, 0.033, 0.01
      assert_in_delta weights.emotional, 0.233, 0.01
    end

    test "cognitive growth can trigger stage transitions", %{character: character} do
      # Set up character close to mature threshold
      character = put_in(character.evolution.temporal_state.maturity, 0.7)

      changeset = Evolution.apply_cognitive_growth(character)

      # Growth should push it past mature threshold
      assert changeset.changes.temporal_state.changes.stage == "mature"

      # Check that both growth and stage transition events were logged
      assert length(changeset.changes.history) == 2
      [growth_event, stage_event] = changeset.changes.history
      assert growth_event.changes.event_type == "cognitive_growth"
      assert stage_event.changes.event_type == "stage_transition"
      assert stage_event.changes.metadata.from_stage == "growing"
      assert stage_event.changes.metadata.to_stage == "mature"
    end
  end
end
