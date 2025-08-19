defmodule Jido.Character.SoulScriptRoot do
  use TypedEctoSchema
  import Ecto.Changeset

  @primary_key false
  typed_embedded_schema do
    field(:version, :string)
    field(:id, :string)

    embeds_one(:entity, Jido.Character.SoulScript.Entity)
    embeds_one(:personality, Jido.Character.SoulScript.Personality)
  end

  def changeset(soul_script, attrs) do
    soul_script
    |> cast(attrs, [:version, :id])
    |> cast_embed(:entity)
    |> cast_embed(:personality)
    |> validate_required([:version, :id])
  end
end
