defmodule Jido.Character.SoulScript.Personality.Relationship do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder,
           only: [
             :trust_level,
             :familiarity,
             :respect,
             :interaction_history,
             :behavioral_adjustments
           ]}
  @primary_key false
  typed_embedded_schema do
    field(:trust_level, :float)
    field(:familiarity, :float)
    field(:respect, :float)
    field(:interaction_history, {:array, :string}, default: [])
    field(:behavioral_adjustments, {:array, :string}, default: [])
  end

  def changeset(relationship, attrs) do
    relationship
    |> cast(attrs, [
      :trust_level,
      :familiarity,
      :respect,
      :interaction_history,
      :behavioral_adjustments
    ])
    |> validate_required([:trust_level, :familiarity, :respect])
    |> validate_number(:trust_level, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:familiarity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:respect, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
