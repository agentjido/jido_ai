defmodule Jido.Character.World.Social do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    field(:relationship_type, :string)
    field(:target_id, :string)
    field(:trust_level, :float, default: 0.5)
    field(:familiarity, :float, default: 0.0)
    field(:last_interaction_at, :utc_datetime_usec)
    field(:metadata, :map, default: %{})
  end

  @relationship_types ~w(friend family colleague acquaintance rival ally enemy)

  def changeset(%__MODULE__{} = social, attrs) when is_map(attrs) do
    social
    |> cast(attrs, [
      :relationship_type,
      :target_id,
      :trust_level,
      :familiarity,
      :last_interaction_at,
      :metadata
    ])
    |> validate_required([:relationship_type, :target_id])
    |> validate_inclusion(:relationship_type, @relationship_types)
    |> validate_number(:trust_level, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_number(:familiarity, greater_than_or_equal_to: 0.0, less_than_or_equal_to: 1.0)
    |> validate_metadata()
  end

  defp validate_metadata(changeset) do
    case get_field(changeset, :metadata) do
      nil -> changeset
      metadata when not is_map(metadata) -> add_error(changeset, :metadata, "must be a map")
      _ -> changeset
    end
  end
end
