defmodule ReqLLM.Providers.OpenAI do
  @moduledoc """
  OpenAI provider implementation using the Provider behavior.

  Supports OpenAI's Chat Completions API with features including:
  - Text generation with GPT models
  - Streaming responses
  - Tool calling
  - Multi-modal inputs (text and images for vision models)

  ## Configuration

  Set your OpenAI API key via environment variable:

      export OPENAI_API_KEY="your-api-key-here"

  ## Examples

      # Simple text generation
      model = ReqLLM.Model.from("openai:gpt-4o-mini")
      {:ok, response} = ReqLLM.generate_text(model, "Hello!")

      # Streaming
      {:ok, stream} = ReqLLM.stream_text(model, "Tell me a story", stream: true)

      # Tool calling
      tools = [%ReqLLM.Tool{name: "get_weather", ...}]
      {:ok, response} = ReqLLM.generate_text(model, "What's the weather?", tools: tools)

  """

  @behaviour ReqLLM.Provider

  use ReqLLM.Provider.DSL,
    id: :openai,
    base_url: "https://api.openai.com/v1",
    metadata: "priv/models_dev/openai.json"

  defstruct [:context]

  @type t :: %__MODULE__{context: ReqLLM.Context.t()}

  @spec new(ReqLLM.Context.t()) :: t()
  def new(context), do: %__MODULE__{context: context}

  @impl ReqLLM.Provider
  def wrap_context(%ReqLLM.Context{} = ctx) do
    %__MODULE__{context: ctx}
  end

  @impl ReqLLM.Provider
  def attach(request, %ReqLLM.Model{} = model, opts \\ []) do
    jido_key = get_env_var_name() |> String.downcase() |> String.to_atom()

    api_key = JidoKeys.get(jido_key)

    unless api_key && api_key != "" do
      raise ArgumentError,
            "OpenAI API key required. Set via JidoKeys.put(#{inspect(jido_key)}, key)"
    end

    # Extract context from opts or build from legacy format
    context = extract_or_build_context(request.body, opts)

    # Extract other params from request body if present
    body_params = extract_body_params(request.body)

    # Protocol handles message translation
    body =
      context
      |> ReqLLM.Context.wrap(model)
      |> ReqLLM.Context.Codec.encode()
      |> add_model_params(model, Keyword.merge(body_params, opts))
      |> add_sampling_params(Keyword.merge(body_params, opts))

    base_url = opts[:base_url] || default_base_url()
    stream = opts[:stream] || false

    request
    |> Req.Request.put_header("authorization", "Bearer #{api_key}")
    |> Req.Request.put_header("content-type", "application/json")
    |> Req.Request.merge_options(base_url: base_url)
    |> Map.put(:body, Jason.encode!(body))
    |> Map.put(:url, URI.parse("/chat/completions"))
    |> maybe_install_stream_steps(stream)
  end

  @impl ReqLLM.Provider
  def parse_response(response, %ReqLLM.Model{} = _model) do
    case response do
      %Req.Response{status: 200, body: body} ->
        chunks =
          body
          |> then(&%__MODULE__{context: &1})
          |> ReqLLM.Context.Codec.decode()

        case chunks do
          [] -> {:ok, [ReqLLM.StreamChunk.text("")]}
          chunks -> {:ok, chunks}
        end

      %Req.Response{status: status, body: body} ->
        {:error, to_error("API error", body, status)}
    end
  end

  @impl ReqLLM.Provider
  def parse_stream(response, %ReqLLM.Model{} = _model) do
    case response do
      %Req.Response{status: 200, body: body} when is_binary(body) ->
        chunks = parse_sse_events(body)
        {:ok, Stream.filter(chunks, &(!is_nil(&1)))}

      %Req.Response{status: status, body: body} ->
        {:error, to_error("Streaming API error", body, status)}
    end
  end

  @impl ReqLLM.Provider
  def extract_usage(response, %ReqLLM.Model{} = _model) do
    case response do
      %Req.Response{status: 200, body: %{"usage" => usage}} ->
        {:ok, usage}

      _ ->
        {:ok, %{}}
    end
  end

  # Private helper functions

  defp maybe_install_stream_steps(req, _stream), do: req

  defp get_env_var_name do
    with {:ok, metadata} <- ReqLLM.Provider.Registry.get_provider_metadata(:openai),
         [env_var | _] <-
           get_in(metadata, ["provider", "env"]) || get_in(metadata, [:provider, :env]) do
      env_var
    else
      _ -> "OPENAI_API_KEY"
    end
  end

  defp extract_body_params(body) when is_map(body) do
    body
    |> Map.drop([:messages])
    |> Enum.map(fn {k, v} -> {k, v} end)
  end

  defp extract_body_params(_), do: []

  defp extract_or_build_context(body, opts) do
    cond do
      # If context is provided in opts, use it
      opts[:context] && is_struct(opts[:context], ReqLLM.Context) ->
        opts[:context]

      # If body has messages, build context from legacy format
      is_map(body) && Map.has_key?(body, :messages) ->
        build_context_from_legacy(body)

      # Default: empty context with user message from body if it's a string
      is_binary(body) ->
        ReqLLM.Context.new([ReqLLM.Context.user(body)])

      # Fallback: empty context
      true ->
        ReqLLM.Context.new([])
    end
  end

  defp build_context_from_legacy(%{messages: messages}) when is_list(messages) do
    converted_messages =
      Enum.map(messages, fn
        %ReqLLM.Message{} = msg ->
          msg

        %{role: role, content: content} ->
          ReqLLM.Context.text(String.to_atom(role), to_string(content))

        message when is_binary(message) ->
          ReqLLM.Context.user(message)
      end)

    ReqLLM.Context.new(converted_messages)
  end

  defp build_context_from_legacy(_), do: ReqLLM.Context.new([])

  defp add_model_params(body, %ReqLLM.Model{} = model, opts) do
    tools = extract_tools_from_opts(opts)

    body
    |> Map.put(:model, model.model)
    |> maybe_add_max_tokens(opts[:max_tokens] || model.max_tokens)
    |> maybe_add_temperature(opts[:temperature])
    |> maybe_add_tools(tools)
  end

  defp add_sampling_params(body, opts) do
    body
    |> Map.put(:stream, opts[:stream] || false)
  end

  defp extract_tools_from_opts(opts) do
    opts[:tools] || []
  end

  defp maybe_add_max_tokens(body, nil), do: body
  defp maybe_add_max_tokens(body, max_tokens), do: Map.put(body, :max_tokens, max_tokens)

  defp maybe_add_temperature(body, nil), do: body
  defp maybe_add_temperature(body, temperature), do: Map.put(body, :temperature, temperature)

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    formatted_tools =
      Enum.map(tools, fn
        %ReqLLM.Tool{} = tool -> ReqLLM.Tool.to_schema(tool, :openai)
        tool -> tool
      end)

    Map.put(body, :tools, formatted_tools)
  end

  defp parse_sse_events(body) when is_binary(body) do
    body
    |> String.split("\n\n")
    |> Enum.map(&parse_sse_event/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_sse_event(""), do: nil

  defp parse_sse_event(chunk) when is_binary(chunk) do
    lines = String.split(String.trim(chunk), "\n")

    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        ["data", data] ->
          case String.trim(data) do
            "[DONE]" ->
              Map.put(acc, :done, true)

            trimmed ->
              case Jason.decode(trimmed) do
                {:ok, json} -> Map.put(acc, :data, json)
                {:error, _} -> Map.put(acc, :data, trimmed)
              end
          end

        _ ->
          acc
      end
    end)
    |> convert_to_stream_chunk()
  end

  defp convert_to_stream_chunk(%{done: true}), do: nil

  defp convert_to_stream_chunk(%{data: data} = _event) do
    case data do
      %{"choices" => [%{"delta" => %{"content" => content}} | _]} when is_binary(content) ->
        ReqLLM.StreamChunk.text(content)

      %{
        "choices" => [
          %{"delta" => %{"tool_calls" => [%{"function" => %{"name" => name}} | _]}} | _
        ]
      } ->
        ReqLLM.StreamChunk.tool_call(name, %{})

      %{
        "choices" => [
          %{"delta" => %{"tool_calls" => [%{"function" => %{"arguments" => args}} | _]}} | _
        ]
      } ->
        ReqLLM.StreamChunk.text(args)

      %{"choices" => [%{"finish_reason" => reason} | _]} when not is_nil(reason) ->
        ReqLLM.StreamChunk.meta(%{finish_reason: reason})

      _ ->
        nil
    end
  end

  defp convert_to_stream_chunk(_), do: nil

  defp to_error(reason, body, status) do
    error_message =
      case body do
        %{"error" => %{"message" => message}} -> message
        %{"error" => error} when is_binary(error) -> error
        _ -> reason
      end

    case status do
      nil ->
        ReqLLM.Error.API.Response.exception(reason: error_message, response_body: body)

      status ->
        ReqLLM.Error.API.Response.exception(
          reason: error_message,
          status: status,
          response_body: body
        )
    end
  end
end
