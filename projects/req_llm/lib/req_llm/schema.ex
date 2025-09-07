defmodule ReqLLM.Schema do
  @moduledoc """
  JSON Schema utilities for converting NimbleOptions schemas to JSON Schema format.

  This module provides functions to convert NimbleOptions parameter definitions
  into JSON Schema format for use with LLM providers that expect structured schemas.
  """

  @doc """
  Compiles a NimbleOptions schema from a keyword list.

  ## Parameters

  - `schema` - A keyword list representing a NimbleOptions schema

  ## Returns

  - `{:ok, compiled_schema}` - Successfully compiled schema
  - `{:error, error}` - Compilation error with details

  ## Examples

      iex> ReqLLM.Schema.compile_schema([name: [type: :string, required: true]])
      {:ok, compiled_schema}

      iex> ReqLLM.Schema.compile_schema("invalid")
      {:error, %ReqLLM.Error.Invalid.Parameter{}}
  """
  @spec compile_schema(keyword() | any()) ::
          {:ok, NimbleOptions.t()} | {:error, ReqLLM.Error.t()}
  def compile_schema(schema) when is_list(schema) do
    try do
      {:ok, NimbleOptions.new!(schema)}
    rescue
      e ->
        {:error,
         ReqLLM.Error.Validation.Error.exception(
           tag: :invalid_schema,
           reason: "Invalid schema: #{Exception.message(e)}",
           context: [schema: schema]
         )}
    end
  end

  def compile_schema(schema) do
    {:error,
     ReqLLM.Error.Invalid.Parameter.exception(
       parameter: "Schema must be a keyword list, got: #{inspect(schema)}"
     )}
  end

  @doc """
  Converts NimbleOptions parameters to JSON Schema format.

  Takes a keyword list of parameter definitions and converts them to
  a JSON Schema object suitable for LLM tool definitions.

  ## Parameters

  - `parameters` - Keyword list of parameter definitions

  ## Returns

  A map representing the JSON Schema object with properties and required fields.

  ## Examples

      iex> ReqLLM.Schema.parameters_to_json_schema([
      ...>   name: [type: :string, required: true, doc: "User name"],
      ...>   age: [type: :integer, doc: "User age"]
      ...> ])
      %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string", "description" => "User name"},
          "age" => %{"type" => "integer", "description" => "User age"}
        },
        "required" => ["name"]
      }
  """
  @spec parameters_to_json_schema(keyword()) :: map()
  def parameters_to_json_schema([]), do: %{"type" => "object", "properties" => %{}}

  def parameters_to_json_schema(parameters) do
    {properties, required} =
      Enum.reduce(parameters, {%{}, []}, fn {key, opts}, {props_acc, req_acc} ->
        property_name = to_string(key)
        json_prop = nimble_type_to_json_schema(opts[:type] || :string, opts)

        new_props = Map.put(props_acc, property_name, json_prop)
        new_req = if opts[:required], do: [property_name | req_acc], else: req_acc

        {new_props, new_req}
      end)

    schema = %{
      "type" => "object",
      "properties" => properties
    }

    if required == [] do
      schema
    else
      Map.put(schema, "required", Enum.reverse(required))
    end
  end

  @doc """
  Converts a NimbleOptions type to JSON Schema property definition.

  Takes a NimbleOptions type atom and options, converting them to the
  corresponding JSON Schema property definition.

  ## Parameters

  - `type` - The NimbleOptions type atom (e.g., `:string`, `:integer`, `{:list, :string}`)
  - `opts` - Additional options including `:doc` for description

  ## Returns

  A map representing the JSON Schema property definition.

  ## Examples

      iex> ReqLLM.Schema.nimble_type_to_json_schema(:string, doc: "A text field")
      %{"type" => "string", "description" => "A text field"}

      iex> ReqLLM.Schema.nimble_type_to_json_schema({:list, :integer}, [])
      %{"type" => "array", "items" => %{"type" => "integer"}}
  """
  @spec nimble_type_to_json_schema(atom() | tuple(), keyword()) :: map()
  def nimble_type_to_json_schema(type, opts) do
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
end
