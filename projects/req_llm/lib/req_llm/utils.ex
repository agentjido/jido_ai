defmodule ReqLLM.Utils do
  @moduledoc """
  Utility functions for ReqLLM, following Vercel AI SDK patterns.
  
  Provides helper functions for tool creation, schema validation, 
  and embedding similarity calculations.
  """

  alias ReqLLM.Tool

  @doc """
  Creates a Tool struct for AI model function calling.
  
  This function is equivalent to Vercel AI SDK's `tool()` helper, 
  providing type-safe tool definitions with parameter validation.
  
  ## Parameters
  
    * `opts` - Tool definition options
  
  ## Options
  
    * `:name` - Tool name (required, must be valid identifier)
    * `:description` - Tool description for AI model (required)
    * `:parameters` - Parameter schema as NimbleOptions keyword list (optional)
    * `:callback` - Callback function or MFA tuple (required)
  
  ## Examples
  
      # Simple tool with no parameters
      tool = ReqLLM.tool(
        name: "get_time",
        description: "Get the current time",
        callback: fn _args -> {:ok, DateTime.utc_now()} end
      )
  
      # Tool with parameters
      weather_tool = ReqLLM.tool(
        name: "get_weather",
        description: "Get current weather for a location",
        parameters: [
          location: [type: :string, required: true, doc: "City name"],
          units: [type: :string, default: "metric", doc: "Temperature units"]
        ],
        callback: {WeatherAPI, :fetch_weather}
      )
  
  """
  @spec tool(keyword()) :: Tool.t()
  def tool(opts) when is_list(opts) do
    Tool.new!(opts)
  end

  @doc """
  Creates a JSON schema object compatible with ReqLLM.
  
  Equivalent to Vercel AI SDK's `jsonSchema()` helper, this function
  creates schema objects for structured data generation and validation.
  
  ## Parameters
  
    * `schema` - NimbleOptions schema definition (keyword list)
    * `opts` - Additional options (optional)
  
  ## Options
  
    * `:validate` - Custom validation function (optional)
  
  ## Examples
  
      # Basic schema
      schema = ReqLLM.json_schema([
        name: [type: :string, required: true, doc: "User name"],
        age: [type: :integer, doc: "User age"]
      ])
  
      # Schema with custom validation
      schema = ReqLLM.json_schema(
        [email: [type: :string, required: true]],
        validate: fn value -> 
          if String.contains?(value["email"], "@") do
            {:ok, value}
          else
            {:error, "Invalid email format"}
          end
        end
      )
  
  """
  @spec json_schema(keyword(), keyword()) :: map()
  def json_schema(schema, opts \\ []) when is_list(schema) and is_list(opts) do
    json_schema = parameters_to_json_schema(schema)
    
    case opts[:validate] do
      nil -> json_schema
      validator when is_function(validator, 1) ->
        Map.put(json_schema, :validate, validator)
    end
  end

  @doc """
  Calculates cosine similarity between two embedding vectors.
  
  Equivalent to Vercel AI SDK's `cosineSimilarity()` function.
  Returns a similarity score between -1 and 1, where:
  - 1.0 indicates identical vectors (maximum similarity)
  - 0.0 indicates orthogonal vectors (no similarity)
  - -1.0 indicates opposite vectors (maximum dissimilarity)
  
  ## Parameters
  
    * `embedding_a` - First embedding vector (list of numbers)
    * `embedding_b` - Second embedding vector (list of numbers)
  
  ## Examples
  
      # Identical vectors
      ReqLLM.cosine_similarity([1.0, 0.0, 0.0], [1.0, 0.0, 0.0])
      #=> 1.0
  
      # Orthogonal vectors
      ReqLLM.cosine_similarity([1.0, 0.0], [0.0, 1.0])
      #=> 0.0
  
      # Opposite vectors
      ReqLLM.cosine_similarity([1.0, 0.0], [-1.0, 0.0])
      #=> -1.0
  
      # Similar vectors
      ReqLLM.cosine_similarity([0.5, 0.8, 0.3], [0.6, 0.7, 0.4])
      #=> 0.9487...
  
  """
  @spec cosine_similarity([number()], [number()]) :: float()
  def cosine_similarity(embedding_a, embedding_b) 
      when is_list(embedding_a) and is_list(embedding_b) do
    if length(embedding_a) != length(embedding_b) do
      raise ArgumentError, "Embedding vectors must have the same length"
    end

    if length(embedding_a) == 0 do
      0.0
    else
      dot_product = 
        embedding_a 
        |> Enum.zip(embedding_b)
        |> Enum.reduce(0, fn {a, b}, acc -> acc + a * b end)

      magnitude_a = :math.sqrt(Enum.reduce(embedding_a, 0, fn x, acc -> acc + x * x end))
      magnitude_b = :math.sqrt(Enum.reduce(embedding_b, 0, fn x, acc -> acc + x * x end))

      if magnitude_a == 0 or magnitude_b == 0 do
        0.0
      else
        dot_product / (magnitude_a * magnitude_b)
      end
    end
  end

  # Private helper functions

  defp parameters_to_json_schema([]), do: %{"type" => "object", "properties" => %{}}

  defp parameters_to_json_schema(parameters) do
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
end
