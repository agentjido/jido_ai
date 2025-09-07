defmodule ReqAI.Providers.OpenAI do
  @moduledoc """
  OpenAI provider adapter implementation using the Chat Completions API.

  ## Usage

      ReqAI.Providers.OpenAI.generate_text("gpt-4", "What is the capital of France?")
      ReqAI.Providers.OpenAI.stream_text("gpt-3.5-turbo", "Tell me a story", stream: true)

  ## Configuration

  Set your OpenAI API key:

      config :req_ai, ReqAI.Providers.OpenAI,
        api_key: "your-api-key"

  Or use environment variable:

      export OPENAI_API_KEY="your-api-key"
  """

  use ReqAI.Provider.DSL,
    id: :openai,
    base_url: "https://api.openai.com",
    auth: {:header, "authorization", :bearer},
    metadata: "openai.json",
    default_temperature: 1,
    default_max_tokens: 4096

  alias ReqAI.Provider.Utils

  def chat_completion_opts do
    [:tools, :tool_choice]
  end

  @impl true
  def build_request(input, provider_opts, request_opts) do
    spec = spec()
    prompt = input
    opts = Keyword.merge(provider_opts, request_opts)

    # Use shared utility for getting default model
    default_model = Utils.default_model(spec) || "gpt-3.5-turbo"
    model = Keyword.get(opts, :model, default_model)
    max_tokens = Keyword.get(opts, :max_tokens, spec.default_max_tokens)
    temperature = Keyword.get(opts, :temperature, spec.default_temperature)
    stream = Keyword.get(opts, :stream?, false)

    url = URI.merge(spec.base_url, "/v1/chat/completions") |> URI.to_string()

    headers = [
      {"content-type", "application/json"}
    ]

    body = %{
      model: model,
      max_tokens: max_tokens,
      messages: Utils.normalize_messages(prompt),
      stream: stream,
      temperature: temperature
    }

    body = maybe_add_tools(body, opts)

    request =
      Req.new(
        method: :post,
        url: url,
        headers: headers,
        json: body
      )

    {:ok, request}
  end

  @impl true
  def parse_response(response, provider_opts, request_opts) do
    opts = Keyword.merge(provider_opts, request_opts)
    stream = Keyword.get(opts, :stream?, false)

    case stream do
      true -> parse_streaming_response(response)
      false -> parse_non_streaming_response(response)
    end
  end

  # Private helper functions

  defp maybe_add_tools(body, opts) do
    case Keyword.get(opts, :tools, []) do
      [] ->
        body

      tools ->
        body
        |> Map.put("tools", encode_tools(tools))
        |> maybe_put_tool_choice(opts)
    end
  end

  defp maybe_put_tool_choice(body, opts) do
    case Keyword.get(opts, :tool_choice) do
      nil -> body
      tool_choice -> Map.put(body, "tool_choice", encode_tool_choice(tool_choice))
    end
  end

  defp encode_tools(tools) do
    Enum.map(tools, fn tool ->
      %{
        "type" => "function",
        "function" => %{
          "name" => tool.name,
          "description" => tool.description,
          "parameters" => tool.parameters_schema
        }
      }
    end)
  end

  defp encode_tool_choice("auto"), do: "auto"
  defp encode_tool_choice("none"), do: "none"

  defp encode_tool_choice(name) when is_binary(name),
    do: %{"type" => "function", "function" => %{"name" => name}}

  defp parse_non_streaming_response(%{status: 200, body: body}) do
    case body do
      %{"choices" => [%{"message" => %{"content" => content}} | _]} when is_binary(content) ->
        {:ok, content}

      %{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]}
      when is_list(tool_calls) ->
        {:ok, %{tool_calls: extract_tool_calls(tool_calls)}}

      %{"error" => %{"message" => message}} ->
        {:error, ReqAI.Error.API.Response.exception(reason: message)}

      _ ->
        {:error, ReqAI.Error.API.Response.exception(reason: "Unexpected response format")}
    end
  end

  defp parse_non_streaming_response(%{status: status, body: body}) do
    error_message =
      case body do
        %{"error" => %{"message" => message}} -> message
        _ -> "HTTP #{status}"
      end

    {:error, ReqAI.Error.API.Response.exception(reason: error_message, status: status)}
  end

  defp parse_streaming_response(response) do
    case response do
      %{status: 200, body: body} when is_binary(body) ->
        parse_sse_chunks(body)

      %{status: status, body: body} ->
        error_message =
          case body do
            %{"error" => %{"message" => message}} -> message
            _ -> "HTTP #{status}"
          end

        {:error, ReqAI.Error.API.Response.exception(reason: error_message, status: status)}
    end
  end

  defp parse_sse_chunks(body) do
    {events, _rest} = ServerSentEvent.parse_all(body)

    if Enum.empty?(events) do
      {:error,
       ReqAI.Error.API.Response.exception(reason: "No events found in streaming response")}
    else
      content_parts =
        events
        |> Enum.filter(&(&1.event == nil or &1.event == "data"))
        |> Enum.map(& &1.data)
        |> Enum.reject(&(&1 in [nil, "", "[DONE]"]))
        |> Enum.map(&Jason.decode/1)
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, data} -> data end)
        |> Enum.flat_map(fn data ->
          case data["choices"] do
            nil -> []
            choices -> choices
          end
        end)
        |> Enum.map(& &1["delta"]["content"])
        |> Enum.filter(&is_binary/1)

      case content_parts do
        [] ->
          {:error,
           ReqAI.Error.API.Response.exception(reason: "No content found in streaming response")}

        parts ->
          {:ok, Enum.join(parts, "")}
      end
    end
  end

  defp extract_tool_calls(tool_calls) when is_list(tool_calls) do
    Enum.map(tool_calls, &normalize_tool_call/1)
  end

  defp extract_tool_calls(_), do: []

  defp normalize_tool_call(%{"id" => id, "function" => func}) do
    %{
      id: id,
      type: "function",
      name: func["name"],
      arguments: Jason.decode!(func["arguments"])
    }
  end
end
