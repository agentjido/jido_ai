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
  alias ReqAI.Response.Parser
  alias ReqAI.Response.Stream

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
    model = case Keyword.get(opts, :model) do
      %ReqAI.Model{model: model_name} -> model_name
      model_name when is_binary(model_name) -> model_name
      _ -> default_model
    end
    
    max_tokens = Keyword.get(opts, :max_tokens, spec.default_max_tokens)
    temperature = Keyword.get(opts, :temperature, spec.default_temperature)
    stream = Keyword.get(opts, :stream?, false)

    # All models use /v1/chat/completions endpoint  
    url = URI.merge(spec.base_url, "/v1/chat/completions") |> URI.to_string()

    headers = Utils.json_headers()

    # Use standard chat completions format with model-specific adjustments
    body = if is_reasoning_model?(model) do
      # o1 models use different parameter names and don't support all parameters
      base_body = %{
        model: model,
        messages: Utils.normalize_messages(prompt),
        stream: stream
        # Note: temperature is not supported for o1 models
      }
      
      # Add max_completion_tokens if max_tokens was specified
      if max_tokens do
        Map.put(base_body, :max_completion_tokens, max_tokens)
      else
        base_body
      end
    else
      # Standard models use standard parameters
      %{
        model: model,
        max_tokens: max_tokens,
        messages: Utils.normalize_messages(prompt),
        stream: stream,
        temperature: temperature
      }
      |> maybe_add_tools(opts)
    end
    |> maybe_add_reasoning(opts)

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

  defp maybe_add_reasoning(body, opts) do
    # Get the model name from body to check if it's a reasoning model
    model_name = Map.get(body, :model, "")
    
    case Keyword.get(opts, :reasoning) do
      nil -> body
      false -> body
      reasoning ->
        if is_reasoning_model?(model_name) do
          # o1 models automatically provide reasoning tokens, don't add reasoning parameter
          body
        else
          case reasoning do
            true -> Map.put(body, "reasoning", %{type: "text"})
            reasoning when is_map(reasoning) -> Map.put(body, "reasoning", reasoning)
            _ -> body
          end
        end
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
      %{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]}
      when is_list(tool_calls) ->
        {:ok, %{tool_calls: extract_tool_calls(tool_calls)}}

      _ ->
        # Use the new parser for text responses (including reasoning)
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
    # Parse SSE body into events, then use Stream parser for reasoning support
    events = parse_sse_body_to_events(body)
    chunks = Stream.parse_events(events)
    {:ok, chunks}
  end

  # Convert SSE body to event maps that Stream.parse_events expects
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
        ["data", value] -> Map.put(acc, :data, String.trim(value))
        ["event", value] -> Map.put(acc, :event, String.trim(value))
        ["id", value] -> Map.put(acc, :id, String.trim(value))
        _ -> acc
      end
    end)
    |> case do
      %{data: _} = event -> event
      _ -> nil
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

  @impl true
  def parse_tool_call(response_body, tool_name) do
    case response_body do
      %{"choices" => [%{"message" => %{"tool_calls" => tool_calls}} | _]}
      when is_list(tool_calls) ->
        tool_calls
        |> Enum.find(fn
          %{"function" => %{"name" => ^tool_name}} -> true
          _ -> false
        end)
        |> case do
          %{"function" => %{"arguments" => arguments}} ->
            case Jason.decode(arguments) do
              {:ok, parsed_args} ->
                {:ok, parsed_args}

              {:error, _} ->
                {:error,
                 ReqAI.Error.API.Response.exception(reason: "Invalid JSON in tool arguments")}
            end

          nil ->
            {:error, ReqAI.Error.API.Response.exception(reason: "Tool call not found")}
        end

      _ ->
        {:error, ReqAI.Error.API.Response.exception(reason: "No tool calls found in response")}
    end
  end

  @impl true
  def stream_tool_init(_tool_name) do
    %{}
  end

  @impl true
  def stream_tool_accumulate(raw_chunk, tool_name, state) do
    case parse_chunk_lines(raw_chunk) do
      {:ok, chunks} ->
        process_chunks(chunks, tool_name, state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helper functions for streaming tool calls

  defp parse_chunk_lines(raw_chunk) do
    Utils.parse_json_chunks(raw_chunk)
  end

  defp process_chunks(chunks, tool_name, state) do
    Enum.reduce(chunks, {state, []}, fn chunk, {current_state, completed} ->
      {new_state, new_completed} = process_single_chunk(chunk, tool_name, current_state)
      {new_state, completed ++ new_completed}
    end)
  end

  defp process_single_chunk(chunk, tool_name, state) do
    case get_in(chunk, ["choices", Access.at(0), "delta", "tool_calls"]) do
      tool_calls when is_list(tool_calls) ->
        process_tool_calls(tool_calls, tool_name, state)

      _ ->
        {state, []}
    end
  end

  defp process_tool_calls(tool_calls, tool_name, state) do
    Enum.reduce(tool_calls, {state, []}, fn tool_call, {current_state, completed} ->
      {new_state, new_completed} = process_tool_call_delta(tool_call, tool_name, current_state)
      {new_state, completed ++ new_completed}
    end)
  end

  defp process_tool_call_delta(tool_call, target_tool_name, state) do
    case tool_call do
      %{"id" => id, "function" => function} when is_map(function) ->
        function_name = Map.get(function, "name")
        arguments_delta = Map.get(function, "arguments", "")

        if function_name == target_tool_name do
          current_args = Map.get(state, id, "")
          new_args = current_args <> arguments_delta
          new_state = Map.put(state, id, new_args)

          case Jason.decode(new_args) do
            {:ok, parsed_args} ->
              final_state = Map.delete(new_state, id)
              {final_state, [parsed_args]}

            {:error, _} ->
              {new_state, []}
          end
        else
          {state, []}
        end

      _ ->
        {state, []}
    end
  end

  # Helper function to detect reasoning models that need /v1/responses endpoint
  defp is_reasoning_model?(model_name) when is_binary(model_name) do
    # OpenAI reasoning models (o1 family) use the /v1/responses endpoint
    model_name in [
      "o1", "o1-mini", "o1-preview", "o1-pro", "o3", "o3-mini", "o3-pro", 
      "o3-deep-research", "o4-mini", "o4-mini-deep-research"
    ] or String.starts_with?(model_name, "o1-") or String.starts_with?(model_name, "o3-") or String.starts_with?(model_name, "o4-")
  end

  defp is_reasoning_model?(_), do: false
end
