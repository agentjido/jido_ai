defmodule Jido.Character.Core do
  @moduledoc """
  Core implementation of Jido.Character operations.
  Handles CRUD and utility functions while maintaining persistence.
  """

  alias Jido.Character.Composer

  @persist_adapter Application.compile_env(
                     :jido_character,
                     :persist_adapter,
                     Jido.Character.Persistence.Memory
                   )

  @type character :: Jido.Character.t()
  @type changeset :: Jido.Character.changeset()
  @type error :: Jido.Character.error()

  @doc "Creates a new character with optional ID"
  @spec new(String.t() | nil) :: {:ok, character()} | error()
  def new(id \\ nil) do
    id = id || UUID.uuid4()
    Process.sleep(1)
    now = DateTime.utc_now()

    Jido.Character.template(%{
      id: id,
      created_at: now,
      updated_at: now
    })
    |> Jido.Character.changeset(%{})
    |> commit_changes()
  end

  @doc "Retrieves a character by ID"
  @spec get(String.t()) :: {:ok, character()} | {:error, :not_found}
  def get(id) when is_binary(id), do: @persist_adapter.get(id)

  @doc "Updates a character with new attributes"
  @spec update(character(), map()) :: {:ok, character()} | error()
  def update(%Jido.Character{} = character, attrs) when is_map(attrs) do
    # Ensure we get a fresh timestamp that's greater than the current one
    Process.sleep(1)
    new_timestamp = DateTime.utc_now()

    attrs = Map.put(attrs, :updated_at, new_timestamp)

    character
    |> Jido.Character.changeset(attrs)
    |> commit_changes()
  end

  @doc "Deletes a character by ID"
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(id) when is_binary(id), do: @persist_adapter.delete(id)

  @doc "Creates a deep copy with a new ID"
  @spec clone(character(), String.t()) :: {:ok, character()} | error()
  def clone(%Jido.Character{} = character, new_id) do
    attrs = %{
      id: new_id,
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      identity: character.identity |> Map.from_struct(),
      personality: character.personality |> Map.from_struct(),
      soulscript: character.soulscript |> Map.from_struct()
    }

    Jido.Character.template(attrs)
    |> Jido.Character.changeset(%{})
    |> commit_changes()
  end

  @doc "Validates a character without persistence"
  @spec validate(character()) :: :ok | {:error, changeset()}
  def validate(%Jido.Character{} = character) do
    case Jido.Character.changeset(character, %{}) do
      %{valid?: true} -> :ok
      changeset -> {:error, changeset}
    end
  end

  @doc "Converts character to JSON string"
  @spec to_json(character()) :: {:ok, String.t()} | {:error, term()}
  def to_json(%Jido.Character{} = character) do
    try do
      {:ok, Jason.encode!(character)}
    rescue
      e in Jason.EncodeError -> {:error, {:encoding_error, e.message}}
    end
  end

  @spec from_json(String.t()) :: {:ok, character()} | error()
  def from_json(json) when is_binary(json) do
    with {:ok, decoded} <- Jason.decode(json),
         # Convert string keys to atoms for embedded schemas
         decoded <- atomize_keys(decoded),
         # Create a new template with the decoded data
         character <- Jido.Character.template(),
         # Apply changes through changeset
         changeset <-
           Jido.Character.changeset(character, %{
             id: decoded[:id],
             created_at: parse_datetime(decoded[:created_at]),
             updated_at: parse_datetime(decoded[:updated_at]),
             identity: decoded[:identity],
             personality: decoded[:personality],
             soulscript: decoded[:soulscript]
           }),
         %{valid?: true} <- changeset do
      {:ok, Ecto.Changeset.apply_changes(changeset)}
    else
      {:error, %Jason.DecodeError{}} = error -> error
      %{valid?: false} = changeset -> {:error, changeset}
    end
  end

  def compose(%Jido.Character{} = character, opts \\ []) do
    with {:ok, identity} <- Composer.compose(character.identity, opts) do
      #  {:ok, personality} <- Composer.compose(character.personality, opts) do
      composed = """
      #{identity}
      """

      {:ok, String.trim(composed)}
    end
  end

  # Private Helpers

  defp commit_changes(%Ecto.Changeset{} = changeset) do
    case changeset do
      %{valid?: true} = valid_changeset ->
        valid_changeset
        |> Ecto.Changeset.apply_changes()
        |> @persist_adapter.save()

      invalid_changeset ->
        {:error, invalid_changeset}
    end
  end

  # WARNING: This is potentially dangerous as it creates atoms at runtime.
  # In a production system, you should use a whitelist of allowed keys.
  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_map(value) -> {String.to_atom(key), atomize_keys(value)}
      {key, value} when is_list(value) -> {String.to_atom(key), Enum.map(value, &atomize_keys/1)}
      {key, value} -> {String.to_atom(key), value}
    end)
  end

  defp atomize_keys(value), do: value

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  @doc false
  def persist_adapter, do: @persist_adapter
end
