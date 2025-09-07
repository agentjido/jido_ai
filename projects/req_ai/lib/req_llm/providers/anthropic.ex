defmodule ReqLLM.Providers.Anthropic do
  @moduledoc """
  Anthropic provider adapter implementation using the Messages API.

  ## Usage

      ReqLLM.Providers.Anthropic.generate_text("claude-3-haiku-20240307", "What is the capital of France?")
      ReqLLM.Providers.Anthropic.stream_text("claude-3-opus-20240229", "Tell me a story", stream: true)

  ## Configuration

  Set your Anthropic API key:

      config :req_llm, ReqLLM.Providers.Anthropic,
        api_key: "your-api-key"

  Or use environment variable:

      export ANTHROPIC_API_KEY="your-api-key"
  """

  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com",
    auth: {:header, "x-api-key", :plain},
    metadata: "anthropic.json",
    default_temperature: 1,
    default_max_tokens: 4096

  alias ReqLLM.Provider.Utils
  alias ReqLLM.Response.Parser
  alias ReqLLM.Response.Stream

  def chat_completion_opts do
    [:tools, :tool_choice]
  end

  @impl true
  def build_request(input, provider_opts, request_opts) do
    spec = spec()
    prompt = input
    opts = Keyword.merge(provider_opts, request_opts)

    # Use shared utility for getting default model
    default_model = Utils.default_model(spec) || "claude-3-haiku-20240307"
    model = Keyword.get(opts, :model, default_model)
    max_tokens = Keyword.get(opts, :max_tokens, spec.default_max_tokens)
    temperature = Keyword.get(opts, :temperature, spec.default_temperature)
    stream = Keyword.get(opts, :stream?, false)

    url = URI.merge(spec.base_url, "/v1/messages") |> URI.to_string()

    headers = Utils.json_headers([{"anthropic-version", "2023-06-01"}])

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

  defp parse_non_streaming_response(%{status: 200, body: body}) do
    case body do
      %{"content" => content} when is_list(content) ->
        tool_calls = extract_tool_calls_from_content(content)

        if Enum.any?(tool_calls) do
          {:ok, %{tool_calls: tool_calls}}
        else
          # Use the new parser for text responses (including thinking)
          Parser.extract_text(%Req.Response{status: 200, body: body})
        end

      _ ->
        # Use the new parser for text responses (including thinking)
        Parser.extract_text(%Req.Response{status: 200, body: body})
    end
  end

  defp parse_non_streaming_response(%{status: status, body: body}) do
    {:error, Utils.parse_error_response(status, body)}
  end

  defp parse_streaming_response(response) do
    case response do
      %{status: 200, body: body} when is_binary(body) ->
        parse_sse_chunks(body)

      %{status: status, body: body} ->
        {:error, Utils.parse_error_response(status, body)}
    end
  end

  defp parse_sse_chunks(body) do
    # Parse SSE body into events, then use Stream parser for thinking support
    events = parse_sse_body_to_events(body)
    chunks = Stream.parse_events(events)
    {:ok, chunks}
  end

  # Convert Anthropic SSE body to event maps that Stream.parse_events expects
  defp parse_sse_body_to_events(body) when is_binary(body) do
    body
    |> String.split("\n\n")
    |> Enum.map(&parse_sse_chunk_to_event/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_sse_chunk_to_event(""), do: nil

  defp parse_sse_chunk_to_event(chunk) when is_binary(chunk) do
    chunk
    |> String.trim()
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        ["data", value] ->
          # Try to parse JSON for Anthropic format
          case Jason.decode(String.trim(value)) do
            {:ok, json_data} -> Map.put(acc, :data, json_data)
            {:error, _} -> Map.put(acc, :data, String.trim(value))
          end

        ["event", value] ->
          Map.put(acc, :event, String.trim(value))

        ["id", value] ->
          Map.put(acc, :id, String.trim(value))

        _ ->
          acc
      end
    end)
    |> case do
      %{data: _} = event -> event
      _ -> nil
    end
  end

  # Tool support functions

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
        "name" => tool.name,
        "description" => tool.description,
        "input_schema" => tool.parameters_schema
      }
    end)
  end

  defp encode_tool_choice("auto"), do: %{"type" => "auto"}
  defp encode_tool_choice("any"), do: %{"type" => "any"}
  defp encode_tool_choice("none"), do: %{"type" => "none"}
  defp encode_tool_choice(name) when is_binary(name), do: %{"type" => "tool", "name" => name}

  defp extract_tool_calls_from_content(content) when is_list(content) do
    content
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.map(&normalize_anthropic_tool_call/1)
  end

  defp normalize_anthropic_tool_call(%{"id" => id, "name" => name, "input" => input}) do
    %{
      id: id,
      type: "function",
      name: name,
      arguments: input
    }
  end

  @impl true
  def parse_tool_call(response_body, tool_name) do
    case response_body do
      %{"content" => content} when is_list(content) ->
        content
        |> Enum.find(fn
          %{"type" => "tool_use", "name" => ^tool_name} -> true
          _ -> false
        end)
        |> case do
          %{"input" => input} ->
            {:ok, input}

          nil ->
            {:error, ReqLLM.Error.API.Response.exception(reason: "Tool call not found")}
        end

      _ ->
        {:error,
         ReqLLM.Error.API.Response.exception(reason: "No tool use blocks found in response")}
    end
  end

  @impl true
  def stream_tool_init(_tool_name) do
    %{}
  end

  @impl true
  def stream_tool_accumulate(raw_chunk, tool_name, state) do
    case Jason.decode(raw_chunk) do
      {:ok, %{"delta" => %{"content" => content}}} when is_list(content) ->
        process_content_blocks(content, tool_name, state)

      {:ok, %{"content" => content}} when is_list(content) ->
        process_content_blocks(content, tool_name, state)

      {:ok, _} ->
        {state, []}

      {:error, _} ->
        {state, []}
    end
  end

  # Private helper to process content blocks for tool calls
  defp process_content_blocks(content_blocks, tool_name, state) when is_list(content_blocks) do
    content_blocks
    |> Enum.filter(&(&1["type"] == "tool_use"))
    |> Enum.filter(&(&1["name"] == tool_name))
    |> case do
      [] ->
        {state, []}

      matching_tools ->
        completed_tools =
          matching_tools
          |> Enum.map(& &1["input"])
          |> Enum.filter(&is_map/1)

        {state, completed_tools}
    end
  end

  defp process_content_blocks(_, _, state), do: {state, []}
end
