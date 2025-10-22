defmodule Jido.AI.ReqLlmBridge.ParameterConverter do
  @moduledoc """
  Handles conversion between JSON parameters from ReqLLM and Elixir data structures
  for Jido Action execution.

  This module provides robust type conversion and validation for tool parameters,
  converting JSON-decoded parameters (typically with string keys) to the format
  expected by Jido Actions. It implements the conversion patterns recommended
  by the Elixir expert consultation.

  ## Features

  - Type coercion with comprehensive support for common types
  - Safe atom creation using existing atoms only
  - Nested structure handling (maps, lists, keyword lists)
  - Detailed error reporting with field-level context
  - Default value application from action schemas
  - Performance optimization for common conversion cases

  ## Usage

      # Convert JSON parameters to Jido Action format
      params = %{"name" => "Pascal", "count" => "5"}
      {:ok, converted} = ParameterConverter.convert_to_jido_format(params, MyAction)
      # Returns: %{name: "Pascal", count: 5}

      # Type coercion with validation
      {:ok, value} = ParameterConverter.coerce_type("123", :integer)
      # Returns: {:ok, 123}
  """

  require Logger

  @type conversion_result :: {:ok, map()} | {:error, term()}
  @type coercion_result :: {:ok, any()} | {:error, String.t()}

  @doc """
  Converts JSON parameters to Jido Action format with type coercion.

  Takes parameters from ReqLLM (typically a map with string keys) and converts
  them to the format expected by a Jido Action, including type coercion based
  on the action's schema and safe atom key conversion.

  ## Parameters

  - `params`: Map of parameters from ReqLLM (string keys, JSON-decoded values)
  - `action_module`: The Jido Action module that defines the expected schema

  ## Returns

  - `{:ok, converted_params}` where converted_params has atom keys and properly typed values
  - `{:error, reason}` if conversion fails

  ## Examples

      iex> params = %{"duration_ms" => "1000", "enabled" => "true"}
      iex> {:ok, converted} = ParameterConverter.convert_to_jido_format(params, SleepAction)
      iex> converted
      %{duration_ms: 1000, enabled: true}

      iex> params = %{"invalid_field" => "value"}
      iex> ParameterConverter.convert_to_jido_format(params, SleepAction)
      {:error, {:unknown_parameter, "invalid_field"}}
  """
  @spec convert_to_jido_format(map(), module()) :: conversion_result()
  def convert_to_jido_format(params, action_module)
      when is_map(params) and is_atom(action_module) do
    schema = get_action_schema(action_module)
    schema_map = build_schema_map(schema)

    params
    |> Enum.reduce_while({:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case convert_parameter(key, value, schema_map) do
        {:ok, converted_key, converted_value} ->
          {:cont, {:ok, Map.put(acc, converted_key, converted_value)}}

        {:error, reason} ->
          {:halt, {:error, {:parameter_conversion_error, key, reason}}}
      end
    end)
    |> case do
      {:ok, converted_params} ->
        apply_default_values(converted_params, schema_map)

      error ->
        error
    end
  rescue
    error ->
      {:error, {:conversion_exception, Exception.message(error)}}
  end

  def convert_to_jido_format(params, _action_module) do
    {:error, {:invalid_params_type, "Expected map, got #{inspect(params)}"}}
  end

  @doc """
  Converts an individual parameter with type coercion and validation.

  Handles the conversion of a single parameter from JSON format to the type
  expected by the action schema. Uses safe atom conversion to prevent
  atom table exhaustion attacks.

  ## Parameters

  - `key`: Parameter key (string or atom)
  - `value`: Parameter value (any JSON-decodable type)
  - `schema_map`: Map of schema definitions keyed by atom

  ## Returns

  - `{:ok, atom_key, converted_value}` on successful conversion
  - `{:error, reason}` if conversion fails

  ## Examples

      iex> schema_map = %{count: [type: :integer, required: true]}
      iex> ParameterConverter.convert_parameter("count", "42", schema_map)
      {:ok, :count, 42}

      iex> ParameterConverter.convert_parameter("unknown", "value", %{})
      {:error, "Unknown parameter: unknown"}
  """
  @spec convert_parameter(String.t() | atom(), any(), map()) ::
          {:ok, atom(), any()} | {:error, String.t()}
  def convert_parameter(key, value, schema_map) when is_map(schema_map) do
    string_key = to_string(key)

    # Safe atom conversion - only use existing atoms
    case find_existing_atom_key(string_key, schema_map) do
      {:ok, atom_key} ->
        field_schema = Map.get(schema_map, atom_key, [])

        case coerce_type(value, Keyword.get(field_schema, :type)) do
          {:ok, coerced_value} -> {:ok, atom_key, coerced_value}
          {:error, reason} -> {:error, "Type conversion failed for #{string_key}: #{reason}"}
        end

      :error ->
        {:error, "Unknown parameter: #{string_key}"}
    end
  end

  @doc """
  Performs type coercion with comprehensive support for common types.

  Converts values from JSON types to Elixir types based on the schema type
  specification. Handles edge cases and provides meaningful error messages
  for conversion failures.

  ## Parameters

  - `value`: Value to convert (any type)
  - `type`: Target type (atom or type specification)

  ## Returns

  - `{:ok, converted_value}` on successful conversion
  - `{:error, reason}` if conversion fails

  ## Examples

      iex> ParameterConverter.coerce_type("123", :integer)
      {:ok, 123}

      iex> ParameterConverter.coerce_type("true", :boolean)
      {:ok, true}

      iex> ParameterConverter.coerce_type(["1", "2", "3"], {:list, :integer})
      {:ok, [1, 2, 3]}

      iex> ParameterConverter.coerce_type("invalid", :integer)
      {:error, "Invalid integer: invalid"}
  """
  @spec coerce_type(any(), atom() | tuple()) :: coercion_result()
  def coerce_type(value, type)

  # String type conversion
  def coerce_type(value, :string) when is_binary(value), do: {:ok, value}
  def coerce_type(value, :string), do: {:ok, to_string(value)}

  # Integer type conversion
  def coerce_type(value, :integer) when is_integer(value), do: {:ok, value}
  def coerce_type(value, :integer) when is_float(value), do: {:ok, trunc(value)}

  def coerce_type(value, :integer) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      # Allow partial parsing for flexibility
      {int, _remainder} -> {:ok, int}
      :error -> {:error, "Invalid integer: #{value}"}
    end
  end

  def coerce_type(value, :integer), do: {:error, "Cannot convert #{inspect(value)} to integer"}

  # Non-negative integer type conversion
  def coerce_type(value, :non_neg_integer) do
    case coerce_type(value, :integer) do
      {:ok, int} when int >= 0 -> {:ok, int}
      {:ok, int} -> {:error, "Expected non-negative integer, got #{int}"}
      error -> error
    end
  end

  # Positive integer type conversion
  def coerce_type(value, :pos_integer) do
    case coerce_type(value, :integer) do
      {:ok, int} when int > 0 -> {:ok, int}
      {:ok, int} -> {:error, "Expected positive integer, got #{int}"}
      error -> error
    end
  end

  # Float type conversion
  def coerce_type(value, :float) when is_float(value), do: {:ok, value}
  def coerce_type(value, :float) when is_integer(value), do: {:ok, value / 1}

  def coerce_type(value, :float) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      {float, _remainder} -> {:ok, float}
      :error -> {:error, "Invalid float: #{value}"}
    end
  end

  def coerce_type(value, :float), do: {:error, "Cannot convert #{inspect(value)} to float"}

  # Boolean type conversion
  def coerce_type(value, :boolean) when is_boolean(value), do: {:ok, value}
  def coerce_type("true", :boolean), do: {:ok, true}
  def coerce_type("false", :boolean), do: {:ok, false}
  def coerce_type("1", :boolean), do: {:ok, true}
  def coerce_type("0", :boolean), do: {:ok, false}
  def coerce_type(1, :boolean), do: {:ok, true}
  def coerce_type(0, :boolean), do: {:ok, false}
  def coerce_type(value, :boolean), do: {:error, "Invalid boolean: #{value}"}

  # List type conversion
  def coerce_type(value, :list) when is_list(value), do: {:ok, value}
  def coerce_type(value, :list), do: {:error, "Expected list, got #{inspect(value)}"}

  # Typed list conversion
  def coerce_type(value, {:list, inner_type}) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case coerce_type(item, inner_type) do
        {:ok, coerced_item} -> {:cont, {:ok, [coerced_item | acc]}}
        {:error, reason} -> {:halt, {:error, "List item conversion failed: #{reason}"}}
      end
    end)
    |> case do
      {:ok, reversed_list} -> {:ok, Enum.reverse(reversed_list)}
      error -> error
    end
  end

  def coerce_type(value, {:list, _inner_type}),
    do: {:error, "Expected list, got #{inspect(value)}"}

  # Map type conversion
  def coerce_type(value, :map) when is_map(value), do: {:ok, value}
  def coerce_type(value, :map), do: {:error, "Expected map, got #{inspect(value)}"}

  # Keyword list type conversion
  def coerce_type(value, :keyword_list) when is_list(value) do
    if Keyword.keyword?(value) do
      {:ok, value}
    else
      {:error, "Expected keyword list, got regular list"}
    end
  end

  def coerce_type(value, :keyword_list) when is_map(value) do
    # Convert map to keyword list
    keyword_list =
      value
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(to_string(k)), v} end)

    {:ok, keyword_list}
  rescue
    ArgumentError -> {:error, "Cannot convert map with invalid atom keys to keyword list"}
  end

  def coerce_type(value, :keyword_list),
    do: {:error, "Expected keyword list, got #{inspect(value)}"}

  # Enum/choice type conversion
  def coerce_type(value, {:in, choices}) when is_list(choices) do
    string_value = to_string(value)
    atom_value = try_string_to_existing_atom(string_value)

    cond do
      value in choices -> {:ok, value}
      string_value in choices -> {:ok, string_value}
      atom_value != nil and atom_value in choices -> {:ok, atom_value}
      true -> {:error, "Value #{inspect(value)} not in allowed choices: #{inspect(choices)}"}
    end
  end

  # Catch-all for unknown types
  def coerce_type(value, type),
    do: {:error, "Unsupported type conversion: #{type} for #{inspect(value)}"}

  # Private helper functions

  defp get_action_schema(action_module) do
    action_module.schema()
  rescue
    _ -> []
  end

  defp build_schema_map(schema) when is_list(schema) do
    Map.new(schema)
  end

  defp find_existing_atom_key(string_key, schema_map) do
    # Try to find an existing atom that matches the string key
    schema_map
    |> Map.keys()
    |> Enum.find(fn atom_key -> to_string(atom_key) == string_key end)
    |> case do
      nil -> :error
      atom_key -> {:ok, atom_key}
    end
  end

  defp apply_default_values(converted_params, schema_map) do
    default_values =
      schema_map
      |> Enum.filter(fn {_key, opts} -> Keyword.has_key?(opts, :default) end)
      |> Enum.reduce(%{}, fn {key, opts}, acc ->
        if Map.has_key?(converted_params, key) do
          acc
        else
          Map.put(acc, key, Keyword.get(opts, :default))
        end
      end)

    merged_params = Map.merge(default_values, converted_params)
    {:ok, merged_params}
  end

  defp try_string_to_existing_atom(string) do
    String.to_existing_atom(string)
  rescue
    ArgumentError -> nil
  end

  @doc """
  Ensures result is JSON serializable for ReqLLM consumption.

  Validates that the result from a tool execution can be properly serialized
  to JSON. If serialization fails, attempts to sanitize the data or provides
  a fallback representation.

  ## Parameters

  - `data`: Data to validate for JSON serialization

  ## Returns

  - `{:ok, data}` if data is JSON serializable
  - `{:error, reason}` if serialization fails and cannot be recovered

  ## Examples

      iex> ParameterConverter.ensure_json_serializable(%{count: 42, name: "test"})
      {:ok, %{count: 42, name: "test"}}

      iex> ParameterConverter.ensure_json_serializable(%{pid: self()})
      {:ok, %{pid: "#PID<0.123.0>", _sanitized: true}}
  """
  @spec ensure_json_serializable(any()) :: {:ok, any()} | {:error, term()}
  def ensure_json_serializable(data) do
    case Jason.encode(data) do
      {:ok, _json} ->
        {:ok, data}

      {:error, reason} ->
        case sanitize_for_json(data) do
          {:ok, sanitized_data} -> {:ok, sanitized_data}
          {:error, _} -> {:error, {:serialization_error, reason}}
        end
    end
  end

  defp sanitize_for_json(data) when is_map(data) do
    sanitized =
      data
      |> Enum.map(fn {key, value} ->
        case sanitize_value_for_json(value) do
          {:ok, sanitized_value} -> {key, sanitized_value}
          {:error, _} -> {key, inspect(value)}
        end
      end)
      |> Map.new()
      |> Map.put(:_sanitized, true)

    {:ok, sanitized}
  rescue
    _ -> {:error, :sanitization_failed}
  end

  defp sanitize_for_json(data) when is_list(data) do
    sanitized =
      Enum.map(data, fn item ->
        case sanitize_value_for_json(item) do
          {:ok, sanitized_item} -> sanitized_item
          {:error, _} -> inspect(item)
        end
      end)

    {:ok, sanitized}
  rescue
    _ -> {:error, :sanitization_failed}
  end

  defp sanitize_for_json(data) do
    sanitize_value_for_json(data)
  end

  defp sanitize_value_for_json(value) when is_pid(value), do: {:ok, inspect(value)}
  defp sanitize_value_for_json(value) when is_reference(value), do: {:ok, inspect(value)}
  defp sanitize_value_for_json(value) when is_function(value), do: {:ok, inspect(value)}
  defp sanitize_value_for_json(value) when is_port(value), do: {:ok, inspect(value)}

  defp sanitize_value_for_json(%{__struct__: _} = struct) do
    {:ok, Map.from_struct(struct)}
  rescue
    _ -> {:ok, inspect(struct)}
  end

  defp sanitize_value_for_json(value) when is_map(value), do: sanitize_for_json(value)
  defp sanitize_value_for_json(value) when is_list(value), do: sanitize_for_json(value)
  defp sanitize_value_for_json(value), do: {:ok, value}
end
