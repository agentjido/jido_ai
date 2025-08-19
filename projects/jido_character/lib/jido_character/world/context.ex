defmodule Jido.Character.World.Context do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    field(:location, :string)
    field(:environment, :map, default: %{})
    field(:current_topic, :string)
    field(:last_updated_at, :utc_datetime_usec)
  end

  def changeset(%__MODULE__{} = context, attrs) when is_map(attrs) do
    context
    |> cast(attrs, [:location, :environment, :current_topic, :last_updated_at])
    |> validate_required([:last_updated_at])
    |> validate_environment()
  end

  defp validate_environment(changeset) do
    case get_field(changeset, :environment) do
      nil -> changeset
      env when not is_map(env) -> add_error(changeset, :environment, "must be a map")
      _ -> changeset
    end
  end
end
