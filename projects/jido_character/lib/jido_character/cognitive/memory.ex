defmodule Jido.Character.Cognitive.Memory do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:description, :timestamp, :importance, :tags]}
  typed_embedded_schema do
    field(:description, :string)
    field(:timestamp, :utc_datetime_usec)
    field(:importance, :float, default: 0.5)
    field(:tags, {:array, :string}, default: [])
  end

  def changeset(%__MODULE__{} = memory, attrs) when is_map(attrs) do
    memory
    |> cast(attrs, [:description, :timestamp, :importance, :tags])
    |> validate_required([:description])
    |> validate_number(:importance, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
  end
end
