defmodule Jido.AI.Actions.OpenaiEx do
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
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias Jido.AI.Actions.OpenaiEx.ToolHelper

  @valid_providers [:openai, :openrouter]

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
    Logger.info("Running OpenAI Ex chat completion with params: #{inspect(params)}")
    Logger.info("Context: #{inspect(context)}")

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

          error ->
            error
        end
      end
    end
  end

  # Private functions

  defp validate_and_get_model(%{model: model}) when is_map(model) do
    case Model.from(model) do
      {:ok, model} -> validate_provider(model)
      error -> error
    end
  end

  defp validate_and_get_model(%{model: {provider, opts}})
       when is_atom(provider) and is_list(opts) do
    case Model.from({provider, opts}) do
      {:ok, model} -> validate_provider(model)
      error -> error
    end
  end

  defp validate_and_get_model(_) do
    {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."}
  end

  defp validate_provider(%Model{provider: provider} = model) when provider in @valid_providers do
    {:ok, model}
  end

  defp validate_provider(%Model{provider: provider}) do
    {:error,
     "Invalid provider: #{inspect(provider)}. Must be one of: #{inspect(@valid_providers)}"}
  end

  defp validate_and_get_messages(%{messages: messages}) when is_list(messages) do
    if Enum.all?(messages, &valid_message?/1) do
      {:ok, messages}
    else
      {:error, "Invalid message format. Each message must have :role and :content fields."}
    end
  end

  defp validate_and_get_messages(%{prompt: prompt}) do
    case Prompt.validate_prompt_opts(prompt) do
      {:ok, prompt} -> {:ok, Prompt.render(prompt)}
      error -> error
    end
  end

  defp validate_and_get_messages(_) do
    {:error, "Either messages or prompt must be provided."}
  end

  defp valid_message?(%{role: role, content: content}) when is_atom(role) and is_binary(content),
    do: true

  defp valid_message?(_), do: false

  defp build_chat_request(model, messages, params) do
    chat_messages =
      Enum.map(messages, fn msg ->
        case msg.role do
          :user -> ChatMessage.user(msg.content)
          :assistant -> ChatMessage.assistant(msg.content)
          :system -> ChatMessage.system(msg.content)
          _ -> %{role: msg.role, content: msg.content}
        end
      end)

    # Build base request with model and messages
    chat_req =
      Chat.Completions.new(
        model: Map.get(model, :model),
        messages: chat_messages,
        temperature: params[:temperature] || Map.get(model, :temperature) || 0.7,
        max_tokens: params[:max_tokens] || Map.get(model, :max_tokens)
      )

    # Add optional parameters if provided
    chat_req =
      chat_req
      |> maybe_add_param(:top_p, params[:top_p])
      |> maybe_add_param(:frequency_penalty, params[:frequency_penalty])
      |> maybe_add_param(:presence_penalty, params[:presence_penalty])
      |> maybe_add_param(:stop, params[:stop])
      |> maybe_add_param(:response_format, params[:response_format])
      |> maybe_add_param(:seed, params[:seed])
      |> maybe_add_param(:stream, params[:stream])

    # Add tool calling configuration if provided
    chat_req =
      case params do
        %{tools: tools} when is_list(tools) ->
          case ToolHelper.to_openai_tools(tools) do
            {:ok, openai_tools} -> Map.put(chat_req, :tools, openai_tools)
            error -> error
          end

        _ ->
          chat_req
      end

    chat_req =
      case params do
        %{tool_choice: choice} when is_map(choice) -> Map.put(chat_req, :tool_choice, choice)
        _ -> chat_req
      end

    {:ok, chat_req}
  end

  defp maybe_add_param(req, _key, nil), do: req
  defp maybe_add_param(req, key, value), do: Map.put(req, key, value)

  defp make_request(model, chat_req) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)

    Chat.Completions.create(client, chat_req)
  end

  defp make_streaming_request(model, chat_req) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)

    Chat.Completions.create(client, chat_req)
  end

  defp maybe_add_base_url(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.OpenRouter.base_url())
  end

  defp maybe_add_base_url(client, _), do: client

  defp maybe_add_headers(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.OpenRouter.request_headers([]))
  end

  defp maybe_add_headers(client, _), do: client
end
