defmodule Jido.Character.SoulScript.Personality.Value do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:value, :importance, :expression_rules]}
  @primary_key false
  typed_embedded_schema do
    field(:value, :string)
    field(:importance, :float)
    field(:expression_rules, {:array, :string}, default: [])
  end

  def changeset(value, attrs) do
    value
    |> cast(attrs, [:value, :importance, :expression_rules])
    |> validate_required([:value, :importance])
    |> validate_number(:importance, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
