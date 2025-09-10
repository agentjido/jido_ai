defmodule ReqLLM.Providers.Anthropic do
  @moduledoc """
  Anthropic provider implementation using the Provider behavior.

  Supports Anthropic's Messages API with features including:
  - Text generation with Claude models
  - Streaming responses
  - Tool calling
  - Multi-modal inputs (text and images)
  - Thinking/reasoning tokens

  ## Configuration

  Set your Anthropic API key via environment variable:

      export ANTHROPIC_API_KEY="your-api-key-here"

  ## Examples

      # Simple text generation
      model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
      {:ok, response} = ReqLLM.generate_text(model, "Hello!")

      # Streaming
      {:ok, stream} = ReqLLM.stream_text(model, "Tell me a story", stream: true)

      # Tool calling
      tools = [%ReqLLM.Tool{name: "get_weather", ...}]
      {:ok, response} = ReqLLM.generate_text(model, "What's the weather?", tools: tools)

  """

  @behaviour ReqLLM.Provider

  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com/v1",
    metadata: "priv/models_dev/anthropic.json"

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
    kagi_key = get_env_var_name() |> String.downcase() |> String.to_atom()

    api_key = Kagi.get(kagi_key)

    unless api_key && api_key != "" do
      raise ArgumentError,
            "Anthropic API key required. Set via Kagi.put(#{inspect(kagi_key)}, key)"
    end

    # Extract context from opts or build from legacy format
    context = extract_or_build_context(request.body, opts)

    # Protocol handles message translation
    body =
      context
      |> ReqLLM.Codec.Helpers.wrap(model)
      |> ReqLLM.Codec.encode()
      |> add_model_params(model, opts)
      |> add_sampling_params(opts)

    base_url = opts[:base_url] || default_base_url()
    stream = opts[:stream] || false

    request
    |> Req.Request.put_header("x-api-key", api_key)
    |> Req.Request.put_header("content-type", "application/json")
    |> Req.Request.put_header("anthropic-version", "2023-06-01")
    |> Req.Request.merge_options(base_url: base_url)
    |> Map.put(:body, Jason.encode!(body))
    |> Map.put(:url, URI.parse("/messages"))
    |> maybe_install_stream_steps(stream)
  end

  @impl ReqLLM.Provider
  def parse_response(response, %ReqLLM.Model{} = _model) do
    case response do
      %Req.Response{status: 200, body: body} ->
        chunks =
          body
          |> then(&%__MODULE__{context: &1})
          |> ReqLLM.Codec.decode()

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
    with {:ok, metadata} <- ReqLLM.Provider.Registry.get_provider_metadata(:anthropic),
         [env_var | _] <-
           get_in(metadata, ["provider", "env"]) || get_in(metadata, [:provider, :env]) do
      env_var
    else
      _ -> "ANTHROPIC_API_KEY"
    end
  end

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
    |> Map.put(:max_tokens, opts[:max_tokens] || model.max_tokens || 4096)
    |> maybe_add_temperature(opts[:temperature] || model.temperature)
    |> maybe_add_tools(tools)
  end

  defp add_sampling_params(body, opts) do
    body
    |> Map.put(:stream, opts[:stream] || false)
  end

  defp extract_tools_from_opts(opts) do
    opts[:tools] || []
  end

  defp maybe_add_temperature(body, nil), do: body
  defp maybe_add_temperature(body, temperature), do: Map.put(body, :temperature, temperature)

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    formatted_tools =
      Enum.map(tools, fn
        %ReqLLM.Tool{} = tool -> ReqLLM.Tool.to_schema(tool, :anthropic)
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
          case Jason.decode(String.trim(data)) do
            {:ok, json} -> Map.put(acc, :data, json)
            {:error, _} -> Map.put(acc, :data, String.trim(data))
          end

        ["event", event] ->
          Map.put(acc, :event, String.trim(event))

        _ ->
          acc
      end
    end)
    |> convert_to_stream_chunk()
  end

  defp convert_to_stream_chunk(%{data: data} = _event) do
    case data do
      %{"type" => "content_block_delta", "delta" => %{"text" => text}} ->
        ReqLLM.StreamChunk.text(text)

      %{"type" => "content_block_delta", "delta" => %{"partial_json" => json}} ->
        ReqLLM.StreamChunk.text(json)

      %{
        "type" => "content_block_start",
        "content_block" => %{"type" => "tool_use", "name" => name}
      } ->
        ReqLLM.StreamChunk.tool_call(name, %{})

      %{"type" => "content_block_delta", "delta" => %{"type" => "tool_use"}} ->
        nil

      %{"type" => "message_delta", "delta" => %{"stop_reason" => reason}} ->
        ReqLLM.StreamChunk.meta(%{finish_reason: reason})

      %{"type" => "message_stop"} ->
        ReqLLM.StreamChunk.meta(%{finish_reason: "stop"})

      # Handle thinking blocks if present in future Claude models
      %{"type" => "thinking_block_delta", "delta" => %{"text" => text}} ->
        ReqLLM.StreamChunk.thinking(text)

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
