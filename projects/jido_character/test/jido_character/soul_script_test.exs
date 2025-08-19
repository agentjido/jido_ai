defmodule Jido.Character.SoulScriptTest do
  use ExUnit.Case
  doctest Jido.Character

  alias Jido.Character.SoulScript.Root, as: SoulScriptRoot

  describe "SoulScript core structure" do
    test "creates a valid character with basic SoulScript fields" do
      changeset =
        Jido.Character.changeset(%Jido.Character{}, %{
          id: "char-1",
          soulscript: %{
            version: "1.0",
            id: "test-soul-1",
            entity: %{
              form: "human",
              occupation: "developer",
              gender: "female",
              age: "30",
              background: "Tech enthusiast",
              expertise: ["coding", "testing"]
            },
            personality: %{
              name: "Test Character",
              core_traits: [
                %{
                  trait: "curious",
                  strength: 0.8,
                  expression_rules: ["Asks many questions", "Shows interest in new topics"]
                },
                %{
                  trait: "analytical",
                  strength: 0.9,
                  expression_rules: ["Breaks down problems", "Seeks logical explanations"]
                }
              ],
              values: [
                %{
                  value: "honesty",
                  importance: 0.9,
                  expression_rules: ["Always tells the truth", "Admits mistakes openly"]
                },
                %{
                  value: "innovation",
                  importance: 0.8,
                  expression_rules: ["Seeks creative solutions", "Embraces new technologies"]
                }
              ],
              voice: %{
                tone: "friendly",
                formality: 0.7,
                verbosity: 0.6,
                expression_patterns: [
                  "Uses warm and welcoming language",
                  "Maintains professional courtesy while being approachable"
                ]
              },
              relationship: %{
                trust_level: 0.8,
                familiarity: 0.7,
                respect: 0.9,
                interaction_history: [
                  "First met during project collaboration",
                  "Worked together on multiple successful projects"
                ],
                behavioral_adjustments: [
                  "Shows more patience when explaining technical concepts",
                  "Maintains professional boundaries while being friendly"
                ]
              }
            }
          }
        })

      assert changeset.valid?

      # Verify the SoulScript fields are properly set
      changes = Ecto.Changeset.apply_changes(changeset)
      assert %SoulScriptRoot{} = changes.soulscript
      assert changes.soulscript.version == "1.0"
      assert changes.soulscript.id == "test-soul-1"

      # Verify entity fields
      assert changes.soulscript.entity.form == "human"
      assert changes.soulscript.entity.occupation == "developer"
      assert changes.soulscript.entity.expertise == ["coding", "testing"]

      # Verify personality fields
      assert changes.soulscript.personality.name == "Test Character"
      assert length(changes.soulscript.personality.core_traits) == 2
      assert length(changes.soulscript.personality.values) == 2

      # Verify first trait
      [trait1, trait2] = changes.soulscript.personality.core_traits
      assert trait1.trait == "curious"
      assert trait1.strength == 0.8
      assert trait1.expression_rules == ["Asks many questions", "Shows interest in new topics"]

      # Verify second trait
      assert trait2.trait == "analytical"
      assert trait2.strength == 0.9
      assert trait2.expression_rules == ["Breaks down problems", "Seeks logical explanations"]

      # Verify first value
      [value1, value2] = changes.soulscript.personality.values
      assert value1.value == "honesty"
      assert value1.importance == 0.9
      assert value1.expression_rules == ["Always tells the truth", "Admits mistakes openly"]

      # Verify second value
      assert value2.value == "innovation"
      assert value2.importance == 0.8
      assert value2.expression_rules == ["Seeks creative solutions", "Embraces new technologies"]

      # Verify voice
      voice = changes.soulscript.personality.voice
      assert voice.tone == "friendly"
      assert voice.formality == 0.7
      assert voice.verbosity == 0.6
      assert length(voice.expression_patterns) == 2

      # Verify relationship
      relationship = changes.soulscript.personality.relationship
      assert relationship.trust_level == 0.8
      assert relationship.familiarity == 0.7
      assert relationship.respect == 0.9
      assert length(relationship.interaction_history) == 2
      assert length(relationship.behavioral_adjustments) == 2
    end

    test "validates trait strength constraints" do
      changeset =
        Jido.Character.changeset(%Jido.Character{}, %{
          id: "char-1",
          soulscript: %{
            version: "1.0",
            id: "test-soul-1",
            entity: %{
              form: "human"
            },
            personality: %{
              name: "Test Character",
              core_traits: [
                %{
                  trait: "invalid",
                  # Invalid: greater than 1
                  strength: 1.5
                }
              ]
            }
          }
        })

      refute changeset.valid?

      # Get the nested error
      error =
        Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
          Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
            opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
          end)
        end)

      assert get_in(error, [:soulscript, :personality, :core_traits]) != nil
    end
  end
end
