defmodule JSV.Cast do
  import JSV, only: [defcast: 2]

  @moduledoc false

  defcast string_to_integer(data) do
    with true <- is_binary(data),
         {int, ""} <- Integer.parse(data) do
      {:ok, int}
    else
      _ -> {:error, "invalid integer representation"}
    end
  end

  defcast string_to_float(data) do
    with true <- is_binary(data),
         {float, ""} <- Float.parse(data) do
      {:ok, float}
    else
      _ -> {:error, "invalid floating point number representation"}
    end
  end

  defcast string_to_number(data) do
    with true <- is_binary(data),
         {:ok, number} <- parse_number(data) do
      {:ok, number}
    else
      _ -> {:error, "invalid number representation"}
    end
  end

  defp parse_number(data) do
    case Float.parse(data) do
      {float, ""} ->
        {:ok, float}

      _ ->
        case Integer.parse(data) do
          {int, ""} -> {:ok, int}
          _ -> :error
        end
    end
  end

  defcast string_to_boolean(data) do
    case data do
      "true" -> {:ok, true}
      "false" -> {:ok, false}
      _ -> {:error, "invalid boolean representation"}
    end
  end

  defcast string_to_existing_atom(data) do
    {:ok, String.to_existing_atom(data)}
  rescue
    ArgumentError -> {:error, "not an existing atom representation"}
  end

  defcast string_to_atom(data) do
    if is_binary(data) do
      {:ok, String.to_atom(data)}
    else
      {:error, "not an atom representation"}
    end
  end

  defcast string_to_atom_or_nil(data) do
    case data do
      b when is_binary(b) -> {:ok, String.to_atom(data)}
      nil -> {:ok, nil}
      _ -> {:error, "not an atom representation or nil"}
    end
  end

  @doc false
  @spec format_error(term, term, term) :: binary
  def format_error(_, message, _) do
    message
  end
end
