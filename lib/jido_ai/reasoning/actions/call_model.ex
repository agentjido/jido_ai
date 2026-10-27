defmodule Jido.AI.Reasoning.Actions.CallModel do
  @moduledoc "Calls one model and returns success or failure as graph data."

  alias Jido.AI.{Telemetry, Toolset, Usage}

  use Jido.Action,
    id: "jido.ai/reasoning/actions/call-model",
    vsn: 1,
    name: "jido_ai_call_model",
    description: "Call or stream one text model",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, _context) when turn.model_calls >= turn.max_model_calls do
    {:ok,
     %{
       turn: turn,
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

  def run(%{turn: turn, messages: messages} = params, context) do
    model = Enum.at(turn.models, turn.model_index)
    started_at = System.system_time(:millisecond)
    stream_id = "stream_#{Jido.generate_id()}"

    result =
      with {:ok, tools} <- model_tools(turn, Map.get(params, :tools, true)) do
        options =
          turn.options
          |> apply_prompt_cache_options(model, turn)
          |> put_conversation_telemetry(turn)
          |> Map.to_list()
          |> put_tools(tools)

        model_call = fn ->
          if turn.stream do
            stream(model, messages, options, turn, stream_id, context)
          else
            generate(model, messages, options)
          end
        end

        case Map.get(params, :reasoning) do
          reasoning when is_map(reasoning) ->
            Telemetry.with_reasoning(context, reasoning, model_call)

          _other ->
            Telemetry.with_agent_span(context, model_call)
        end
      end

    completed_at = System.system_time(:millisecond)
    normalize(result, turn, model, started_at, completed_at)
  end

  defp generate(model, messages, options) do
    context = ReqLLM.Context.new(Enum.map(messages, &to_req_llm_message/1))
    ReqLLM.generate_text(model, context, options)
  end

  defp model_tools(turn, true), do: Toolset.definitions(turn.tools)
  defp model_tools(_turn, false), do: {:ok, nil}

  defp put_tools(options, nil), do: options
  defp put_tools(options, tools), do: Keyword.put(options, :tools, tools)

  defp stream(model, messages, options, turn, stream_id, context) do
    request = correlation(turn, stream_id, 0, System.system_time(:millisecond))
    _result = dispatch_stream_signal(context, "jido.ai.model.stream.started", request)
    req_context = ReqLLM.Context.new(Enum.map(messages, &to_req_llm_message/1))

    case ReqLLM.stream_text(model, req_context, options) do
      {:ok, response} ->
        sequence_counter = :atomics.new(1, [])

        result =
          ReqLLM.StreamResponse.process_stream(response,
            on_chunk: fn chunk ->
              sequence = :atomics.add_get(sequence_counter, 1, 1)
              publish_chunk(chunk, sequence, turn, stream_id, context)
            end
          )

        sequence = :atomics.get(sequence_counter, 1) + 1

        case result do
          {:ok, materialized} = success ->
            classified = ReqLLM.Response.classify(materialized)

            data =
              correlation(turn, stream_id, sequence, System.system_time(:millisecond))
              |> Map.put(:response_id, materialized.id)
              |> Map.put(:outcome, classified.type)
              |> Map.put(:finish_reason, classified.finish_reason)

            _result = dispatch_stream_signal(context, "jido.ai.model.stream.completed", data)
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

  defp publish_chunk(chunk, sequence, turn, stream_id, context) do
    data =
      correlation(turn, stream_id, sequence, System.system_time(:millisecond))
      |> Map.put(:chunk, portable_chunk(chunk))

    _result = dispatch_stream_signal(context, "jido.ai.model.stream.chunk", data)
    :ok
  end

  defp publish_stream_failure(reason, turn, stream_id, sequence, context) do
    data =
      correlation(turn, stream_id, sequence, System.system_time(:millisecond))
      |> Map.put(:reason, error_message(reason))

    _result = dispatch_stream_signal(context, "jido.ai.model.stream.failed", data)
    :ok
  end

  defp dispatch_stream_signal(context, type, data) do
    case Map.get(context, :jido_ai_dispatch) do
      nil ->
        :ok

      dispatch ->
        with {:ok, signal} <- Jido.Agent.build_signal(context, type, data) do
          Jido.Signal.Dispatch.dispatch(signal, dispatch)
        end
    end
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
    session = Jido.Session.decode!(turn.session)

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

  defp normalize({:ok, response}, turn, model, started_at, completed_at) do
    classified = ReqLLM.Response.classify(response)
    call_metadata = ReqLLM.Response.call_metadata(response)
    usage = ReqLLM.Usage.normalize(ReqLLM.Response.usage(response))
    next_turn = record_call(turn, usage)

    {:ok,
     %{
       turn: next_turn,
       outcome: %{
         status: :ok,
         kind: classified.type,
         finish_reason: classified.finish_reason,
         text: classified.text,
         tool_calls: Enum.map(classified.tool_calls, &Map.take(&1, [:id, :name, :arguments])),
         req_llm_request_id: call_metadata[:request_id],
         response_id: response.id,
         model: model,
         usage: usage,
         prompt_cache: Usage.cache_observation(turn.prompt_cache, usage, completed_at),
         started_at_ms: started_at,
         completed_at_ms: completed_at
       }
     }}
  end

  defp normalize({:error, reason}, turn, model, started_at, completed_at) do
    usage = ReqLLM.Usage.normalize(nil)
    next_turn = record_call(turn, usage)

    {:ok,
     %{
       turn: next_turn,
       outcome: %{
         status: :error,
         category: category(reason),
         retryable: retryable?(reason),
         reason: error_message(reason),
         model: model,
         usage: usage,
         prompt_cache: Usage.cache_observation(turn.prompt_cache, usage, completed_at),
         started_at_ms: started_at,
         completed_at_ms: completed_at
       }
     }}
  end

  defp record_call(turn, usage) do
    turn
    |> Map.update!(:model_calls, &(&1 + 1))
    |> Map.update!(:model_attempt, &(&1 + 1))
    |> Map.update!(:usage, &Usage.add(&1, usage))
  end

  defp apply_prompt_cache_options(options, model, turn) do
    config = turn.prompt_cache

    if field(config, :enabled) == true do
      provider = model |> String.split(":", parts: 2) |> hd()
      ttl = field(config, :ttl)

      case provider do
        "openai" ->
          cache_options = if ttl, do: %{ttl: ttl}, else: %{}
          session_id = turn.session |> Jido.Session.decode!() |> Map.fetch!(:id)
          key = field(config, :key) || session_id

          options
          |> update_provider_options(:prompt_cache_key, key)
          |> maybe_put_provider_options(:prompt_cache_options, cache_options)

        "anthropic" ->
          options
          |> update_provider_options(:anthropic_prompt_cache, true)
          |> maybe_put_provider_option(:anthropic_prompt_cache_ttl, ttl)

        provider when provider in ["amazon_bedrock", "bedrock"] ->
          options
          |> update_provider_options(:prompt_cache, true)
          |> maybe_put_provider_option(:prompt_cache_ttl, ttl)

        _provider ->
          options
      end
    else
      options
    end
  end

  defp put_conversation_telemetry(options, turn) do
    thread_id = turn.session |> Jido.Session.decode!() |> then(& &1.thread.id)

    telemetry =
      case field(options, :telemetry) do
        value when is_map(value) -> value
        value when is_list(value) -> Map.new(value)
        _other -> %{}
      end

    Map.put(options, :telemetry, Map.put(telemetry, :conversation_id, thread_id))
  end

  defp update_provider_options(options, key, value) do
    provider_options = options |> field(:provider_options) |> provider_options_map()
    Map.put(options, :provider_options, Map.put(provider_options, key, value))
  end

  defp maybe_put_provider_option(options, _key, nil), do: options
  defp maybe_put_provider_option(options, key, value), do: update_provider_options(options, key, value)
  defp maybe_put_provider_options(options, _key, value) when value == %{}, do: options
  defp maybe_put_provider_options(options, key, value), do: update_provider_options(options, key, value)
  defp provider_options_map(nil), do: %{}
  defp provider_options_map(options) when is_map(options), do: options
  defp provider_options_map(options) when is_list(options), do: Map.new(options)
  defp field(nil, _key), do: nil
  defp field(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
  defp field(_value, _key), do: nil

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
