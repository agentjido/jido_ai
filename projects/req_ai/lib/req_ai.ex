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
  alias ReqAI.Messages

  # ===========================================================================
  # NimbleOptions Compiled Schemas for validation
  # ===========================================================================

  # Base text generation schema - shared by generate_text and stream_text
  @text_opts_schema NimbleOptions.new!(
                      temperature: [
                        type: :float,
                        doc: "Controls randomness in the output (0.0 to 2.0)"
                      ],
                      max_tokens: [
                        type: :pos_integer,
                        doc: "Maximum number of tokens to generate"
                      ],
                      top_p: [type: :float, doc: "Nucleus sampling parameter"],
                      presence_penalty: [
                        type: :float,
                        doc: "Penalize new tokens based on presence"
                      ],
                      frequency_penalty: [
                        type: :float,
                        doc: "Penalize new tokens based on frequency"
                      ],
                      tools: [type: :any, doc: "List of tool definitions"],
                      tool_choice: [
                        type: {:or, [:string, :atom, :map]},
                        default: "auto",
                        doc: "Tool choice strategy"
                      ],
                      system_prompt: [type: :string, doc: "System prompt to prepend"],
                      provider_options: [type: :map, doc: "Provider-specific options"],
                      reasoning: [
                        type: {:in, [nil, false, true, "low", "auto", "high"]},
                        doc: "Request reasoning tokens from the model"
                      ]
                    )

  # Object generation schema - extends text options with additional fields
  @object_opts_schema NimbleOptions.new!(
                        temperature: [
                          type: :float,
                          doc: "Controls randomness in the output (0.0 to 2.0)"
                        ],
                        max_tokens: [
                          type: :pos_integer,
                          doc: "Maximum number of tokens to generate"
                        ],
                        top_p: [type: :float, doc: "Nucleus sampling parameter"],
                        presence_penalty: [
                          type: :float,
                          doc: "Penalize new tokens based on presence"
                        ],
                        frequency_penalty: [
                          type: :float,
                          doc: "Penalize new tokens based on frequency"
                        ],
                        tools: [type: :any, doc: "List of tool definitions"],
                        tool_choice: [
                          type: {:or, [:string, :atom, :map]},
                          default: "auto",
                          doc: "Tool choice strategy"
                        ],
                        system_prompt: [type: :string, doc: "System prompt to prepend"],
                        provider_options: [type: :map, doc: "Provider-specific options"],
                        output_type: [
                          type: {:in, [:object, :array, :enum, :no_schema]},
                          default: :object,
                          doc: "Type of output structure"
                        ],
                        enum_values: [
                          type: {:list, :string},
                          doc: "Allowed values when output_type is :enum"
                        ],
                        reasoning: [
                          type: {:in, [nil, false, true, "low", "auto", "high"]},
                          doc: "Request reasoning tokens from the model"
                        ]
                      )

  # Embedding schema - shared by embed and embed_many
  @embed_opts_schema NimbleOptions.new!(
                       dimensions: [
                         type: :pos_integer,
                         doc: "Number of dimensions for embeddings"
                       ],
                       provider_options: [type: :map, doc: "Provider-specific options"]
                     )

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
    Kagi.get(key, nil)
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
  Creates a messages collection from a list of messages.

  ## Parameters

    * `messages` - List of Message structs

  ## Examples

      messages = [
        ReqAI.Messages.system("You are helpful"),
        ReqAI.Messages.user("Hello!")
      ]
      collection = ReqAI.messages(messages)
      # Now you can use Enum functions on the collection
      user_msgs = collection |> Enum.filter(&(&1.role == :user))

  """
  @spec messages([struct()]) :: Messages.t()
  def messages(message_list) when is_list(message_list) do
    Messages.new(message_list)
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

      {:ok, response} = ReqAI.generate_text("anthropic:claude-3-sonnet", "Hello world")
      response.body
      #=> "Hello! How can I assist you today?"

      # Access usage metadata
      {:ok, text, usage} = ReqAI.generate_text("anthropic:claude-3-sonnet", "Hello") |> ReqAI.with_usage()

  """
  @spec generate_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Req.Response.t()} | {:error, term()}
  def generate_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
         {:ok, model} <- ReqAI.Model.from(model_spec),
         {:ok, provider_module} <- provider(model.provider) do
      # Always return full response for metadata access
      enhanced_opts = Keyword.put(validated_opts, :return_response, true)
      provider_module.generate_text(model, messages, enhanced_opts)
    else
      {:error, :not_found} ->
        {:error, ReqAI.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end

  @doc """
  Generates text using an AI model, returning only the text content.

  This is a convenience function that extracts just the text from the response.
  For access to usage metadata and other response data, use `generate_text/3`.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, text} = ReqAI.generate_text!("anthropic:claude-3-sonnet", "Hello world")
      text
      #=> "Hello! How can I assist you today?"

  """
  @spec generate_text!(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def generate_text!(model_spec, messages, opts \\ []) do
    case generate_text(model_spec, messages, opts) do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Streams text generation using an AI model with full response metadata.

  Returns the complete response containing usage data and metadata.
  For simple streaming without metadata, use `stream_text!/3`.

  ## Parameters

  Same as `generate_text/3`.

  ## Examples

      {:ok, response} = ReqAI.stream_text("anthropic:claude-3-sonnet", "Tell me a story")
      response.body |> Enum.each(&IO.write/1)

      # Access usage metadata after streaming
      {:ok, stream, usage} = ReqAI.stream_text("anthropic:claude-3-sonnet", "Hello") |> ReqAI.with_usage()

  """
  @spec stream_text(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Req.Response.t()} | {:error, term()}
  def stream_text(model_spec, messages, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
         {:ok, model} <- ReqAI.Model.from(model_spec),
         {:ok, provider_module} <- provider(model.provider) do
      # Always return full response for metadata access
      enhanced_opts =
        validated_opts
        |> Keyword.put(:stream?, true)
        |> Keyword.put(:return_response, true)

      provider_module.stream_text(model, messages, enhanced_opts)
    else
      {:error, :not_found} ->
        {:error, ReqAI.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end

  @doc """
  Streams text generation using an AI model, returning only the stream.

  This is a convenience function that extracts just the stream from the response.
  For access to usage metadata and other response data, use `stream_text/3`.

  ## Parameters

  Same as `stream_text/3`.

  ## Examples

      {:ok, stream} = ReqAI.stream_text!("anthropic:claude-3-sonnet", "Tell me a story")
      stream |> Enum.each(&IO.write/1)

  """
  @spec stream_text!(
          String.t() | {atom(), keyword()} | struct(),
          String.t() | list(),
          keyword()
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_text!(model_spec, messages, opts \\ []) do
    case stream_text(model_spec, messages, opts) do
      {:ok, %Req.Response{body: body}} -> {:ok, body}
      {:error, error} -> {:error, error}
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
        ) :: {:ok, map() | list() | String.t()} | {:error, ReqAI.Error.t()}
  def generate_object(model_spec, messages, schema, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @object_opts_schema),
         {:ok, compiled_schema} <- compile_schema(schema),
         {:ok, tool} <- create_response_tool(schema),
         enhanced_opts <- prepare_tool_opts(validated_opts, tool),
         {:ok, response} <- generate_text(model_spec, messages, enhanced_opts),
         {:ok, model} <- ReqAI.Model.from(model_spec),
         {:ok, provider_module} <- provider(model.provider),
         {:ok, tool_args} <- parse_tool_response(response, provider_module),
         {:ok, validated_result} <- validate_result(tool_args, compiled_schema) do
      {:ok, validated_result}
    else
      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error,
         ReqAI.Error.Validation.Error.exception(
           tag: :invalid_options,
           reason: Exception.message(error),
           context: []
         )}

      {:error, :not_found} ->
        {:error, ReqAI.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
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
  def stream_object(model_spec, messages, schema, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @object_opts_schema),
         {:ok, compiled_schema} <- compile_schema(schema),
         {:ok, tool} <- create_response_tool(schema),
         enhanced_opts <- prepare_tool_opts(validated_opts, tool),
         streaming_opts <- Keyword.merge(enhanced_opts, stream?: true, return_response: true),
         {:ok, response} <- stream_text(model_spec, messages, streaming_opts),
         {:ok, model} <- ReqAI.Model.from(model_spec),
         {:ok, provider_module} <- provider(model.provider) do
      # Build the validating stream
      validating_stream =
        build_validating_stream(
          response.body,
          provider_module,
          compiled_schema,
          "response_object"
        )

      # Return the stream in the same response structure for consistency
      updated_response = %{response | body: validating_stream}
      {:ok, updated_response}
    else
      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error,
         ReqAI.Error.Validation.Error.exception(
           tag: :invalid_options,
           reason: Exception.message(error),
           context: []
         )}

      {:error, :not_found} ->
        {:error, ReqAI.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
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
      {:error, ReqAI.Error.Invalid.NotImplemented.exception(feature: "embed")}
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
    with {:ok, _validated_opts} <- NimbleOptions.validate(opts, @embed_opts_schema) do
      # Implementation will delegate to provider
      # This is a stub
      {:error, ReqAI.Error.Invalid.NotImplemented.exception(feature: "embed_many")}
    end
  end

  @doc """
  Extracts token usage information from a ReqAI result.

  Designed to be used in a pipeline after `generate_text` or `stream_text` calls.
  Works with both Response objects (from `generate_text/3`) and plain results (from `generate_text!/3`).

  ## Parameters

    * `result` - The result tuple from any ReqAI function

  ## Examples

      # Generate text with usage info - pipeline style
      {:ok, text, usage} = 
        ReqAI.generate_text("openai:gpt-4o", "Hello")
        |> ReqAI.with_usage()
      
      usage
      #=> %{tokens: %{input: 10, output: 15}, cost: 0.00075}

      # Works with bang functions too (returns nil usage)
      {:ok, text, usage} = 
        ReqAI.generate_text!("openai:gpt-4o", "Hello")
        |> ReqAI.with_usage()
      
      usage  #=> nil

      # Stream text with usage info
      {:ok, stream, usage} = 
        ReqAI.stream_text("openai:gpt-4o", "Hello")
        |> ReqAI.with_usage()

  """
  @spec with_usage({:ok, any()} | {:error, term()}) ::
          {:ok, String.t() | Enumerable.t(), map() | nil} | {:error, term()}
  def with_usage({:ok, %Req.Response{body: body} = response}) do
    # Extract usage from response private data
    usage = get_in(response.private, [:req_ai, :usage])
    {:ok, body, usage}
  end

  def with_usage({:ok, result}) do
    # Graceful passthrough for results without response metadata (like from bang functions)
    {:ok, result, nil}
  end

  def with_usage({:error, error}) do
    {:error, error}
  end

  @doc """
  Extracts cost information from a ReqAI result.

  Designed to be used in a pipeline after `generate_text` or `stream_text` calls.
  Works with both Response objects (from `generate_text/3`) and plain results (from `generate_text!/3`).

  ## Parameters

    * `result` - The result tuple from any ReqAI function

  ## Examples

      # Generate text with cost info - pipeline style
      {:ok, text, cost} = 
        ReqAI.generate_text("openai:gpt-4o", "Hello")
        |> ReqAI.with_cost()
      
      cost
      #=> 0.00075

      # Works with bang functions too (returns nil cost)
      {:ok, text, cost} = 
        ReqAI.generate_text!("openai:gpt-4o", "Hello")
        |> ReqAI.with_cost()
      
      cost  #=> nil

      # Stream text with cost info - pipeline style
      {:ok, stream, cost} = 
        ReqAI.stream_text("openai:gpt-4o", "Hello")
        |> ReqAI.with_cost()

  """
  @spec with_cost({:ok, any()} | {:error, term()}) ::
          {:ok, String.t() | Enumerable.t(), float() | nil} | {:error, term()}
  def with_cost(result) do
    case with_usage(result) do
      {:ok, content, %{cost: cost}} -> {:ok, content, cost}
      {:ok, content, _} -> {:ok, content, nil}
      {:error, error} -> {:error, error}
    end
  end

  # Private helper functions for generate_object/4

  defp compile_schema(schema) when is_list(schema) do
    try do
      {:ok, NimbleOptions.new!(schema)}
    rescue
      e ->
        {:error,
         ReqAI.Error.Validation.Error.exception(
           tag: :invalid_schema,
           reason: "Invalid schema: #{Exception.message(e)}",
           context: [schema: schema]
         )}
    end
  end

  defp compile_schema(schema) do
    {:error,
     ReqAI.Error.Invalid.Parameter.exception(
       parameter: "Schema must be a keyword list, got: #{inspect(schema)}"
     )}
  end

  defp create_response_tool(schema) do
    ReqAI.Tool.new(
      name: "response_object",
      description: "Return the response for the user request as arguments",
      parameters: schema,
      callback: fn args -> {:ok, args} end
    )
  end

  defp prepare_tool_opts(validated_opts, tool) do
    # Remove generate_object-specific options that don't apply to generate_text
    text_opts =
      validated_opts
      |> Keyword.delete(:output_type)
      |> Keyword.delete(:enum_values)

    # Convert Tool struct to format expected by providers
    provider_tool = convert_tool_for_provider(tool)

    text_opts
    |> Keyword.put(:tools, [provider_tool])
    |> Keyword.put(:tool_choice, "response_object")
  end

  defp convert_tool_for_provider(%ReqAI.Tool{} = tool) do
    %{
      name: tool.name,
      description: tool.description,
      parameters_schema: parameters_to_json_schema(tool.parameters)
    }
  end

  # Import the private function from ReqAI.Tool 
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

  defp parse_tool_response(%Req.Response{body: %{tool_calls: tool_calls}}, _provider_module)
       when is_list(tool_calls) and tool_calls != [] do
    case Enum.find(tool_calls, &(&1[:name] == "response_object")) do
      %{arguments: args} ->
        {:ok, args}

      nil ->
        {:error,
         ReqAI.Error.API.Response.exception(
           reason: "No response_object tool call found in response"
         )}
    end
  end

  defp parse_tool_response(%Req.Response{body: body}, provider_module) do
    case provider_module.parse_tool_call(body, "response_object") do
      {:ok, args} ->
        {:ok, args}

      {:error, :tool_not_found} ->
        {:error,
         ReqAI.Error.API.Response.exception(
           reason: "No response_object tool call found in response"
         )}

      {:error, :no_tool_calls} ->
        {:error, ReqAI.Error.API.Response.exception(reason: "No tool calls found in response")}

      {:error, reason} ->
        {:error,
         ReqAI.Error.API.Response.exception(
           reason: "Failed to parse tool call: #{inspect(reason)}"
         )}
    end
  end

  defp validate_result(tool_args, compiled_schema) do
    case NimbleOptions.validate(tool_args, compiled_schema) do
      {:ok, validated_result} ->
        {:ok, validated_result}

      {:error, error} ->
        {:error,
         ReqAI.Error.Validation.Error.exception(
           tag: :result_validation,
           reason: Exception.message(error),
           context: [result: tool_args]
         )}
    end
  end

  # Helper functions for stream_object/4

  defp build_validating_stream(stream, provider_module, compiled_schema, _tool_name) do
    Stream.resource(
      fn -> stream_tool_init(provider_module) end,
      fn state ->
        case Enum.take(stream, 1) do
          [] ->
            {:halt, state}

          [chunk] ->
            case stream_tool_accumulate(provider_module, chunk, state) do
              {:ok, new_state} ->
                {[], new_state}

              {:ok, new_state, completed_args} ->
                case validate_all(completed_args, compiled_schema) do
                  {:ok, validated_results} ->
                    {validated_results, new_state}

                  {:error, error} ->
                    raise error
                end

              {:error, error} ->
                raise ReqAI.Error.API.Response.exception(
                        reason: "Stream processing error: #{inspect(error)}"
                      )
            end
        end
      end,
      fn _state -> :ok end
    )
  end

  defp stream_tool_init(provider_module) do
    if function_exported?(provider_module, :stream_tool_init, 1) do
      provider_module.stream_tool_init("response_object")
    else
      %{}
    end
  end

  defp stream_tool_accumulate(provider_module, chunk, state) do
    if function_exported?(provider_module, :stream_tool_accumulate, 3) do
      provider_module.stream_tool_accumulate(chunk, "response_object", state)
    else
      {:error, :not_implemented}
    end
  end

  defp validate_all(args_list, compiled_schema) when is_list(args_list) do
    try do
      validated =
        Enum.map(args_list, fn args ->
          case NimbleOptions.validate(args, compiled_schema) do
            {:ok, validated_args} -> validated_args
            {:error, error} -> throw({:validation_error, error})
          end
        end)

      {:ok, validated}
    catch
      {:validation_error, error} ->
        {:error,
         ReqAI.Error.Validation.Error.exception(
           tag: :result_validation,
           reason: Exception.message(error),
           context: [result: args_list]
         )}
    end
  end

  defp validate_all(args, compiled_schema) do
    validate_all([args], compiled_schema)
  end
end
