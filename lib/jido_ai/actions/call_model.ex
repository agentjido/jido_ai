defmodule Jido.AI.Actions.CallModel do
  @moduledoc "Calls one model and returns success or failure as graph data."

  alias Jido.AI.{Conversation, PromptCache, Runtime, Usage}

  use Jido.Action,
    name: "jido_ai_call_model",
    description: "Call or stream one text model",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn, prompt_cache: cache}, _context)
      when turn.model_calls >= turn.max_model_calls do
    {:ok,
     %{
       turn: turn,
       prompt_cache: cache,
       outcome: %{
         status: :budget,
         category: :limits,
         retryable: false,
         reason: "maximum model calls reached",
         model: Enum.at(turn.models, turn.model_index),
         usage: ReqLLM.Usage.normalize(nil)
       }
     }}
  end

  def run(%{turn: turn, messages: messages, prompt_cache: cache}, context) do
    model = Enum.at(turn.models, turn.model_index)
    started_at = Runtime.now_ms(context)
    stream_id = "stream_#{Jido.generate_id()}"

    result =
      with {:ok, tools} <- Jido.AI.ToolRegistry.definitions(turn.allowed_tools) do
        options =
          turn.options
          |> PromptCache.apply_options(cache)
          |> Map.to_list()
          |> Keyword.put(:tools, tools)

        if turn.stream do
          stream(model, messages, options, turn, stream_id, context)
        else
          generate(model, messages, options)
        end
      end

    completed_at = Runtime.now_ms(context)
    normalize(result, turn, cache, model, started_at, completed_at)
  end

  defp generate(model, messages, options) do
    context = ReqLLM.Context.new(Enum.map(messages, &to_req_llm_message/1))
    ReqLLM.generate_text(model, context, options)
  end

  defp stream(model, messages, options, turn, stream_id, context) do
    request = correlation(turn, stream_id, 0, Runtime.now_ms(context))
    _result = Runtime.publish(context, "jido.ai.model.stream.started", request)
    req_context = ReqLLM.Context.new(Enum.map(messages, &to_req_llm_message/1))

    case ReqLLM.stream_text(model, req_context, options) do
      {:ok, response} ->
        {:ok, counter} = Agent.start_link(fn -> 0 end)

        result =
          ReqLLM.StreamResponse.process_stream(response,
            on_chunk: fn chunk -> publish_chunk(chunk, counter, turn, stream_id, context) end
          )

        sequence = Agent.get(counter, &(&1 + 1))
        Agent.stop(counter)

        case result do
          {:ok, materialized} = success ->
            classified = ReqLLM.Response.classify(materialized)

            data =
              correlation(turn, stream_id, sequence, Runtime.now_ms(context))
              |> Map.put(:response_id, materialized.id)
              |> Map.put(:outcome, classified.type)
              |> Map.put(:finish_reason, classified.finish_reason)

            _result = Runtime.publish(context, "jido.ai.model.stream.completed", data)
            success

          {:error, reason} = error ->
            publish_stream_failure(reason, turn, stream_id, sequence, context)
            error
        end

      {:error, reason} = error ->
        publish_stream_failure(reason, turn, stream_id, 1, context)
        error
    end
  end

  defp publish_chunk(chunk, counter, turn, stream_id, context) do
    sequence = Agent.get_and_update(counter, fn value -> {value + 1, value + 1} end)

    data =
      correlation(turn, stream_id, sequence, Runtime.now_ms(context))
      |> Map.put(:chunk, portable_chunk(chunk))

    _result = Runtime.publish(context, "jido.ai.model.stream.chunk", data)
    :ok
  end

  defp publish_stream_failure(reason, turn, stream_id, sequence, context) do
    data =
      correlation(turn, stream_id, sequence, Runtime.now_ms(context))
      |> Map.put(:reason, error_message(reason))

    _result = Runtime.publish(context, "jido.ai.model.stream.failed", data)
    :ok
  end

  defp portable_chunk(chunk) do
    %{
      type: chunk.type,
      text: chunk.text,
      name: chunk.name,
      arguments: chunk.arguments,
      metadata: chunk.metadata
    }
  end

  defp correlation(turn, stream_id, sequence, at) do
    session = Conversation.decode!(turn.session)

    %{
      session_id: session.id,
      thread_id: session.thread.id,
      request_id: turn.request_id,
      run_id: turn.run_id,
      model: Enum.at(turn.models, turn.model_index),
      model_call: turn.model_calls + 1,
      model_index: turn.model_index,
      model_attempt: turn.model_attempt + 1,
      tool_rounds: turn.tool_rounds,
      stream_id: stream_id,
      sequence: sequence,
      timestamp_ms: at
    }
  end

  defp normalize({:ok, response}, turn, cache, model, started_at, completed_at) do
    classified = ReqLLM.Response.classify(response)
    usage = ReqLLM.Usage.normalize(ReqLLM.Response.usage(response))
    cache = PromptCache.observe(cache, usage, completed_at)

    next_turn = record_call(turn, usage, cache)

    {:ok,
     %{
       turn: next_turn,
       prompt_cache: cache,
       outcome: %{
         status: :ok,
         kind: classified.type,
         finish_reason: classified.finish_reason,
         text: classified.text,
         tool_calls: Enum.map(classified.tool_calls, &Map.take(&1, [:id, :name, :arguments])),
         response_id: response.id,
         model: model,
         usage: usage,
         started_at_ms: started_at,
         completed_at_ms: completed_at
       }
     }}
  end

  defp normalize({:error, reason}, turn, cache, model, started_at, completed_at) do
    usage = ReqLLM.Usage.normalize(nil)
    cache = PromptCache.observe(cache, usage, completed_at)

    next_turn = record_call(turn, usage, cache)

    {:ok,
     %{
       turn: next_turn,
       prompt_cache: cache,
       outcome: %{
         status: :error,
         category: category(reason),
         retryable: retryable?(reason),
         reason: error_message(reason),
         model: model,
         usage: usage,
         started_at_ms: started_at,
         completed_at_ms: completed_at
       }
     }}
  end

  defp record_call(turn, usage, cache) do
    turn
    |> Map.update!(:model_calls, &(&1 + 1))
    |> Map.update!(:model_attempt, &(&1 + 1))
    |> Map.update!(:usage, &Usage.add(&1, usage))
    |> Map.update!(:prompt_cache_observations, &(&1 ++ [cache]))
  end

  defp to_req_llm_message(%{role: :system, content: content}), do: ReqLLM.Context.system(content)
  defp to_req_llm_message(%{role: :user, content: content}), do: ReqLLM.Context.user(content)

  defp to_req_llm_message(%{role: :assistant, content: content, tool_calls: calls})
       when is_list(calls) and calls != [] do
    tool_calls =
      Enum.map(calls, fn call ->
        ReqLLM.ToolCall.new(call.id, call.name, Jason.encode!(call.arguments))
      end)

    ReqLLM.Context.assistant(content, tool_calls: tool_calls)
  end

  defp to_req_llm_message(%{role: :assistant, content: content}),
    do: ReqLLM.Context.assistant(content)

  defp to_req_llm_message(%{role: :tool} = message) do
    ReqLLM.Context.tool_result_message(message.name, message.tool_call_id, message.output)
  end

  @retryable_statuses [408, 409, 425, 429, 500, 502, 503, 504]
  @retryable_transport_reasons [
    :closed,
    :connect_timeout,
    :econnrefused,
    :enetdown,
    :enetunreach,
    :ehostunreach,
    :nxdomain,
    :timeout
  ]

  defp retryable?(%ReqLLM.Error.API.Timeout{}), do: true
  defp retryable?(%ReqLLM.Error.API.Request{retryable: true}), do: true

  defp retryable?(%ReqLLM.Error.API.Request{status: status})
       when status in @retryable_statuses,
       do: true

  defp retryable?(%ReqLLM.Error.API.Request{cause: cause}) when not is_nil(cause),
    do: retryable?(cause)

  defp retryable?(%ReqLLM.Error.API.Stream{cause: cause}) when not is_nil(cause),
    do: retryable?(cause)

  defp retryable?(%Req.TransportError{reason: reason}), do: retryable?(reason)
  defp retryable?(reason) when reason in @retryable_transport_reasons, do: true

  defp retryable?(reason) do
    text = reason |> inspect() |> String.downcase()

    Enum.any?(
      ["timeout", "overload", "rate_limit", "rate limit", "unavailable", "closed"],
      &String.contains?(text, &1)
    )
  end

  defp category(%ReqLLM.Error.API.Timeout{}), do: :timeout
  defp category(%ReqLLM.Error.API.Request{status: 429}), do: :rate_limit

  defp category(%ReqLLM.Error.API.Request{status: status})
       when status in [500, 502, 503, 504],
       do: :unavailable

  defp category(%ReqLLM.Error.API.Request{}), do: :provider_error
  defp category(%Req.TransportError{reason: reason}), do: category(reason)
  defp category(:timeout), do: :timeout

  defp category(reason) do
    text = reason |> inspect() |> String.downcase()

    cond do
      String.contains?(text, "timeout") -> :timeout
      String.contains?(text, "rate") -> :rate_limit
      String.contains?(text, "overload") -> :overloaded
      String.contains?(text, "unavailable") -> :unavailable
      true -> :provider_error
    end
  end

  defp error_message(%{__exception__: true} = error) do
    Exception.message(error)
  rescue
    _error -> "model request failed"
  end

  defp error_message(reason) when is_binary(reason), do: reason
  defp error_message(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp error_message({kind, detail}) when is_atom(kind) and (is_atom(detail) or is_binary(detail)) do
    "#{kind}: #{detail}"
  end

  defp error_message(_reason), do: "model request failed"
end
