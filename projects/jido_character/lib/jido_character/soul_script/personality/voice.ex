defmodule Jido.Character.SoulScript.Personality.Voice do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:tone, :formality, :verbosity, :expression_patterns]}
  @primary_key false
  typed_embedded_schema do
    field(:tone, :string)
    field(:formality, :float)
    field(:verbosity, :float)
    field(:expression_patterns, {:array, :string}, default: [])
  end

  def changeset(voice, attrs) do
    voice
    |> cast(attrs, [:tone, :formality, :verbosity, :expression_patterns])
    |> validate_required([:tone, :formality, :verbosity])
    |> validate_number(:formality, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_number(:verbosity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
