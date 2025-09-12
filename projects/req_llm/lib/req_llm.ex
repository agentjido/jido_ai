defmodule ReqLLM do
  @moduledoc """
  Main API facade for Req AI.

  Inspired by the Vercel AI SDK, provides a unified interface to AI providers with
  flexible model specifications, rich prompt support, configuration management,
  and structured data generation.

  ## Quick Start

      # Simple text generation using string format
      ReqLLM.generate_text("anthropic:claude-3-5-sonnet", "Hello world")
      #=> {:ok, "Hello! How can I assist you today?"}

      # Structured data generation with schema validation
      schema = [
        name: [type: :string, required: true],
        age: [type: :pos_integer, required: true]
      ]
      ReqLLM.generate_object("anthropic:claude-3-5-sonnet", "Generate a person", schema)
      #=> {:ok, %{name: "John Doe", age: 30}}

  ## Model Specifications

  Multiple formats supported for maximum flexibility:

      # String format: "provider:model"
      ReqLLM.generate_text("anthropic:claude-3-5-sonnet-20241022", messages)

      # Tuple format: {provider, options}
      ReqLLM.generate_text({:anthropic, "claude-3-5-sonnet", temperature: 0.7}, messages)

      # Model struct format
      model = %ReqLLM.Model{provider: :anthropic, model: "claude-3-5-sonnet", temperature: 0.5}
      ReqLLM.generate_text(model, messages)

  ## Configuration

  ReqLLM uses the Kagi keyring for API key storage:

      # Store API keys in session keyring
      ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")
      ReqLLM.put_key(:openai_api_key, "sk-...")

      # Retrieve API keys
      ReqLLM.get_key(:anthropic_api_key)

  ## Providers

  Built-in support for major AI providers:

  - **Anthropic**: Claude 3.5 Sonnet, Claude 3 Haiku, Claude 3 Opus

      # Access provider modules directly
      provider = ReqLLM.provider(:anthropic)
      provider.generate_text(model, messages, opts)
  """

  alias ReqLLM.{Embedding, Generation, Schema, Tool}

  # ===========================================================================
  # Configuration API - Direct Kagi integration
  # ===========================================================================

  @doc """
  Stores an API key in the session keyring.

  Key normalization is handled automatically (case-insensitive).

  ## Parameters

    * `key` - The configuration key (atom or string)
    * `value` - The value to store

  ## Examples

      ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")

  """
  @spec put_key(atom() | String.t(), term()) :: :ok
  def put_key(key, value) do
    normalized_key = normalize_key(key)
    JidoKeys.put(normalized_key, value)
  end

  @doc """
  Gets an API key from the keyring.

  Key lookup is case-insensitive and accepts both atoms and strings.

  ## Parameters

    * `key` - The configuration key (atom or string, case-insensitive)

  ## Examples

      ReqLLM.get_key(:anthropic_api_key)
      ReqLLM.get_key("ANTHROPIC_API_KEY")

  """
  @spec get_key(atom() | String.t()) :: String.t() | nil
  def get_key(key) do
    normalized_key = normalize_key(key)
    JidoKeys.get(normalized_key, nil)
  end

  # Private helper for key normalization
  @spec normalize_key(atom() | String.t()) :: atom()
  defp normalize_key(key) when is_binary(key) do
    normalized_string = String.downcase(key)

    try do
      String.to_existing_atom(normalized_string)
    rescue
      ArgumentError -> String.to_atom(normalized_string)
    end
  end

  defp normalize_key(key) when is_atom(key) do
    normalized_string = key |> Atom.to_string() |> String.downcase()

    try do
      String.to_existing_atom(normalized_string)
    rescue
      ArgumentError -> String.to_atom(normalized_string)
    end
  end

  @doc """
  Creates a messages collection from a list of messages.

  ## Parameters

    * `messages` - List of Message structs

  ## Examples

      messages = [
        ReqLLM.Context.system("You are helpful"),
        ReqLLM.Context.user("Hello!")
      ]
      collection = ReqLLM.messages(messages)
      # Now you can use Enum functions on the collection
      user_msgs = collection |> Enum.filter(&(&1.role == :user))

  """
  @spec messages([struct()]) :: ReqLLM.Context.t()
  def messages(message_list) when is_list(message_list) do
    ReqLLM.Context.new(message_list)
  end

  @doc """
  Gets a provider module from the registry.

  ## Parameters

    * `provider` - Provider identifier (atom)

  ## Examples

      ReqLLM.provider(:anthropic)
      #=> {:ok, ReqLLM.Providers.Anthropic}

      ReqLLM.provider(:unknown)
      #=> {:error, :not_found}

  """
  @spec provider(atom()) :: {:ok, module()} | {:error, :not_found}
  def provider(provider) when is_atom(provider) do
    ReqLLM.Provider.Registry.fetch(provider)
  end

  @doc """
  Creates a model struct from various specifications.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - String format: `"anthropic:claude-3-sonnet"`
      - Tuple format: `{:anthropic, "claude-3-sonnet", temperature: 0.7}`
      - Model struct: `%ReqLLM.Model{}`

  ## Examples

      ReqLLM.model("anthropic:claude-3-sonnet")
      #=> {:ok, %ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet"}}

      ReqLLM.model({:anthropic, "claude-3-sonnet", temperature: 0.5})
      #=> {:ok, %ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet", temperature: 0.5}}

  """
  @spec model(String.t() | {atom(), keyword()} | struct()) :: {:ok, struct()} | {:error, term()}
  def model(model_spec) do
    ReqLLM.Model.from(model_spec)
  end

  # ===========================================================================
  # Text Generation API - Delegated to ReqLLM.Generation
  # ===========================================================================

  @doc """
  Generates text using an AI model with full response metadata.

  Returns the complete Req.Response which includes usage data, headers, and metadata.
  For simple text-only results, use `generate_text!/3`.

  ## Parameters

    * `model_spec` - Model specification in various formats
    * `messages` - Text prompt or list of messages
    * `opts` - Additional options (keyword list)

  ## Options

    * `:temperature` - Control randomness in responses (0.0 to 2.0)
    * `:max_tokens` - Limit the length of the response
    * `:top_p` - Nucleus sampling parameter
    * `:presence_penalty` - Penalize new tokens based on presence
    * `:frequency_penalty` - Penalize new tokens based on frequency
    * `:tools` - List of tool definitions
    * `:tool_choice` - Tool choice strategy
    * `:system_prompt` - System prompt to prepend
    * `:provider_options` - Provider-specific options

  ## Examples

      {:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello world")
      response.body
      #=> "Hello! How can I assist you today?"

      # Access usage metadata
      {:ok, text, usage} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello") |> ReqLLM.with_usage()

  """
  defdelegate generate_text(model_spec, messages, opts \\ []), to: Generation

  @doc """
  Generates text using an AI model, returning only the text content.

  This is a convenience function that extracts just the text from the response.
  For access to usage metadata and other response data, use `generate_text/3`.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-sonnet", "Hello world")
      text
      #=> "Hello! How can I assist you today?"

  """
  defdelegate generate_text!(model_spec, messages, opts \\ []), to: Generation

  @doc """
  Streams text generation using an AI model with full response metadata.

  Returns the complete response containing usage data and metadata.
  For simple streaming without metadata, use `stream_text!/3`.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, response} = ReqLLM.stream_text("anthropic:claude-3-sonnet", "Tell me a story")
      response.body |> Enum.each(&IO.write/1)

      # Access usage metadata after streaming
      {:ok, stream, usage} = ReqLLM.stream_text("anthropic:claude-3-sonnet", "Hello") |> ReqLLM.with_usage()

  """
  defdelegate stream_text(model_spec, messages, opts \\ []), to: Generation

  @doc """
  Streams text generation using an AI model, returning only the stream.

  This is a convenience function that extracts just the stream from the response.
  For access to usage metadata and other response data, use `stream_text/3`.

  ## Parameters

  Same as `stream_text/3`.

  ## Examples

      {:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Tell me a story")
      stream |> Enum.each(&IO.write/1)

  """
  defdelegate stream_text!(model_spec, messages, opts \\ []), to: Generation

  @doc """
  Extracts token usage information from a ReqLLM result.

  Designed to be used in a pipeline after `generate_text` or `stream_text` calls.
  Works with both Response objects (from `generate_text/3`) and plain results (from `generate_text!/3`).

  ## Parameters

    * `result` - The result tuple from any ReqLLM function

  ## Examples

      # Generate text with usage info - pipeline style
      {:ok, text, usage} =
        ReqLLM.generate_text("openai:gpt-4o", "Hello")
        |> ReqLLM.with_usage()

      usage
      #=> %{tokens: %{input: 10, output: 15}, cost: 0.00075}

      # Works with bang functions too (returns nil usage)
      {:ok, text, usage} =
        ReqLLM.generate_text!("openai:gpt-4o", "Hello")
        |> ReqLLM.with_usage()

      usage  #=> nil

      # Stream text with usage info
      {:ok, stream, usage} =
        ReqLLM.stream_text("openai:gpt-4o", "Hello")
        |> ReqLLM.with_usage()

  """
  defdelegate with_usage(result), to: Generation

  @doc """
  Extracts cost information from a ReqLLM result.

  Designed to be used in a pipeline after `generate_text` or `stream_text` calls.
  Works with both Response objects (from `generate_text/3`) and plain results (from `generate_text!/3`).

  ## Parameters

    * `result` - The result tuple from any ReqLLM function

  ## Examples

      # Generate text with cost info - pipeline style
      {:ok, text, cost} =
        ReqLLM.generate_text("openai:gpt-4o", "Hello")
        |> ReqLLM.with_cost()

      cost
      #=> 0.00075

      # Works with bang functions too (returns nil cost)
      {:ok, text, cost} =
        ReqLLM.generate_text!("openai:gpt-4o", "Hello")
        |> ReqLLM.with_cost()

      cost  #=> nil

      # Stream text with cost info - pipeline style
      {:ok, stream, cost} =
        ReqLLM.stream_text("openai:gpt-4o", "Hello")
        |> ReqLLM.with_cost()

  """
  defdelegate with_cost(result), to: Generation

  # ===========================================================================
  # Embedding API - Delegated to ReqLLM.Embedding
  # ===========================================================================

  @doc """
  Generates embeddings for a single text input.

  ## Parameters

    * `model_spec` - Model specification in various formats
    * `text` - Text to generate embeddings for
    * `opts` - Additional options (keyword list)

  ## Options

    * `:dimensions` - Number of dimensions for embeddings
    * `:provider_options` - Provider-specific options

  ## Examples

      {:ok, embedding} = ReqLLM.embed("openai:text-embedding-3-small", "Hello world")
      #=> {:ok, [0.1, -0.2, 0.3, ...]}

  """
  defdelegate embed(model_spec, text, opts \\ []), to: Embedding

  @doc """
  Generates embeddings for multiple text inputs.

  ## Parameters

    * `model_spec` - Model specification in various formats
    * `texts` - List of texts to generate embeddings for
    * `opts` - Additional options (keyword list)

  ## Options

  Same as `embed/3`.

  ## Examples

      {:ok, embeddings} = ReqLLM.embed_many(
        "openai:text-embedding-3-small",
        ["Hello", "World"]
      )
      #=> {:ok, [[0.1, -0.2, ...], [0.3, 0.4, ...]]}

  """
  defdelegate embed_many(model_spec, texts, opts \\ []), to: Embedding

  # ===========================================================================
  # Vercel AI SDK Utility API - Delegated to ReqLLM.Utils
  # ===========================================================================

  @doc """
  Creates a Tool struct for AI model function calling.

  Equivalent to Vercel AI SDK's `tool()` helper, providing type-safe tool
  definitions with parameter validation. This is a convenience function
  for creating ReqLLM.Tool structs.

  ## Parameters

    * `opts` - Tool definition options (keyword list)

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
    json_schema = Schema.to_json(schema)

    case opts[:validate] do
      nil ->
        json_schema

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

  # ===========================================================================
  # Provider Plugin System - Core Infrastructure
  # ===========================================================================

  @doc """
  Attaches a provider plugin to a Req request for AI model interaction.

  This function bridges the Provider/Client architecture by:
  1. Parsing the model specification into a ReqLLM.Model struct
  2. Looking up the provider plugin from the registry
  3. Calling the provider's attach/2 callback to configure the request

  ## Parameters

    * `request` - Req.Request struct to configure
    * `model_spec` - Model specification in supported formats:
      - String: "anthropic:claude-3-sonnet"
      - Tuple: {:anthropic, "claude-3-sonnet", temperature: 0.7}
      - Struct: %ReqLLM.Model{}

  ## Returns

    * `{:ok, configured_request}` - Request ready for execution
    * `{:error, reason}` - Configuration failed

  ## Examples

      # Basic usage with model string
      request = Req.Request.new(url: "/chat/completions", method: :post)
      {:ok, configured} = ReqLLM.attach(request, "anthropic:claude-3-sonnet")

      # The configured request includes:
      # - Authentication headers
      # - Provider-specific base URL
      # - Request body formatting
      # - Any provider-specific configuration

  """
  @spec attach(Req.Request.t(), String.t() | tuple() | ReqLLM.Model.t()) ::
          {:ok, Req.Request.t()} | {:error, term()}
  def attach(%Req.Request{} = request, model_spec) do
    with {:ok, model} <- ReqLLM.Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.Provider.Registry.get_provider(model.provider) do
      configured_request = provider_module.attach(request, model)
      {:ok, configured_request}
    end
  end

  @doc """
  Attaches a provider plugin with bang syntax (raises on error).

  Same as `attach/2` but raises `ArgumentError` on failure instead of returning error tuples.

  ## Examples

      request = Req.Request.new()
      configured = ReqLLM.attach!(request, "anthropic:claude-3-sonnet")

  """
  @spec attach!(Req.Request.t(), String.t() | tuple() | ReqLLM.Model.t()) :: Req.Request.t()
  def attach!(request, model_spec) do
    case attach(request, model_spec) do
      {:ok, configured_request} -> configured_request
      {:error, reason} -> raise ArgumentError, "Failed to attach provider: #{inspect(reason)}"
    end
  end
end
