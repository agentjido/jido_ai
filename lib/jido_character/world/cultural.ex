defmodule Jido.Character.World.Cultural do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, except: []}
  @primary_key false
  typed_embedded_schema do
    field(:background, :string)
    field(:norms, :map, default: %{})
    field(:references, {:array, :string}, default: [])
    field(:values, :map, default: %{})
    field(:customs, :map, default: %{})
  end

  def changeset(%__MODULE__{} = cultural, attrs) when is_map(attrs) do
    cultural
    |> cast(attrs, [:background, :norms, :references, :values, :customs])
    |> validate_required([:background])
    |> validate_map_fields()
  end

  defp validate_map_fields(changeset) do
    changeset
    |> validate_is_map(:norms)
    |> validate_is_map(:values)
    |> validate_is_map(:customs)
  end

  defp validate_is_map(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      value when not is_map(value) -> add_error(changeset, field, "must be a map")
      _ -> changeset
    end
  end
end
