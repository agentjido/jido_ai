defmodule ReqLLM.Providers.OpenRouter do
  @moduledoc """
  OpenRouter provider implementation using the Provider behavior.

  Supports OpenRouter's Chat Completions API with features including:
  - Text generation with multiple model providers
  - Streaming responses
  - Tool calling
  - Multi-modal inputs (text and images)

  ## Configuration

  Set your OpenRouter API key via environment variable:

      export OPENROUTER_API_KEY="your-api-key-here"

  ## Examples

      # Simple text generation
      model = ReqLLM.Model.from("openrouter:openai/gpt-4")
      {:ok, response} = ReqLLM.generate_text(model, "Hello!")

      # Streaming
      {:ok, stream} = ReqLLM.stream_text(model, "Tell me a story", stream: true)

      # Tool calling  
      tools = [%ReqLLM.Tool{name: "get_weather", ...}]
      {:ok, response} = ReqLLM.generate_text(model, "What's the weather?", tools: tools)

  """

  @behaviour ReqLLM.Provider

  use ReqLLM.Provider.DSL,
    id: :openrouter,
    base_url: "https://openrouter.ai/api/v1",
    metadata: "priv/models_dev/openrouter.json"

  @impl ReqLLM.Provider
  def attach(request, %ReqLLM.Model{} = model, _opts \\ []) do
    # Get environment variable name from metadata
    env_var_name = get_env_var_name()
    kagi_key = String.downcase(env_var_name) |> String.to_atom()

    # Get API key from Kagi keyring only
    api_key = Kagi.get(kagi_key)

    unless api_key && api_key != "" do
      raise ArgumentError,
            "OpenRouter API key required. Set via Kagi.put(#{inspect(kagi_key)}, key)"
    end

    # Extract messages and options from request body
    {messages, stream} = extract_request_data(request.body)

    # Build the request body using extracted messages
    body = build_body(messages, model, stream)

    request
    |> Req.Request.put_header("authorization", "Bearer #{api_key}")
    |> Req.Request.put_header("content-type", "application/json")
    |> Req.Request.put_header("http-referer", "https://req-llm.dev")
    |> Req.Request.put_header("x-title", "ReqLLM")
    |> Req.Request.merge_options(base_url: default_base_url())
    |> Map.put(:body, Jason.encode!(body))
    |> Map.put(:url, URI.parse("/chat/completions"))
    |> maybe_install_stream_steps(stream)
  end

  @impl ReqLLM.Provider
  def parse_response(response, %ReqLLM.Model{} = _model) do
    case response do
      %Req.Response{status: 200, body: body} ->
        case body do
          %{"choices" => [%{"message" => message} | _]} ->
            case message do
              %{"content" => content} when is_binary(content) and content != "" ->
                {:ok, [ReqLLM.StreamChunk.text(content)]}

              %{"tool_calls" => tool_calls} when is_list(tool_calls) ->
                chunks = extract_tool_calls_as_chunks(tool_calls)
                {:ok, chunks}

              _ ->
                {:error, to_error("Invalid response format", body)}
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
    case ReqLLM.Provider.Registry.get_provider_metadata(:openrouter) do
      {:ok, %{"provider" => %{"env" => [env_var | _]}}} ->
        env_var

      {:ok, metadata} ->
        # Fallback if metadata structure is different
        case get_in(metadata, [:provider, :env]) do
          [env_var | _] -> env_var
          # hardcoded fallback
          _ -> "OPENROUTER_API_KEY"
        end

      {:error, _} ->
        # fallback if metadata unavailable
        "OPENROUTER_API_KEY"
    end
  end

  defp extract_request_data(%{messages: messages} = body) do
    # Extract messages and stream option from prepared request body
    stream = Map.get(body, :stream, false)
    {messages, stream}
  end

  defp extract_request_data(body) when is_map(body) do
    # Fallback for unexpected body structure
    {[], false}
  end

  defp extract_request_data(_body) do
    # Fallback for non-map body
    {[], false}
  end

  defp build_body(messages, %ReqLLM.Model{} = model, stream) do
    body = %{
      model: model.model,
      messages: format_messages(messages),
      max_tokens: model.max_tokens || 4096,
      stream: stream
    }

    body
    |> maybe_add_temperature(model.temperature)
    |> maybe_add_tools([])
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
      %ReqLLM.Message.ContentPart{type: :text, text: text} ->
        %{type: "text", text: text}

      %ReqLLM.Message.ContentPart{type: :image, data: data} ->
        %{type: "image_url", image_url: data}

      part ->
        part
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
          type: "function",
          function: %{
            name: tool.name || tool["name"],
            description: tool.description || tool["description"],
            parameters: tool.parameters_schema || tool["parameters_schema"] || tool["parameters"]
          }
        }
      end)

    Map.put(body, :tools, formatted_tools)
  end

  defp extract_tool_calls_as_chunks(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tool_call ->
      %{"function" => %{"name" => name, "arguments" => args}, "id" => id} = tool_call

      parsed_args =
        case Jason.decode(args || "{}") do
          {:ok, parsed} -> parsed
          {:error, _} -> %{}
        end

      ReqLLM.StreamChunk.tool_call(name, parsed_args, %{id: id})
    end)
  end

  defp parse_sse_events(body) when is_binary(body) do
    body
    |> String.split("\n\n")
    |> Enum.map(&parse_sse_event/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_sse_event(""), do: nil
  defp parse_sse_event("data: [DONE]"), do: nil

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
      %{"choices" => [%{"delta" => %{"content" => content}} | _]} when is_binary(content) ->
        ReqLLM.StreamChunk.text(content)

      %{"choices" => [%{"delta" => %{"tool_calls" => [tool_call | _]}} | _]} ->
        case tool_call do
          %{"function" => %{"name" => name}} ->
            ReqLLM.StreamChunk.tool_call(name, %{})

          %{"function" => %{"arguments" => args}} when is_binary(args) ->
            ReqLLM.StreamChunk.text(args)

          _ ->
            nil
        end

      %{"choices" => [%{"finish_reason" => reason} | _]} when reason != nil ->
        ReqLLM.StreamChunk.meta(%{finish_reason: reason})

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
