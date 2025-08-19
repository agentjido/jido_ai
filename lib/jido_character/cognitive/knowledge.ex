defmodule Jido.Character.Cognitive.Knowledge do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:fact, :source, :confidence, :category, :learned_at]}
  typed_embedded_schema do
    field(:fact, :string)
    field(:source, :string)
    field(:confidence, :float, default: 0.75)
    field(:category, :string)
    field(:learned_at, :utc_datetime_usec, default: nil)
  end

  def changeset(%__MODULE__{} = knowledge, attrs) when is_map(attrs) do
    knowledge
    |> cast(attrs, [:fact, :source, :confidence, :category, :learned_at])
    |> validate_required([:fact])
    |> validate_number(:confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> maybe_set_learned_at()
  end

  defp maybe_set_learned_at(changeset) do
    if get_field(changeset, :learned_at) == nil do
      put_change(changeset, :learned_at, DateTime.utc_now())
    else
      changeset
    end
  end
end
