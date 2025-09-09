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

  @impl ReqLLM.Provider
  def attach(request, %ReqLLM.Model{} = model, _opts \\ []) do
    kagi_key = get_env_var_name() |> String.downcase() |> String.to_atom()

    api_key = Kagi.get(kagi_key)

    unless api_key && api_key != "" do
      raise ArgumentError,
            "Anthropic API key required. Set via Kagi.put(#{inspect(kagi_key)}, key)"
    end

    # Extract messages and options from request body
    {messages, stream, tools} = extract_request_data(request.body)

    # Build the request body using extracted messages
    body = build_body(messages, model, stream, tools)

    request
    |> Req.Request.put_header("x-api-key", api_key)
    |> Req.Request.put_header("content-type", "application/json")
    |> Req.Request.put_header("anthropic-version", "2023-06-01")
    |> Req.Request.merge_options(base_url: default_base_url())
    |> Map.put(:body, Jason.encode!(body))
    |> Map.put(:url, URI.parse("/messages"))
    |> maybe_install_stream_steps(stream)
  end

  @impl ReqLLM.Provider
  def parse_response(response, %ReqLLM.Model{} = _model) do
    case response do
      %Req.Response{status: 200, body: body} ->
        case body do
          %{"content" => content} ->
            # Extract both text and tool calls from content
            text_chunks =
              case extract_content_text(content) do
                text when text != "" -> [ReqLLM.StreamChunk.text(text)]
                "" -> []
              end

            tool_call_chunks = extract_tool_calls_as_chunks(content)

            all_chunks = text_chunks ++ tool_call_chunks

            case all_chunks do
              [] -> {:ok, [ReqLLM.StreamChunk.text("")]}
              chunks -> {:ok, chunks}
            end

          _ ->
            {:error, to_error("Invalid response format", body)}
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
    case ReqLLM.Provider.Registry.get_provider_metadata(:anthropic) do
      {:ok, %{"provider" => %{"env" => [env_var | _]}}} ->
        env_var

      {:ok, metadata} ->
        # Fallback if metadata structure is different
        case get_in(metadata, [:provider, :env]) do
          [env_var | _] -> env_var
          # hardcoded fallback
          _ -> "ANTHROPIC_API_KEY"
        end

      {:error, _} ->
        # fallback if metadata unavailable
        "ANTHROPIC_API_KEY"
    end
  end

  defp extract_request_data(%{messages: messages} = body) do
    # Extract messages, stream option, and tools from prepared request body
    stream = Map.get(body, :stream, false)
    tools = Map.get(body, :tools, [])
    {messages, stream, tools}
  end

  defp extract_request_data(body) when is_map(body) do
    # Fallback for unexpected body structure
    {[], false, []}
  end

  defp extract_request_data(_body) do
    # Fallback for non-map body
    {[], false, []}
  end

  defp build_body(messages, %ReqLLM.Model{} = model, stream, tools) do
    body = %{
      model: model.model,
      messages: format_messages(messages),
      max_tokens: model.max_tokens || 4096,
      stream: stream
    }

    body
    |> maybe_add_temperature(model.temperature)
    |> maybe_add_tools(tools)
  end

  defp format_messages(messages) when is_list(messages) do
    Enum.map(messages, fn
      %ReqLLM.Message{role: role, content: content} ->
        %{role: to_string(role), content: format_content(content)}

      %{role: role, content: content} ->
        %{role: to_string(role), content: format_content(content)}

      message when is_binary(message) ->
        %{role: "user", content: message}
    end)
  end

  defp format_messages(message) when is_binary(message) do
    [%{role: "user", content: message}]
  end

  defp format_content(content) when is_binary(content), do: content

  defp format_content(content) when is_list(content) do
    Enum.map(content, fn
      %ReqLLM.Message.ContentPart{type: :text, text: text} -> %{type: "text", text: text}
      %ReqLLM.Message.ContentPart{type: :image, data: data} -> %{type: "image", source: data}
      part -> part
    end)
  end

  defp format_content(content), do: to_string(content)

  defp maybe_add_temperature(body, nil), do: body
  defp maybe_add_temperature(body, temperature), do: Map.put(body, :temperature, temperature)

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    formatted_tools =
      Enum.map(tools, fn tool ->
        %{
          name: tool.name || tool["name"],
          description: tool.description || tool["description"],
          input_schema:
            tool.parameters_schema || tool["parameters_schema"] || tool["input_schema"]
        }
      end)

    Map.put(body, :tools, formatted_tools)
  end

  defp extract_content_text(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "text"))
    |> Enum.map(& &1["text"])
    |> Enum.join("")
  end

  defp extract_tool_calls_as_chunks(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(fn tool_call ->
      ReqLLM.StreamChunk.tool_call(
        tool_call["name"],
        tool_call["input"],
        %{id: tool_call["id"]}
      )
    end)
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

  defp to_error(reason, body, status \\ nil) do
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
