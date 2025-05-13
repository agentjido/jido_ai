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
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias OpenaiEx.Chat
  alias OpenaiEx.ChatMessage
  alias Jido.AI.Actions.OpenaiEx.ToolHelper

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
    {:error, %{reason: "Invalid model specification", details: "Must be a map or {provider, opts} tuple"}}
  end

  defp validate_provider(%Model{provider: provider} = model) when provider in @valid_providers do
    {:ok, model}
  end

  defp validate_provider(%Model{provider: provider}) do
    {:error, %{reason: "Invalid provider", details: "Got #{inspect(provider)}, expected one of #{inspect(@valid_providers)}"}}
  end

  defp validate_and_get_messages(%{messages: messages}) when is_list(messages) and messages != [] do
    if Enum.all?(messages, &valid_message?/1) do
      {:ok, messages}
    else
      invalid = Enum.filter(messages, &(not valid_message?(&1)))
      {:error, %{reason: "Invalid message format", details: "Messages must have :role and :content, got #{inspect(invalid)}"}}
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

  defp valid_message?(%{role: role, content: content}) when is_atom(role) and is_binary(content), do: true
  defp valid_message?(_), do: false

  defp build_chat_request(model, messages, params) do
    with {:ok, chat_messages} <- build_chat_messages(messages),
         {:ok, base_req} <- build_base_request(model, chat_messages, params),
         {:ok, req_with_tools} <- add_tools(base_req, params),
         {:ok, final_req} <- add_tool_choice(req_with_tools, params) do
      {:ok, final_req}
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

  defp add_tool_choice(req, %{tool_choice: choice}) when is_map(choice), do: {:ok, Map.put(req, :tool_choice, choice)}
  defp add_tool_choice(req, _), do: {:ok, req}

  defp maybe_add_param(req, _key, nil), do: req
  defp maybe_add_param(req, key, value), do: Map.put(req, key, value)

  defp make_request(model, chat_req) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)
      |> maybe_remove_auth_header(model)

    Logger.debug("Making request with client: #{inspect(client)}", module: __MODULE__)
    Logger.debug("Chat request: #{inspect(chat_req)}", module: __MODULE__)

    case model.provider do
      :google ->
        make_google_request(model, chat_req, client)

      _ ->
        Chat.Completions.create(client, chat_req)
    end
  end

  defp make_google_request(model, chat_req, client) do
    google_req = %{
      contents: [
        %{
          parts: [
            %{
              text: hd(chat_req.messages).content
            }
          ]
        }
      ],
      generationConfig: %{
        temperature: chat_req.temperature,
        maxOutputTokens: chat_req.max_tokens
      }
    }

    url = "#{model.base_url}#{model.model}:generateContent"
    Logger.debug("Google URL: #{url}", module: __MODULE__)
    Logger.debug("Google request: #{inspect(google_req)}", module: __MODULE__)

    case Req.post(url, json: google_req, headers: client._http_headers) do
      {:ok, %{status: 200, body: body}} ->
        {:ok, %{choices: [%{message: %{content: extract_google_response(body)}}]}}

      {:ok, %{status: status, body: body}} ->
        {:error, %{reason: "Google API error", details: %{status: status, body: body}}}

      {:error, reason} ->
        {:error, %{reason: "Google request failed", details: reason}}
    end
  end

  defp make_streaming_request(model, chat_req) do
    client =
      OpenaiEx.new(model.api_key)
      |> maybe_add_base_url(model)
      |> maybe_add_headers(model)

    Logger.debug("Making streaming request with client: #{inspect(client)}", module: __MODULE__)
    Logger.debug("Chat request: #{inspect(chat_req)}", module: __MODULE__)

    Chat.Completions.create(client, chat_req)
  end

  defp extract_google_response(%{
         "candidates" => [%{"content" => %{"parts" => [%{"text" => text}]}} | _]
       }) do
    text
  end

  defp extract_google_response(body) do
    Logger.error("Unexpected Google API response: #{inspect(body)}", module: __MODULE__)
    {:error, %{reason: "Unexpected response format", details: inspect(body)}}
  end

  defp maybe_add_base_url(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.OpenRouter.base_url())
  end

  defp maybe_add_base_url(client, %Model{provider: :google}) do
    OpenaiEx.with_base_url(client, Jido.AI.Provider.Google.base_url())
  end

  defp maybe_add_base_url(client, _), do: client

  defp maybe_add_headers(client, %Model{provider: :openrouter}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.OpenRouter.request_headers([]))
  end

  defp maybe_add_headers(client, %Model{provider: :google}) do
    OpenaiEx.with_additional_headers(client, Jido.AI.Provider.Google.request_headers([]))
  end

  defp maybe_add_headers(client, _), do: client

  defp maybe_remove_auth_header(client, %Model{provider: :google}) do
    Map.update!(client, :_http_headers, fn headers ->
      Enum.reject(headers, fn {key, _} -> key == "Authorization" end)
    end)
  end

  defp maybe_remove_auth_header(client, _), do: client
end
