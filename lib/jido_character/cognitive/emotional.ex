defmodule Jido.Character.Cognitive.Emotional do
  use TypedEctoSchema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [:mood, :intensity, :last_changed_at, :secondary_moods]}
  @valid_moods [
    "happy",
    "sad",
    "angry",
    "excited",
    "calm",
    "anxious",
    "neutral",
    "curious",
    "frustrated",
    "content"
  ]

  typed_embedded_schema do
    field(:mood, :string)
    field(:intensity, :float, default: 0.5)
    field(:last_changed_at, :utc_datetime_usec)
    field(:secondary_moods, {:array, :string}, default: [])
  end

  def changeset(%__MODULE__{} = emotional, attrs) when is_map(attrs) do
    emotional
    |> cast(attrs, [:mood, :intensity, :last_changed_at, :secondary_moods])
    |> validate_required([:mood])
    |> validate_inclusion(:mood, @valid_moods)
    |> validate_number(:intensity, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> validate_secondary_moods()
    |> put_change(:last_changed_at, DateTime.utc_now())
  end

  defp validate_secondary_moods(changeset) do
    case get_change(changeset, :secondary_moods) do
      nil ->
        changeset

      moods when is_list(moods) ->
        if Enum.all?(moods, &(&1 in @valid_moods)) do
          changeset
        else
          add_error(changeset, :secondary_moods, "contains invalid moods")
        end
    end
  end

  def valid_moods, do: @valid_moods
end
