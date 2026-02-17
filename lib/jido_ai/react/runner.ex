defmodule Jido.AI.ReAct.Runner do
  @moduledoc """
  Task-based ReAct runner.

  Produces a lazy event stream via `Stream.resource/3` and does not persist runtime
  state outside of caller-owned checkpoint tokens.
  """

  alias Jido.AI.ReAct.{Config, Event, PendingToolCall, State, Token}
  alias Jido.AI.{Thread, Turn}

  require Logger

  @receive_timeout 30_000

  @type stream_opt ::
          {:request_id, String.t()}
          | {:run_id, String.t()}
          | {:state, State.t()}
          | {:task_supervisor, pid() | atom()}
          | {:context, map()}

  @spec stream(String.t(), Config.t(), [stream_opt()]) :: Enumerable.t()
  def stream(query, %Config{} = config, opts \\ []) when is_binary(query) do
    initial_state =
      case Keyword.get(opts, :state) do
        %State{} = state -> state
        _ -> State.new(query, config.system_prompt, request_id_opts(opts))
      end

    build_stream(initial_state, config, Keyword.put(opts, :query, query), emit_start?: true)
  end

  @spec stream_from_state(State.t(), Config.t(), [stream_opt()]) :: Enumerable.t()
  def stream_from_state(%State{} = state, %Config{} = config, opts \\ []) do
    query = Keyword.get(opts, :query)

    state =
      if is_binary(query) and query != "" do
        append_query(state, query)
      else
        state
      end

    build_stream(state, config, opts, emit_start?: false)
  end

  defp build_stream(%State{} = initial_state, %Config{} = config, opts, stream_opts) do
    owner = self()
    ref = make_ref()

    case start_task(fn -> coordinator(owner, ref, initial_state, config, opts, stream_opts) end, opts) do
      {:ok, pid} ->
        monitor_ref = Process.monitor(pid)

        Stream.resource(
          fn -> %{done?: false, down?: false, pid: pid, monitor_ref: monitor_ref, ref: ref} end,
          &next_event(owner, &1),
          &cleanup(owner, &1)
        )

      {:error, reason} ->
        Stream.map([reason], fn error ->
          raise "Failed to start ReAct runner task: #{inspect(error)}"
        end)
    end
  end

  defp coordinator(owner, ref, state, config, opts, stream_opts) do
    context = Keyword.get(opts, :context, %{})

    state =
      if stream_opts[:emit_start?] do
        {state, _} =
          emit_event(state, owner, ref, :request_started, %{
            query: latest_query(state),
            config_fingerprint: Config.fingerprint(config)
          })

        state
      else
        state
      end

    try do
      state
      |> run_loop(owner, ref, config, context)
      |> finalize(owner, ref, config)
    catch
      {:cancelled, %State{} = current_state, reason} ->
        cancelled_state =
          current_state
          |> State.put_status(:cancelled)
          |> State.put_result("Request cancelled (reason: #{inspect(reason)})")

        {cancelled_state, _} =
          emit_event(cancelled_state, owner, ref, :request_cancelled, %{reason: reason})

        {_cancelled_state, _token} = emit_checkpoint(cancelled_state, owner, ref, config, :terminal)
        send(owner, {:react_runner, ref, :done})

      kind, reason ->
        failed_state =
          state
          |> State.put_status(:failed)
          |> State.put_error(%{kind: kind, reason: inspect(reason)})

        {failed_state, _} =
          emit_event(failed_state, owner, ref, :request_failed, %{
            error: %{kind: kind, reason: inspect(reason)},
            error_type: :runtime
          })

        {_failed_state, _token} = emit_checkpoint(failed_state, owner, ref, config, :terminal)
        send(owner, {:react_runner, ref, :done})
    end
  end

  defp run_loop(%State{} = state, owner, ref, %Config{} = config, context) do
    check_cancel!(state, ref)

    cond do
      state.status in [:completed, :failed, :cancelled] ->
        state

      state.status == :awaiting_tools and state.pending_tool_calls != [] ->
        state
        |> run_pending_tool_round(owner, ref, config, context)
        |> run_loop(owner, ref, config, context)

      state.iteration > config.max_iterations ->
        state
        |> State.put_status(:completed)
        |> State.put_result("Maximum iterations reached without a final answer.")
        |> then(fn completed ->
          {completed, _} =
            emit_event(completed, owner, ref, :request_completed, %{
              result: completed.result,
              termination_reason: :max_iterations,
              usage: completed.usage
            })

          completed
        end)

      true ->
        case run_llm_step(state, owner, ref, config) do
          {:final_answer, state} ->
            state

          {:tool_calls, state, tool_calls} ->
            state
            |> run_tool_round(owner, ref, config, context, tool_calls)
            |> run_loop(owner, ref, config, context)

          {:error, state, reason, error_type} ->
            state
            |> State.put_status(:failed)
            |> State.put_error(reason)
            |> then(fn failed ->
              {failed, _} =
                emit_event(failed, owner, ref, :request_failed, %{
                  error: reason,
                  error_type: error_type
                })

              failed
            end)
        end
    end
  end

  defp run_llm_step(%State{} = state, owner, ref, %Config{} = config) do
    check_cancel!(state, ref)

    call_id = "call_#{state.run_id}_#{state.iteration}_#{Jido.Util.generate_id()}"
    state = State.put_llm_call_id(state, call_id)

    {state, _} =
      emit_event(
        state,
        owner,
        ref,
        :llm_started,
        %{
          call_id: call_id,
          model: config.model,
          message_count: Thread.length(state.thread) + if(state.thread.system_prompt, do: 1, else: 0)
        }, llm_call_id: call_id)

    messages = Thread.to_messages(state.thread)
    llm_opts = Config.llm_opts(config)

    case ReqLLM.Generation.stream_text(config.model, messages, llm_opts) do
      {:ok, stream_response} ->
        case consume_stream(state, owner, ref, config, stream_response) do
          {:ok, state, turn} ->
            state = State.merge_usage(state, turn.usage)

            {state, _} =
              emit_event(
                state,
                owner,
                ref,
                :llm_completed,
                %{
                  call_id: call_id,
                  turn_type: turn.type,
                  text: turn.text,
                  thinking_content: turn.thinking_content,
                  tool_calls: turn.tool_calls,
                  usage: turn.usage
                }, llm_call_id: call_id)

            state =
              Thread.append_assistant(
                state.thread,
                turn.text,
                if(turn.type == :tool_calls, do: turn.tool_calls, else: nil),
                maybe_thinking_opt(turn.thinking_content)
              )
              |> then(&%{state | thread: &1})

            {state, _token} = emit_checkpoint(state, owner, ref, config, :after_llm)

            if Turn.needs_tools?(turn) do
              {:tool_calls, State.put_status(state, :awaiting_tools), turn.tool_calls}
            else
              completed =
                state
                |> State.put_status(:completed)
                |> State.put_result(turn.text)

              {completed, _} =
                emit_event(completed, owner, ref, :request_completed, %{
                  result: turn.text,
                  termination_reason: :final_answer,
                  usage: completed.usage
                })

              {:final_answer, completed}
            end

          {:error, state, reason} ->
            {:error, state, reason, :llm_stream}
        end

      {:error, reason} ->
        {:error, state, reason, :llm_request}
    end
  end

  defp consume_stream(%State{} = state, owner, ref, %Config{} = config, stream_response) do
    check_cancel!(state, ref)

    trace_cfg = config.trace

    acc =
      Enum.reduce_while(stream_response.stream, %{chunks: [], state: state}, fn chunk, %{state: current} = acc ->
        check_cancel!(current, ref)

        current = maybe_emit_chunk_delta(current, owner, ref, chunk, trace_cfg)
        {:cont, %{acc | chunks: [chunk | acc.chunks], state: current}}
      end)

    chunks = Enum.reverse(acc.chunks)
    summary = ReqLLM.Response.Stream.summarize(chunks)

    turn_type =
      if is_list(summary.tool_calls) and summary.tool_calls != [] do
        :tool_calls
      else
        :final_answer
      end

    turn =
      Turn.from_result_map(%{
        type: turn_type,
        text: summary.text,
        thinking_content: normalize_blank(summary.thinking),
        tool_calls: summary.tool_calls,
        usage: ReqLLM.StreamResponse.usage(stream_response) || summary.usage,
        model: config.model
      })

    {:ok, acc.state, turn}
  rescue
    e ->
      {:error, state, %{error: Exception.message(e), type: e.__struct__}}
  end

  defp maybe_emit_chunk_delta(%State{} = state, owner, ref, %ReqLLM.StreamChunk{type: :content, text: text}, trace_cfg)
       when is_binary(text) and text != "" do
    if trace_cfg[:capture_deltas?] do
      {state, _} = emit_event(state, owner, ref, :llm_delta, %{chunk_type: :content, delta: text})
      state
    else
      state
    end
  end

  defp maybe_emit_chunk_delta(%State{} = state, owner, ref, %ReqLLM.StreamChunk{type: :thinking, text: text}, trace_cfg)
       when is_binary(text) and text != "" do
    if trace_cfg[:capture_deltas?] do
      {state, _} = emit_event(state, owner, ref, :llm_delta, %{chunk_type: :thinking, delta: text})
      state
    else
      state
    end
  end

  defp maybe_emit_chunk_delta(%State{} = state, _owner, _ref, _chunk, _trace_cfg), do: state

  defp run_tool_round(%State{} = state, owner, ref, %Config{} = config, context, tool_calls)
       when is_list(tool_calls) do
    pending = Enum.map(tool_calls, &PendingToolCall.from_tool_call/1)
    state = State.put_pending_tools(state, pending)

    {state, _} =
      Enum.reduce(pending, {state, nil}, fn pending_call, {acc, _} ->
        emit_event(
          acc,
          owner,
          ref,
          :tool_started,
          %{
            tool_call_id: pending_call.id,
            tool_name: pending_call.name,
            arguments: maybe_redact_args(pending_call.arguments, config)
          },
          tool_call_id: pending_call.id,
          tool_name: pending_call.name
        )
      end)

    results =
      pending
      |> Task.async_stream(
        fn call -> execute_tool_with_retries(call, config, context) end,
        ordered: false,
        max_concurrency: config.tool_exec.concurrency,
        timeout: config.tool_exec.timeout_ms + 50
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, %{type: :task_exit, reason: inspect(reason)}}
      end)

    {state, thread} =
      Enum.reduce(results, {state, state.thread}, fn
        {pending_call, result, attempts, duration_ms}, {acc, thread_acc} ->
          completed = PendingToolCall.complete(pending_call, result, attempts, duration_ms)

          {acc, _} =
            emit_event(
              acc,
              owner,
              ref,
              :tool_completed,
              %{
                tool_call_id: completed.id,
                tool_name: completed.name,
                result: result,
                attempts: attempts,
                duration_ms: duration_ms
              },
              tool_call_id: completed.id,
              tool_name: completed.name
            )

          content = Turn.format_tool_result_content(result)
          thread_acc = Thread.append_tool_result(thread_acc, completed.id, completed.name, content)
          {acc, thread_acc}

        {:error, reason}, {acc, thread_acc} ->
          Logger.error("tool task failure", reason: inspect(reason))
          {acc, thread_acc}
      end)

    state =
      state
      |> State.put_status(:running)
      |> State.clear_pending_tools()
      |> State.inc_iteration()
      |> Map.put(:thread, thread)

    {state, _token} = emit_checkpoint(state, owner, ref, config, :after_tools)
    state
  end

  defp run_pending_tool_round(%State{} = state, owner, ref, %Config{} = config, context) do
    run_tool_round(
      State.put_status(state, :awaiting_tools),
      owner,
      ref,
      config,
      context,
      Enum.map(state.pending_tool_calls, fn
        %PendingToolCall{} = call -> %{id: call.id, name: call.name, arguments: call.arguments}
        %{} = call -> call
      end)
    )
  end

  defp execute_tool_with_retries(%PendingToolCall{} = pending_call, %Config{} = config, context) do
    module = Map.get(config.tools, pending_call.name)

    if is_nil(module) do
      {pending_call, {:error, %{type: :unknown_tool, message: "Tool '#{pending_call.name}' not found"}}, 1, 0}
    else
      do_execute_tool_with_retries(pending_call, module, config, context, 1)
    end
  end

  defp do_execute_tool_with_retries(%PendingToolCall{} = pending_call, module, %Config{} = config, context, attempt) do
    start_ms = System.monotonic_time(:millisecond)

    result =
      Turn.execute_module(module, pending_call.arguments, context,
        timeout: config.tool_exec.timeout_ms,
        max_retries: 0
      )

    duration_ms = max(System.monotonic_time(:millisecond) - start_ms, 0)

    if retryable?(result) and attempt <= config.tool_exec.max_retries do
      if config.tool_exec.retry_backoff_ms > 0, do: Process.sleep(config.tool_exec.retry_backoff_ms)
      do_execute_tool_with_retries(pending_call, module, config, context, attempt + 1)
    else
      {pending_call, result, attempt, duration_ms}
    end
  end

  defp retryable?({:ok, _}), do: false

  defp retryable?({:error, %{type: :timeout}}), do: true
  defp retryable?({:error, %{type: :exception}}), do: true
  defp retryable?({:error, %{type: :execution_error}}), do: true
  defp retryable?({:error, _}), do: false
  defp retryable?(_), do: false

  defp finalize(%State{} = state, owner, ref, %Config{} = config) do
    {state, _token} = emit_checkpoint(state, owner, ref, config, :terminal)
    send(owner, {:react_runner, ref, :done})
    state
  end

  defp emit_checkpoint(%State{} = state, owner, ref, %Config{} = config, reason)
       when reason in [:after_llm, :after_tools, :terminal] do
    token = Token.issue(state, config)

    emit_event(state, owner, ref, :checkpoint, %{
      token: token,
      reason: reason
    })
    |> then(fn {updated, _event} -> {updated, token} end)
  end

  defp emit_event(%State{} = state, owner, ref, kind, data, extra \\ %{}) do
    {state, seq} = State.bump_seq(state)

    event =
      Event.new(%{
        seq: seq,
        run_id: state.run_id,
        request_id: state.request_id,
        iteration: state.iteration,
        kind: kind,
        llm_call_id: fetch_extra(extra, :llm_call_id, state.llm_call_id),
        tool_call_id: fetch_extra(extra, :tool_call_id),
        tool_name: fetch_extra(extra, :tool_name),
        data: data
      })

    send(owner, {:react_runner, ref, :event, event})
    {state, event}
  end

  defp next_event(_owner, %{done?: true} = state), do: {:halt, state}

  defp next_event(_owner, %{done?: false, down?: true, ref: ref} = state) do
    receive do
      {:react_runner, ^ref, :event, event} ->
        {[event], state}

      {:react_runner, ^ref, :done} ->
        {:halt, %{state | done?: true}}
    after
      0 ->
        {:halt, %{state | done?: true}}
    end
  end

  defp next_event(_owner, %{ref: ref} = state) do
    receive do
      {:react_runner, ^ref, :event, event} ->
        {[event], state}

      {:react_runner, ^ref, :done} ->
        {:halt, %{state | done?: true}}

      {:DOWN, monitor_ref, :process, _pid, _reason} when monitor_ref == state.monitor_ref ->
        next_event(nil, %{state | down?: true})
    after
      @receive_timeout ->
        {:halt, %{state | done?: true}}
    end
  end

  defp cleanup(_owner, %{pid: pid, ref: ref}) when is_pid(pid) do
    if Process.alive?(pid) do
      send(pid, {:react_cancel, ref, :stream_halted})
      Process.exit(pid, :kill)
    end

    :ok
  end

  defp start_task(fun, opts) do
    case Keyword.get(opts, :task_supervisor) do
      task_sup when is_pid(task_sup) ->
        Task.Supervisor.start_child(task_sup, fun)

      task_sup when is_atom(task_sup) and not is_nil(task_sup) ->
        if Process.whereis(task_sup) do
          Task.Supervisor.start_child(task_sup, fun)
        else
          Task.start(fun)
        end

      _ ->
        Task.start(fun)
    end
  end

  defp request_id_opts(opts) do
    opts
    |> Keyword.take([:request_id, :run_id])
  end

  defp latest_query(%State{} = state) do
    case Thread.last_entry(state.thread) do
      %{role: :user, content: content} when is_binary(content) -> content
      _ -> ""
    end
  end

  defp append_query(%State{} = state, query) when is_binary(query) do
    %{state | thread: Thread.append_user(state.thread, query), status: :running, updated_at_ms: now_ms()}
  end

  defp maybe_thinking_opt(nil), do: []
  defp maybe_thinking_opt(""), do: []
  defp maybe_thinking_opt(thinking), do: [thinking: thinking]

  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value

  defp maybe_redact_args(arguments, %Config{} = config) do
    if config.observability[:redact_tool_args?] do
      Jido.AI.Observe.sanitize_sensitive(arguments)
    else
      arguments
    end
  end

  defp check_cancel!(%State{} = state, ref) do
    receive do
      {:react_cancel, ^ref, reason} -> throw({:cancelled, state, reason})
    after
      0 -> :ok
    end
  end

  defp fetch_extra(extra, key, default \\ nil)

  defp fetch_extra(extra, key, default) when is_map(extra) do
    Map.get(extra, key, default)
  end

  defp fetch_extra(extra, key, default) when is_list(extra) do
    Keyword.get(extra, key, default)
  end

  defp fetch_extra(_, _, default), do: default

  defp now_ms, do: System.system_time(:millisecond)
end
