defmodule Jido.Character.SoulScript.Entity do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:form, :occupation, :gender, :age, :background, :expertise]}
  @primary_key false
  typed_embedded_schema do
    field(:form, :string)
    field(:occupation, :string)
    field(:gender, :string)
    field(:age, :string)
    field(:background, :string)
    field(:expertise, {:array, :string})
  end

  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:form, :occupation, :gender, :age, :background, :expertise])
    |> validate_required([:form])
  end
end
