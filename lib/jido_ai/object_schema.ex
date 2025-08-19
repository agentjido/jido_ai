defmodule Jido.AI.ObjectSchema do
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

  ## Enum Validation

  For enum output types, provide the allowed values:

      {:ok, schema} = ObjectSchema.new([
        output_type: :enum,
        enum_values: ["red", "green", "blue"]
      ])

      {:ok, "red"} = ObjectSchema.validate(schema, "red")
      {:error, _} = ObjectSchema.validate(schema, "purple")

  ## Examples

      # Object schema
      schema_opts = [
        output_type: :object,
        properties: [
          user: [
            type: {:map, [
              name: [type: :string, required: true],
              email: [type: :string, required: true]
            ]},
            required: true
          ],
          preferences: [
            type: {:list, :string},
            default: []
          ]
        ]
      ]

      # Array schema
      schema_opts = [
        output_type: :array,
        properties: [
          name: [type: :string, required: true],
          score: [type: :integer, required: true]
        ]
      ]

      # Enum schema
      schema_opts = [
        output_type: :enum,
        enum_values: ["small", "medium", "large"]
      ]

  """
  use TypedStruct

  alias Jido.AI.Error.SchemaValidation

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

  ## Examples

      # Object schema
      {:ok, schema} = ObjectSchema.new([
        output_type: :object,
        properties: [
          name: [type: :string, required: true],
          age: [type: :pos_integer]
        ]
      ])

      # Array schema  
      {:ok, schema} = ObjectSchema.new([
        output_type: :array,
        properties: [
          id: [type: :string, required: true],
          value: [type: :number]
        ]
      ])

      # Enum schema
      {:ok, schema} = ObjectSchema.new([
        output_type: :enum,
        enum_values: ["red", "green", "blue"]
      ])

      # No schema (unstructured)
      {:ok, schema} = ObjectSchema.new([output_type: :no_schema])

  """
  @spec new(schema_opts() | t()) :: {:ok, t()} | {:error, String.t()}
  def new(%__MODULE__{} = schema), do: {:ok, schema}

  def new(opts) when is_list(opts) do
    output_type = Keyword.get(opts, :output_type, :object)
    properties = Keyword.get(opts, :properties, [])
    enum_values = Keyword.get(opts, :enum_values, [])

    # Validate output type
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

  def new(_), do: {:error, "Schema options must be a keyword list or ObjectSchema struct"}

  @spec validate_output_type(atom()) :: :ok | {:error, String.t()}
  defp validate_output_type(output_type) do
    if output_type in [:object, :array, :enum, :no_schema] do
      :ok
    else
      {:error, "Invalid output_type: #{inspect(output_type)}. Must be one of: :object, :array, :enum, :no_schema"}
    end
  end

  @spec validate_enum_values(atom(), list()) :: :ok | {:error, String.t()}
  defp validate_enum_values(:enum, enum_values) do
    if enum_values == [] or not is_list(enum_values) do
      {:error, "enum_values must be a non-empty list when output_type is :enum"}
    else
      :ok
    end
  end

  defp validate_enum_values(_output_type, _enum_values), do: :ok

  @spec build_nimble_schema(atom(), keyword()) :: {:ok, NimbleOptions.t() | nil} | {:error, String.t()}
  defp build_nimble_schema(:no_schema, _properties), do: {:ok, nil}
  defp build_nimble_schema(:enum, _properties), do: {:ok, nil}
  defp build_nimble_schema(_output_type, []), do: {:ok, nil}

  defp build_nimble_schema(_output_type, properties) do
    schema = NimbleOptions.new!(properties)
    {:ok, schema}
  rescue
    e -> {:error, "Invalid properties schema: #{Exception.message(e)}"}
  end

  @doc """
  Creates a new ObjectSchema from various input formats, raising on error.

  See `new/1` for details.

  ## Examples

      schema = ObjectSchema.new!([
        output_type: :object,
        properties: [name: [type: :string, required: true]]
      ])

  """
  @spec new!(schema_opts() | t()) :: t() | no_return()
  def new!(opts) do
    case new(opts) do
      {:ok, schema} -> schema
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Validates data against the schema, raising an exception on validation failure.

  ## Parameters

    * `schema` - The ObjectSchema to validate against
    * `data` - The data to validate

  ## Examples

      schema = ObjectSchema.new!([
        output_type: :object,
        properties: [name: [type: :string, required: true]]
      ])

      user = ObjectSchema.validate!(schema, %{"name" => "John"})
      #=> %{"name" => "John"}

      # Raises SchemaValidation exception
      ObjectSchema.validate!(schema, %{})

  """
  @spec validate!(t(), term()) :: term() | no_return()
  def validate!(schema, data) do
    case validate(schema, data) do
      {:ok, validated_data} -> validated_data
      {:error, error} -> raise error
    end
  end

  @doc """
  Validates data against the schema.

  Returns `{:ok, validated_data}` on success or `{:error, validation_error}` on failure.

  ## Parameters

    * `schema` - The ObjectSchema to validate against  
    * `data` - The data to validate

  ## Examples

      # Object validation
      {:ok, schema} = ObjectSchema.new([
        output_type: :object,
        properties: [
          name: [type: :string, required: true],
          age: [type: :pos_integer]
        ]
      ])

      {:ok, validated} = ObjectSchema.validate(schema, %{"name" => "John", "age" => 30})
      {:error, _} = ObjectSchema.validate(schema, %{"age" => 30}) # missing required name

      # Enum validation
      {:ok, enum_schema} = ObjectSchema.new([
        output_type: :enum,
        enum_values: ["small", "medium", "large"]
      ])

      {:ok, "medium"} = ObjectSchema.validate(enum_schema, "medium")
      {:error, _} = ObjectSchema.validate(enum_schema, "extra-large")

      # Array validation
      {:ok, array_schema} = ObjectSchema.new([
        output_type: :array,
        properties: [name: [type: :string, required: true]]
      ])

      {:ok, validated} = ObjectSchema.validate(array_schema, [%{"name" => "Alice"}, %{"name" => "Bob"}])

  """
  @spec validate(t(), term()) :: validation_result()
  def validate(%__MODULE__{output_type: :no_schema}, data) do
    # No schema validation - accept any data
    {:ok, data}
  end

  def validate(%__MODULE__{output_type: :enum, enum_values: enum_values}, data) do
    if data in enum_values do
      {:ok, data}
    else
      error =
        SchemaValidation.exception(
          validation_errors: ["Value #{inspect(data)} is not one of: #{inspect(enum_values)}"],
          schema: %{output_type: :enum, enum_values: enum_values}
        )

      {:error, error}
    end
  end

  def validate(%__MODULE__{output_type: :array, schema: nil}, data) when is_list(data) do
    # Array with no properties schema - accept any list
    {:ok, data}
  end

  def validate(%__MODULE__{output_type: :array, schema: schema}, data) when is_list(data) do
    # Validate each item in the array against the schema
    case validate_array_items(data, schema, []) do
      {:ok, validated_items} ->
        {:ok, validated_items}

      {:error, errors} ->
        error =
          SchemaValidation.exception(
            validation_errors: errors,
            schema: %{output_type: :array, properties: schema}
          )

        {:error, error}
    end
  end

  def validate(%__MODULE__{output_type: :array}, data) do
    error =
      SchemaValidation.exception(
        validation_errors: ["Expected array, got: #{inspect(data)}"],
        schema: %{output_type: :array}
      )

    {:error, error}
  end

  def validate(%__MODULE__{output_type: :object, schema: nil}, data) when is_map(data) do
    # Object with no properties schema - accept any map
    {:ok, data}
  end

  def validate(%__MODULE__{output_type: :object, schema: schema}, data) when is_map(data) do
    # Convert string keys to atoms for NimbleOptions validation if needed
    normalized_data = normalize_map_keys(data)

    case NimbleOptions.validate(normalized_data, schema) do
      {:ok, validated_data} ->
        {:ok, validated_data}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        validation_error =
          SchemaValidation.exception(
            validation_errors: [Exception.message(error)],
            schema: %{output_type: :object, properties: schema}
          )

        {:error, validation_error}
    end
  end

  def validate(%__MODULE__{output_type: :object}, data) do
    error =
      SchemaValidation.exception(
        validation_errors: ["Expected object (map), got: #{inspect(data)}"],
        schema: %{output_type: :object}
      )

    {:error, error}
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

  # Private helpers

  @spec validate_array_items(list(), NimbleOptions.t(), list()) ::
          {:ok, list()} | {:error, list(String.t())}
  defp validate_array_items([], _schema, acc), do: {:ok, Enum.reverse(acc)}

  defp validate_array_items([item | rest], schema, acc) do
    case validate_single_item(item, schema) do
      {:ok, validated_item} ->
        validate_array_items(rest, schema, [validated_item | acc])

      {:error, error_msg} ->
        {:error, ["Item #{length(acc) + 1}: #{error_msg}"]}
    end
  end

  @spec validate_single_item(term(), NimbleOptions.t()) :: {:ok, term()} | {:error, String.t()}
  defp validate_single_item(item, schema) when is_map(item) do
    normalized_item = normalize_map_keys(item)

    case NimbleOptions.validate(normalized_item, schema) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error, Exception.message(error)}
    end
  end

  defp validate_single_item(item, _schema) do
    {:error, "Expected map, got: #{inspect(item)}"}
  end

  @spec normalize_map_keys(map()) :: map()
  defp normalize_map_keys(map) when is_map(map) do
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
end
