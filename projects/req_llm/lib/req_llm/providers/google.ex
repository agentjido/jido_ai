defmodule ReqLLM.Providers.Google do
  @moduledoc """
  Google provider implementation using the Provider behavior.

  Supports Google's Generative Language API (Gemini models) with features including:
  - Text generation with Gemini models
  - Streaming responses
  - Tool calling
  - Multi-modal inputs (text, images, audio, video)

  ## Configuration

  Set your Google API key via environment variable:

      export GOOGLE_API_KEY="your-api-key-here"

  ## Examples

      # Simple text generation
      model = ReqLLM.Model.from("google:gemini-1.5-flash")
      {:ok, response} = ReqLLM.generate_text(model, "Hello!")

      # Streaming
      {:ok, stream} = ReqLLM.stream_text(model, "Tell me a story", stream: true)

      # Tool calling  
      tools = [%ReqLLM.Tool{name: "get_weather", ...}]
      {:ok, response} = ReqLLM.generate_text(model, "What's the weather?", tools: tools)

  """

  @behaviour ReqLLM.Provider

  use ReqLLM.Provider.DSL,
    id: :google,
    base_url: "https://generativelanguage.googleapis.com/v1",
    metadata: "priv/models_dev/google.json"

  @impl ReqLLM.Provider
  def attach(request, %ReqLLM.Model{} = model, _opts \\ []) do
    # Get environment variable name from metadata
    env_var_name = get_env_var_name()
    kagi_key = String.downcase(env_var_name) |> String.to_atom()

    # Get API key from Kagi keyring only
    api_key = Kagi.get(kagi_key)

    unless api_key && api_key != "" do
      raise ArgumentError,
            "Google API key required. Set via Kagi.put(#{inspect(kagi_key)}, key)"
    end

    # Extract messages and options from request body
    {messages, stream, tools, tool_choice} = extract_request_data(request.body)

    # Build the request body using extracted messages
    body = build_body(messages, model, stream, tools, tool_choice)

    # Google API uses a different path structure: /models/{model}:generateContent
    api_path = "/models/#{model.model}:generateContent"

    request
    |> Req.Request.put_header("content-type", "application/json")
    |> Req.Request.merge_options(base_url: default_base_url())
    |> Map.put(:body, Jason.encode!(body))
    |> Map.put(:url, URI.parse(api_path))
    |> maybe_add_api_key_param(api_key)
    |> maybe_install_stream_steps(stream)
  end

  @impl ReqLLM.Provider
  def parse_response(response, %ReqLLM.Model{} = _model) do
    case response do
      %Req.Response{status: 200, body: body} ->
        case body do
          %{"candidates" => [%{"content" => content} | _]} ->
            # Extract both text content and tool calls from content
            text_chunks = extract_text_chunks(content)
            tool_call_chunks = extract_tool_call_chunks(content)

            all_chunks = text_chunks ++ tool_call_chunks

            case all_chunks do
              [] -> {:error, to_error("Invalid response format", body)}
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
      %Req.Response{status: 200, body: %{"usageMetadata" => usage}} ->
        # Convert Google format to common format
        common_usage = %{
          "input_tokens" => Map.get(usage, "promptTokenCount", 0),
          "output_tokens" => Map.get(usage, "candidatesTokenCount", 0),
          "total_tokens" => Map.get(usage, "totalTokenCount", 0)
        }

        {:ok, common_usage}

      _ ->
        {:ok, %{}}
    end
  end

  # Private helper functions

  defp maybe_install_stream_steps(req, _stream), do: req

  defp get_env_var_name do
    case ReqLLM.Provider.Registry.get_provider_metadata(:google) do
      {:ok, %{"provider" => %{"env" => [env_var | _]}}} ->
        env_var

      {:ok, metadata} ->
        # Fallback if metadata structure is different
        case get_in(metadata, [:provider, :env]) do
          [env_var | _] -> env_var
          # hardcoded fallback
          _ -> "GOOGLE_API_KEY"
        end

      {:error, _} ->
        # fallback if metadata unavailable
        "GOOGLE_API_KEY"
    end
  end

  defp maybe_add_api_key_param(request, api_key) do
    # Google API uses query parameter for API key instead of header
    current_url = Map.get(request, :url, URI.parse(""))
    query_params = URI.decode_query(current_url.query || "")
    new_query_params = Map.put(query_params, "key", api_key)
    new_query = URI.encode_query(new_query_params)
    new_url = Map.put(current_url, :query, new_query)
    Map.put(request, :url, new_url)
  end

  defp extract_request_data(%{messages: messages} = body) do
    # Extract messages, stream option, tools, and tool_choice from prepared request body
    stream = Map.get(body, :stream, false)
    tools = Map.get(body, :tools, [])
    tool_choice = Map.get(body, :tool_choice, "auto")
    {messages, stream, tools, tool_choice}
  end

  defp extract_request_data(body) when is_map(body) do
    # Fallback for unexpected body structure
    {[], false, [], "auto"}
  end

  defp extract_request_data(_body) do
    # Fallback for non-map body
    {[], false, [], "auto"}
  end

  defp build_body(messages, %ReqLLM.Model{} = model, stream, tools, _tool_choice) do
    body = %{
      contents: format_messages(messages),
      generationConfig: build_generation_config(model)
    }

    body
    |> maybe_add_tools(tools)
    |> maybe_add_stream(stream)
  end

  defp build_generation_config(%ReqLLM.Model{} = model) do
    config = %{}

    config
    |> maybe_add_temperature(model.temperature)
    |> maybe_add_max_tokens(model.max_tokens)
  end

  defp format_messages(messages) when is_list(messages) do
    Enum.map(messages, fn
      %ReqLLM.Message{role: role, content: content} ->
        %{role: format_role(role), parts: format_content(content)}

      %{role: role, content: content} ->
        %{role: format_role(role), parts: format_content(content)}

      message when is_binary(message) ->
        %{role: "user", parts: [%{text: message}]}
    end)
  end

  defp format_messages(message) when is_binary(message) do
    [%{role: "user", parts: [%{text: message}]}]
  end

  defp format_role(:user), do: "user"
  defp format_role(:assistant), do: "model"
  # Google doesn't have system role, use user
  defp format_role(:system), do: "user"
  defp format_role(role), do: to_string(role)

  defp format_content(content) when is_binary(content), do: [%{text: content}]

  defp format_content(content) when is_list(content) do
    Enum.map(content, fn
      %ReqLLM.Message.ContentPart{type: :text, text: text} ->
        %{text: text}

      %ReqLLM.Message.ContentPart{type: :image, data: data} ->
        %{inlineData: %{mimeType: "image/jpeg", data: data}}

      part ->
        part
    end)
  end

  defp format_content(content), do: [%{text: to_string(content)}]

  defp maybe_add_temperature(config, nil), do: config
  defp maybe_add_temperature(config, temperature), do: Map.put(config, :temperature, temperature)

  defp maybe_add_max_tokens(config, nil), do: config
  defp maybe_add_max_tokens(config, max_tokens), do: Map.put(config, :maxOutputTokens, max_tokens)

  defp maybe_add_tools(body, []), do: body

  defp maybe_add_tools(body, tools) do
    formatted_tools = %{
      function_declarations:
        Enum.map(tools, fn tool ->
          %{
            name: tool.name || tool["name"],
            description: tool.description || tool["description"],
            parameters:
              tool.parameters_schema || tool["parameters_schema"] || tool["parameters"] || %{}
          }
        end)
    }

    Map.put(body, :tools, [formatted_tools])
  end

  defp maybe_add_stream(body, false), do: body
  defp maybe_add_stream(body, true), do: Map.put(body, :stream, true)

  defp extract_text_chunks(%{"parts" => parts}) do
    parts
    |> Enum.filter(fn part -> Map.has_key?(part, "text") end)
    |> Enum.map(fn %{"text" => text} -> ReqLLM.StreamChunk.text(text) end)
  end

  defp extract_text_chunks(_), do: []

  defp extract_tool_call_chunks(%{"parts" => parts}) do
    parts
    |> Enum.filter(fn part -> Map.has_key?(part, "functionCall") end)
    |> Enum.map(fn %{"functionCall" => function_call} ->
      name = Map.get(function_call, "name", "")
      args = Map.get(function_call, "args", %{})
      ReqLLM.StreamChunk.tool_call(name, args, %{})
    end)
  end

  defp extract_tool_call_chunks(_), do: []

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
      %{"candidates" => [%{"content" => %{"parts" => [%{"text" => text} | _]}} | _]}
      when is_binary(text) ->
        ReqLLM.StreamChunk.text(text)

      %{
        "candidates" => [
          %{"content" => %{"parts" => [%{"functionCall" => function_call} | _]}} | _
        ]
      } ->
        name = Map.get(function_call, "name", "")
        args = Map.get(function_call, "args", %{})
        ReqLLM.StreamChunk.tool_call(name, args, %{})

      %{"candidates" => [%{"finishReason" => reason} | _]} when reason != nil ->
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
