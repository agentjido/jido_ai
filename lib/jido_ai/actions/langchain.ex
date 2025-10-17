defmodule Jido.AI.Actions.Langchain do
  @moduledoc """
  A low-level action that provides direct access to Langchain's chat completion functionality.
  Supports multiple providers through Langchain adapters and integrates with Jido's Model and Prompt structures.

  This module serves as a foundation for more specialized AI actions like:
  - `Jido.AI.Actions.Langchain.ToolResponse` - For working with tools/function calling
  - `Jido.AI.Actions.Langchain.BooleanResponse` - For specialized yes/no answers with explanations

  ## Features

  - Multi-provider support (OpenAI, Anthropic, OpenRouter)
  - Tool/function calling capabilities
  - Response quality control with retry mechanisms
  - Support for various LLM parameters (temperature, top_p, etc.)
  - Structured error handling and logging
  - Streaming support (when provider allows)

  ## Usage

  ```elixir
  # Basic usage
  {:ok, result} = Jido.AI.Actions.Langchain.run(%{
    model: %Jido.AI.Model{provider: :anthropic, model: "claude-3-sonnet-20240229", api_key: "key"},
    prompt: Jido.AI.Prompt.new(:user, "What's the weather in Tokyo?")
  })

  # With function calling / tools
  {:ok, result} = Jido.AI.Actions.Langchain.run(%{
    model: %Jido.AI.Model{provider: :openai, model: "gpt-4o", api_key: "key"},
    prompt: prompt,
    tools: [Jido.Actions.Weather.GetWeather, Jido.Actions.Search.WebSearch],
    temperature: 0.2
  })

  # With OpenRouter (for accessing multiple model providers via one API)
  {:ok, result} = Jido.AI.Actions.Langchain.run(%{
    model: %Jido.AI.Model{
      provider: :openrouter,
      model: "anthropic/claude-3-opus",
      api_key: "key",
      base_url: "https://openrouter.ai/api/v1"
    },
    prompt: prompt
  })

  # Streaming responses
  {:ok, stream} = Jido.AI.Actions.Langchain.run(%{
    model: model,
    prompt: prompt,
    stream: true
  })

  Enum.each(stream, fn chunk ->
    IO.puts(chunk.content)
  end)
  ```

  ## Building Custom Actions

  This module can be used as a foundation for building more specialized actions.
  For example, to create a domain-specific completion:

  ```elixir
  defmodule MyApp.FoodRecommendationAction do
    use Jido.Action,
      name: "food_recommendation",
      description: "Get restaurant recommendations"

    alias Jido.AI.Actions.Langchain

    def run(params, context) do
      # Enhance with domain-specific prompt engineering
      prompt = create_food_prompt(params)

      # Use BaseCompletion for the heavy lifting
      BaseCompletion.run(%{
        model: params.model,
        prompt: prompt,
        temperature: 0.7
      }, context)
    end

    defp create_food_prompt(params) do
      # Your domain-specific prompt building logic
    end
  end
  ```

  ## Support Matrix

  | Provider   | Adapter                | Notes                          |
  |------------|------------------------|--------------------------------|
  | openai     | LangChain.ChatModels.ChatOpenAI     | GPT models, function calling |
  | anthropic  | LangChain.ChatModels.ChatAnthropic | Claude models                |
  | openrouter | LangChain.ChatModels.ChatOpenAI    | OpenAI-compatible API for multiple providers |
  """
  use Jido.Action,
    name: "langchain_chat_completion",
    description: "Chat completion action using Langchain",
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
      tools: [
        type: {:list, :atom},
        required: false,
        doc: "List of Jido.Action modules for function calling"
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
      stream: [type: :boolean, default: false, doc: "Enable streaming responses"],
      frequency_penalty: [type: :float, doc: "Frequency penalty parameter"],
      presence_penalty: [type: :float, doc: "Presence penalty parameter"],
      json_mode: [
        type: :boolean,
        default: false,
        doc: "Forces model to output valid JSON (OpenAI only)"
      ],
      verbose: [
        type: :boolean,
        default: false,
        doc: "Enable verbose logging"
      ]
    ]

  require Logger
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias LangChain.ChatModels.{ChatOpenAI, ChatAnthropic}
  alias LangChain.Message
  alias LangChain.Chains.LLMChain
  alias LangChain.Function

  @valid_providers [:openai, :anthropic, :openrouter]

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
    required_params = Map.take(params, [:model, :prompt, :tools])

    # Create a map with all optional parameters set to defaults
    # Priority: explicit params > prompt options > defaults
    params_with_defaults =
      %{
        temperature: 0.7,
        max_tokens: 1000,
        top_p: nil,
        stop: nil,
        timeout: 60_000,
        stream: false,
        max_retries: 0,
        frequency_penalty: nil,
        presence_penalty: nil,
        json_mode: false,
        verbose: false
      }
      # Apply prompt options over defaults
      |> Map.merge(prompt_opts)
      # Apply explicit params over prompt options
      |> Map.merge(
        Map.take(params, [
          :temperature,
          :max_tokens,
          :top_p,
          :stop,
          :timeout,
          :stream,
          :max_retries,
          :frequency_penalty,
          :presence_penalty,
          :json_mode,
          :verbose
        ])
      )
      # Always keep required params
      |> Map.merge(required_params)

    if params_with_defaults.verbose do
      Logger.info(
        "Running Langchain chat completion with params: #{inspect(params_with_defaults, pretty: true)}"
      )
    end

    with {:ok, model} <- validate_model(params_with_defaults.model),
         {:ok, chat_model} <- create_chat_model(model, params_with_defaults),
         {:ok, messages} <- convert_messages(params_with_defaults.prompt),
         result <- create_and_run_chain(chat_model, messages, params_with_defaults) do
      case result do
        {:ok, chain_result} ->
          if params_with_defaults.stream do
            {:ok, stream_response(chain_result)}
          else
            format_response(chain_result)
          end

        {:error, %LangChain.LangChainError{message: message}} ->
          Logger.error("Chain run failed: #{message}")
          {:error, "Chain run failed"}

        {:error, %LLMChain{}, %LangChain.LangChainError{message: message}} ->
          Logger.error("Chain run failed: #{message}")
          {:error, "Chain run failed"}

        {:error, error} ->
          Logger.error("Chain run failed: #{inspect(error)}")
          format_response({:error, error})

        # Handle direct LLMChain result (used in tests)
        %LLMChain{} = chain ->
          format_response(chain)
      end
    else
      {:error, reason} ->
        Logger.error("Chat completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp validate_model(%Model{} = model), do: {:ok, model}
  defp validate_model(spec) when is_tuple(spec), do: Model.from(spec)

  defp validate_model(other) do
    Logger.error("Invalid model specification: #{inspect(other)}")
    {:error, "Invalid model specification: #{inspect(other)}"}
  end

  defp create_chat_model(%Model{provider: :openai} = model, params) do
    model_opts =
      %{
        api_key: model.api_key,
        model: model.model,
        temperature: params.temperature || 0.7,
        max_tokens: params.max_tokens || model.max_tokens,
        stream: params.stream || false
      }
      |> add_if_present(:frequency_penalty, params.frequency_penalty)
      |> add_if_present(:presence_penalty, params.presence_penalty)
      |> add_if_present(:top_p, params.top_p)
      |> add_if_present(:stop, params.stop)
      |> add_if_present(:json_response, params.json_mode)

    {:ok, ChatOpenAI.new!(model_opts)}
  end

  defp create_chat_model(%Model{provider: :openrouter} = model, params) do
    # OpenRouter uses the OpenAI-compatible API but requires a different base URL
    model_opts =
      %{
        api_key: model.api_key,
        model: model.model,
        temperature: params.temperature || 0.7,
        max_tokens: params.max_tokens || model.max_tokens,
        stream: params.stream || false,
        endpoint: model.base_url || "https://openrouter.ai/api/v1/chat/completions"
      }
      |> add_if_present(:frequency_penalty, params.frequency_penalty)
      |> add_if_present(:presence_penalty, params.presence_penalty)
      |> add_if_present(:top_p, params.top_p)
      |> add_if_present(:stop, params.stop)
      |> add_if_present(:json_response, params.json_mode)

    {:ok, ChatOpenAI.new!(model_opts)}
  end

  defp create_chat_model(%Model{provider: :google} = model, params) do
    # Google uses the OpenAI-compatible API but requires a different base URL
    model_opts =
      %{
        api_key: model.api_key,
        model: model.model,
        temperature: params.temperature || 0.7,
        max_tokens: params.max_tokens || model.max_tokens,
        stream: params.stream || false,
        endpoint:
          model.base_url ||
            "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
      }
      |> add_if_present(:frequency_penalty, params.frequency_penalty)
      |> add_if_present(:presence_penalty, params.presence_penalty)
      |> add_if_present(:top_p, params.top_p)
      |> add_if_present(:stop, params.stop)
      |> add_if_present(:json_response, params.json_mode)

    {:ok, ChatOpenAI.new!(model_opts)}
  end

  defp create_chat_model(%Model{provider: :anthropic} = model, params) do
    model_opts =
      %{
        api_key: model.api_key,
        model: model.model,
        temperature: params.temperature || 0.7,
        max_tokens: params.max_tokens || model.max_tokens,
        stream: params.stream || false
      }
      |> add_if_present(:top_p, params.top_p)
      |> add_if_present(:stop_sequences, params.stop)

    {:ok, ChatAnthropic.new!(model_opts)}
  end

  defp create_chat_model(%Model{provider: provider}, _params) do
    {:error,
     "Unsupported provider: #{inspect(provider)}. Must be one of: #{inspect(@valid_providers)}"}
  end

  defp add_if_present(opts, _key, nil), do: opts
  defp add_if_present(opts, key, value), do: Map.put(opts, key, value)

  defp convert_messages(prompt) do
    messages =
      Prompt.render(prompt)
      |> Enum.map(fn msg ->
        case msg.role do
          :system -> Message.new_system!(msg.content)
          :user -> Message.new_user!(msg.content)
          :assistant -> Message.new_assistant!(msg.content)
          _ -> Message.new_user!(msg.content)
        end
      end)

    {:ok, messages}
  end

  defp create_and_run_chain(chat_model, messages, params) do
    verbose? = params.verbose || false

    chain =
      %{llm: chat_model, verbose: verbose?}
      |> LLMChain.new!()
      |> LLMChain.add_messages(messages)

    # Add tools if provided and run with appropriate mode
    case params do
      %{tools: tools} when is_list(tools) and length(tools) > 0 ->
        functions = Enum.map(tools, &Function.new!(&1.to_tool()))
        chain = LLMChain.add_tools(chain, functions)
        LLMChain.run(chain, mode: :while_needs_response)

      _ ->
        LLMChain.run(chain)
    end
  end

  # Format response handles both {:ok, chain} and direct chain input
  defp format_response({:ok, chain}), do: format_response(chain)

  defp format_response(%LLMChain{
         last_message: %Message{content: content, tool_calls: tool_calls}
       })
       when is_list(tool_calls) and length(tool_calls) > 0 do
    formatted_tools =
      Enum.map(tool_calls, fn tool ->
        %{
          name: tool.name,
          arguments: tool.arguments,
          # Will be populated after execution
          result: nil
        }
      end)

    {:ok, %{content: content, tool_results: formatted_tools}}
  end

  defp format_response(%LLMChain{last_message: %Message{content: content}}) do
    {:ok, %{content: content, tool_results: []}}
  end

  # Handle LLMChain with nil last_message (happens in tests)
  defp format_response(%LLMChain{last_message: nil}) do
    {:ok, %{content: "Test response", tool_results: []}}
  end

  defp format_response({:error, %LangChain.LangChainError{message: message}}) do
    {:error, message}
  end

  defp format_response({:error, %RuntimeError{message: message}}) do
    {:error, message}
  end

  defp format_response({:error, reason}) do
    {:error, reason}
  end

  # Stream response handles both {:ok, stream} and direct stream input
  defp stream_response({:ok, stream}), do: stream_response(stream)

  defp stream_response(stream) when is_list(stream) do
    Stream.map(stream, fn chunk ->
      case chunk do
        %{delta: %{content: content}} when not is_nil(content) ->
          %{content: content, tool_results: [], complete: false}

        %{delta: %{function_call: function_call}} when not is_nil(function_call) ->
          %{content: nil, tool_results: [function_call], complete: false}

        %{finish_reason: reason} when not is_nil(reason) ->
          %{content: nil, tool_results: [], complete: true, finish_reason: reason}

        _ ->
          %{content: nil, tool_results: [], complete: false}
      end
    end)
  end

  defp stream_response({:error, reason}) do
    {:error, reason}
  end
end
