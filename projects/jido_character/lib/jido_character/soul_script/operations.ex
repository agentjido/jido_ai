defmodule Jido.Character.SoulScript.Operations do
  @moduledoc """
  Operations for managing SoulScript-compatible character data.
  Handles creation, updates, deletion, and persistence.
  """
  import Ecto.Changeset

  @doc "Creates a new character with optional ID"
  def new(id \\ nil) do
    attrs = %{
      id: id || UUID.uuid4(),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    %Jido.Character{}
    |> Jido.Character.changeset(attrs)
    |> case do
      %{valid?: true} = changeset -> {:ok, apply_changes(changeset)}
      changeset -> {:error, changeset}
    end
  end

  @doc "Updates a character with new attributes"
  def update(%Jido.Character{} = character, attrs) when is_map(attrs) do
    attrs = Map.put(attrs, :updated_at, DateTime.utc_now())

    character
    |> Jido.Character.changeset(attrs)
    |> case do
      %{valid?: true} = changeset -> {:ok, apply_changes(changeset)}
      changeset -> {:error, changeset}
    end
  end

  @doc "Validates a character"
  def validate(%Jido.Character{} = character) do
    case Jido.Character.changeset(character, %{}) do
      %{valid?: true} -> :ok
      changeset -> {:error, changeset}
    end
  end

  @doc "Creates a deep copy of a character with a new ID"
  def clone(%Jido.Character{} = character, new_id) do
    attrs = %{
      id: new_id,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }

    character
    |> Map.from_struct()
    |> Map.merge(attrs)
    |> then(&Jido.Character.changeset(%Jido.Character{}, &1))
    |> case do
      %{valid?: true} = changeset -> {:ok, apply_changes(changeset)}
      changeset -> {:error, changeset}
    end
  end

  @doc "Serializes a character to JSON"
  def to_json(%Jido.Character{} = character) do
    Jason.encode(character)
  end

  @doc "Deserializes a character from JSON"
  def from_json(json) when is_binary(json) do
    with {:ok, decoded} <- Jason.decode(json, keys: :atoms),
         {:ok, character} <- new(decoded[:id]),
         {:ok, character} <- update(character, decoded) do
      {:ok, character}
    end
  end

  # These are stubs for now - they would normally interact with a persistence layer
  def get(id) when is_binary(id), do: {:error, :not_found}
  def delete(id) when is_binary(id), do: :ok
end
