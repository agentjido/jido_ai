defmodule Jido.AI.Schema do
  @moduledoc """
  Internal schema definition system for structured LLM responses.

  This module provides a lightweight schema DSL for defining and validating
  structured data from LLM responses. It replaces the need for Ecto schemas
  and the Instructor library while maintaining similar functionality.

  ## Usage

  Define a schema using `defschema/2`:

      defmodule MyResponse do
        use Jido.AI.Schema

        defschema "A response with text and confidence" do
          field :response, :string, required: true, doc: "The response text"
          field :confidence, :float, required: true, doc: "Confidence score 0.0-1.0"
        end
      end

  The schema can then be used for validation and JSON schema generation:

      # Validate data
      Jido.AI.SchemaValidator.validate(data, MyResponse)

      # Generate JSON schema for LLM prompt
      Jido.AI.Schema.to_json_schema(MyResponse)

  ## Supported Field Types

  - `:string` - Text values
  - `:boolean` - true/false values
  - `:integer` - Whole numbers
  - `:float` - Decimal numbers
  - `{:list, type}` - Lists of a specific type
  """

  defmacro __using__(_opts) do
    quote do
      import Jido.AI.Schema, only: [defschema: 2, field: 2, field: 3]
      Module.register_attribute(__MODULE__, :schema_doc, [])
      Module.register_attribute(__MODULE__, :schema_fields, accumulate: true)
    end
  end

  @doc """
  Define a schema with a documentation string and field definitions.

  ## Options

  - `:required` - Whether the field is required (default: false)
  - `:doc` - Documentation for the field (used in JSON schema)
  - `:default` - Default value if not provided

  ## Example

      defschema "A user profile" do
        field :name, :string, required: true, doc: "User's full name"
        field :age, :integer, doc: "User's age in years"
        field :active, :boolean, default: true
      end
  """
  defmacro defschema(doc, do: block) do
    quote do
      @schema_doc unquote(doc)
      unquote(block)

      def __schema__(:doc), do: @schema_doc

      def __schema__(:fields) do
        @schema_fields
        |> Enum.reverse()
        |> Enum.map(fn {name, type, opts} ->
          %{
            name: name,
            type: type,
            required: Keyword.get(opts, :required, false),
            doc: Keyword.get(opts, :doc, ""),
            default: Keyword.get(opts, :default, nil)
          }
        end)
      end

      def __schema__(:field, field_name) do
        __schema__(:fields)
        |> Enum.find(&(&1.name == field_name))
      end
    end
  end

  @doc """
  Define a field in the schema.

  ## Options

  - `:required` - Field is required (default: false)
  - `:doc` - Documentation string
  - `:default` - Default value
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @schema_fields {unquote(name), unquote(type), unquote(opts)}
    end
  end

  @doc """
  Convert a schema module to JSON Schema format for LLM prompts.

  This generates a JSON Schema object that can be included in prompts
  to guide the LLM's output format.

  ## Example

      iex> Jido.AI.Schema.to_json_schema(MyResponse)
      %{
        "type" => "object",
        "description" => "A response with text and confidence",
        "properties" => %{
          "response" => %{"type" => "string", "description" => "The response text"},
          "confidence" => %{"type" => "number", "description" => "Confidence score 0.0-1.0"}
        },
        "required" => ["response", "confidence"]
      }
  """
  def to_json_schema(schema_module) do
    doc = schema_module.__schema__(:doc)
    fields = schema_module.__schema__(:fields)

    properties =
      fields
      |> Enum.map(fn field ->
        {Atom.to_string(field.name), field_to_json_schema(field)}
      end)
      |> Enum.into(%{})

    required =
      fields
      |> Enum.filter(& &1.required)
      |> Enum.map(&Atom.to_string(&1.name))

    %{
      "type" => "object",
      "description" => doc,
      "properties" => properties,
      "required" => required
    }
  end

  defp field_to_json_schema(field) do
    base = %{
      "type" => type_to_json_type(field.type),
      "description" => field.doc
    }

    case field.type do
      {:list, item_type} ->
        Map.put(base, "items", %{"type" => type_to_json_type(item_type)})

      _ ->
        base
    end
  end

  defp type_to_json_type(:string), do: "string"
  defp type_to_json_type(:boolean), do: "boolean"
  defp type_to_json_type(:integer), do: "integer"
  defp type_to_json_type(:float), do: "number"
  defp type_to_json_type({:list, _}), do: "array"

  @doc """
  Convert a schema to a human-readable format string for prompts.

  This generates a text description of the expected schema that can be
  included in system messages to guide the LLM.

  ## Example

      iex> Jido.AI.Schema.to_prompt_format(MyResponse)
      \"\"\"
      A response with text and confidence

      Expected JSON format:
      {
        "response": string (required) - The response text
        "confidence": number (required) - Confidence score 0.0-1.0
      }
      \"\"\"
  """
  def to_prompt_format(schema_module) do
    doc = schema_module.__schema__(:doc)
    fields = schema_module.__schema__(:fields)

    field_lines =
      fields
      |> Enum.map_join("\n", fn field ->
        required = if field.required, do: " (required)", else: ""
        type_str = format_type(field.type)
        ~s|  "#{field.name}": #{type_str}#{required} - #{field.doc}|
      end)

    """
    #{doc}

    Expected JSON format:
    {
    #{field_lines}
    }
    """
  end

  defp format_type(:string), do: "string"
  defp format_type(:boolean), do: "boolean"
  defp format_type(:integer), do: "integer"
  defp format_type(:float), do: "number"
  defp format_type({:list, type}), do: "array of #{format_type(type)}"
end
