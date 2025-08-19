defmodule Jido.Character.Personality.Narrative do
  @moduledoc """
  Represents the character's backstory, thematic role, and story-based context
  that doesn't frequently change.
  """
  use TypedEctoSchema
  import Ecto.Changeset

  @derive Inspect
  @derive Jason.Encoder
  @primary_key false
  typed_embedded_schema do
    field(:backstory, :string)
    field(:thematic_role, :string)
    field(:key_events, {:array, :string}, default: [])
    field(:motivations, {:array, :string}, default: [])
  end

  def changeset(narrative \\ %__MODULE__{}, attrs) do
    narrative
    |> cast(attrs, [:backstory, :thematic_role, :key_events, :motivations])
    |> validate_length(:key_events, max: 20)
    |> validate_length(:motivations, max: 10)
  end

  @spec template(map()) :: %__MODULE__{}
  def template(attrs \\ %{}) do
    %__MODULE__{
      backstory: nil,
      thematic_role: nil,
      key_events: [],
      motivations: []
    }
    |> Map.merge(attrs)
  end

  @doc """
  Adds a key event to the narrative's key_events list if not already present
  and if it wouldn't exceed the maximum number of key events.
  """
  @spec add_key_event(t(), String.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t() | :event_exists}
  def add_key_event(narrative, event) do
    if event in narrative.key_events do
      {:error, :event_exists}
    else
      narrative
      |> changeset(%{key_events: [event | narrative.key_events]})
      |> apply_action(:update)
    end
  end

  @doc """
  Removes a key event from the narrative's key_events list.
  """
  @spec remove_key_event(t(), String.t()) :: {:ok, t()}
  def remove_key_event(narrative, event) do
    {:ok, %{narrative | key_events: Enum.reject(narrative.key_events, &(&1 == event))}}
  end

  @doc """
  Updates the backstory of the narrative.
  """
  @spec update_backstory(t(), String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update_backstory(narrative, new_backstory) do
    narrative
    |> changeset(%{backstory: new_backstory})
    |> apply_action(:update)
  end
end
