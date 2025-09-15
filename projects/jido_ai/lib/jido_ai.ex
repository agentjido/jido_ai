defmodule Jido.AI do
  @moduledoc """
  Main API facade for Jido AI.

  Provides unified access to AI providers with flexible model specifications, rich prompt support,
  configuration management, and structured data generation.

  ## Quick Start

      # Simple text generation using string format
      Jido.AI.generate_text("openai:gpt-4o", "Hello world")
      #=> {:ok, "Hello! How can I assist you today?"}

      # Structured data generation with schema validation
      schema = [
        name: [type: :string, required: true],
        age: [type: :pos_integer, required: true]
      ]
      Jido.AI.generate_object("openai:gpt-4o", "Generate a person", schema)
      #=> {:ok, %{name: "John Doe", age: 30}}

      # Rich prompts with message arrays
      import Jido.AI.Messages

      messages = [
        system("You are a helpful coding assistant"),
        user("Explain how to use pattern matching in Elixir")
      ]
      Jido.AI.generate_text("openai:gpt-4o", messages)

      # Multi-modal content
      messages = [
        user_with_image("Describe this code screenshot", "https://example.com/code.png"),
        assistant("This code shows a GenServer implementation..."),
        user("Can you suggest improvements?")
      ]
      Jido.AI.generate_text("openai:gpt-4o-vision", messages)

  ## Rich Prompts & Messages

  Inspired by the Vercel AI SDK patterns, the library supports three prompt formats:

  ### 1. Simple Strings (Primary Support)

      # String format: "provider:model" is fully supported
      Jido.AI.generate_text("openai:gpt-4o", "Write a haiku about programming")

  ### 2. Message Arrays (Recommended)

      import Jido.AI.Messages

      # Basic conversation
      messages = [
        system("You are a helpful assistant"),
        user("Hello!"),
        assistant("Hi there! How can I help?"),
        user("What's the weather like?")
      ]

      # With multi-modal content
      messages = [
        user_with_image("Analyze this chart", "data:image/png;base64,iVBOR..."),
        user_with_file("Also check this CSV", csv_data, "text/csv", "sales.csv")
      ]

  ### 3. System Prompt + Messages

      # Separate system prompt for clarity
      system_prompt = "You are an expert Elixir developer"
      messages = [
        user("How do I handle errors in GenServers?"),
        assistant("There are several patterns..."),
        user("Show me an example")
      ]

      Jido.AI.generate_text(model, {system_prompt, messages})

  ## Structured Data Generation

  Generate validated structured data using NimbleOptions schemas:

      # Object generation with validation
      schema = [
        user: [
          type: {:map, [
            name: [type: :string, required: true],
            email: [type: :string, required: true]
          ]},
          required: true
        ],
        preferences: [type: {:list, :string}, default: []]
      ]

      {:ok, result} = Jido.AI.generate_object("openai:gpt-4o", "Create user data", schema)
      # => {:ok, %{user: %{name: "Alice", email: "alice@example.com"}, preferences: ["coding"]}}

      # Array generation
      schema = [
        name: [type: :string, required: true],
        score: [type: :integer, required: true]
      ]

      {:ok, results} = Jido.AI.generate_object(
        "openai:gpt-4o",
        "Generate 3 player scores",
        schema,
        output_type: :array
      )

      # Stream structured data generation
      {:ok, stream} = Jido.AI.stream_object("openai:gpt-4o", "Generate data", schema)
      stream |> Enum.each(&IO.inspect/1)

   ## Tool Calls & Function Integration

       # Generate with Jido Actions as tools (seamless integration)
       Jido.AI.generate_text(
         "openai:gpt-4o",
         "What's the weather in SF and what's 5 + 3?",
         actions: [MyApp.Actions.Weather, MyApp.Actions.Calculator]
       )

       # With raw tool definitions
       Jido.AI.generate_text(
         "openai:gpt-4o",
         "Use my custom tools",
         tools: [%{type: "function", function: %{name: "my_tool", description: "..."}}]
       )

       # Manual tool workflow with rich messages
       import Jido.AI.Messages
       messages = [
         user("What's the weather in SF?"),
         assistant("I'll check the weather for you", [
           tool_call("call_123", "get_weather", %{location: "San Francisco"})
         ]),
         tool_result("call_123", "get_weather", %{temp: 68, condition: "sunny"}),
         assistant("It's 68°F and sunny in San Francisco!")
       ]

  ## Migration Guide: String → Rich Prompts

      # Before (still works)
      Jido.AI.generate_text(model, "You are a helpful assistant. User: Hello")

      # After (recommended)
      import Jido.AI.Messages
      messages = [
        system("You are a helpful assistant"),
        user("Hello")
      ]
      Jido.AI.generate_text(model, messages)

  ## Configuration

  The library uses a layered configuration system with Keyring integration:

  1. **Environment Variables**: `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, etc.
  2. **Application Config**: `config :jido_ai, provider: [api_key: "key"]`
  3. **Runtime Session**: `Jido.AI.put_key(:openai_api_key, "session-key")`

      # Get configuration values
      Jido.AI.config([:openai, :api_key], "default-key")

      # List all available keys
      Jido.AI.list_keys()

  ## Model Specifications

  Multiple formats supported for maximum flexibility:

      # String format: "provider:model"
      Jido.AI.generate_text("openai:gpt-4o", messages)
      Jido.AI.generate_text("anthropic:claude-3-5-sonnet-20241022", messages)

      # Tuple format: {provider, options}
      Jido.AI.generate_text({:openai, model: "gpt-4o", temperature: 0.7}, messages)
      Jido.AI.generate_text({:anthropic, model: "claude-3-haiku-20240307", max_tokens: 1000}, messages)

      # Model struct format
      model = %Jido.AI.Model{provider: :openai, model: "gpt-4o", temperature: 0.5}
      Jido.AI.generate_text(model, messages)

  ## Provider Options & Advanced Usage

      # Provider-specific options
      Jido.AI.generate_text(
        "openai:gpt-4o",
        messages,
        temperature: 0.9,
        max_tokens: 2000,
        presence_penalty: 0.1,
        frequency_penalty: 0.1
      )

      # Streaming with rich prompts
      Jido.AI.stream_text("openai:gpt-4o", messages)
      |> Stream.each(&IO.write/1)
      |> Stream.run()

  ## Providers

  Built-in support for major AI providers:

  - **OpenAI**: GPT-4o, GPT-4o Mini, GPT-3.5 Turbo, o1, o1-mini
  - **Anthropic**: Claude 3.5 Sonnet, Claude 3 Haiku, Claude 3 Opus
  - **OpenRouter**: Access to 200+ models from various providers
  - **Google**: Gemini 1.5 Pro, Gemini 1.5 Flash

      # Access provider modules directly
      provider = Jido.AI.provider(:openai)
      provider.generate_text(model, messages, opts)
  """

  alias Jido.Action.Tool
  alias Jido.AI.Messages
  alias Jido.AI.{Keyring, Message, Model, ObjectSchema, Util}

  # ===========================================================================
  # Configuration API - Simple facades for common operations
  # ===========================================================================

  @doc """
  Gets a configuration value from the keyring.

  Key lookup is case-insensitive and accepts both atoms and strings.

  ## Parameters

    * `key` - The configuration key (atom or string, case-insensitive)

  ## Examples

      Jido.AI.api_key(:openai_api_key)
      Jido.AI.api_key("ANTHROPIC_API_KEY")
      Jido.AI.api_key("OpenAI_API_Key")

  """
  @spec api_key(atom() | String.t()) :: String.t() | nil
  def api_key(key) when is_atom(key) do
    Keyring.get(Keyring, key, nil)
  end

  def api_key(key) when is_binary(key) do
    normalized = String.downcase(key)
    Keyring.get(normalized, nil)
  end

  @doc """
  Lists all available configuration keys.

  Returns a list of strings representing available configuration keys.
  """
  @spec list_keys() :: [String.t()]
  def list_keys do
    Keyring.list(Keyring)
  end

  @doc """
  Gets configuration values using atom list paths with Keyring fallback.

  Supports various configuration access patterns:
  - Simple keys: `[:http_client]`
  - Provider configs: `[:openai]`
  - Nested provider settings: `[:openai, :api_key]`
  - Timeout configs: `[:receive_timeout]`

  ## Examples

      # Get provider config
      Jido.AI.config([:openai])

      # Get specific provider setting
      Jido.AI.config([:openai, :base_url])

      # Get timeout with default
      Jido.AI.config([:receive_timeout], 60_000)

      # Get API key with Keyring fallback
      Jido.AI.config([:openai, :api_key])
  """
  @spec config(list(atom()), term()) :: term()
  def config(keyspace, default \\ nil)

  def config([main_key | rest] = keyspace, default) when is_list(keyspace) do
    case Application.get_env(:jido_ai, main_key) do
      nil when rest == [] ->
        # For simple keys like [:http_client], try keyring fallback
        Keyring.get(Keyring, main_key, default)

      nil ->
        # For nested keys like [:openai, :api_key], check keyring with provider format
        if length(rest) == 1 and hd(rest) == :api_key do
          key = :"#{main_key}_api_key"
          Keyring.get(Keyring, key, default)
        else
          default
        end

      main when rest == [] ->
        main

      main when is_list(main) ->
        Enum.reduce(rest, main, fn next_key, current ->
          case Keyword.fetch(current, next_key) do
            {:ok, val} ->
              val

            :error ->
              # For :api_key, try keyring fallback with provider format
              if next_key == :api_key do
                key = :"#{main_key}_api_key"
                Keyring.get(Keyring, key, default)
              else
                default
              end
          end
        end)

      _main ->
        default
    end
  end

  # ===========================================================================
  # Model API - Developer sugar for creating models
  # ===========================================================================

  @doc """
  Gets a provider module from the provider registry.

  ## Parameters

    * `provider` - The AI provider atom

  ## Examples

      {:ok, provider_module} = Jido.AI.provider(:openai)
      {:ok, provider_module} = Jido.AI.provider(:anthropic)
      {:error, "Provider not found: unknown"} = Jido.AI.provider(:unknown)

  """
  @spec provider(atom()) :: {:ok, module()} | {:error, String.t()}
  def provider(provider) do
    Jido.AI.Provider.Registry.fetch(provider)
  end

  @doc """
  Creates a model from various input formats for maximum developer ergonomics.

  Supports multiple input formats:
  - String format: `"provider:model"` (e.g., "openrouter:anthropic/claude-3.5-sonnet")
  - Tuple format: `{provider, opts}` where provider is atom and opts is keyword list
  - Existing Model struct (returns as-is)

  ## Examples

      # String format - super concise
      Jido.AI.model("openrouter:anthropic/claude-3.5-sonnet")

      # Tuple format - flexible with options
      Jido.AI.model({:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7})

      # With additional configuration
      Jido.AI.model({:openai, model: "gpt-4", max_tokens: 2000, temperature: 0.5})

  """
  @spec model(Model.t() | {atom(), keyword()} | String.t()) ::
          {:ok, Model.t()} | {:error, String.t()}
  def model(spec) do
    Model.from(spec)
  end

  @doc """
  Generates text using an AI model with maximum developer ergonomics.

  Accepts flexible model specifications and generates text using the appropriate provider.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - Model struct: `%Jido.AI.Model{}`
      - String format: `"openrouter:anthropic/claude-3.5-sonnet"` (important supported format)
      - Tuple format: `{:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7}`
    * `messages` - Messages for generation (string or list of Message structs)
    * `opts` - Additional options (keyword list), including:
      - `system_prompt` - Optional system prompt to prepend to the conversation (string or nil)
      - `actions` - List of Jido Action modules to make available as tools
      - `tools` - Raw tool definitions (alternative to actions)
      - `temperature` - Control randomness in responses
      - `max_tokens` - Limit the length of the response
      - Provider-specific options via `provider_options`

  ## Examples

      # Basic usage with string format (primary supported format)
      {:ok, response} = Jido.AI.generate_text(
        "openrouter:anthropic/claude-3.5-sonnet",
        "Hello, world!"
      )

      # With Jido Actions as tools
      {:ok, response} = Jido.AI.generate_text(
        "openai:gpt-4o",
        "What's the weather in SF and what's 5 + 3?",
        actions: [MyApp.Actions.Weather, MyApp.Actions.Calculator]
      )

      # With system prompt and actions
      {:ok, response} = Jido.AI.generate_text(
        "openai:gpt-4o",
        "Help me with calculations",
        system_prompt: "You are a helpful assistant",
        actions: [MyApp.Actions.Calculator]
      )

      # With raw tool definitions
      {:ok, response} = Jido.AI.generate_text(
        "openai:gpt-4o",
        "Call my custom function",
        tools: [%{type: "function", function: %{name: "my_tool", description: "..."}}]
      )

      # System prompt with message arrays
      messages = [%Jido.AI.Message{role: :user, content: "Hello"}]
      {:ok, response} = Jido.AI.generate_text(
        "openrouter:anthropic/claude-3.5-sonnet",
        messages,
        system_prompt: "You are helpful"
      )

  """

  @generate_text_opts_schema [
    temperature: [
      type: {:custom, Util, :validate_temperature, []},
      doc: "Sampling temperature in the OpenAI range 0.0 – 2.0"
    ],
    max_tokens: [
      type: :pos_integer,
      doc: "Maximum number of tokens to generate (provider default when nil)"
    ],
    system_prompt: [
      type: {:or, [:string, nil]},
      doc: "Optional system prompt prepended to the conversation"
    ],
    actions: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: [],
      doc: "List of Jido Action modules to expose as tools"
    ],
    tools: [
      type: {:list, :map},
      default: [],
      doc: "Raw tool definitions (alternative to :actions)"
    ],
    provider_options: [
      type: :keyword_list,
      default: [],
      doc: "Options forwarded verbatim to the provider adapter"
    ]
  ]

  @generate_object_opts_schema [
    output_type: [
      type: {:in, [:object, :array, :enum, :no_schema]},
      default: :object,
      doc: "Type of output to generate"
    ],
    enum_values: [
      type: {:list, :string},
      default: [],
      doc: "List of allowed values when output_type is :enum"
    ],
    temperature: [
      type: {:custom, Util, :validate_temperature, []},
      doc: "Sampling temperature in the OpenAI range 0.0 – 2.0"
    ],
    max_tokens: [
      type: :pos_integer,
      doc: "Maximum number of tokens to generate (provider default when nil)"
    ],
    system_prompt: [
      type: {:or, [:string, nil]},
      doc: "Optional system prompt prepended to the conversation"
    ],
    actions: [
      type: {:custom, Jido.Util, :validate_actions, []},
      default: [],
      doc: "List of Jido Action modules to expose as tools"
    ],
    tools: [
      type: {:list, :map},
      default: [],
      doc: "Raw tool definitions (alternative to :actions)"
    ],
    provider_options: [
      type: :keyword_list,
      default: [],
      doc: "Options forwarded verbatim to the provider adapter"
    ]
  ]

  @spec generate_text(
          Model.t() | {atom(), keyword()} | String.t(),
          String.t() | [Message.t()],
          keyword()
        ) :: {:ok, String.t()} | {:error, term()}
  def generate_text(model_spec, messages, opts \\ []) when is_binary(messages) or is_list(messages) do
    opts = process_tool_options(opts)

    with {:ok, model} <- Jido.AI.model(model_spec),
         {:ok, provider} <- Jido.AI.provider(model.provider),
         {:ok, messages} <- Messages.validate(messages),
         {:ok, validated_opts} <- Util.validate_schema(opts, @generate_text_opts_schema) do
      provider.generate_text(model, messages, validated_opts)
    end
  end

  @doc """
  Streams text using an AI model with maximum developer ergonomics.

  Accepts flexible model specifications and streams text using the appropriate provider.
  Returns a Stream that emits text chunks as they arrive.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - Model struct: `%Jido.AI.Model{}`
      - String format: `"openrouter:anthropic/claude-3.5-sonnet"` (important supported format)
      - Tuple format: `{:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7}`
    * `prompt` - Text prompt to generate from (string or list of messages)
    * `opts` - Additional options (keyword list), including:
      - `system_prompt` - Optional system prompt to prepend to the conversation (string or nil)
      - `actions` - List of Jido Action modules to make available as tools
      - `tools` - Raw tool definitions (alternative to actions)
      - `temperature` - Control randomness in responses
      - `max_tokens` - Limit the length of the response
      - Provider-specific options via `provider_options`

  ## Examples

      # Basic usage with string format (primary supported format)
      {:ok, stream} = Jido.AI.stream_text(
        "openrouter:anthropic/claude-3.5-sonnet",
        "Hello, world!"
      )

      # With Jido Actions as tools
      {:ok, stream} = Jido.AI.stream_text(
        "openai:gpt-4o",
        "What's the weather and calculate 5 + 3",
        actions: [MyApp.Actions.Weather, MyApp.Actions.Calculator]
      )

      # Consume the stream
      stream |> Enum.each(&IO.write/1)

      # With system prompt and actions
      {:ok, stream} = Jido.AI.stream_text(
        "openai:gpt-4o",
        "Help me with math",
        system_prompt: "You are a helpful assistant",
        actions: [MyApp.Actions.Calculator]
      )

      # With raw tool definitions
      {:ok, stream} = Jido.AI.stream_text(
        "openai:gpt-4o",
        "Use my custom tool",
        tools: [%{type: "function", function: %{name: "my_tool", description: "..."}}]
      )

  """

  @spec stream_text(
          Model.t() | {atom(), keyword()} | String.t(),
          String.t() | [Message.t()],
          keyword()
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_text(model_spec, messages, opts \\ []) when is_binary(messages) or is_list(messages) do
    opts = process_tool_options(opts)

    with {:ok, model} <- Jido.AI.model(model_spec),
         {:ok, provider} <- Jido.AI.provider(model.provider),
         {:ok, messages} <- Messages.validate(messages),
         {:ok, validated_opts} <- Util.validate_schema(opts, @generate_text_opts_schema) do
      provider.stream_text(model, messages, validated_opts)
    end
  end

  @doc """
  Generates structured data using an AI model with schema validation.

  Accepts flexible model specifications and generates validated structured data using the appropriate provider.
  The response is validated against the provided NimbleOptions schema and returns a structured map.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - Model struct: `%Jido.AI.Model{}`
      - String format: `"openrouter:anthropic/claude-3.5-sonnet"` (important supported format)
      - Tuple format: `{:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7}`
    * `prompt` - Text prompt to generate from (string or list of messages)
    * `schema` - NimbleOptions schema definition for validation (keyword list)
    * `opts` - Additional options (keyword list)

  ## Options

    * `:output_type` - Type of output: `:object`, `:array`, `:enum`, `:no_schema` (default: `:object`)
    * `:enum_values` - List of allowed values when output_type is `:enum`
    * `:system_prompt` - Optional system prompt to prepend to the conversation (string or nil)
    * `:actions` - List of Jido Action modules to make available as tools
    * `:tools` - Raw tool definitions (alternative to actions)
    * `:temperature` - Control randomness in responses
    * `:max_tokens` - Limit the length of the response
    * `:provider_options` - Provider-specific options

  ## Examples

      # Basic object generation
      schema = [
        name: [type: :string, required: true],
        age: [type: :pos_integer, required: true]
      ]
      {:ok, result} = Jido.AI.generate_object(
        "openai:gpt-4o",
        "Generate a person",
        schema
      )
      #=> {:ok, %{name: "John Doe", age: 30}}

      # Array generation
      schema = [
        name: [type: :string, required: true],
        score: [type: :integer, required: true]
      ]
      {:ok, results} = Jido.AI.generate_object(
        "openai:gpt-4o",
        "Generate 3 player scores",
        schema,
        output_type: :array
      )
      #=> {:ok, [%{name: "Alice", score: 95}, %{name: "Bob", score: 87}]}

      # Enum generation
      {:ok, color} = Jido.AI.generate_object(
        "openai:gpt-4o",
        "Choose a color",
        [],
        output_type: :enum,
        enum_values: ["red", "green", "blue"]
      )
      #=> {:ok, "blue"}

      # With system prompt
      {:ok, result} = Jido.AI.generate_object(
        "openai:gpt-4o",
        "Create user data",
        schema,
        system_prompt: "You are a helpful assistant"
      )

  """

  @spec generate_object(
          Model.t() | {atom(), keyword()} | String.t(),
          String.t() | [Message.t()],
          keyword(),
          keyword()
        ) :: {:ok, map()} | {:error, term()}
  def generate_object(model_spec, messages, schema, opts \\ [])
      when (is_binary(messages) or is_list(messages)) and is_list(schema) and is_list(opts) do
    opts = process_tool_options(opts)

    with {:ok, model} <- Jido.AI.model(model_spec),
         {:ok, provider} <- Jido.AI.provider(model.provider),
         {:ok, messages} <- Messages.validate(messages),
         {:ok, validated_opts} <- Util.validate_schema(opts, @generate_object_opts_schema),
         {:ok, object_schema} <- build_object_schema(schema, validated_opts) do
      case provider.generate_object(model, messages, object_schema, validated_opts) do
        {:ok, raw_result} ->
          ObjectSchema.validate(object_schema, raw_result)

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc """
  Streams structured data using an AI model with schema validation.

  Accepts flexible model specifications and streams validated structured data using the appropriate provider.
  Returns a Stream that emits validated structured data chunks as they arrive.

  ## Parameters

    * `model_spec` - Model specification in various formats:
      - Model struct: `%Jido.AI.Model{}`
      - String format: `"openrouter:anthropic/claude-3.5-sonnet"` (important supported format)
      - Tuple format: `{:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7}`
    * `prompt` - Text prompt to generate from (string or list of messages)
    * `schema` - NimbleOptions schema definition for validation (keyword list)
    * `opts` - Additional options (keyword list)

  ## Options

  Same as `generate_object/4`.

  ## Examples

      # Stream object generation
      schema = [
        name: [type: :string, required: true],
        score: [type: :integer, required: true]
      ]

      {:ok, stream} = Jido.AI.stream_object(
        "openai:gpt-4o",
        "Generate player data",
        schema
      )

      # Consume the stream
      stream |> Enum.each(&IO.inspect/1)

      # With system prompt and tools
      {:ok, stream} = Jido.AI.stream_object(
        "openai:gpt-4o",
        "Generate structured data",
        schema,
        system_prompt: "You are a data generator",
        actions: [MyApp.Actions.DataHelper]
      )

  """

  # 4-arity: model_spec, messages, schema, opts
  @spec stream_object(
          Model.t() | {atom(), keyword()} | String.t(),
          String.t() | [Message.t()],
          keyword(),
          keyword()
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_object(model_spec, messages, schema, opts \\ [])
      when (is_binary(messages) or is_list(messages)) and is_list(schema) and is_list(opts) do
    opts = process_tool_options(opts)

    with {:ok, model} <- Jido.AI.model(model_spec),
         {:ok, provider} <- Jido.AI.provider(model.provider),
         {:ok, messages} <- Messages.validate(messages),
         {:ok, validated_opts} <- Util.validate_schema(opts, @generate_object_opts_schema),
         {:ok, object_schema} <- build_object_schema(schema, validated_opts) do
      case provider.stream_object(model, messages, object_schema, validated_opts) do
        {:ok, stream} ->
          # Validate each chunk in the stream
          validated_stream =
            Stream.map(stream, fn chunk ->
              case ObjectSchema.validate(object_schema, chunk) do
                {:ok, validated} -> validated
                {:error, error} -> raise error
              end
            end)

          {:ok, validated_stream}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  @doc false
  @spec process_tool_options(keyword()) :: keyword()
  defp process_tool_options(opts) do
    {actions, opts} = Keyword.pop(opts, :actions, [])
    {tools_opt, opts} = Keyword.pop(opts, :tools, [])

    tools =
      cond do
        actions != [] ->
          actions
          |> Enum.map(&Tool.to_tool/1)
          |> Enum.map(&convert_tool_to_openai_format/1)

        tools_opt != [] ->
          tools_opt

        true ->
          []
      end

    if tools == [] do
      opts
    else
      Keyword.put(opts, :tools, tools)
    end
  end

  @doc false
  @spec convert_tool_to_openai_format(%{name: String.t(), description: String.t(), parameters_schema: map()}) :: %{
          String.t() => String.t() | map()
        }
  defp convert_tool_to_openai_format(%{name: name, description: description, parameters_schema: schema}) do
    %{
      type: "function",
      function: %{
        "name" => name,
        "description" => description,
        "parameters" => schema
      }
    }
  end

  @doc false
  @spec build_object_schema(keyword(), keyword()) ::
          {:ok, ObjectSchema.t()} | {:error, String.t()}
  defp build_object_schema(schema, opts) do
    output_type = Keyword.get(opts, :output_type, :object)
    enum_values = Keyword.get(opts, :enum_values, [])

    schema_opts = [
      output_type: output_type,
      properties: schema,
      enum_values: enum_values
    ]

    ObjectSchema.new(schema_opts)
  end
end
