defmodule Jido.AI.Actions.ReqLlm.ChatCompletion do
  @moduledoc """
  Chat completion action using ReqLLM for multi-provider support.

  This action provides direct access to chat completion functionality across
  57+ providers through ReqLLM, replacing the LangChain-based implementation
  with lighter dependencies and broader provider support.

  ## Features

  - Multi-provider support (57+ providers via ReqLLM)
  - Tool/function calling capabilities
  - Response quality control with retry mechanisms
  - Support for various LLM parameters (temperature, top_p, etc.)
  - Structured error handling and logging
  - Streaming support (when provider allows)

  ## Usage

  ```elixir
  # Basic usage
  {:ok, result} = Jido.AI.Actions.ReqLlm.ChatCompletion.run(%{
    model: %Jido.AI.Model{provider: :anthropic, model: "claude-3-sonnet-20240229"},
    prompt: Jido.AI.Prompt.new(:user, "What's the weather in Tokyo?")
  })

  # With function calling / tools
  {:ok, result} = Jido.AI.Actions.ReqLlm.ChatCompletion.run(%{
    model: %Jido.AI.Model{provider: :openai, model: "gpt-4o"},
    prompt: prompt,
    tools: [Jido.Actions.Weather.GetWeather, Jido.Actions.Search.WebSearch],
    temperature: 0.2
  })

  # Streaming responses
  {:ok, stream} = Jido.AI.Actions.ReqLlm.ChatCompletion.run(%{
    model: model,
    prompt: prompt,
    stream: true
  })

  Enum.each(stream, fn chunk ->
    IO.puts(chunk.content)
  end)
  ```

  ## Support Matrix

  Supports all providers available in ReqLLM (57+), including:
  - OpenAI (GPT models)
  - Anthropic (Claude models)
  - Google (Gemini models)
  - Mistral, Cohere, Groq, and many more

  See ReqLLM documentation for full provider list.
  """
  use Jido.Action,
    name: "reqllm_chat_completion",
    description: "Chat completion action using ReqLLM",
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
        doc: "Forces model to output valid JSON (provider-dependent)"
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
  alias ReqLLM.Response, as: ReqResponse

  @impl true
  def on_before_validate_params(params) do
    with {:ok, model} <- validate_model(params.model),
         {:ok, prompt} <- Prompt.validate_prompt_opts(params.prompt) do
      {:ok, %{params | model: model, prompt: prompt}}
    else
      {:error, reason} ->
        Logger.error("ChatCompletion validation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def run(params, _context) do
    # Validate required parameters exist
    with :ok <- validate_required_param(params, :model, "model"),
         :ok <- validate_required_param(params, :prompt, "prompt") do
      run_with_validated_params(params)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_with_validated_params(params) do
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
        "Running ReqLLM chat completion with params: #{inspect(params_with_defaults, pretty: true)}"
      )
    end

    with {:ok, model} <- validate_model(params_with_defaults.model),
         {:ok, messages} <- convert_messages(params_with_defaults.prompt),
         {:ok, req_options} <- build_req_llm_options(model, params_with_defaults),
         result <- call_reqllm(model, messages, req_options, params_with_defaults) do
      result
    else
      {:error, reason} ->
        Logger.error("Chat completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private functions

  defp validate_required_param(params, key, name) do
    if Map.has_key?(params, key) do
      :ok
    else
      {:error, "Missing required parameter: #{name}"}
    end
  end

  defp validate_model(%ReqLLM.Model{} = model), do: {:ok, model}
  defp validate_model(%Model{} = model), do: Model.from(model)
  defp validate_model(spec) when is_tuple(spec), do: Model.from(spec)

  defp validate_model(other) do
    Logger.error("Invalid model specification: #{inspect(other)}")
    {:error, "Invalid model specification: #{inspect(other)}"}
  end

  defp convert_messages(prompt) do
    messages =
      Prompt.render(prompt)
      |> Enum.map(fn msg ->
        %{role: msg.role, content: msg.content}
      end)

    {:ok, messages}
  end

  defp build_req_llm_options(_model, params) do
    # Build base options
    base_opts =
      []
      |> add_opt_if_present(:temperature, params.temperature)
      |> add_opt_if_present(:max_tokens, params.max_tokens)
      |> add_opt_if_present(:top_p, params.top_p)
      |> add_opt_if_present(:stop, params.stop)
      |> add_opt_if_present(:frequency_penalty, params.frequency_penalty)
      |> add_opt_if_present(:presence_penalty, params.presence_penalty)

    # Add tools if provided
    opts_with_tools =
      case params[:tools] do
        tools when is_list(tools) and length(tools) > 0 ->
          # Convert tools directly to ReqLLM format
          tool_specs =
            Enum.map(tools, fn tool ->
              %{
                name: tool.name,
                description: Map.get(tool, :description, ""),
                parameters: Map.get(tool, :parameters, %{})
              }
            end)

          Keyword.put(base_opts, :tools, tool_specs)

        _ ->
          base_opts
      end

    # ReqLLM handles authentication internally via environment variables
    {:ok, opts_with_tools}
  end

  defp add_opt_if_present(opts, _key, nil), do: opts
  defp add_opt_if_present(opts, key, value), do: Keyword.put(opts, key, value)

  defp call_reqllm(model, messages, req_options, params) do
    # Build model spec string from ReqLLM.Model
    model_spec = "#{model.provider}:#{model.model}"

    if params.stream do
      call_streaming(model_spec, messages, req_options)
    else
      call_standard(model_spec, messages, req_options)
    end
  end

  defp call_standard(model_id, messages, req_options) do
    case ReqLLM.generate_text(model_id, messages, req_options) do
      {:ok, response} ->
        # Use ReqLLM response directly
        format_response(response)

      {:error, error} ->
        {:error, error}
    end
  end

  defp call_streaming(model_id, messages, req_options) do
    opts_with_stream = Keyword.put(req_options, :stream, true)

    case ReqLLM.stream_text(model_id, messages, opts_with_stream) do
      {:ok, stream} ->
        # Return the stream wrapped in :ok tuple
        {:ok, stream}

      {:error, error} ->
        {:error, error}
    end
  end

  # Suppress dialyzer warning: the map fallback clause is kept for 
  # test compatability
  @dialyzer {:nowarn_function, format_response: 1}
  defp format_response(%ReqResponse{} = response) do
    content = ReqResponse.text(response) || ""
    tool_calls = ReqResponse.tool_calls(response)
    usage = ReqResponse.usage(response)

    formatted_tools = format_tool_calls(tool_calls)

    %{content: content, tool_results: formatted_tools}
    |> maybe_add_usage(usage)
    |> then(&{:ok, &1})
  end

  defp format_response(response) when is_map(response) do
    content = response[:content] || response["content"] || ""
    tool_calls = response[:tool_calls] || response["tool_calls"] || []
    usage = response[:usage] || response["usage"]

    formatted_tools = format_tool_calls(tool_calls)

    %{content: content, tool_results: formatted_tools}
    |> maybe_add_usage(usage)
    |> then(&{:ok, &1})
  end

  defp format_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tool ->
      %{
        name: tool[:name] || tool["name"],
        arguments: tool[:arguments] || tool["arguments"],
        result: nil
      }
    end)
  end

  defp maybe_add_usage(result, nil), do: result
  defp maybe_add_usage(result, usage) when map_size(usage) == 0, do: result
  defp maybe_add_usage(result, usage), do: Map.put(result, :usage, usage)
end
