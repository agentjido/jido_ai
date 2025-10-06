defmodule Jido.AI.Actions.Instructor do
  @moduledoc """
  A low-level action that provides direct access to Instructor's chat completion functionality.
  Supports most Instructor options and integrates with Jido's Model and Prompt structures.

  ## Features

  - Multi-provider support (Anthropic, OpenAI, Ollama, llamacpp, Together, OpenRouter, etc.)
  - Streaming capabilities with array or partial response models
  - Response mode configuration (:json, :function_call)
  - Structured output validation with automatic retries
  - Optional context window validation and automatic truncation
  - Specialized features support (RAG, code execution, plugins, fine-tuning)
    - Check feature availability: `Jido.AI.Features.supports?(model, :rag)`
    - RAG document preparation: `Jido.AI.Features.RAG.prepare_documents/2`
    - Plugin configuration: `Jido.AI.Features.Plugins.configure_plugin/2`
    - Fine-tuning detection: `Jido.AI.Features.FineTuning.is_fine_tuned?/1`

  ## Usage

  ```elixir
  # Define a response model with Ecto
  defmodule WeatherResponse do
    use Ecto.Schema

    embedded_schema do
      field :temperature, :float
      field :conditions, :string
      field :city, :string
    end
  end

  # Create a structured response
  {:ok, result, _} = Jido.AI.Actions.Instructor.run(%{
    model: %Jido.AI.Model{provider: :anthropic, model: "claude-3-sonnet-20240229", api_key: "key"},
    prompt: Jido.AI.Prompt.new(:user, "What's the weather in Tokyo?"),
    response_model: WeatherResponse,
    max_retries: 2
  })

  # Advanced: JSON mode with OpenAI
  {:ok, result, _} = Jido.AI.Actions.Instructor.run(%{
    model: %Jido.AI.Model{provider: :openai, model: "gpt-4", api_key: "key"},
    prompt: Jido.AI.Prompt.new(:user, "List cities"),
    response_model: CitiesList,
    response_format: %{type: "json_object"}
  })

  # Advanced: Logit bias to control token probabilities
  {:ok, result, _} = Jido.AI.Actions.Instructor.run(%{
    model: %Jido.AI.Model{provider: :openai, model: "gpt-4", api_key: "key"},
    prompt: Jido.AI.Prompt.new(:user, "Write a response"),
    response_model: Response,
    logit_bias: %{1234 => -100}  # Suppress specific token
  })

  # Advanced: Provider-specific options
  {:ok, result, _} = Jido.AI.Actions.Instructor.run(%{
    model: %Jido.AI.Model{provider: :openai, model: "gpt-4", api_key: "key"},
    prompt: Jido.AI.Prompt.new(:user, "Analyze text"),
    response_model: Analysis,
    provider_options: [
      logprobs: true,
      top_logprobs: 5
    ]
  })

  # Advanced: Context window validation
  {:ok, result, _} = Jido.AI.Actions.Instructor.run(%{
    model: %Jido.AI.Model{provider: :openai, model: "gpt-3.5-turbo", api_key: "key"},
    prompt: very_long_prompt,
    response_model: Analysis,
    check_context_window: true,
    truncation_strategy: :smart_truncate,
    max_tokens: 500
  })
  ```

  ## Advanced Parameters

  ### JSON Mode & Response Format
  The `response_format` parameter controls structured output generation:
  - OpenAI/Compatible: `%{type: "json_object"}` enables JSON mode
  - Combined with Ecto schemas for automatic validation

  ### Logit Bias
  The `logit_bias` parameter adjusts token probabilities (OpenAI/compatible providers):
  - Map of token IDs to bias values (-100 to 100)
  - Use to suppress/encourage specific tokens

  ### Provider Options
  The `provider_options` parameter allows provider-specific features:
  - OpenAI: `[logprobs: true, top_logprobs: 5]` - Get token probabilities
  - Groq: `[reasoning_effort: "high"]` - Control reasoning depth
  - Anthropic: `[anthropic_top_k: 40]` - Nucleus sampling parameter
  - OpenRouter: `[openrouter_models: ["fallback/model"]]` - Fallback models

  ### Context Window Management
  The `check_context_window` and `truncation_strategy` parameters enable automatic prompt management:
  - **`check_context_window: true`** - Validates prompt fits in model's context window
  - **`truncation_strategy`** - Chooses how to truncate if needed:
    - `:smart_truncate` (default) - Preserves system message, first user message, and recent context
    - `:keep_recent` - Keeps only the most recent messages
    - `:keep_bookends` - Preserves system message plus recent messages
    - `:sliding_window` - Uses overlapping windows for continuity
  - Automatically reserves space for `max_tokens` completion
  - Logs warning when truncation occurs

  ### Grammar Constraints (Note)
  Traditional grammar-constrained generation (GBNF/BNF) is not currently supported
  by ReqLLM or most API-based providers. Instead, use:
  - **Ecto schemas** with Instructor for structured output validation
  - **JSON mode** (`response_format`) for format constraints
  - **Tool definitions** for controlled outputs
  - **Provider-specific modes** (e.g., Anthropic strict mode via provider_options)

  ## Support Matrix

  | Provider   | Adapter               | Configuration                     |
  |------------|----------------------|----------------------------------|
  | anthropic  | Anthropic            | api_key                          |
  | openai     | OpenAI               | openai: [api_key: "key"]         |
  | openrouter | OpenAI               | openai: [api_key, api_url]       |
  | ollama     | OpenAI               | openai: [api_key, api_url]       |
  | llamacpp   | Llamacpp             | llamacpp: [api_url]              |
  | together   | OpenAI               | openai: [api_key, api_url]       |
  | other      | Defaults to Anthropic| api_key                          |
  """
  use Jido.Action,
    name: "instructor_chat_completion",
    description: "Makes a raw chat completion call using Instructor with structured prompting",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc:
          "The AI model to use (e.g., {:anthropic, [model: \"claude-3-sonnet-20240229\"]} or %Jido.AI.Model{})"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt to use for the response"
      ],
      response_model: [
        type: :any,
        required: true,
        doc: "Ecto schema or type definition for structured response"
      ],
      max_retries: [
        type: :integer,
        default: 0,
        doc: "Number of retries for validation failures"
      ],
      temperature: [type: :float, default: 0.7, doc: "Temperature for response randomness"],
      max_tokens: [type: :integer, default: 1000, doc: "Maximum tokens in response"],
      top_p: [type: :float, doc: "Top p sampling parameter"],
      stop: [type: {:list, :string}, doc: "Stop sequences"],
      timeout: [type: :integer, default: 60_000, doc: "Request timeout in milliseconds"],
      mode: [
        type: {:in, [:tools, :json, :md_json]},
        default: :tools,
        doc: "Response mode (:tools, :json, :md_json, or nil for default)"
      ],
      stream: [type: :boolean, default: false, doc: "Enable streaming responses"],
      partial: [type: :boolean, default: false, doc: "Return partial responses while streaming"],
      response_format: [
        type: :map,
        doc: "Response format specification (e.g., %{type: \"json_object\"}) for JSON mode"
      ],
      logit_bias: [
        type: :map,
        doc: "Map of token IDs to bias values (-100 to 100) to adjust token likelihood"
      ],
      provider_options: [
        type: {:or, [:map, {:list, :any}]},
        doc: """
        Provider-specific options (keyword list or map). Examples:
        - OpenAI: [logprobs: true, top_logprobs: 5]
        - Groq: [reasoning_effort: "high", service_tier: "performance"]
        - Anthropic: [anthropic_top_k: 40]
        - OpenRouter: [openrouter_top_logprobs: 5, openrouter_models: ["fallback/model"]]
        """
      ],
      check_context_window: [
        type: :boolean,
        default: false,
        doc: "Enable automatic context window validation and truncation if needed"
      ],
      truncation_strategy: [
        type: {:in, [:keep_recent, :keep_bookends, :sliding_window, :smart_truncate]},
        default: :smart_truncate,
        doc: "Strategy to use if context window truncation is needed"
      ]
    ]

  alias Jido.AI.{Model, Prompt, ContextWindow}
  require Logger

  @impl true
  def on_before_validate_params(params) do
    with {:ok, model} <- validate_model(params.model),
         {:ok, prompt} <- Prompt.validate_prompt_opts(params.prompt) do
      {:ok, %{params | model: model, prompt: prompt}}
    else
      {:error, reason} ->
        Logger.error("BaseCompletion validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def run(params, _context) do
    # Extract options from prompt if available
    prompt_opts =
      case params[:prompt] do
        %Prompt{options: options} when is_list(options) and length(options) > 0 ->
          Map.new(options)

        _ ->
          %{}
      end

    # Keep required parameters
    required_params = Map.take(params, [:model, :prompt, :response_model])

    # Create a map with all optional parameters set to defaults
    # Priority: explicit params > prompt options > defaults
    params_with_defaults =
      %{
        top_p: nil,
        stop: nil,
        stream: false,
        partial: false,
        max_retries: 0,
        temperature: 0.7,
        max_tokens: 1000,
        mode: nil,
        response_format: nil,
        logit_bias: nil,
        provider_options: nil,
        check_context_window: false,
        truncation_strategy: :smart_truncate
      }
      # Apply prompt options over defaults
      |> Map.merge(prompt_opts)
      # Apply explicit params over prompt options
      |> Map.merge(
        Map.take(params, [
          :top_p,
          :stop,
          :stream,
          :partial,
          :max_retries,
          :temperature,
          :max_tokens,
          :mode,
          :response_format,
          :logit_bias,
          :provider_options,
          :check_context_window,
          :truncation_strategy
        ])
      )
      # Always keep required params
      |> Map.merge(required_params)

    # Validate and potentially truncate prompt if context window checking is enabled
    case maybe_check_context(params_with_defaults) do
      {:ok, final_params} ->
        execute_instructor_call(final_params)

      {:error, reason} ->
        Logger.error("Context window validation failed: #{inspect(reason)}")
        {:error, "Context window exceeded: #{inspect(reason)}", %{}}
    end
  end

  defp maybe_check_context(%{check_context_window: false} = params), do: {:ok, params}

  defp maybe_check_context(params) do
    case ContextWindow.ensure_fit(
           params.prompt,
           params.model,
           strategy: params.truncation_strategy,
           reserve_completion: params.max_tokens
         ) do
      {:ok, truncated_prompt} ->
        if truncated_prompt != params.prompt do
          Logger.info("Prompt truncated to fit context window")
        end

        {:ok, %{params | prompt: truncated_prompt}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_instructor_call(params_with_defaults) do
    # Build the Instructor options
    model = get_model(params_with_defaults.model)

    # Configure Instructor with the appropriate adapter and API key
    config = get_instructor_config(params_with_defaults.model)

    opts =
      [
        model: model,
        messages: convert_messages(params_with_defaults.prompt.messages),
        response_model: get_response_model(params_with_defaults),
        temperature: params_with_defaults.temperature,
        max_tokens: params_with_defaults.max_tokens,
        max_retries: params_with_defaults.max_retries,
        stream: params_with_defaults.stream
      ]
      |> add_if_present(:top_p, params_with_defaults.top_p)
      |> add_if_present(:stop, params_with_defaults.stop)
      |> add_if_present(:mode, params_with_defaults.mode)
      |> add_if_present(:response_format, params_with_defaults.response_format)
      |> add_if_present(:logit_bias, params_with_defaults.logit_bias)
      |> maybe_add_provider_options(params_with_defaults.provider_options)

    # IO.inspect(opts, label: "Instructor opts")
    # IO.inspect(config, label: "Instructor config")
    # Make the chat completion call
    case Instructor.chat_completion(opts, config) do
      {:ok, response} ->
        {:ok, %{result: response}, %{}}

      {:error, reason} ->
        Logger.error("Chat completion failed: #{inspect(reason)}")
        {:error, reason, %{}}

      nil ->
        Logger.error("Chat completion returned nil")
        {:error, "Instructor chat completion returned nil", %{}}

      other ->
        Logger.error("Unexpected response: #{inspect(other)}")
        {:error, "Unexpected response from Instructor: #{inspect(other)}", %{}}
    end
  end

  # Helper to validate model input
  defp validate_model(%Model{} = model), do: {:ok, model}

  defp validate_model(spec) when is_tuple(spec), do: Model.from(spec)

  defp validate_model(other) do
    Logger.error("Invalid model specification: #{inspect(other)}")
    {:error, "Invalid model specification: #{inspect(other)}"}
  end

  # Helper to get the model ID from our Model struct
  defp get_model(%Model{model: model}), do: model
  defp get_model(_), do: nil

  # Helper to handle array and partial response models
  defp get_response_model(%{response_model: model, stream: true, partial: true}),
    do: {:partial, model}

  defp get_response_model(%{response_model: model, stream: true}), do: {:array, model}
  defp get_response_model(%{response_model: model}), do: model

  defp add_if_present(opts, _key, nil), do: opts
  defp add_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  # Handle provider-specific options (map or keyword list)
  defp maybe_add_provider_options(opts, nil), do: opts

  defp maybe_add_provider_options(opts, provider_opts) when is_map(provider_opts) do
    provider_opts
    |> Enum.reduce(opts, fn {key, value}, acc ->
      Keyword.put(acc, key, value)
    end)
  end

  defp maybe_add_provider_options(opts, provider_opts) when is_list(provider_opts) do
    Keyword.merge(opts, provider_opts)
  end

  # Convert messages to Instructor format
  defp convert_messages(messages) do
    Enum.map(messages, fn message ->
      %{
        role: to_string(message.role),
        content: message.content
      }
    end)
  end

  # Select appropriate adapter based on model provider
  defp get_instructor_config(%Model{provider: :anthropic, api_key: api_key}) do
    [
      adapter: Instructor.Adapters.Anthropic,
      api_key: api_key
    ]
  end

  defp get_instructor_config(%Model{provider: :openai, api_key: api_key}) do
    [
      adapter: Instructor.Adapters.OpenAI,
      openai: [
        api_key: api_key
      ]
    ]
  end

  defp get_instructor_config(%Model{provider: :openrouter, api_key: api_key, base_url: base_url}) do
    [
      adapter: Instructor.Adapters.OpenAI,
      openai: [
        api_key: api_key,
        api_url: base_url || "https://openrouter.ai/api/v1"
      ]
    ]
  end

  defp get_instructor_config(%Model{provider: :ollama, api_key: api_key, base_url: base_url}) do
    [
      adapter: Instructor.Adapters.OpenAI,
      openai: [
        api_key: api_key || "ollama",
        api_url: base_url || "http://localhost:11434"
      ]
    ]
  end

  defp get_instructor_config(%Model{provider: :llamacpp, base_url: base_url}) do
    [
      adapter: Instructor.Adapters.Llamacpp,
      llamacpp: [
        api_url: base_url || "http://localhost:8080/completion"
      ]
    ]
  end

  defp get_instructor_config(%Model{provider: :together, api_key: api_key}) do
    [
      adapter: Instructor.Adapters.OpenAI,
      openai: [
        api_key: api_key,
        api_url: "https://api.together.xyz"
      ]
    ]
  end

  defp get_instructor_config(%Model{provider: provider, api_key: api_key}) do
    Logger.warning(
      "No specific adapter for provider: #{provider}, defaulting to Anthropic adapter"
    )

    [
      adapter: Instructor.Adapters.Anthropic,
      api_key: api_key
    ]
  end
end
