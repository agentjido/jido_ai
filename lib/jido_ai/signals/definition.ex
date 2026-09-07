defmodule Jido.AI.Signal.Definition do
  @moduledoc false

  # Keep only AI input and metadata compatibility. Core Signal owns schemas,
  # constructors, errors and the CloudEvents envelope.
  def validate_data(data, schema) do
    with {:ok, data} <- normalize_keys(data, schema) do
      # Zoi defaults also replace explicit nil. AI defaults apply only to
      # missing fields. Use the declared inner schema for a present nil.
      fields =
        Enum.map(schema.fields, fn
          {key, %Zoi.Types.Default{inner: inner} = field} ->
            {key, if(is_map(data) and Map.fetch(data, key) == {:ok, nil}, do: inner, else: field)}

          field ->
            field
        end)

      Zoi.parse(%{schema | fields: fields}, data)
    end
  end

  defp normalize_keys(data, %{fields: fields}) when is_map(data) do
    keys = Map.new(fields, fn {key, _} -> {Atom.to_string(key), key} end)

    Enum.reduce_while(Map.to_list(data), {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      key = if is_binary(key), do: Map.get(keys, key, key), else: key

      cond do
        not (is_atom(key) or is_binary(key)) ->
          {:halt, {:error, "invalid Signal data field #{inspect(key)}"}}

        Map.has_key?(acc, key) ->
          {:halt, {:error, "duplicate Signal data field #{inspect(key)}"}}

        true ->
          {:cont, {:ok, Map.put(acc, key, value)}}
      end
    end)
  end

  defp normalize_keys(data, _schema), do: {:ok, data}

  # The public v2 map fields accept structs and retain their nested keys.
  def map_value(value, _opts) when is_map(value), do: :ok
  def map_value(_, _opts), do: {:error, "must be a map"}

  def metadata(module) do
    %{
      type: module.type(),
      default_source: module.default_source(),
      datacontenttype: module.datacontenttype(),
      dataschema: module.dataschema(),
      schema: module.schema(),
      extension_policy: %{}
    }
  end
end
