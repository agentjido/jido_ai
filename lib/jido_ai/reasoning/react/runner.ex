defmodule Jido.AI.Reasoning.ReAct.Runner do
  @moduledoc """
  Task-based ReAct runner.

  Produces a lazy event stream via `Stream.resource/3` and does not persist runtime
  state outside of caller-owned checkpoint tokens.
  """

  alias Jido.AI.Reasoning.ReAct.{Config, Event, PendingToolCall, State, Token}
  alias Jido.AI.{Thread, Turn}

  require Logger

  @receive_timeout 30_000

  @type stream_opt ::
          {:request_id, String.t()}
          | {:run_id, String.t()}
          | {:state, State.t()}
          | {:task_supervisor, pid() | atom()}
          | {:context, map()}

  @doc """
  Starts a new ReAct coordinator task and returns a lazy event stream.
  """
  @spec stream(String.t(), Config.t(), [stream_opt()]) :: Enumerable.t()
  def stream(query, %Config{} = config, opts \\ []) when is_binary(query) do
    initial_state =
      case Keyword.get(opts, :state) do
        %State{} = state -> state
        _ -> State.new(query, config.system_prompt, request_id_opts(opts))
      end

    build_stream(initial_state, config, Keyword.put(opts, :query, query), emit_start?: true)
  end

  @doc """
  Continues a ReAct run from an existing runtime state.
  """
  @spec stream_from_state(State.t(), Config.t(), [stream_opt()]) :: Enumerable.t()
  def stream_from_state(%State{} = state, %Config{} = config, opts \\ []) do
    query = Keyword.get(opts, :query)

    state =
      case query do
        q when is_binary(q) and q != "" -> append_query(state, q)
        _ -> state
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
          fn -> %{done?: false, down?: false, cancel_sent?: false, pid: pid, monitor_ref: monitor_ref, ref: ref} end,
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
      case stream_opts[:emit_start?] do
        true ->
          {state, _} =
            emit_event(state, owner, ref, :request_started, %{
              query: latest_query(state),
              config_fingerprint: Config.fingerprint(config)
            })

          state

        _ ->
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
          message_count:
            Thread.length(state.thread) +
              case state.thread.system_prompt do
                nil -> 0
                _ -> 1
              end
        },
        llm_call_id: call_id
      )

    messages = Thread.to_messages(state.thread)
    llm_opts = Config.llm_opts(config)

    case request_turn(state, owner, ref, config, messages, llm_opts) do
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
            },
            llm_call_id: call_id
          )

        state =
          Thread.append_assistant(
            state.thread,
            turn.text,
            case turn.type do
              :tool_calls -> turn.tool_calls
              _ -> nil
            end,
            maybe_thinking_opt(turn.thinking_content)
          )
          |> then(&%{state | thread: &1})

        {state, _token} = emit_checkpoint(state, owner, ref, config, :after_llm)

        case Turn.needs_tools?(turn) do
          true ->
            {:tool_calls, State.put_status(state, :awaiting_tools), turn.tool_calls}

          _ ->
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

      {:error, state, reason, error_type} ->
        {:error, state, reason, error_type}
    end
  end

  defp request_turn(%State{} = state, owner, ref, %Config{} = config, messages, llm_opts) do
    case config.streaming do
      false ->
        request_turn_generate(state, config, messages, llm_opts)

      _ ->
        request_turn_stream(state, owner, ref, config, messages, llm_opts)
    end
  end

  defp request_turn_stream(%State{} = state, owner, ref, %Config{} = config, messages, llm_opts) do
    case ReqLLM.Generation.stream_text(config.model, messages, llm_opts) do
      {:ok, stream_response} ->
        case consume_stream(state, owner, ref, config, stream_response) do
          {:ok, updated_state, turn} -> {:ok, updated_state, turn}
          {:error, updated_state, reason} -> {:error, updated_state, reason, :llm_stream}
        end

      {:error, reason} ->
        {:error, state, reason, :llm_request}
    end
  end

  defp request_turn_generate(%State{} = state, %Config{} = config, messages, llm_opts) do
    case ReqLLM.Generation.generate_text(config.model, messages, llm_opts) do
      {:ok, response} ->
        consume_generate(state, config, response)

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
      case summary.tool_calls do
        tool_calls when is_list(tool_calls) and tool_calls != [] -> :tool_calls
        _ -> :final_answer
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

  defp consume_generate(%State{} = state, %Config{} = config, response) do
    turn = Turn.from_response(response, model: config.model)
    {:ok, state, turn}
  rescue
    e ->
      {:error, state, %{error: Exception.message(e), type: e.__struct__}, :llm_response}
  end

  defp maybe_emit_chunk_delta(%State{} = state, owner, ref, %ReqLLM.StreamChunk{type: :content, text: text}, trace_cfg)
       when is_binary(text) and text != "" do
    case trace_cfg[:capture_deltas?] do
      true ->
        {state, _} = emit_event(state, owner, ref, :llm_delta, %{chunk_type: :content, delta: text})
        state

      _ ->
        state
    end
  end

  defp maybe_emit_chunk_delta(%State{} = state, owner, ref, %ReqLLM.StreamChunk{type: :thinking, text: text}, trace_cfg)
       when is_binary(text) and text != "" do
    case trace_cfg[:capture_deltas?] do
      true ->
        {state, _} = emit_event(state, owner, ref, :llm_delta, %{chunk_type: :thinking, delta: text})
        state

      _ ->
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

    case is_atom(module) and function_exported?(module, :name, 0) and function_exported?(module, :run, 2) do
      true ->
        do_execute_tool_with_retries(pending_call, module, config, context, 1)

      _ ->
        {pending_call, {:error, %{type: :unknown_tool, message: "Tool '#{pending_call.name}' not found"}, []}, 1, 0}
    end
  end

  defp do_execute_tool_with_retries(%PendingToolCall{} = pending_call, module, %Config{} = config, context, attempt) do
    start_ms = System.monotonic_time(:millisecond)
    timeout_ms = normalize_timeout(config.tool_exec[:timeout_ms])

    result =
      safe_execute_module(module, pending_call.arguments, context,
        timeout: timeout_ms,
        max_retries: 0
      )

    duration_ms = max(System.monotonic_time(:millisecond) - start_ms, 0)
    max_retries = normalize_retry_count(config.tool_exec[:max_retries])
    backoff_ms = normalize_backoff(config.tool_exec[:retry_backoff_ms])

    case retryable?(result) and attempt <= max_retries do
      true ->
        case backoff_ms > 0 do
          true -> Process.sleep(backoff_ms)
          _ -> :ok
        end

        do_execute_tool_with_retries(pending_call, module, config, context, attempt + 1)

      _ ->
        {pending_call, result, attempt, duration_ms}
    end
  end

  defp retryable?({:ok, _, _}), do: false

  defp retryable?({:error, %{type: :timeout}, _}), do: true
  defp retryable?({:error, %{type: :exception}, _}), do: true
  defp retryable?({:error, %{type: :execution_error}, _}), do: true
  defp retryable?({:error, _, _}), do: false

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
      {:react_stream_cancel, _reason} ->
        next_event(nil, state)

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
      {:react_stream_cancel, reason} ->
        next_event(nil, request_stream_cancel(state, reason))

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
    case Process.alive?(pid) do
      true ->
        send(pid, {:react_cancel, ref, :stream_halted})
        Process.exit(pid, :kill)

      _ ->
        :ok
    end

    :ok
  end

  defp start_task(fun, opts) do
    case Keyword.get(opts, :task_supervisor) do
      task_sup when is_pid(task_sup) ->
        Task.Supervisor.start_child(task_sup, fun)

      task_sup when is_atom(task_sup) and not is_nil(task_sup) ->
        case Process.whereis(task_sup) do
          pid when is_pid(pid) ->
            Task.Supervisor.start_child(task_sup, fun)

          _ ->
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
    case config.observability[:redact_tool_args?] do
      true -> Jido.AI.Observe.sanitize_sensitive(arguments)
      _ -> arguments
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

  defp request_stream_cancel(%{cancel_sent?: true} = state, _reason), do: state

  defp request_stream_cancel(%{pid: pid, ref: ref} = state, reason) when is_pid(pid) do
    case Process.alive?(pid) do
      true -> send(pid, {:react_cancel, ref, reason})
      _ -> :ok
    end

    Map.put(state, :cancel_sent?, true)
  end

  defp request_stream_cancel(state, _reason), do: state

  defp safe_execute_module(module, params, context, opts) do
    Turn.execute_module(module, params, context, opts)
  rescue
    error ->
      {:error, %{type: :exception, error: Exception.message(error), exception_type: error.__struct__}, []}
  catch
    kind, reason ->
      {:error, %{type: :caught, kind: kind, error: inspect(reason)}, []}
  end

  defp normalize_timeout(value) when is_integer(value) and value > 0, do: value
  defp normalize_timeout(_), do: 15_000

  defp normalize_retry_count(value) when is_integer(value) and value >= 0, do: value
  defp normalize_retry_count(_), do: 0

  defp normalize_backoff(value) when is_integer(value) and value >= 0, do: value
  defp normalize_backoff(_), do: 0

  defp now_ms, do: System.system_time(:millisecond)
end
