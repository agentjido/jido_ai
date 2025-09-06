defmodule ReqAI do
  @moduledoc """
  Main API facade for Req AI.

  Inspired by the Vercel AI SDK, provides a unified interface to AI providers with 
  flexible model specifications, rich prompt support, configuration management, 
  and structured data generation.

  ## Quick Start

      # Simple text generation using string format
      ReqAI.generate_text("openai:gpt-4o", "Hello world")
      #=> {:ok, "Hello! How can I assist you today?"}

      # Structured data generation with schema validation
      schema = [
        name: [type: :string, required: true],
        age: [type: :pos_integer, required: true]
      ]
      ReqAI.generate_object("openai:gpt-4o", "Generate a person", schema)
      #=> {:ok, %{name: "John Doe", age: 30}}

  ## Model Specifications

  Multiple formats supported for maximum flexibility:

      # String format: "provider:model"
      ReqAI.generate_text("openai:gpt-4o", messages)
      ReqAI.generate_text("anthropic:claude-3-5-sonnet-20241022", messages)

      # Tuple format: {provider, options}
      ReqAI.generate_text({:openai, model: "gpt-4o", temperature: 0.7}, messages)

      # Model struct format
      model = %ReqAI.Model{provider: :openai, model: "gpt-4o", temperature: 0.5}
      ReqAI.generate_text(model, messages)

  ## Configuration

  The library uses a layered configuration system with Kagi integration:

  1. **Environment Variables**: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.
  2. **Application Config**: `config :req_ai, provider: [api_key: "key"]`
  3. **Runtime Session**: `ReqAI.put_key(:openai_api_key, "session-key")`

      # Get configuration values
      ReqAI.config([:openai, :api_key], "default-key")

  ## Providers

  Built-in support for major AI providers:

  - **OpenAI**: GPT-4o, GPT-4o Mini, GPT-3.5 Turbo, o1, o1-mini
  - **Anthropic**: Claude 3.5 Sonnet, Claude 3 Haiku, Claude 3 Opus
  - **OpenRouter**: Access to 200+ models from various providers
  - **Google**: Gemini 1.5 Pro, Gemini 1.5 Flash

      # Access provider modules directly
      provider = ReqAI.provider(:openai)
      provider.generate_text(model, messages, opts)
  """

  alias Kagi

  # ===========================================================================
  # NimbleOptions Schemas for validation
  # ===========================================================================

  @generate_text_opts_schema [
    temperature: [type: :float, doc: "Controls randomness in the output (0.0 to 2.0)"],
    max_tokens: [type: :pos_integer, doc: "Maximum number of tokens to generate"],
    top_p: [type: :float, doc: "Nucleus sampling parameter"],
    presence_penalty: [type: :float, doc: "Penalize new tokens based on presence"],
    frequency_penalty: [type: :float, doc: "Penalize new tokens based on frequency"],
    tools: [type: {:list, :map}, doc: "List of tool definitions"],
    tool_choice: [type: {:or, [:string, :atom, :map]}, doc: "Tool choice strategy"],
    system_prompt: [type: :string, doc: "System prompt to prepend"],
    provider_options: [type: :map, doc: "Provider-specific options"]
  ]

  @stream_text_opts_schema @generate_text_opts_schema

  @generate_object_opts_schema @generate_text_opts_schema ++
                                 [
                                   output_type: [
                                     type: {:in, [:object, :array, :enum, :no_schema]},
                                     default: :object,
                                     doc: "Type of output structure"
                                   ],
                                   enum_values: [
                                     type: {:list, :string},
                                     doc: "Allowed values when output_type is :enum"
                                   ]
                                 ]

  @stream_object_opts_schema @generate_object_opts_schema

  @embed_opts_schema [
    dimensions: [type: :pos_integer, doc: "Number of dimensions for embeddings"],
    provider_options: [type: :map, doc: "Provider-specific options"]
  ]

  @embed_many_opts_schema @embed_opts_schema

  # ===========================================================================
  # Configuration API - Simple facades for common operations
  # ===========================================================================

  @doc """
  Gets an API key from the keyring.

  Key lookup is case-insensitive and accepts both atoms and strings.

  ## Parameters

    * `key` - The configuration key (atom or string, case-insensitive)

  ## Examples

      ReqAI.api_key(:openai_api_key)
      ReqAI.api_key("ANTHROPIC_API_KEY")
      ReqAI.api_key("OpenAI_API_Key")

  """
  @spec api_key(atom() | String.t()) :: String.t() | nil
  def api_key(key) when is_atom(key) do
    Kagi.get(Kagi, key, nil)
  end

  def api_key(key) when is_binary(key) do
    normalized = String.downcase(key)
    Kagi.get(normalized, nil)
  end

  @doc """
  Gets a configuration value from the keyring with keyspace support.

  ## Parameters

    * `keyspace` - Key path as atom list (e.g., [:openai, :api_key])
    * `default` - Default value if key not found

  ## Examples

      ReqAI.config([:openai, :api_key], "default-key")
      ReqAI.config([:anthropic, :max_tokens], 1000)

  """
  @spec config(list(atom()), term()) :: term()
  def config(keyspace, default \\ nil) when is_list(keyspace) do
    # Implementation will delegate to Kagi
    # This is a stub
    default
  end

  @doc """
  Gets a provider module from the registry.

  ## Parameters

    * `provider` - Provider identifier (atom)

  ## Examples

      ReqAI.provider(:anthropic)
      #=> {:ok, ReqAI.Providers.Anthropic}

      ReqAI.provider(:unknown)
      #=> {:error, :not_found}

  """
  @spec provider(atom()) :: {:ok, module()} | {:error, :not_found}
  def provider(provider) when is_atom(provider) do
    ReqAI.Provider.Registry.fetch(provider)
  end

  @doc """
  Creates a model struct from various specifications.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - String format: `"anthropic:claude-3-sonnet"`
      - Tuple format: `{:anthropic, model: "claude-3-sonnet", temperature: 0.7}`
      - Model struct: `%ReqAI.Model{}`

  ## Examples

      ReqAI.model("anthropic:claude-3-sonnet")
      #=> {:ok, %ReqAI.Model{provider: :anthropic, model: "claude-3-sonnet"}}

      ReqAI.model({:anthropic, model: "claude-3-sonnet", temperature: 0.5})
      #=> {:ok, %ReqAI.Model{provider: :anthropic, model: "claude-3-sonnet", temperature: 0.5}}

  """
  @spec model(String.t() | {atom(), keyword()} | struct()) :: {:ok, struct()} | {:error, term()}
  def model(model_spec) do
    ReqAI.Model.from(model_spec)
  end

  # ===========================================================================
  # Core API Methods - Stubs following Vercel AI SDK patterns
  # ===========================================================================

  @doc """
  Generates text using an AI model.

  Accepts flexible model specifications and generates text using the appropriate provider.

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

      ReqAI.generate_text("anthropic:claude-3-sonnet", "Hello world")
      #=> {:ok, "Hello! How can I assist you today?"}

      ReqAI.generate_text(
        "anthropic:claude-3-sonnet",
        "Explain AI",
        temperature: 0.7,
        max_tokens: 100
      )

  """
  @spec generate_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def generate_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @generate_text_opts_schema),
         {:ok, model} <- ReqAI.Model.from(model_spec),
         {:ok, provider_module} <- provider(model.provider) do
      provider_module.generate_text(model, messages, validated_opts)
    else
      {:error, :not_found} ->
        {:error, ReqAI.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end

  @doc """
  Streams text generation using an AI model.

  Accepts flexible model specifications and streams text using the appropriate provider.
  Returns a Stream that emits text chunks as they arrive.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, stream} = ReqAI.stream_text("anthropic:claude-3-sonnet", "Tell me a story")
      stream |> Enum.each(&IO.write/1)

  """
  @spec stream_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @stream_text_opts_schema),
         {:ok, model} <- ReqAI.Model.from(model_spec),
         {:ok, provider_module} <- provider(model.provider) do
      provider_module.stream_text(model, messages, Keyword.put(validated_opts, :stream?, true))
    else
      {:error, :not_found} ->
        {:error, ReqAI.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end

  @doc """
  Generates structured data using an AI model with schema validation.

  Accepts flexible model specifications and generates validated structured data using the appropriate provider.
  The response is validated against the provided NimbleOptions schema and returns a structured map.

  ## Parameters

    * `model_spec` - Model specification in various formats
    * `messages` - Text prompt or list of messages
    * `schema` - NimbleOptions schema definition for validation (keyword list)
    * `opts` - Additional options (keyword list)

  ## Options

  Same as `generate_text/3` plus:

    * `:output_type` - Type of output: `:object`, `:array`, `:enum`, `:no_schema` (default: `:object`)
    * `:enum_values` - List of allowed values when output_type is `:enum`

  ## Examples

      schema = [
        name: [type: :string, required: true],
        age: [type: :pos_integer, required: true]
      ]
      {:ok, result} = ReqAI.generate_object(
        "openai:gpt-4o",
        "Generate a person",
        schema
      )
      #=> {:ok, %{name: "John Doe", age: 30}}

  """
  @spec generate_object(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def generate_object(_model_spec, _messages, _schema, opts \\ []) do
    with {:ok, _validated_opts} <- NimbleOptions.validate(opts, @generate_object_opts_schema) do
      # Implementation will delegate to provider
      # This is a stub
      {:error, "generate_object not implemented"}
    end
  end

  @doc """
  Streams structured data using an AI model with schema validation.

  Accepts flexible model specifications and streams validated structured data using the appropriate provider.
  Returns a Stream that emits validated structured data chunks as they arrive.

  ## Parameters

  Same as `generate_object/4`.

  ## Examples

      schema = [
        name: [type: :string, required: true],
        score: [type: :integer, required: true]
      ]

      {:ok, stream} = ReqAI.stream_object(
        "openai:gpt-4o",
        "Generate player data",
        schema
      )

      stream |> Enum.each(&IO.inspect/1)

  """
  @spec stream_object(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword(),
          keyword()
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_object(_model_spec, _messages, _schema, opts \\ []) do
    with {:ok, _validated_opts} <- NimbleOptions.validate(opts, @stream_object_opts_schema) do
      # Implementation will delegate to provider
      # This is a stub
      {:error, "stream_object not implemented"}
    end
  end

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

      {:ok, embedding} = ReqAI.embed("openai:text-embedding-3-small", "Hello world")
      #=> {:ok, [0.1, -0.2, 0.3, ...]}

  """
  @spec embed(
          String.t() | {atom(), keyword()} | struct(),
          String.t(),
          keyword()
        ) :: {:ok, list(float())} | {:error, term()}
  def embed(_model_spec, text, opts \\ []) when is_binary(text) do
    with {:ok, _validated_opts} <- NimbleOptions.validate(opts, @embed_opts_schema) do
      # Implementation will delegate to provider
      # This is a stub
      {:error, "embed not implemented"}
    end
  end

  @doc """
  Generates embeddings for multiple text inputs.

  ## Parameters

    * `model_spec` - Model specification in various formats
    * `texts` - List of texts to generate embeddings for
    * `opts` - Additional options (keyword list)

  ## Options

  Same as `embed/3`.

  ## Examples

      {:ok, embeddings} = ReqAI.embed_many(
        "openai:text-embedding-3-small", 
        ["Hello", "World"]
      )
      #=> {:ok, [[0.1, -0.2, ...], [0.3, 0.4, ...]]}

  """
  @spec embed_many(
          String.t() | {atom(), keyword()} | struct(),
          list(String.t()),
          keyword()
        ) :: {:ok, list(list(float()))} | {:error, term()}
  def embed_many(_model_spec, texts, opts \\ []) when is_list(texts) do
    with {:ok, _validated_opts} <- NimbleOptions.validate(opts, @embed_many_opts_schema) do
      # Implementation will delegate to provider
      # This is a stub
      {:error, "embed_many not implemented"}
    end
  end
end
