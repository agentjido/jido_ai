defmodule Jido.Character.SoulScript.Personality.Trait do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:trait, :strength, :expression_rules]}
  @primary_key false
  typed_embedded_schema do
    field(:trait, :string)
    field(:strength, :float)
    field(:expression_rules, {:array, :string}, default: [])
  end

  def changeset(trait, attrs) do
    trait
    |> cast(attrs, [:trait, :strength, :expression_rules])
    |> validate_required([:trait, :strength])
    |> validate_number(:strength, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
