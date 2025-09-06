defmodule ReqAI.ObjectSchema do
  @moduledoc """
  Schema handling and validation for structured data generation.

  Provides schema definition, validation, and configuration for AI-generated structured objects.
  Supports various output types including objects, arrays, enums, and unstructured responses.

  ## Schema Definition

  Schemas are defined using NimbleOptions-compatible keyword lists:

      schema = [
        name: [type: :string, required: true, doc: "Full name"],
        age: [type: :pos_integer, doc: "Age in years"],
        tags: [type: {:list, :string}, default: [], doc: "List of tags"]
      ]

  ## Output Types

  - `:object` - Generate a structured object matching the schema
  - `:array` - Generate an array of objects matching the schema  
  - `:enum` - Generate one of the predefined enum values
  - `:no_schema` - Generate unstructured text (no validation)

  ## Basic Usage

      # Create schema
      {:ok, schema} = ObjectSchema.new([
        output_type: :object,
        properties: [
          name: [type: :string, required: true],
          age: [type: :pos_integer]
        ]
      ])

      # Validate data
      data = %{"name" => "John", "age" => 30}
      {:ok, validated} = ObjectSchema.validate(schema, data)

      # Or validate with exceptions
      validated = ObjectSchema.validate!(schema, data)

  ## JSON Schema Export

  Convert to JSON Schema format for LLM integration:

      json_schema = ObjectSchema.to_json_schema(schema)
      # Returns standard JSON Schema with field descriptions

  """
  use TypedStruct

  alias ReqAI.Error.SchemaValidation

  typedstruct do
    @derive {Jason.Encoder, only: [:output_type, :properties, :enum_values]}

    field(:output_type, :object | :array | :enum | :no_schema)
    field(:properties, keyword() | nil)
    field(:enum_values, [String.t()] | nil)
    field(:schema, NimbleOptions.t() | nil)
  end

  @type schema_opts :: [
          output_type: :object | :array | :enum | :no_schema,
          properties: keyword(),
          enum_values: [String.t()]
        ]

  @type validation_result :: {:ok, term()} | {:error, SchemaValidation.t()}

  @doc """
  Creates a new ObjectSchema from various input formats.

  ## Parameters

    * `opts` - Schema options as keyword list or existing ObjectSchema struct

  ## Options

    * `:output_type` - Type of output: `:object`, `:array`, `:enum`, `:no_schema` (default: `:object`)
    * `:properties` - Schema properties for object/array validation (keyword list)
    * `:enum_values` - List of allowed values for enum validation

  """
  @spec new(schema_opts() | t()) :: {:ok, t()} | {:error, String.t()}
  def new(%__MODULE__{} = schema), do: {:ok, schema}

  def new(opts) when is_list(opts) do
    output_type = Keyword.get(opts, :output_type, :object)
    properties = Keyword.get(opts, :properties, [])
    enum_values = Keyword.get(opts, :enum_values, [])

    with :ok <- validate_output_type(output_type),
         :ok <- validate_enum_values(output_type, enum_values),
         {:ok, nimble_schema} <- build_nimble_schema(output_type, properties) do
      schema = %__MODULE__{
        output_type: output_type,
        properties: properties,
        enum_values: enum_values,
        schema: nimble_schema
      }

      {:ok, schema}
    end
  end

  def new(_),
    do:
      {:error,
       ReqAI.Error.Invalid.Schema.exception(
         reason: "Schema options must be a keyword list or ObjectSchema struct"
       )}

  @doc """
  Creates a new ObjectSchema from various input formats, raising on error.

  See `new/1` for details.
  """
  @spec new!(schema_opts() | t()) :: t() | no_return()
  def new!(opts) do
    case new(opts) do
      {:ok, schema} -> schema
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Validates data against the schema.

  Returns `{:ok, validated_data}` on success or `{:error, validation_error}` on failure.
  """
  @spec validate(t(), term()) :: validation_result()
  def validate(%__MODULE__{output_type: :no_schema}, data) do
    {:ok, data}
  end

  def validate(%__MODULE__{output_type: :enum, enum_values: enum_values}, data) do
    if data in enum_values do
      {:ok, data}
    else
      {:error,
       build_error(["Value #{inspect(data)} is not one of: #{inspect(enum_values)}"], %{
         output_type: :enum,
         enum_values: enum_values
       })}
    end
  end

  def validate(%__MODULE__{output_type: :object, schema: nil}, data) when is_map(data) do
    {:ok, data}
  end

  def validate(%__MODULE__{output_type: :object, schema: schema}, data) when is_map(data) do
    normalized_data = normalize_keys(data)

    case NimbleOptions.validate(normalized_data, schema) do
      {:ok, validated_data} ->
        {:ok, validated_data}

      {:error, error} ->
        {:error, build_error([Exception.message(error)], %{output_type: :object})}
    end
  end

  def validate(%__MODULE__{output_type: :object}, data) do
    {:error,
     build_error(["Expected object (map), got: #{inspect(data)}"], %{output_type: :object})}
  end

  def validate(%__MODULE__{output_type: :array, schema: nil}, data) when is_list(data) do
    {:ok, data}
  end

  def validate(%__MODULE__{output_type: :array, schema: schema}, data) when is_list(data) do
    case validate_array_items(data, schema) do
      {:ok, validated_items} -> {:ok, validated_items}
      {:error, errors} -> {:error, build_error(errors, %{output_type: :array})}
    end
  end

  def validate(%__MODULE__{output_type: :array}, data) do
    {:error, build_error(["Expected array, got: #{inspect(data)}"], %{output_type: :array})}
  end

  @doc """
  Validates data against the schema, raising an exception on validation failure.
  """
  @spec validate!(t(), term()) :: term() | no_return()
  def validate!(schema, data) do
    case validate(schema, data) do
      {:ok, validated_data} -> validated_data
      {:error, error} -> raise error
    end
  end

  @doc """
  Extracts the output type from schema options.

  ## Parameters

    * `schema` - ObjectSchema struct or schema options

  ## Examples

      ObjectSchema.output_type(%ObjectSchema{output_type: :array})
      #=> :array

      ObjectSchema.output_type([output_type: :enum])
      #=> :enum

      ObjectSchema.output_type([]) # default
      #=> :object

  """
  @spec output_type(t() | schema_opts()) :: :object | :array | :enum | :no_schema
  def output_type(%__MODULE__{output_type: type}), do: type
  def output_type(opts) when is_list(opts), do: Keyword.get(opts, :output_type, :object)

  @doc """
  Converts ObjectSchema to JSON Schema format for LLM integration.

  Returns a map containing standard JSON Schema structure with field descriptions
  from `:doc` fields.

  ## Examples

      schema = ObjectSchema.new!([
        output_type: :object,
        properties: [
          name: [type: :string, required: true, doc: "Full name"],
          age: [type: :integer, doc: "Age in years"]
        ]
      ])

      json_schema = ObjectSchema.to_json_schema(schema)
      #=> %{
      #     "type" => "object",
      #     "properties" => %{
      #       "name" => %{"type" => "string", "description" => "Full name"},
      #       "age" => %{"type" => "integer", "description" => "Age in years"}
      #     },
      #     "required" => ["name"]
      #   }

  """
  @spec to_json_schema(t()) :: map()
  def to_json_schema(%__MODULE__{output_type: :no_schema}) do
    %{"type" => "string"}
  end

  def to_json_schema(%__MODULE__{output_type: :enum, enum_values: values}) do
    %{"enum" => values}
  end

  def to_json_schema(%__MODULE__{output_type: :object, properties: properties}) do
    %{"type" => "object"}
    |> add_object_properties(properties)
  end

  def to_json_schema(%__MODULE__{output_type: :array, properties: properties}) do
    item_schema =
      %{"type" => "object"}
      |> add_object_properties(properties)

    %{
      "type" => "array",
      "items" => item_schema
    }
  end

  # Private helpers

  defp validate_output_type(output_type) do
    if output_type in [:object, :array, :enum, :no_schema] do
      :ok
    else
      {:error,
       "Invalid output_type: #{inspect(output_type)}. Must be one of: :object, :array, :enum, :no_schema"}
    end
  end

  defp validate_enum_values(:enum, enum_values) do
    if enum_values == [] or not is_list(enum_values) do
      {:error,
       ReqAI.Error.Invalid.Schema.exception(
         reason: "enum_values must be a non-empty list when output_type is :enum"
       )}
    else
      :ok
    end
  end

  defp validate_enum_values(_output_type, _enum_values), do: :ok

  defp build_nimble_schema(type, _properties) when type in [:no_schema, :enum], do: {:ok, nil}
  defp build_nimble_schema(_output_type, []), do: {:ok, nil}

  defp build_nimble_schema(_output_type, properties) do
    {:ok, NimbleOptions.new!(properties)}
  rescue
    e ->
      {:error,
       ReqAI.Error.Invalid.Schema.exception(
         reason: "Invalid properties schema: #{Exception.message(e)}"
       )}
  end

  defp validate_array_items(items, schema) do
    items
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case validate_item(item, schema) do
        {:ok, validated_item} -> {:cont, {:ok, [validated_item | acc]}}
        {:error, error} -> {:halt, {:error, ["Item #{index}: #{error}"]}}
      end
    end)
    |> case do
      {:ok, validated_items} -> {:ok, Enum.reverse(validated_items)}
      error -> error
    end
  end

  defp validate_item(item, schema) when is_map(item) do
    normalized_item = normalize_keys(item)

    case NimbleOptions.validate(normalized_item, schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, error} -> {:error, Exception.message(error)}
    end
  end

  defp validate_item(item, _schema) do
    {:error, ReqAI.Error.Invalid.Schema.exception(reason: "Expected map, got: #{inspect(item)}")}
  end

  defp normalize_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_binary(key) ->
        try do
          {String.to_existing_atom(key), value}
        rescue
          ArgumentError -> {String.to_atom(key), value}
        end

      {key, value} ->
        {key, value}
    end)
  end

  defp build_error(errors, schema_info) do
    SchemaValidation.exception(
      validation_errors: errors,
      schema: schema_info
    )
  end

  defp add_object_properties(schema, nil), do: schema
  defp add_object_properties(schema, []), do: schema

  defp add_object_properties(schema, properties) do
    {json_properties, required_fields} =
      Enum.reduce(properties, {%{}, []}, fn {key, opts}, {props_acc, req_acc} ->
        property_name = to_string(key)
        json_prop = nimble_type_to_json_schema(opts[:type] || :string, opts)

        new_props = Map.put(props_acc, property_name, json_prop)
        new_req = if opts[:required], do: [property_name | req_acc], else: req_acc

        {new_props, new_req}
      end)

    schema
    |> Map.put("properties", json_properties)
    |> maybe_add_required(required_fields)
  end

  defp nimble_type_to_json_schema(type, opts) do
    base_schema =
      case type do
        :string ->
          %{"type" => "string"}

        :integer ->
          %{"type" => "integer"}

        :pos_integer ->
          %{"type" => "integer", "minimum" => 1}

        :float ->
          %{"type" => "number"}

        :number ->
          %{"type" => "number"}

        :boolean ->
          %{"type" => "boolean"}

        {:list, :string} ->
          %{"type" => "array", "items" => %{"type" => "string"}}

        {:list, :integer} ->
          %{"type" => "array", "items" => %{"type" => "integer"}}

        {:list, item_type} ->
          %{"type" => "array", "items" => nimble_type_to_json_schema(item_type, %{})}

        :map ->
          %{"type" => "object"}

        _ ->
          %{"type" => "string"}
      end

    case opts[:doc] do
      nil -> base_schema
      doc -> Map.put(base_schema, "description", doc)
    end
  end

  defp maybe_add_required(schema, []), do: schema

  defp maybe_add_required(schema, required_fields) do
    Map.put(schema, "required", Enum.reverse(required_fields))
  end
end
