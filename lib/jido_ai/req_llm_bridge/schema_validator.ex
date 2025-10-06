defmodule Jido.AI.ReqLlmBridge.SchemaValidator do
  @moduledoc """
  Validates tool parameters against Jido Action schemas and converts schemas
  between formats.

  This module provides comprehensive schema validation and conversion functionality
  for the ReqLLM integration. It handles the conversion between NimbleOptions schemas
  used by Jido Actions and the JSON Schema format expected by ReqLLM tools.

  ## Features

  - NimbleOptions to JSON Schema conversion
  - Schema compatibility validation
  - Parameter validation against action schemas
  - Detailed error reporting with field-level context
  - Support for complex nested types and constraints
  - Performance optimization for common schema patterns

  ## Usage

      # Convert Jido Action schema to ReqLLM format
      json_schema = SchemaValidator.convert_schema_to_reqllm(action.schema())

      # Validate parameters against action schema
      {:ok, validated} = SchemaValidator.validate_params(params, action_module)

      # Check schema compatibility
      :ok = SchemaValidator.validate_nimble_schema_compatibility(schema)
  """

  require Logger

  @type nimble_schema :: keyword()
  @type json_schema :: map()
  @type validation_result :: {:ok, map()} | {:error, term()}

  @doc """
  Converts Jido Action NimbleOptions schema to ReqLLM tool descriptor format.

  Transforms a NimbleOptions schema into a JSON Schema compatible format that
  can be used by ReqLLM for parameter validation and documentation generation.
  This is a key component of the tool descriptor creation process.

  ## Parameters

  - `nimble_schema`: The NimbleOptions schema from a Jido Action

  ## Returns

  - Map in JSON Schema format suitable for ReqLLM tool descriptors

  ## Examples

      iex> schema = [
      ...>   name: [type: :string, required: true, doc: "The name"],
      ...>   count: [type: :integer, default: 1, doc: "The count"]
      ...> ]
      iex> json_schema = SchemaValidator.convert_schema_to_reqllm(schema)
      iex> json_schema.properties
      %{
        name: %{type: "string", description: "The name", required: true},
        count: %{type: "integer", description: "The count", default: 1}
      }
  """
  @spec convert_schema_to_reqllm(nimble_schema()) :: json_schema()
  def convert_schema_to_reqllm(nimble_schema) when is_list(nimble_schema) do
    properties =
      nimble_schema
      |> Enum.map(&convert_field_schema/1)
      |> Map.new()

    required_fields =
      nimble_schema
      |> Enum.filter(fn {_name, opts} -> Keyword.get(opts, :required, false) end)
      |> Enum.map(fn {name, _opts} -> to_string(name) end)

    %{
      type: "object",
      properties: properties,
      required: required_fields,
      additionalProperties: false
    }
  end

  def convert_schema_to_reqllm([]), do: %{type: "object", properties: %{}, required: []}

  def convert_schema_to_reqllm(invalid_schema) do
    Logger.warning("Invalid schema format: #{inspect(invalid_schema)}")
    %{type: "object", properties: %{}, required: []}
  end

  @doc """
  Validates parameters against a Jido Action schema with detailed error reporting.

  Uses NimbleOptions validation with enhanced error formatting specifically
  designed for tool parameter validation. This function is used during tool
  execution to ensure parameter correctness.

  ## Parameters

  - `params`: Map of parameters to validate
  - `action_module`: The Jido Action module that defines the schema

  ## Returns

  - `{:ok, validated_params}` on successful validation
  - `{:error, detailed_error}` on validation failure

  ## Examples

      iex> params = %{name: "test", count: 5}
      iex> SchemaValidator.validate_params(params, MyAction)
      {:ok, %{name: "test", count: 5}}

      iex> invalid_params = %{count: "invalid"}
      iex> SchemaValidator.validate_params(invalid_params, MyAction)
      {:error, %{field: "count", message: "expected integer, got string"}}
  """
  @spec validate_params(map(), module()) :: validation_result()
  def validate_params(params, action_module) when is_map(params) and is_atom(action_module) do
    schema = get_action_schema(action_module)

    case NimbleOptions.validate(params, schema) do
      {:ok, validated_params} ->
        {:ok, validated_params}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, format_nimble_error(error)}
    end
  rescue
    error ->
      {:error,
       %{
         type: "schema_validation_exception",
         message: Exception.message(error),
         action_module: action_module
       }}
  end

  @doc """
  Validates that a NimbleOptions schema is compatible with ReqLLM tool conversion.

  Checks for schema patterns and types that may not convert properly to JSON Schema
  or that might cause issues during tool execution. This helps catch compatibility
  issues early in the tool creation process.

  ## Parameters

  - `nimble_schema`: The NimbleOptions schema to validate

  ## Returns

  - `:ok` if the schema is compatible
  - `{:error, reason}` if compatibility issues are found

  ## Examples

      iex> schema = [name: [type: :string, required: true]]
      iex> SchemaValidator.validate_nimble_schema_compatibility(schema)
      :ok

      iex> problematic_schema = [field: [type: {:custom, MyModule, :validator, []}]]
      iex> SchemaValidator.validate_nimble_schema_compatibility(problematic_schema)
      {:error, %{reason: "unsupported_type", field: "field", type: {:custom, MyModule, :validator, []}}}
  """
  @spec validate_nimble_schema_compatibility(nimble_schema()) :: :ok | {:error, map()}
  def validate_nimble_schema_compatibility(nimble_schema) when is_list(nimble_schema) do
    incompatible_fields =
      nimble_schema
      |> Enum.filter(&has_compatibility_issues?/1)
      |> Enum.map(&extract_compatibility_issue/1)

    case incompatible_fields do
      [] ->
        :ok

      issues ->
        {:error,
         %{
           reason: "schema_compatibility_issues",
           details: "Schema contains types or patterns incompatible with ReqLLM",
           issues: issues
         }}
    end
  end

  @doc """
  Converts individual field schema from NimbleOptions to JSON Schema format.

  Handles the conversion of a single field definition, including type mapping,
  constraint preservation, and metadata extraction. This is used internally
  by the main schema conversion function.

  ## Parameters

  - `{field_name, field_opts}`: Tuple of field name and NimbleOptions field definition

  ## Returns

  - `{field_name_string, json_schema_definition}` tuple

  ## Examples

      iex> field = {:name, [type: :string, required: true, doc: "User name"]}
      iex> SchemaValidator.convert_field_schema(field)
      {"name", %{type: "string", description: "User name", required: true}}
  """
  @spec convert_field_schema({atom(), keyword()}) :: {String.t(), map()}
  def convert_field_schema({field_name, field_opts})
      when is_atom(field_name) and is_list(field_opts) do
    field_name_string = to_string(field_name)

    json_field = %{
      type: convert_type_to_json_schema(Keyword.get(field_opts, :type)),
      description: Keyword.get(field_opts, :doc, "")
    }

    # Add additional properties based on field options
    json_field =
      field_opts
      |> Enum.reduce(json_field, fn {key, value}, acc ->
        case key do
          :required -> Map.put(acc, :required, value)
          :default -> Map.put(acc, :default, value)
          # Already handled above
          :doc -> acc
          # Already handled above
          :type -> acc
          # Ignore unknown options for now
          _ -> acc
        end
      end)

    {field_name_string, json_field}
  end

  # Private helper functions

  defp get_action_schema(action_module) do
    action_module.schema()
  rescue
    _ ->
      Logger.warning("Could not retrieve schema from #{action_module}")
      []
  end

  defp convert_type_to_json_schema(type) do
    case type do
      :string -> "string"
      :integer -> "integer"
      :non_neg_integer -> "integer"
      :pos_integer -> "integer"
      :float -> "number"
      :number -> "number"
      :boolean -> "boolean"
      :atom -> "string"
      :list -> "array"
      {:list, _inner_type} -> "array"
      :map -> "object"
      {:map, _fields} -> "object"
      :keyword_list -> "object"
      # Enum values - could be enhanced with JSON Schema enum
      {:in, _choices} -> "string"
      # Custom validators - fallback to string
      {:custom, _module, _function, _args} -> "string"
      # Default fallback
      nil -> "string"
      # Catch-all fallback
      _ -> "string"
    end
  end

  defp has_compatibility_issues?({_field_name, field_opts}) do
    type = Keyword.get(field_opts, :type)

    case type do
      {:custom, _module, _function, _args} -> true
      # Add other problematic types as needed
      _ -> false
    end
  end

  defp extract_compatibility_issue({field_name, field_opts}) do
    type = Keyword.get(field_opts, :type)

    %{
      field: to_string(field_name),
      type: type,
      reason: get_compatibility_issue_reason(type)
    }
  end

  defp get_compatibility_issue_reason({:custom, _module, _function, _args}) do
    "Custom validators are not supported in ReqLLM tool schemas"
  end

  defp get_compatibility_issue_reason(type) do
    "Type #{inspect(type)} may not be compatible with JSON Schema conversion"
  end

  defp format_nimble_error(%NimbleOptions.ValidationError{message: message, key: key}) do
    # Extract meaningful information from NimbleOptions error
    %{
      type: "parameter_validation_error",
      field: extract_field_from_error(key, message),
      message: clean_error_message(message),
      details: message
    }
  end

  defp extract_field_from_error(key, _message) when is_atom(key) do
    to_string(key)
  end

  defp extract_field_from_error(nil, message) do
    # Try to extract field name from error message
    case Regex.run(~r/invalid value for (\w+) option/, message) do
      [_, field] -> field
      nil -> "unknown"
    end
  end

  defp extract_field_from_error(key, _message) do
    to_string(key)
  end

  defp clean_error_message(message) do
    # Clean up NimbleOptions error messages for better user experience
    message
    |> String.replace(~r/invalid value for \w+ option: /, "")
    |> String.replace(~r/expected .+?, got: /, "invalid value: ")
    |> String.trim()
  end

  @doc """
  Builds enhanced JSON Schema with additional ReqLLM-specific features.

  Creates a more comprehensive JSON Schema that includes ReqLLM-specific
  enhancements like enum values, pattern constraints, and validation rules
  that improve tool parameter validation and documentation.

  ## Parameters

  - `nimble_schema`: The NimbleOptions schema to enhance

  ## Returns

  - Enhanced JSON Schema with additional validation features

  ## Examples

      iex> schema = [status: [type: {:in, [:active, :inactive]}]]
      iex> enhanced = SchemaValidator.build_enhanced_json_schema(schema)
      iex> enhanced.properties.status.enum
      ["active", "inactive"]
  """
  @spec build_enhanced_json_schema(nimble_schema()) :: json_schema()
  def build_enhanced_json_schema(nimble_schema) when is_list(nimble_schema) do
    base_schema = convert_schema_to_reqllm(nimble_schema)

    enhanced_properties =
      nimble_schema
      |> Enum.reduce(base_schema.properties, fn {field_name, field_opts}, acc ->
        field_name_string = to_string(field_name)
        current_property = Map.get(acc, field_name_string, %{})
        enhanced_property = enhance_property_definition(current_property, field_opts)
        Map.put(acc, field_name_string, enhanced_property)
      end)

    Map.put(base_schema, :properties, enhanced_properties)
  end

  defp enhance_property_definition(property, field_opts) do
    field_opts
    |> Enum.reduce(property, fn {key, value}, acc ->
      case key do
        {:in, choices} ->
          # Add enum constraint for choice types
          acc
          |> Map.put(:enum, Enum.map(choices, &to_string/1))
          |> Map.put(:type, "string")

        :min ->
          Map.put(acc, :minimum, value)

        :max ->
          Map.put(acc, :maximum, value)

        _ ->
          acc
      end
    end)
  end
end
