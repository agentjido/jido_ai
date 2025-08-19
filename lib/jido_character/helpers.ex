defmodule Jido.Character.Helpers do
  @moduledoc """
  Common helper functions for working with Jido.Character structs.
  """

  import Ecto.Changeset

  @doc """
  Safely accesses nested fields in a character struct.
  Returns nil if any part of the path is missing.

  ## Example
      iex> get_in_character(character, [:identity, :username])
      "some_user"
  """
  def get_in_character(character, path) when is_list(path) do
    get_in(character, path)
  end

  @doc """
  Validates a character and returns friendly error messages.

  ## Example
      iex> friendly_errors(invalid_character)
      ["Username must be between 3 and 30 characters", "Display name is required"]
  """
  def friendly_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> flatten_error_messages()
  end

  @doc """
  Creates a basic changeset with updated timestamps.
  """
  def with_timestamps(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    Map.merge(attrs, %{
      updated_at: now,
      created_at: Map.get(attrs, :created_at, now)
    })
  end

  @doc """
  Checks if two characters are effectively equal by comparing relevant fields.
  Ignores timestamps and other metadata.
  """
  def equal?(char1, char2) do
    Map.take(char1, [:id, :name, :description, :identity]) ==
      Map.take(char2, [:id, :name, :description, :identity])
  end

  @doc """
  Returns a map of differences between two characters.
  Useful for debugging or logging changes.
  """
  def diff(old_char, new_char) do
    Map.take(new_char, [:id, :name, :description, :identity])
    |> Map.reject(fn {k, v} -> Map.get(old_char, k) == v end)
  end

  def ensure_field(changeset, field, default_func) do
    case get_change(changeset, field) do
      nil ->
        if get_field(changeset, field) do
          changeset
        else
          put_embed(changeset, field, default_func.())
        end

      _ ->
        changeset
    end
  end

  def deep_atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_map(v) -> {String.to_existing_atom(k), deep_atomize_keys(v)}
      {k, v} when is_list(v) -> {String.to_existing_atom(k), Enum.map(v, &deep_atomize_keys/1)}
      {k, v} -> {String.to_existing_atom(k), v}
    end)
  end

  def random_sample(list, count \\ 1) when is_list(list) do
    list
    |> Enum.shuffle()
    |> Enum.take(count)
  end

  def add_section_header(title, content) when byte_size(content) > 0 do
    """
    # #{title}
    #{content}
    """
  end

  def add_section_header(_, _), do: ""
  # Private Helpers

  defp flatten_error_messages(errors) when is_map(errors) do
    errors
    |> Enum.reduce([], fn
      {key, value}, acc ->
        if is_map(value) do
          acc ++ flatten_error_messages(value)
        else
          if is_list(value) do
            acc ++ Enum.map(value, &"#{key} #{&1}")
          else
            acc
          end
        end
    end)
  end
end
