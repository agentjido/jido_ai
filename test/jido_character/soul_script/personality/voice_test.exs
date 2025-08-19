defmodule Jido.Character.SoulScript.Personality.VoiceTest do
  use ExUnit.Case
  doctest Jido.Character

  alias Jido.Character.SoulScript.Personality.Voice

  describe "voice validation" do
    test "creates a valid voice with required fields" do
      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          formality: 0.7,
          verbosity: 0.6,
          expression_patterns: [
            "Uses warm and welcoming language",
            "Maintains professional courtesy while being approachable"
          ]
        })

      assert changeset.valid?
      changes = Ecto.Changeset.apply_changes(changeset)
      assert changes.tone == "friendly"
      assert changes.formality == 0.7
      assert changes.verbosity == 0.6
      assert length(changes.expression_patterns) == 2
    end

    test "validates formality is between 0 and 1" do
      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          formality: 1.5,
          verbosity: 0.6
        })

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).formality

      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          formality: -0.5,
          verbosity: 0.6
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).formality
    end

    test "validates verbosity is between 0 and 1" do
      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          formality: 0.7,
          verbosity: 1.5
        })

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).verbosity

      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          formality: 0.7,
          verbosity: -0.5
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).verbosity
    end

    test "requires tone field" do
      changeset =
        Voice.changeset(%Voice{}, %{
          formality: 0.7,
          verbosity: 0.6
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).tone
    end

    test "requires formality field" do
      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          verbosity: 0.6
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).formality
    end

    test "requires verbosity field" do
      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          formality: 0.7
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).verbosity
    end

    test "expression_patterns is optional" do
      changeset =
        Voice.changeset(%Voice{}, %{
          tone: "friendly",
          formality: 0.7,
          verbosity: 0.6
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
