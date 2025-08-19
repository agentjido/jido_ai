defmodule Jido.Character.SoulScript.Personality.ValueTest do
  use ExUnit.Case
  doctest Jido.Character

  alias Jido.Character.SoulScript.Personality.Value

  describe "value validation" do
    test "creates a valid value with required fields" do
      changeset =
        Value.changeset(%Value{}, %{
          value: "honesty",
          importance: 0.9,
          expression_rules: ["Always tells the truth", "Admits mistakes openly"]
        })

      assert changeset.valid?
      changes = Ecto.Changeset.apply_changes(changeset)
      assert changes.value == "honesty"
      assert changes.importance == 0.9
      assert changes.expression_rules == ["Always tells the truth", "Admits mistakes openly"]
    end

    test "validates importance is between 0 and 1" do
      changeset =
        Value.changeset(%Value{}, %{
          value: "honesty",
          importance: 1.5,
          expression_rules: ["Always tells the truth"]
        })

      refute changeset.valid?
      assert "must be less than or equal to 1" in errors_on(changeset).importance

      changeset =
        Value.changeset(%Value{}, %{
          value: "honesty",
          importance: -0.5,
          expression_rules: ["Always tells the truth"]
        })

      refute changeset.valid?
      assert "must be greater than or equal to 0" in errors_on(changeset).importance
    end

    test "requires value field" do
      changeset =
        Value.changeset(%Value{}, %{
          importance: 0.8,
          expression_rules: ["Always tells the truth"]
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).value
    end

    test "requires importance field" do
      changeset =
        Value.changeset(%Value{}, %{
          value: "honesty",
          expression_rules: ["Always tells the truth"]
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).importance
    end

    test "expression_rules is optional" do
      changeset =
        Value.changeset(%Value{}, %{
          value: "honesty",
          importance: 0.8
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
