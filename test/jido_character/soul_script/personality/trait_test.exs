defmodule Jido.Character.SoulScript.Personality.TraitTest do
  use ExUnit.Case
  doctest Jido.Character

  alias Jido.Character.SoulScript.Personality.Trait

  describe "trait validation" do
    test "creates a valid trait with required fields" do
      changeset =
        Trait.changeset(%Trait{}, %{
          trait: "curious",
          strength: 0.8,
          expression_rules: ["Asks many questions", "Shows interest in new topics"]
        })

      assert changeset.valid?
      changes = Ecto.Changeset.apply_changes(changeset)
      assert changes.trait == "curious"
      assert changes.strength == 0.8
      assert changes.expression_rules == ["Asks many questions", "Shows interest in new topics"]
    end

    test "validates strength is between 0 and 1" do
      changeset =
        Trait.changeset(%Trait{}, %{
          trait: "curious",
          strength: 1.5,
          expression_rules: ["Asks many questions"]
        })

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).strength

      changeset =
        Trait.changeset(%Trait{}, %{
          trait: "curious",
          strength: -0.5,
          expression_rules: ["Asks many questions"]
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).strength
    end

    test "requires trait field" do
      changeset =
        Trait.changeset(%Trait{}, %{
          strength: 0.8,
          expression_rules: ["Asks many questions"]
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).trait
    end

    test "requires strength field" do
      changeset =
        Trait.changeset(%Trait{}, %{
          trait: "curious",
          expression_rules: ["Asks many questions"]
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).strength
    end

    test "expression_rules is optional" do
      changeset =
        Trait.changeset(%Trait{}, %{
          trait: "curious",
          strength: 0.8
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
