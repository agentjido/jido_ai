defmodule Jido.Character.SoulScript.Personality.RelationshipTest do
  use ExUnit.Case
  doctest Jido.Character

  alias Jido.Character.SoulScript.Personality.Relationship

  describe "relationship validation" do
    test "creates a valid relationship with required fields" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
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
        })

      assert changeset.valid?
      changes = Ecto.Changeset.apply_changes(changeset)
      assert changes.trust_level == 0.8
      assert changes.familiarity == 0.7
      assert changes.respect == 0.9
      assert length(changes.interaction_history) == 2
      assert length(changes.behavioral_adjustments) == 2
    end

    test "validates trust_level is between 0 and 1" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 1.5,
          familiarity: 0.7,
          respect: 0.9
        })

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).trust_level

      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: -0.5,
          familiarity: 0.7,
          respect: 0.9
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).trust_level
    end

    test "validates familiarity is between 0 and 1" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 0.8,
          familiarity: 1.5,
          respect: 0.9
        })

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).familiarity

      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 0.8,
          familiarity: -0.5,
          respect: 0.9
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).familiarity
    end

    test "validates respect is between 0 and 1" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 0.8,
          familiarity: 0.7,
          respect: 1.5
        })

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).respect

      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 0.8,
          familiarity: 0.7,
          respect: -0.5
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).respect
    end

    test "requires trust_level field" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          familiarity: 0.7,
          respect: 0.9
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).trust_level
    end

    test "requires familiarity field" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 0.8,
          respect: 0.9
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).familiarity
    end

    test "requires respect field" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 0.8,
          familiarity: 0.7
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).respect
    end

    test "interaction_history and behavioral_adjustments are optional" do
      changeset =
        Relationship.changeset(%Relationship{}, %{
          trust_level: 0.8,
          familiarity: 0.7,
          respect: 0.9
        })

      assert changeset.valid?
    end
  end

  # Helper function to get errors for a field
  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
