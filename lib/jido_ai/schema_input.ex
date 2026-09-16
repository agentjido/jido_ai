defmodule Jido.AI.SchemaInput do
  @moduledoc false

  @doc "Normalizes tool arguments, including complete numeric strings for numeric schema fields."
  def normalize_tool(schema, value) do
    schema |> normalize(value) |> then(&normalize_numbers(schema, &1))
  end

  defp normalize_numbers(%Zoi.Types.Default{inner: inner}, value),
    do: normalize_numbers(inner, value)

  defp normalize_numbers(%Zoi.Types.Map{fields: fields}, value)
       when is_map(value) and not is_nil(fields) do
    fields = Map.new(fields)
    Map.new(value, fn {key, item} -> {key, normalize_numbers(Map.get(fields, key), item)} end)
  end

  defp normalize_numbers(%Zoi.Types.Array{inner: inner}, value) when is_list(value),
    do: Enum.map(value, &normalize_numbers(inner, &1))

  defp normalize_numbers(%Zoi.Types.Integer{}, value), do: numeric_value(:integer, value)
  defp normalize_numbers(%Zoi.Types.Float{}, value), do: numeric_value(:float, value)

  defp normalize_numbers(fields, value) when is_list(fields) and is_map(value) do
    if Keyword.keyword?(fields) do
      Map.new(value, fn {key, item} ->
        opts = if is_atom(key), do: Keyword.get(fields, key, []), else: []
        {key, numeric_value(opts[:type], item)}
      end)
    else
      value
    end
  end

  defp normalize_numbers(_schema, value), do: value

  defp numeric_value(:integer, value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} -> number
      _ -> value
    end
  end

  defp numeric_value(:float, value) when is_binary(value) do
    case Float.parse(value) do
      {number, ""} -> number
      _ -> value
    end
  end

  defp numeric_value(:float, value) when is_integer(value) do
    value / 1
  rescue
    ArithmeticError -> value
  end

  defp numeric_value(_type, value), do: value

  def normalize(%Zoi.Types.Default{inner: inner}, value), do: normalize(inner, value)

  def normalize(%Zoi.Types.Map{fields: fields}, value)
      when is_map(value) and not is_nil(fields) do
    fields = Map.new(fields)

    field_map =
      Map.new(fields, fn {field, _schema} ->
        {to_string(field), field}
      end)

    Enum.reduce(value, %{}, fn {key, field_value}, normalized ->
      normalized_key =
        if is_binary(key) do
          Map.get(field_map, key, key)
        else
          key
        end

      if key != normalized_key and Map.has_key?(value, normalized_key) do
        normalized
      else
        field_schema = Map.get(fields, normalized_key)
        Map.put(normalized, normalized_key, normalize(field_schema, field_value))
      end
    end)
  end

  def normalize(%Zoi.Types.Array{inner: inner}, value) when is_list(value) do
    Enum.map(value, &normalize(inner, &1))
  end

  def normalize(%Zoi.Types.Atom{}, value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  def normalize(%Zoi.Types.Enum{enum_type: :atom, values: values}, value) when is_binary(value) do
    values
    |> Map.new(fn
      {label, atom} -> {to_string(label), atom}
      atom when is_atom(atom) -> {Atom.to_string(atom), atom}
    end)
    |> Map.get(value, value)
  end

  def normalize(fields, value) when is_list(fields) and is_map(value) do
    if Keyword.keyword?(fields) do
      keys = Map.new(fields, fn {key, _} -> {Atom.to_string(key), key} end)

      Map.new(value, fn {key, item} ->
        key = if is_binary(key), do: Map.get(keys, key, key), else: key
        options = if is_atom(key), do: Keyword.get(fields, key, []), else: []
        {key, keyword_value(options[:type], options, item)}
      end)
    else
      value
    end
  end

  def normalize(_schema, value), do: value

  defp keyword_value({:in, values}, _opts, value) when is_binary(value),
    do: Enum.find(values, value, &(is_atom(&1) and Atom.to_string(&1) == value))

  defp keyword_value(:keyword_list, opts, value) when is_map(value),
    do: normalize(opts[:keys] || [], value)

  defp keyword_value(_, _, value), do: value
end
