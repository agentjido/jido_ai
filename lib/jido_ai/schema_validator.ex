defmodule Jido.AI.SchemaValidator do
  @moduledoc """
  Validates data against Jido.AI.Schema definitions.

  This module provides validation for JSON data from LLM responses
  against defined schemas. It checks types, required fields, and
  provides detailed error messages for validation failures.

  ## Usage

      # Validate a map against a schema
      case SchemaValidator.validate(data, MySchema) do
        {:ok, validated_data} -> # Use validated_data
        {:error, errors} -> # Handle validation errors
      end

  ## Error Format

  Validation errors are returned as a list of maps with:
  - `:field` - The field name that failed validation
  - `:error` - The error type (`:required`, `:type_mismatch`, etc.)
  - `:message` - Human-readable error message

  ## Example

      iex> data = %{"name" => "Alice", "age" => "not a number"}
      iex> SchemaValidator.validate(data, UserSchema)
      {:error, [%{field: :age, error: :type_mismatch, message: "Expected integer, got string"}]}
  """

  @doc """
  Validate data against a schema module.

  Returns `{:ok, validated_data}` if validation passes, where validated_data
  is a map with atom keys and properly typed values.

  Returns `{:error, errors}` if validation fails, where errors is a list
  of error maps describing what went wrong.
  """
  def validate(data, schema_module) when is_map(data) do
    fields = schema_module.__schema__(:fields)

    # Convert string keys to atoms if needed
    data = atomize_keys(data)

    # Validate all fields
    errors =
      fields
      |> Enum.flat_map(fn field ->
        validate_field(data, field)
      end)

    if Enum.empty?(errors) do
      # Apply defaults for missing optional fields
      validated_data = apply_defaults(data, fields)
      {:ok, validated_data}
    else
      {:error, errors}
    end
  end

  def validate(_data, _schema_module) do
    {:error, [%{field: nil, error: :invalid_input, message: "Data must be a map"}]}
  end

  defp validate_field(data, field) do
    value = Map.get(data, field.name)

    cond do
      # Required field is missing
      field.required and is_nil(value) ->
        [
          %{
            field: field.name,
            error: :required,
            message: "Required field '#{field.name}' is missing"
          }
        ]

      # Optional field is missing - no error
      is_nil(value) ->
        []

      # Field is present - validate type
      true ->
        validate_type(field.name, value, field.type)
    end
  end

  defp validate_type(field_name, value, expected_type) do
    case {expected_type, value} do
      # String validation
      {:string, v} when is_binary(v) ->
        []

      {:string, v} ->
        [type_mismatch_error(field_name, :string, v)]

      # Boolean validation
      {:boolean, v} when is_boolean(v) ->
        []

      {:boolean, v} ->
        [type_mismatch_error(field_name, :boolean, v)]

      # Integer validation
      {:integer, v} when is_integer(v) ->
        []

      {:integer, v} ->
        [type_mismatch_error(field_name, :integer, v)]

      # Float validation (accepts both float and integer)
      {:float, v} when is_float(v) or is_integer(v) ->
        []

      {:float, v} ->
        [type_mismatch_error(field_name, :float, v)]

      # List validation
      {{:list, item_type}, v} when is_list(v) ->
        v
        |> Enum.with_index()
        |> Enum.flat_map(fn {item, index} ->
          validate_type(:"#{field_name}[#{index}]", item, item_type)
        end)

      {{:list, _item_type}, v} ->
        [type_mismatch_error(field_name, :list, v)]

      # Unknown type
      {type, _v} ->
        [
          %{
            field: field_name,
            error: :unknown_type,
            message: "Unknown type '#{inspect(type)}' for field '#{field_name}'"
          }
        ]
    end
  end

  defp type_mismatch_error(field_name, expected_type, value) do
    actual_type = get_type_name(value)

    %{
      field: field_name,
      error: :type_mismatch,
      message:
        "Field '#{field_name}' expected #{format_type_name(expected_type)}, got #{actual_type}"
    }
  end

  defp get_type_name(v) when is_binary(v), do: "string"
  defp get_type_name(v) when is_boolean(v), do: "boolean"
  defp get_type_name(v) when is_integer(v), do: "integer"
  defp get_type_name(v) when is_float(v), do: "float"
  defp get_type_name(v) when is_list(v), do: "list"
  defp get_type_name(v) when is_map(v), do: "map"
  defp get_type_name(_v), do: "unknown"

  defp format_type_name(:string), do: "string"
  defp format_type_name(:boolean), do: "boolean"
  defp format_type_name(:integer), do: "integer"
  defp format_type_name(:float), do: "number"
  defp format_type_name({:list, _}), do: "list"

  defp atomize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn
      {k, v} when is_binary(k) -> {String.to_existing_atom(k), v}
      {k, v} when is_atom(k) -> {k, v}
    end)
    |> Enum.into(%{})
  rescue
    ArgumentError ->
      # If conversion fails, return original map
      map
  end

  defp apply_defaults(data, fields) do
    fields
    |> Enum.reduce(data, fn field, acc ->
      if Map.has_key?(acc, field.name) do
        acc
      else
        # Apply default if present
        if field.default != nil do
          Map.put(acc, field.name, field.default)
        else
          acc
        end
      end
    end)
  end

  @doc """
  Format validation errors as a human-readable string.

  ## Example

      iex> errors = [%{field: :age, error: :type_mismatch, message: "Expected integer"}]
      iex> SchemaValidator.format_errors(errors)
      "Validation errors:\\n  - age: Expected integer"
  """
  def format_errors(errors) when is_list(errors) do
    error_lines =
      errors
      |> Enum.map_join("\n", fn error ->
        "  - #{error.field}: #{error.message}"
      end)

    "Validation errors:\n#{error_lines}"
  end
end
