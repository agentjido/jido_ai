defmodule Jido.AI.Actions.OpenaiEx do
  @moduledoc """
  Provides chat completion functionality using OpenAI Ex with support for tool calling and multiple providers.
  """
  use Jido.Action,
    name: "openai_ex_chat_completion",
    description: "Chat completion using OpenAI Ex with support for tool calling",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc: "The AI model to use (e.g., {:openai, [model: \"gpt-4\"]} or %Jido.AI.Model{})"
      ],
      messages: [
        type: {:list, {:map, [role: :atom, content: :string]}},
        required: false,
        doc: "List of message maps with :role and :content (required if prompt is not provided)"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: false,
        doc: "The prompt to use for the response (required if messages is not provided)"
      ],
      tools: [
        type: {:list, :atom},
        required: false,
        doc: "List of Jido.Action modules for function calling"
      ],
      tool_choice: [
        type: :map,
        required: false,
        doc: "Tool choice configuration"
      ],
      temperature: [
        type: :float,
        required: false,
        default: 0.7,
        doc: "Temperature for response randomness (0-2)"
      ],
      max_tokens: [
        type: :integer,
        required: false,
        doc: "Maximum tokens in response"
      ],
      top_p: [
        type: :float,
        required: false,
        doc: "Top p sampling parameter (0-1)"
      ],
      frequency_penalty: [
        type: :float,
        required: false,
        doc: "Frequency penalty (-2.0 to 2.0)"
      ],
      presence_penalty: [
        type: :float,
        required: false,
        doc: "Presence penalty (-2.0 to 2.0)"
      ],
      stop: [
        type: {:list, :string},
        required: false,
        doc: "Stop sequences"
      ],
      response_format: [
        type: {:in, [:text, :json]},
        required: false,
        default: :text,
        doc: "Response format (text or json)"
      ],
      seed: [
        type: :integer,
        required: false,
        doc: "Random number seed for deterministic responses"
      ],
      stream: [
        type: :boolean,
        required: false,
        default: false,
        doc: "Whether to stream the response"
      ]
    ]

  require Logger
  alias Jido.AI.Actions.OpenaiEx.ToolHelper
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias Jido.AI.ReqLlmBridge
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias ReqLLM.Provider.Generated.ValidProviders

  @valid_providers [:openai, :openrouter, :google]

  @doc """
  Runs a chat completion request using OpenAI Ex.

  ## Parameters
    - params: Map containing:
      - model: Either a %Jido.AI.Model{} struct or a tuple of {provider, opts}
      - messages: List of message maps with :role and :content (required if prompt is not provided)
      - prompt: A %Jido.AI.Prompt{} struct or string (required if messages is not provided)
      - tools: Optional list of Jido.Action modules for function calling
      - tool_choice: Optional tool choice configuration
      - temperature: Optional float between 0 and 2 (defaults to model's temperature)
      - max_tokens: Optional integer (defaults to model's max_tokens)
      - top_p: Optional float between 0 and 1
      - frequency_penalty: Optional float between -2.0 and 2.0
      - presence_penalty: Optional float between -2.0 and 2.0
      - stop: Optional list of strings
      - response_format: Optional atom (:text or :json)
      - seed: Optional integer for deterministic responses
      - stream: Optional boolean for streaming responses
    - context: The action context containing state and other information

  ## Returns
    - {:ok, %{content: content, tool_results: results}} on success
    - {:error, reason} on failure
    - Stream of chunks if streaming is enabled
  """
  def run(params, context) do
    Logger.info("Running chat completion with params: #{inspect(params)}", module: __MODULE__)
    Logger.info("Context: #{inspect(context)}", module: __MODULE__)

    params = Map.put_new(params, :stream, false)

    with {:ok, model} <- validate_and_get_model(params),
         {:ok, messages} <- validate_and_get_messages(params),
         {:ok, chat_req} <- build_chat_request(model, messages, params) do
      if params.stream do
        make_streaming_request(model, chat_req)
      else
        case make_request(model, chat_req) do
          {:ok, response} ->
            ToolHelper.process_response(response, params[:tools] || [])

          {:error, reason} = error ->
            Logger.error("Request failed: #{inspect(reason)}", module: __MODULE__)
            error
        end
      end
    else
      {:error, reason} = error ->
        Logger.error("Validation failed: #{inspect(reason)}", module: __MODULE__)
        error
    end
  end

  # Private functions

  defp validate_and_get_model(%{model: model}) when is_map(model) do
    case Model.from(model) do
      {:ok, model} -> validate_provider(model)
      {:error, reason} -> {:error, %{reason: "Invalid model", details: reason}}
    end
  end

  defp validate_and_get_model(%{model: {provider, opts}})
       when is_atom(provider) and is_list(opts) do
    case Model.from({provider, opts}) do
      {:ok, model} -> validate_provider(model)
      {:error, reason} -> {:error, %{reason: "Invalid model tuple", details: reason}}
    end
  end

  defp validate_and_get_model(_) do
    {:error,
     %{reason: "Invalid model specification", details: "Must be a map or {provider, opts} tuple"}}
  end

  defp validate_provider(%Model{provider: provider} = model) when provider in @valid_providers do
    {:ok, model}
  end

  defp validate_provider(%Model{provider: provider}) do
    {:error,
     %{
       reason: "Invalid provider",
       details: "Got #{inspect(provider)}, expected one of #{inspect(@valid_providers)}"
     }}
  end

  defp validate_and_get_messages(%{messages: messages})
       when is_list(messages) and messages != [] do
    if Enum.all?(messages, &valid_message?/1) do
      {:ok, messages}
    else
      invalid = Enum.filter(messages, &(not valid_message?(&1)))

      {:error,
       %{
         reason: "Invalid message format",
         details: "Messages must have :role and :content, got #{inspect(invalid)}"
       }}
    end
  end

  defp validate_and_get_messages(%{prompt: prompt}) do
    case Prompt.validate_prompt_opts(prompt) do
      {:ok, prompt} ->
        {:ok, Prompt.render(prompt)}

      {:error, reason} ->
        {:error, %{reason: "Invalid prompt", details: reason}}

      error ->
        # Normalize unexpected error formats from Prompt.validate_prompt_opts/1
        {:error, %{reason: "Unexpected prompt validation error", details: inspect(error)}}
    end
  end

  defp validate_and_get_messages(_) do
    {:error, %{reason: "Missing input", details: "Either messages or prompt must be provided"}}
  end

  defp valid_message?(%{role: role, content: content}) when is_atom(role) and is_binary(content),
    do: true

  defp valid_message?(_), do: false

  defp build_chat_request(model, messages, params) do
    with {:ok, chat_messages} <- build_chat_messages(messages),
         {:ok, base_req} <- build_base_request(model, chat_messages, params),
         {:ok, req_with_tools} <- add_tools(base_req, params) do
      add_tool_choice(req_with_tools, params)
    end
  end

  defp build_chat_messages(messages) do
    chat_messages =
      Enum.map(messages, fn msg ->
        case msg.role do
          :user -> ChatMessage.user(msg.content)
          :assistant -> ChatMessage.assistant(msg.content)
          :system -> ChatMessage.system(msg.content)
          _ -> %{role: msg.role, content: msg.content}
        end
      end)

    {:ok, chat_messages}
  end

  defp build_base_request(model, chat_messages, params) do
    prompt_opts =
      case params[:prompt] do
        %Prompt{options: options} when is_list(options) and options != [] -> Map.new(options)
        _ -> %{}
      end

    params_with_prompt_opts = Map.merge(prompt_opts, params)

    req =
      Chat.Completions.new(
        model: Map.get(model, :model),
        messages: chat_messages,
        temperature: params_with_prompt_opts[:temperature] || Map.get(model, :temperature) || 0.7,
        max_tokens: params_with_prompt_opts[:max_tokens] || Map.get(model, :max_tokens)
      )
      |> maybe_add_param(:top_p, params_with_prompt_opts[:top_p])
      |> maybe_add_param(:frequency_penalty, params_with_prompt_opts[:frequency_penalty])
      |> maybe_add_param(:presence_penalty, params_with_prompt_opts[:presence_penalty])
      |> maybe_add_param(:stop, params_with_prompt_opts[:stop])
      |> maybe_add_param(:response_format, params_with_prompt_opts[:response_format])
      |> maybe_add_param(:seed, params_with_prompt_opts[:seed])
      |> maybe_add_param(:stream, params_with_prompt_opts[:stream])

    {:ok, req}
  end

  defp add_tools(req, %{tools: tools}) when is_list(tools) and tools != [] do
    case ToolHelper.to_openai_tools(tools) do
      {:ok, openai_tools} -> {:ok, Map.put(req, :tools, openai_tools)}
      {:error, reason} -> {:error, %{reason: "Invalid tools", details: reason}}
    end
  end

  defp add_tools(req, _), do: {:ok, req}

  defp add_tool_choice(req, %{tool_choice: choice}) when is_map(choice),
    do: {:ok, Map.put(req, :tool_choice, choice)}

  defp add_tool_choice(req, _), do: {:ok, req}

  defp maybe_add_param(req, _key, nil), do: req
  defp maybe_add_param(req, key, value), do: Map.put(req, key, value)

  defp make_request(model, chat_req) do
    Logger.debug("Making request with ReqLLM", module: __MODULE__)
    Logger.debug("Chat request: #{inspect(chat_req)}", module: __MODULE__)

    # Convert OpenaiEx ChatMessage format to Jido format for ReqLLM
    messages = convert_chat_messages_to_jido_format(chat_req.messages)

    # Build ReqLLM options from chat_req
    opts = build_req_llm_options_from_chat_req(chat_req, model)

    # Use ReqLLM with the model's reqllm_id
    case ReqLLM.generate_text(model.reqllm_id, messages, opts) do
      {:ok, response} ->
        # Convert ReqLLM response through bridge first, then to OpenaiEx format
        converted = ReqLlmBridge.convert_response(response)
        {:ok, convert_to_openai_response_format(converted)}

      {:error, error} ->
        # Map ReqLLM errors to existing error patterns
        ReqLlmBridge.map_error({:error, error})
    end
  end

  defp make_streaming_request(model, chat_req) do
    Logger.debug("Making streaming request with ReqLLM", module: __MODULE__)
    Logger.debug("Chat request: #{inspect(chat_req)}", module: __MODULE__)

    # Convert OpenaiEx ChatMessage format to Jido format for ReqLLM
    messages = convert_chat_messages_to_jido_format(chat_req.messages)

    # Build ReqLLM options from chat_req with streaming enabled
    opts = build_req_llm_options_from_chat_req(chat_req, model) |> Keyword.put(:stream, true)

    # Use ReqLLM streaming with the model's reqllm_id
    case ReqLLM.stream_text(model.reqllm_id, messages, opts) do
      {:ok, stream} ->
        # Convert ReqLLM stream to Jido AI compatible format using bridge functions
        converted_stream = ReqLlmBridge.convert_streaming_response(stream)
        {:ok, converted_stream}

      {:error, error} ->
        # Map ReqLLM streaming errors to existing error patterns
        ReqLlmBridge.map_streaming_error({:error, error})
    end
  end

  # Helper functions for ReqLLM integration

  defp convert_chat_messages_to_jido_format(chat_messages) do
    Enum.map(chat_messages, fn
      %{role: role, content: content} ->
        %{role: role, content: content}

      # Handle OpenaiEx ChatMessage structs
      %module{} = msg when module in [ChatMessage] ->
        %{role: msg.role, content: msg.content}

      # Handle other message formats
      msg when is_map(msg) ->
        %{role: msg[:role] || msg["role"], content: msg[:content] || msg["content"]}
    end)
  end

  defp build_req_llm_options_from_chat_req(chat_req, model) do
    opts = []

    # Set API key via JidoKeys if available
    if model.api_key do
      provider_atom = extract_provider_from_reqllm_id(model.reqllm_id)

      if provider_atom do
        env_var_name = ReqLLM.Keys.env_var_name(provider_atom)
        JidoKeys.put(env_var_name, model.api_key)
      end
    end

    # Add other parameters from chat_req
    opts =
      if Map.get(chat_req, :temperature),
        do: [{:temperature, Map.get(chat_req, :temperature)} | opts],
        else: opts

    opts =
      if Map.get(chat_req, :max_tokens),
        do: [{:max_tokens, Map.get(chat_req, :max_tokens)} | opts],
        else: opts

    opts =
      if Map.get(chat_req, :top_p), do: [{:top_p, Map.get(chat_req, :top_p)} | opts], else: opts

    opts =
      if Map.get(chat_req, :frequency_penalty),
        do: [{:frequency_penalty, Map.get(chat_req, :frequency_penalty)} | opts],
        else: opts

    opts =
      if Map.get(chat_req, :presence_penalty),
        do: [{:presence_penalty, Map.get(chat_req, :presence_penalty)} | opts],
        else: opts

    opts = if Map.get(chat_req, :stop), do: [{:stop, Map.get(chat_req, :stop)} | opts], else: opts

    opts =
      if Map.get(chat_req, :tools),
        do: [{:tools, convert_tools_for_reqllm(Map.get(chat_req, :tools))} | opts],
        else: opts

    opts =
      if Map.get(chat_req, :tool_choice),
        do: [{:tool_choice, Map.get(chat_req, :tool_choice)} | opts],
        else: opts

    opts
  end

  defp extract_provider_from_reqllm_id(reqllm_id) do
    provider_str =
      reqllm_id
      |> String.split(":")
      |> hd()

    # Create a safe string-to-atom mapping from ReqLLM's valid providers
    # This avoids creating arbitrary atoms from user input
    valid_providers =
      ValidProviders.list()
      |> Map.new(fn atom -> {to_string(atom), atom} end)

    Map.get(valid_providers, provider_str)
  end

  defp convert_tools_for_reqllm(tools) when is_list(tools) do
    # Convert OpenAI format tool maps to ReqLLM.Tool structs
    Enum.map(tools, fn tool ->
      case tool do
        %{type: "function", function: func} ->
          # Use ReqLLM.Tool.new/1 to create proper tool structs
          {:ok, reqllm_tool} =
            ReqLLM.Tool.new(
              name: func[:name] || func["name"],
              description: func[:description] || func["description"],
              parameter_schema:
                convert_parameters_to_schema(func[:parameters] || func["parameters"]),
              callback: fn _args -> {:ok, "Tool not executable in test"} end
            )

          reqllm_tool

        # Already a ReqLLM.Tool struct
        %ReqLLM.Tool{} = t ->
          t

        # Fallback for other formats
        _ ->
          tool
      end
    end)
  end

  defp convert_parameters_to_schema(nil), do: []

  defp convert_parameters_to_schema(params) when is_map(params) do
    # Convert OpenAI parameter format to NimbleOptions format
    # OpenAI format: %{type: "object", properties: %{...}, required: [...]}
    # NimbleOptions format: keyword list
    properties = params[:properties] || params["properties"] || %{}
    required = params[:required] || params["required"] || []

    Enum.map(properties, fn {key, prop} ->
      key_atom = if is_binary(key), do: String.to_atom(key), else: key
      type = get_nimble_type(prop[:type] || prop["type"])
      is_required = key in required || to_string(key) in required

      opts = [
        type: type,
        required: is_required,
        doc: prop[:description] || prop["description"] || ""
      ]

      {key_atom, opts}
    end)
  end

  defp get_nimble_type("string"), do: :string
  defp get_nimble_type("integer"), do: :integer
  defp get_nimble_type("number"), do: :float
  defp get_nimble_type("boolean"), do: :boolean
  defp get_nimble_type("array"), do: {:list, :any}
  defp get_nimble_type("object"), do: :map
  defp get_nimble_type(_), do: :any

  defp convert_to_openai_response_format(%{content: content} = response) do
    # Convert ReqLLM response to OpenAI format expected by ToolHelper
    %{
      choices: [
        %{
          message: %{
            content: content,
            role: "assistant",
            tool_calls: Map.get(response, :tool_calls, [])
          },
          finish_reason: Map.get(response, :finish_reason, "stop"),
          index: 0
        }
      ],
      usage: Map.get(response, :usage, %{}),
      model: "unknown"
    }
  end

  defp convert_to_openai_response_format(response) when is_map(response) do
    # Handle other ReqLLM response formats
    content = response[:content] || response["content"] || ""

    %{
      choices: [
        %{
          message: %{
            content: content,
            role: "assistant",
            tool_calls: response[:tool_calls] || response["tool_calls"] || []
          },
          finish_reason: response[:finish_reason] || response["finish_reason"] || "stop",
          index: 0
        }
      ],
      usage: response[:usage] || response["usage"] || %{},
      model: "unknown"
    }
  end
end
