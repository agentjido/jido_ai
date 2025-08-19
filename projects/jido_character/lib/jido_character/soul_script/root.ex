defmodule Jido.Character.SoulScript.Root do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:version, :id, :entity, :personality]}
  @primary_key false
  typed_embedded_schema do
    field(:version, :string)
    field(:id, :string)

    embeds_one(:entity, Jido.Character.SoulScript.Entity, on_replace: :update)
    embeds_one(:personality, Jido.Character.SoulScript.Personality, on_replace: :update)
  end

  def changeset(soul_script, attrs) do
    soul_script
    |> cast(attrs, [:version, :id])
    |> cast_embed(:entity)
    |> cast_embed(:personality)
    |> validate_required([:version, :id])
  end
end
