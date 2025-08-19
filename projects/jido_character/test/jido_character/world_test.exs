defmodule Jido.Character.WorldTest do
  use ExUnit.Case, async: true
  alias Jido.Character.World

  describe "world operations" do
    setup do
      context = %World.Context{
        location: "virtual space",
        environment: %{
          "weather" => "sunny",
          "time_of_day" => "morning"
        },
        current_topic: "testing",
        last_updated_at: DateTime.utc_now()
      }

      social = [
        %World.Social{
          relationship_type: "friend",
          target_id: "user123",
          trust_level: 0.8,
          familiarity: 0.6,
          last_interaction_at: DateTime.utc_now(),
          metadata: %{
            "shared_interests" => ["coding", "testing"]
          }
        },
        %World.Social{
          relationship_type: "colleague",
          target_id: "user456",
          trust_level: 0.5,
          familiarity: 0.3,
          last_interaction_at: DateTime.utc_now(),
          metadata: %{}
        }
      ]

      cultural = %World.Cultural{
        background: "digital native",
        norms: %{
          "communication_style" => "formal",
          "greeting" => "Hello!"
        },
        references: ["internet culture", "programming", "tech community"],
        values: %{
          "privacy" => "high",
          "collaboration" => "essential"
        },
        customs: %{
          "code_review" => "mandatory",
          "testing" => "thorough"
        }
      }

      world = %World{
        context: context,
        social: social,
        cultural: cultural
      }

      {:ok, world: world}
    end

    test "validates context", %{world: world} do
      changeset =
        World.changeset(world, %{
          context: %{
            location: "new location",
            environment: %{"weather" => "rainy"},
            current_topic: "new topic",
            last_updated_at: DateTime.utc_now()
          }
        })

      assert changeset.valid?
      context_changes = changeset.changes.context.changes
      assert context_changes.location == "new location"
      assert context_changes.environment == %{"weather" => "rainy"}
    end

    test "validates social relationships", %{world: world} do
      changeset =
        World.changeset(world, %{
          social: [
            %{
              relationship_type: "colleague",
              target_id: "user456",
              trust_level: 0.7,
              familiarity: 0.3,
              last_interaction_at: DateTime.utc_now()
            }
          ]
        })

      assert changeset.valid?
      social_change = Enum.find(changeset.changes.social, &(&1.changes[:target_id] == "user456"))
      assert social_change.changes.relationship_type == "colleague"
      assert social_change.changes.target_id == "user456"
    end

    test "validates cultural background", %{world: world} do
      changeset =
        World.changeset(world, %{
          cultural: %{
            background: "tech enthusiast",
            norms: %{"communication_style" => "casual"},
            references: ["tech culture"],
            values: %{"innovation" => "high"},
            customs: %{"daily_standups" => "required"}
          }
        })

      assert changeset.valid?
      cultural_changes = changeset.changes.cultural.changes
      assert cultural_changes.background == "tech enthusiast"
    end

    test "rejects invalid relationship type", %{world: world} do
      changeset =
        World.changeset(world, %{
          social: [
            %{
              relationship_type: "invalid_type",
              target_id: "user789"
            }
          ]
        })

      refute changeset.valid?
      social_change = Enum.find(changeset.changes.social, &(&1.changes[:target_id] == "user789"))

      assert {"is invalid", [validation: :inclusion, enum: _]} =
               social_change.errors[:relationship_type]
    end

    test "rejects invalid trust level", %{world: world} do
      changeset =
        World.changeset(world, %{
          social: [
            %{
              relationship_type: "friend",
              target_id: "user789",
              trust_level: 2.0
            }
          ]
        })

      refute changeset.valid?
      social_change = Enum.find(changeset.changes.social, &(&1.changes[:target_id] == "user789"))
      assert {"must be less than or equal to %{number}", _} = social_change.errors[:trust_level]
    end

    test "requires context last_updated_at", %{world: world} do
      changeset =
        World.changeset(world, %{
          context: %{
            location: "new location",
            environment: %{},
            last_updated_at: nil
          }
        })

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.changes.context.errors[:last_updated_at]
    end

    test "requires cultural background", %{world: world} do
      changeset =
        World.changeset(world, %{
          cultural: %{
            background: nil,
            norms: %{},
            references: []
          }
        })

      refute changeset.valid?
      assert {"can't be blank", _} = changeset.changes.cultural.errors[:background]
    end

    test "updates context with new data", %{world: world} do
      changeset =
        World.update_context(world, "new location", %{"weather" => "rainy"}, "new topic")

      assert changeset.valid?
      context_changes = changeset.changes.context.changes
      assert context_changes.location == "new location"
      assert context_changes.environment == %{"weather" => "rainy"}
      assert context_changes.current_topic == "new topic"
      assert %DateTime{} = context_changes.last_updated_at
    end

    test "finds relationships by type", %{world: world} do
      relationships = World.find_relationships_by_type(world, "friend")
      assert length(relationships) == 1
      [friend] = relationships
      assert friend.target_id == "user123"
    end

    test "finds relationship by target", %{world: world} do
      relationship = World.find_relationship(world, "user456")
      assert relationship.relationship_type == "colleague"
    end

    test "records interaction with trust and familiarity changes", %{world: world} do
      changeset =
        World.record_interaction(world, "user123",
          trust_change: 0.1,
          familiarity_increase: 0.2
        )

      assert changeset.valid?
      social_change = Enum.find(changeset.changes.social, &(&1.changes[:target_id] == "user123"))
      assert_in_delta social_change.changes.trust_level, 0.9, 0.0001
      assert_in_delta social_change.changes.familiarity, 0.8, 0.0001
      assert %DateTime{} = social_change.changes.last_interaction_at
    end

    test "handles interaction with unknown target", %{world: world} do
      result = World.record_interaction(world, "unknown_user")
      assert result == {:error, :relationship_not_found}
    end

    test "gets cultural norm value", %{world: world} do
      assert World.get_cultural_norm(world, "communication_style") == "formal"
      assert World.get_cultural_norm(world, "nonexistent") == nil
    end

    test "gets cultural custom value", %{world: world} do
      assert World.get_cultural_custom(world, "code_review") == "mandatory"
      assert World.get_cultural_custom(world, "nonexistent") == nil
    end

    test "finds cultural references by pattern", %{world: world} do
      refs = World.find_cultural_references(world, "tech")
      assert length(refs) == 1
      assert hd(refs) == "tech community"
    end

    test "checks cultural background match", %{world: world} do
      assert World.matches_cultural_background?(world, "digital")
      refute World.matches_cultural_background?(world, "analog")
    end

    test "gets current environment", %{world: world} do
      env = World.current_environment(world)
      assert env["weather"] == "sunny"
      assert env["time_of_day"] == "morning"
    end
  end
end
