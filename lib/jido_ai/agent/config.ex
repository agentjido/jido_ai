defmodule Jido.AI.Agent.Config do
  @moduledoc false

  @reserved_keys [:input, "input"]

  @spec normalize(map(), module()) :: {:ok, map()} | {:error, term()}
  def normalize(config, _target) when is_map(config) and map_size(config) == 0, do: {:ok, %{}}

  def normalize(config, target)
      when is_map(config) and not is_struct(config) and is_atom(target) do
    with :ok <- reserved(config),
         {:ok, fields} <- schema_fields(target),
         {:ok, normalized} <- normalize_fields(config, fields),
         :ok <- portable(normalized) do
      {:ok, normalized}
    end
  end

  def normalize(_config, _target), do: {:error, :configuration_must_be_a_map}

  @spec encode(map(), module()) :: {:ok, map()} | {:error, term()}
  def encode(config, target) do
    case normalize(config, target) do
      {:ok, config} -> encode_value(config)
      error -> error
    end
  end

  @spec decode(map(), module()) :: {:ok, map()} | {:error, term()}
  def decode(config, target), do: normalize(config, target)

  defp reserved(config) do
    case Enum.find(@reserved_keys, &Map.has_key?(config, &1)) do
      nil -> :ok
      key -> {:error, {:reserved_field, key}}
    end
  end

  defp schema_fields(target) do
    case target.schema() do
      %Zoi.Types.Map{fields: fields} when is_list(fields) and fields != [] ->
        {:ok, fields}

      %Zoi.Types.Map{fields: fields} when fields in [nil, []] ->
        {:ok, :open}

      _schema ->
        {:error, :reasoning_flow_requires_an_object_input_schema}
    end
  rescue
    error -> {:error, error}
  end

  defp normalize_fields(config, fields) when is_list(fields) do
    names = Map.new(fields, fn {key, schema} -> {to_string(key), {key, schema}} end)

    if map_size(names) != length(fields) do
      {:error, :schema_contains_ambiguous_field_names}
    else
      do_normalize_fields(config, names)
    end
  end

  defp normalize_fields(config, :open), do: {:ok, config}

  defp do_normalize_fields(config, fields) do
    Enum.reduce_while(config, {:ok, %{}}, fn {key, value}, {:ok, normalized} ->
      with {:ok, name} <- field_name(key),
           {:ok, {canonical, schema}} <- fetch_field(fields, name),
           :ok <- unique_field(normalized, canonical, name),
           {:ok, value} <- parse_field(schema, value) do
        {:cont, {:ok, Map.put(normalized, canonical, value)}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp field_name(key) when is_atom(key) or is_binary(key), do: {:ok, to_string(key)}
  defp field_name(key), do: {:error, {:invalid_field_name, key}}

  defp fetch_field(fields, name) do
    case Map.fetch(fields, name) do
      {:ok, field} -> {:ok, field}
      :error -> {:error, {:unknown_field, name}}
    end
  end

  defp unique_field(normalized, canonical, name) do
    if Map.has_key?(normalized, canonical),
      do: {:error, {:duplicate_field, name}},
      else: :ok
  end

  defp parse_field(schema, value) do
    case Zoi.parse(schema, value, coerce: true) do
      {:ok, normalized} -> {:ok, normalized}
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  defp portable(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: :ok

  defp portable(value) when is_atom(value), do: :ok

  defp portable(value) when is_list(value) do
    if List.improper?(value), do: {:error, :improper_list}, else: portable_items(value)
  end

  defp portable(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.flat_map(fn {key, item} -> [key, item] end)
    |> portable_items()
  end

  defp portable(_value), do: {:error, :configuration_contains_nonportable_data}

  defp portable_items(values) do
    Enum.reduce_while(values, :ok, fn value, :ok ->
      case portable(value) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp encode_value(value)
       when is_nil(value) or is_boolean(value) or is_number(value) or is_binary(value),
       do: {:ok, value}

  defp encode_value(value) when is_atom(value), do: {:ok, Atom.to_string(value)}

  defp encode_value(value) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, encoded} ->
      case encode_value(item) do
        {:ok, item} -> {:cont, {:ok, [item | encoded]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, encoded} -> {:ok, Enum.reverse(encoded)}
      error -> error
    end)
  end

  defp encode_value(value) when is_map(value) and not is_struct(value) do
    Enum.reduce_while(value, {:ok, %{}}, fn {key, item}, {:ok, encoded} ->
      with {:ok, key} <- encode_key(key),
           false <- Map.has_key?(encoded, key),
           {:ok, item} <- encode_value(item) do
        {:cont, {:ok, Map.put(encoded, key, item)}}
      else
        true -> {:halt, {:error, {:duplicate_encoded_key, key}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp encode_value(_value), do: {:error, :configuration_contains_nonportable_data}

  defp encode_key(key) when is_atom(key), do: {:ok, Atom.to_string(key)}
  defp encode_key(key) when is_binary(key), do: {:ok, key}
  defp encode_key(key), do: {:error, {:invalid_map_key, key}}
end
