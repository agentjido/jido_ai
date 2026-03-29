defmodule Jido.AI.Reasoning.ReAct.Runner do
  @moduledoc """
  Task-based ReAct runner.

  Produces a lazy event stream via `Stream.resource/3` and does not persist runtime
  state outside of caller-owned checkpoint tokens.
  """

  alias Jido.AI.PendingInputServer
  alias Jido.AI.Reasoning.ReAct.{Config, Event, PendingToolCall, State, Token, ToolSelection}
  alias Jido.AI.Effects
  alias Jido.AI.Context, as: AIContext
  alias Jido.AI.Signal.Helpers, as: SignalHelpers
  alias Jido.AI.Turn
  alias Jido.Agent.State, as: AgentState

  require Logger

  @cleanup_wait_ms 25
  @stream_control_wait_ms 10

  # Injected as a user message when the agent repeats the exact same tool
  # calls with identical arguments on consecutive iterations.
  @cycle_warning "You already called the same tool(s) with identical parameters in the previous iteration and got the same results. Do NOT repeat the same calls. Either use the results you already have to form a final answer, or try a different approach."

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
    receive_timeout_ms = Config.stream_timeout(config)

    case start_task(fn -> coordinator(owner, ref, initial_state, config, opts, stream_opts) end, opts) do
      {:ok, pid} ->
        monitor_ref = Process.monitor(pid)

        Stream.resource(
          fn ->
            %{
              done?: false,
              down?: false,
              cancel_sent?: false,
              pid: pid,
              monitor_ref: monitor_ref,
              receive_timeout_ms: receive_timeout_ms,
              stream_cancel: nil,
              stream_cancelled?: false,
              ref: ref
            }
          end,
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
    context = build_runtime_context(Keyword.get(opts, :context, %{}), state, config)

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
        seal_pending_input_server(config)

        cancelled_state =
          current_state
          |> State.put_status(:cancelled)
          |> State.put_result("Request cancelled (reason: #{inspect(reason)})")

        {cancelled_state, _} =
          emit_event(cancelled_state, owner, ref, :request_cancelled, %{reason: reason})

        {_cancelled_state, _token} = emit_checkpoint(cancelled_state, owner, ref, config, :terminal)
        send(owner, {:react_runner, ref, :done})

      kind, reason ->
        seal_pending_input_server(config)

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
        {state, context} = run_pending_tool_round(state, owner, ref, config, context)
        run_loop(state, owner, ref, config, context)

      state.iteration > config.max_iterations ->
        seal_pending_input_server(config)

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
        case drain_pending_input(state, owner, ref, config) do
          {:ok, state} ->
            case run_llm_step(state, owner, ref, config, context) do
              {:final_answer, state} ->
                case maybe_continue_after_final_answer(state, owner, ref, config) do
                  {:continue, state} ->
                    run_loop(state, owner, ref, config, context)

                  {:complete, state} ->
                    state

                  {:error, state, reason, error_type} ->
                    fail_run(state, owner, ref, config, reason, error_type)
                end

              {:tool_calls, state, tool_calls} ->
                prev_signature = Map.get(state, :__prev_tool_signature__)
                current_signature = tool_call_signature(tool_calls)

                {state, context} = run_tool_round(state, owner, ref, config, context, tool_calls)

                state = Map.put(state, :__prev_tool_signature__, current_signature)

                state =
                  if prev_signature == current_signature and prev_signature != nil do
                    corrected_context = AIContext.append_user(state.context, @cycle_warning)
                    %{state | context: corrected_context}
                  else
                    state
                  end

                run_loop(state, owner, ref, config, context)

              {:error, state, reason, error_type} ->
                fail_run(state, owner, ref, config, reason, error_type)
            end

          {:error, state, reason} ->
            fail_run(state, owner, ref, config, {:pending_input_server, reason}, :runtime)
        end
    end
  end

  defp run_llm_step(%State{} = state, owner, ref, %Config{} = config, runtime_context) do
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
            AIContext.length(state.context) +
              case state.context.system_prompt do
                nil -> 0
                _ -> 1
              end
        },
        llm_call_id: call_id
      )

    with {:ok, request} <- build_turn_request(state, config, runtime_context) do
      state = %{state | active_tools: request.tools}

      case request_turn(state, owner, ref, config, request.messages, request.llm_opts) do
        {:ok, state, turn, response_id} ->
          state =
            state
            |> State.merge_usage(turn.usage)
            |> State.put_llm_response_id(response_id)

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
                reasoning_details: Map.get(turn, :reasoning_details),
                tool_calls: turn.tool_calls,
                usage: turn.usage
              },
              llm_call_id: call_id
            )

          state =
            AIContext.append_assistant(
              state.context,
              turn.text,
              case turn.type do
                :tool_calls -> turn.tool_calls
                _ -> nil
              end,
              assistant_context_opts(turn)
            )
            |> then(&%{state | context: &1})

          {state, _token} = emit_checkpoint(state, owner, ref, config, :after_llm)

          case Turn.needs_tools?(turn) do
            true ->
              {:tool_calls, State.put_status(state, :awaiting_tools), turn.tool_calls}

            _ ->
              case validate_terminal_response(turn) do
                :ok ->
                  completed =
                    state
                    |> State.put_status(:completed)
                    |> State.put_result(turn.text)

                  {:final_answer, completed}

                {:error, reason} ->
                  {:error, state, reason, :llm_response}
              end
          end

        {:error, state, reason, error_type} ->
          {:error, state, reason, error_type}
      end
    else
      {:error, reason} ->
        {:error, state, reason, :request_transform}
    end
  end

  defp build_turn_request(%State{} = state, %Config{} = config, runtime_context) do
    base_request = %{
      messages: AIContext.to_messages(state.context),
      llm_opts: config |> Config.llm_opts() |> maybe_put_previous_response_id(state.llm_response_id),
      tools: config.tools
    }

    with {:ok, request} <- maybe_transform_request(base_request, state, config, runtime_context),
         {:ok, messages} <- normalize_request_messages(request),
         {:ok, tools} <- normalize_request_tools(request),
         llm_opts <- sync_tools_in_llm_opts(config, request.llm_opts, tools) do
      {:ok, %{messages: messages, llm_opts: llm_opts, tools: tools}}
    end
  end

  defp maybe_transform_request(request, _state, %Config{request_transformer: nil}, _runtime_context), do: {:ok, request}

  defp maybe_transform_request(request, %State{} = state, %Config{} = config, runtime_context) do
    module = config.request_transformer

    case module.transform_request(request, state, config, runtime_context) do
      {:ok, %{} = overrides} ->
        {:ok, apply_request_overrides(request, overrides, config)}

      {:error, reason} ->
        {:error, {:request_transformer, reason}}

      other ->
        {:error, {:invalid_request_transformer_result, other}}
    end
  rescue
    e ->
      {:error, {:request_transformer_exception, %{error: Exception.message(e), type: e.__struct__}}}
  end

  defp apply_request_overrides(request, overrides, %Config{} = config) when is_map(request) and is_map(overrides) do
    request
    |> maybe_put_request_field(:messages, Map.get(overrides, :messages, Map.get(overrides, "messages")))
    |> maybe_put_request_field(:tools, Map.get(overrides, :tools, Map.get(overrides, "tools")))
    |> maybe_merge_request_llm_opts(config, Map.get(overrides, :llm_opts, Map.get(overrides, "llm_opts")))
  end

  defp maybe_put_request_field(request, _field, nil), do: request
  defp maybe_put_request_field(request, field, value), do: Map.put(request, field, value)

  defp maybe_merge_request_llm_opts(request, _config, nil), do: request

  defp maybe_merge_request_llm_opts(request, %Config{} = config, llm_opts_override) do
    Map.update!(request, :llm_opts, fn base_opts ->
      Config.merge_llm_opts(config, base_opts, llm_opts_override)
    end)
  end

  defp normalize_request_messages(%{messages: messages}) when is_list(messages), do: {:ok, messages}
  defp normalize_request_messages(_request), do: {:error, :invalid_request_messages}

  defp normalize_request_tools(%{tools: tools}) do
    case ToolSelection.normalize_input(tools) do
      {:ok, action_map} -> {:ok, action_map}
      {:error, reason} -> {:error, {:invalid_request_tools, reason}}
    end
  end

  defp normalize_request_tools(_request), do: {:error, :invalid_request_tools}

  defp sync_tools_in_llm_opts(%Config{} = config, llm_opts, tools) when is_list(llm_opts) and is_map(tools) do
    reqllm_tools = Config.reqllm_tools(%{config | tools: tools})

    llm_opts
    |> Keyword.delete(:tools)
    |> Keyword.put(:tools, reqllm_tools)
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
        announce_stream_control(owner, ref, stream_response)

        case consume_stream(state, owner, ref, config, stream_response) do
          {:ok, updated_state, turn, response_id} -> {:ok, updated_state, turn, response_id}
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
    state_key = stream_state_key(ref)
    heartbeat_interval_ms = progress_interval_ms(config)

    Process.put(state_key, state)
    Process.put(stream_signal_key(ref), monotonic_ms())

    case ReqLLM.StreamResponse.process_stream(
           stream_response,
           stream_process_opts(owner, ref, trace_cfg, state_key, heartbeat_interval_ms)
         ) do
      {:ok, response} ->
        {:ok, current_stream_state(state_key, state),
         Turn.from_response(response, model: Jido.AI.model_label(config.model)), extract_response_id(response)}

      {:error, reason} ->
        {:error, current_stream_state(state_key, state), reason}
    end
  rescue
    e ->
      {:error, current_stream_state(stream_state_key(ref), state), %{error: Exception.message(e), type: e.__struct__}}
  after
    Process.delete(stream_state_key(ref))
    Process.delete(stream_signal_key(ref))
  end

  defp consume_generate(%State{} = state, %Config{} = config, response) do
    turn = Turn.from_response(response, model: Jido.AI.model_label(config.model))
    {:ok, state, turn, extract_response_id(response)}
  rescue
    e ->
      {:error, state, %{error: Exception.message(e), type: e.__struct__}, :llm_response}
  end

  defp extract_response_id(%ReqLLM.Response{message: %ReqLLM.Message{metadata: metadata}})
       when is_map(metadata) do
    metadata[:response_id] || metadata["response_id"]
  end

  defp extract_response_id(%{message: %{metadata: metadata}}) when is_map(metadata) do
    metadata[:response_id] || metadata["response_id"]
  end

  defp extract_response_id(_), do: nil

  defp maybe_put_previous_response_id(llm_opts, nil), do: llm_opts

  defp maybe_put_previous_response_id(llm_opts, response_id) when is_list(llm_opts) and is_binary(response_id) do
    provider_options = llm_opts |> Keyword.get(:provider_options, []) |> normalize_provider_options()
    Keyword.put(llm_opts, :provider_options, Keyword.put(provider_options, :previous_response_id, response_id))
  end

  defp maybe_put_previous_response_id(llm_opts, _response_id), do: llm_opts

  defp normalize_provider_options(options) when is_list(options), do: Enum.reject(options, fn {k, _v} -> is_nil(k) end)

  defp normalize_provider_options(options) when is_map(options) do
    options
    |> Enum.reject(fn {k, _v} -> is_nil(k) end)
    |> Enum.flat_map(fn
      {k, v} when is_atom(k) -> [{k, v}]
      {"previous_response_id", v} -> [previous_response_id: v]
      _ -> []
    end)
  end

  defp normalize_provider_options(_options), do: []

  defp run_tool_round(%State{} = state, owner, ref, %Config{} = config, context, tool_calls)
       when is_list(tool_calls) do
    effective_tools =
      case state.active_tools do
        %{} = tools when map_size(tools) > 0 -> tools
        _ -> config.tools
      end

    tool_config = %{config | tools: effective_tools}
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
        fn call -> execute_tool_with_retries(call, tool_config, context) end,
        # Preserve deterministic tool completion/event ordering by original call order.
        ordered: true,
        max_concurrency: tool_config.tool_exec.concurrency,
        timeout: tool_config.tool_exec.timeout_ms + 50
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, %{type: :task_exit, reason: inspect(reason)}}
      end)

    {state, updated_context} =
      Enum.reduce(results, {state, state.context}, fn
        {pending_call, result, attempts, duration_ms}, {acc, context_acc} ->
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
          context_acc = AIContext.append_tool_result(context_acc, completed.id, completed.name, content)
          {acc, context_acc}

        {:error, reason}, {acc, context_acc} ->
          Logger.error("tool task failure", reason: inspect(reason))
          {acc, context_acc}
      end)

    state =
      state
      |> State.put_status(:running)
      |> State.clear_pending_tools()
      |> State.inc_iteration()
      |> Map.put(:context, updated_context)

    {state, _token} = emit_checkpoint(state, owner, ref, config, :after_tools)
    {state, evolve_context_state_snapshot(context, results)}
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

  defp evolve_context_state_snapshot(context, results) when is_map(context) and is_list(results) do
    case current_state_snapshot(context) do
      {:ok, snapshot} ->
        updated_snapshot =
          Enum.reduce(results, snapshot, fn
            {_pending_call, result, _attempts, _duration_ms}, acc ->
              apply_state_effects(acc, result)

            {:error, _reason}, acc ->
              acc

            _other, acc ->
              acc
          end)

        Map.put(context, :state, updated_snapshot)

      :error ->
        context
    end
  end

  defp evolve_context_state_snapshot(context, _results), do: context

  defp current_state_snapshot(context) when is_map(context) do
    case context[:state] do
      %{} = snapshot -> {:ok, snapshot}
      _ -> :error
    end
  end

  defp build_runtime_context(context, %State{} = state, %Config{} = config) when is_map(context) do
    context
    |> Map.put_new(:request_id, state.request_id)
    |> Map.put_new(:run_id, state.run_id)
    |> Map.put_new(:effect_policy, config.effect_policy)
    |> Map.put_new(:observability, config.observability)
  end

  defp build_runtime_context(_context, %State{} = state, %Config{} = config) do
    build_runtime_context(%{}, state, config)
  end

  defp apply_state_effects(snapshot, result) when is_map(snapshot) do
    {_status, _payload, effects} = Effects.normalize_result(result)

    Enum.reduce(effects, snapshot, fn
      %Jido.Agent.StateOp.SetState{attrs: attrs}, acc when is_map(attrs) ->
        AgentState.merge(acc, attrs)

      %Jido.Agent.StateOp.ReplaceState{state: new_state}, _acc when is_map(new_state) ->
        new_state

      %Jido.Agent.StateOp.DeleteKeys{keys: keys}, acc when is_list(keys) ->
        Map.drop(acc, keys)

      %Jido.Agent.StateOp.SetPath{path: path, value: value}, acc when is_list(path) ->
        put_in_path(acc, path, value)

      %Jido.Agent.StateOp.DeletePath{path: path}, acc when is_list(path) ->
        delete_in_path(acc, path)

      _other, acc ->
        acc
    end)
  end

  defp apply_state_effects(snapshot, _result), do: snapshot

  defp put_in_path(map, [key], value) when is_map(map), do: Map.put(map, key, value)

  defp put_in_path(map, [key | rest], value) when is_map(map) do
    nested =
      case Map.get(map, key) do
        %{} = current -> current
        _ -> %{}
      end

    Map.put(map, key, put_in_path(nested, rest, value))
  end

  defp put_in_path(map, _path, _value), do: map

  defp delete_in_path(map, [key]) when is_map(map), do: Map.delete(map, key)

  defp delete_in_path(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      %{} = nested ->
        Map.put(map, key, delete_in_path(nested, rest))

      _ ->
        map
    end
  end

  defp delete_in_path(map, _path), do: map

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

    case SignalHelpers.retryable?(result) and attempt <= max_retries do
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

      {:react_runner, ^ref, :stream_control, control} ->
        next_event(nil, apply_stream_control(state, control))

      {:react_runner, ^ref, :progress} ->
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
    receive_timeout_ms = Map.get(state, :receive_timeout_ms, 30_000)

    receive do
      {:react_stream_cancel, reason} ->
        next_event(nil, request_stream_cancel(state, reason))

      {:react_runner, ^ref, :stream_control, control} ->
        next_event(nil, apply_stream_control(state, control))

      {:react_runner, ^ref, :progress} ->
        next_event(nil, state)

      {:react_runner, ^ref, :event, event} ->
        {[event], state}

      {:react_runner, ^ref, :done} ->
        {:halt, %{state | done?: true}}

      {:DOWN, monitor_ref, :process, _pid, _reason} when monitor_ref == state.monitor_ref ->
        next_event(nil, %{state | down?: true})
    after
      receive_timeout_ms ->
        {:halt, %{state | done?: true}}
    end
  end

  defp notify_progress(owner, ref) do
    send(owner, {:react_runner, ref, :progress})
    :ok
  end

  defp cleanup(_owner, %{pid: pid} = state) when is_pid(pid) do
    state = request_stream_cancel(state, :stream_halted)
    await_runner_shutdown(state)
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
    case AIContext.last_entry(state.context) do
      %{role: :user, content: content} when is_binary(content) -> content
      _ -> ""
    end
  end

  defp append_query(%State{} = state, query) when is_binary(query) do
    %{state | context: AIContext.append_user(state.context, query), status: :running, updated_at_ms: now_ms()}
  end

  defp maybe_thinking_opt(nil), do: []
  defp maybe_thinking_opt(""), do: []
  defp maybe_thinking_opt(thinking), do: [thinking: thinking]

  defp assistant_context_opts(%Turn{} = turn) do
    turn.thinking_content
    |> maybe_thinking_opt()
    |> maybe_put_assistant_context_opt(:reasoning_details, turn.reasoning_details)
  end

  defp maybe_put_assistant_context_opt(opts, _key, nil), do: opts
  defp maybe_put_assistant_context_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_note_owner_signal(true, _owner, _ref, _last_owner_signal_ms, _interval_ms), do: monotonic_ms()

  defp maybe_note_owner_signal(false, owner, ref, last_owner_signal_ms, interval_ms) do
    current_ms = monotonic_ms()

    if current_ms - last_owner_signal_ms >= interval_ms do
      notify_progress(owner, ref)
      current_ms
    else
      last_owner_signal_ms
    end
  end

  defp progress_interval_ms(%Config{} = config) do
    max(1, div(Config.stream_timeout(config), 2))
  end

  defp visible_chunk?(%ReqLLM.StreamChunk{type: :content, text: text}, trace_cfg), do: delta_captured?(text, trace_cfg)
  defp visible_chunk?(%ReqLLM.StreamChunk{type: :thinking, text: text}, trace_cfg), do: delta_captured?(text, trace_cfg)
  defp visible_chunk?(_chunk, _trace_cfg), do: false

  defp delta_captured?(text, trace_cfg), do: trace_cfg[:capture_deltas?] == true and is_binary(text) and text != ""

  defp stream_process_opts(owner, ref, trace_cfg, state_key, heartbeat_interval_ms) do
    []
    |> Keyword.put(:on_chunk, fn chunk ->
      note_stream_chunk_activity(chunk, state_key, owner, ref, trace_cfg, heartbeat_interval_ms)
    end)
    |> maybe_put_stream_callback(trace_cfg, :on_result, fn text ->
      emit_stream_delta(state_key, owner, ref, :content, text)
    end)
    |> maybe_put_stream_callback(trace_cfg, :on_thinking, fn text ->
      emit_stream_delta(state_key, owner, ref, :thinking, text)
    end)
  end

  defp maybe_put_stream_callback(opts, trace_cfg, callback_key, callback_fun) do
    case trace_cfg[:capture_deltas?] do
      true -> Keyword.put(opts, callback_key, callback_fun)
      _ -> opts
    end
  end

  defp emit_stream_delta(_state_key, _owner, _ref, _chunk_type, text) when text in [nil, ""], do: :ok

  defp emit_stream_delta(state_key, owner, ref, chunk_type, text) do
    update_stream_state(state_key, fn
      %State{} = current_state ->
        {next_state, _} =
          emit_event(current_state, owner, ref, :llm_delta, %{chunk_type: chunk_type, delta: text})

        next_state

      other ->
        other
    end)

    :ok
  end

  defp stream_state_key(ref), do: {__MODULE__, :stream_state, ref}
  defp stream_signal_key(ref), do: {__MODULE__, :stream_signal, ref}

  defp note_stream_chunk_activity(chunk, state_key, owner, ref, trace_cfg, heartbeat_interval_ms) do
    case current_stream_state(state_key, nil) do
      %State{} = current_state -> check_cancel!(current_state, ref)
      _ -> :ok
    end

    last_owner_signal_ms = Process.get(stream_signal_key(ref), monotonic_ms())

    last_owner_signal_ms =
      maybe_note_owner_signal(
        visible_chunk?(chunk, trace_cfg),
        owner,
        ref,
        last_owner_signal_ms,
        heartbeat_interval_ms
      )

    Process.put(stream_signal_key(ref), last_owner_signal_ms)
    :ok
  end

  defp current_stream_state(state_key, default) do
    Process.get(state_key, default)
  end

  defp update_stream_state(state_key, update_fun) when is_function(update_fun, 1) do
    current_state = Process.get(state_key)
    next_state = update_fun.(current_state)
    Process.put(state_key, next_state)
    next_state
  end

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

  defp maybe_continue_after_final_answer(%State{} = state, owner, ref, %Config{} = config) do
    case seal_pending_input_server_if_empty(config) do
      :pending ->
        case drain_pending_input(state, owner, ref, config) do
          {:ok, state} ->
            state =
              state
              |> State.put_status(:running)
              |> State.put_result(nil)
              |> State.inc_iteration()

            {:continue, state}

          {:error, state, reason} ->
            {:error, state, {:pending_input_server, reason}, :runtime}
        end

      :sealed ->
        {state, _} =
          emit_event(state, owner, ref, :request_completed, %{
            result: state.result,
            termination_reason: :final_answer,
            usage: state.usage
          })

        {:complete, state}

      {:error, reason} ->
        {:error, state, {:pending_input_server, reason}, :runtime}
    end
  end

  defp drain_pending_input(%State{} = state, _owner, _ref, %Config{pending_input_server: nil}),
    do: {:ok, state}

  defp drain_pending_input(%State{} = state, owner, ref, %Config{pending_input_server: server}) do
    case PendingInputServer.drain_result(server) do
      {:ok, items} ->
        next_state =
          Enum.reduce(items, state, fn item, acc ->
            refs = normalize_optional_refs(item[:refs])
            next_context = AIContext.append_user(acc.context, item.content, refs: refs)
            next_state = %{acc | context: next_context}

            {next_state, _} =
              emit_event(next_state, owner, ref, :input_injected, %{
                input_id: item.id,
                content: item.content,
                source: item.source,
                refs: refs,
                at_ms: item.at_ms
              })

            next_state
          end)

        {:ok, next_state}

      {:error, reason} ->
        {:error, state, reason}
    end
  end

  # Returns :ok if the turn is a valid terminal response, or {:error, reason} if the LLM
  # returned a failure-like finish reason with no meaningful content. Preventing an empty
  # incomplete response from being silently accepted as a successful final answer.
  defp validate_terminal_response(%Turn{} = turn) do
    blank_text? = turn.text == ""
    failure_reason? = turn.finish_reason in [:error, :incomplete, :cancelled]

    if blank_text? and failure_reason? do
      {:error, {:incomplete_response, turn.finish_reason}}
    else
      :ok
    end
  end

  defp fail_run(%State{} = state, owner, ref, %Config{} = config, reason, error_type) do
    seal_pending_input_server(config)

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

  defp seal_pending_input_server(%Config{pending_input_server: nil}), do: :ok
  defp seal_pending_input_server(%Config{pending_input_server: server}), do: PendingInputServer.seal(server)

  defp seal_pending_input_server_if_empty(%Config{pending_input_server: nil}), do: :sealed

  defp seal_pending_input_server_if_empty(%Config{pending_input_server: server}) do
    PendingInputServer.seal_if_empty(server)
  end

  defp normalize_optional_refs(%{} = refs), do: refs
  defp normalize_optional_refs(_), do: nil

  defp fetch_extra(extra, key, default \\ nil)

  defp fetch_extra(extra, key, default) when is_map(extra) do
    Map.get(extra, key, default)
  end

  defp fetch_extra(extra, key, default) when is_list(extra) do
    Keyword.get(extra, key, default)
  end

  defp request_stream_cancel(%{cancel_sent?: true} = state, _reason), do: state

  defp request_stream_cancel(%{pid: pid, ref: ref} = state, reason) when is_pid(pid) do
    state =
      state
      |> maybe_capture_stream_control()
      |> invoke_stream_cancel()

    case Process.alive?(pid) do
      true -> send(pid, {:react_cancel, ref, reason})
      _ -> :ok
    end

    Map.put(state, :cancel_sent?, true)
  end

  defp request_stream_cancel(state, _reason) do
    state
    |> maybe_capture_stream_control()
    |> invoke_stream_cancel()
    |> Map.put(:cancel_sent?, true)
  end

  defp announce_stream_control(owner, ref, stream_response) do
    case stream_cancel_fun(stream_response) do
      cancel_fun when is_function(cancel_fun, 0) ->
        send(owner, {:react_runner, ref, :stream_control, %{cancel: cancel_fun}})

      _ ->
        :ok
    end

    :ok
  end

  defp apply_stream_control(state, %{cancel: cancel_fun}) when is_function(cancel_fun, 0) do
    %{state | stream_cancel: cancel_fun}
  end

  defp apply_stream_control(state, _control), do: state

  defp maybe_capture_stream_control(%{stream_cancel: cancel_fun} = state) when is_function(cancel_fun, 0), do: state

  defp maybe_capture_stream_control(%{ref: ref} = state) do
    receive do
      {:react_runner, ^ref, :stream_control, control} ->
        apply_stream_control(state, control)
    after
      @stream_control_wait_ms ->
        state
    end
  end

  defp invoke_stream_cancel(%{stream_cancelled?: true} = state), do: state

  defp invoke_stream_cancel(%{stream_cancel: cancel_fun} = state) when is_function(cancel_fun, 0) do
    _ = cancel_fun.()
    %{state | stream_cancelled?: true}
  rescue
    _ -> %{state | stream_cancelled?: true}
  end

  defp invoke_stream_cancel(state), do: state

  defp await_runner_shutdown(%{pid: pid, monitor_ref: monitor_ref}) when is_pid(pid) do
    case Process.alive?(pid) do
      true ->
        receive do
          {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
            :ok
        after
          @cleanup_wait_ms ->
            Process.exit(pid, :kill)
            :ok
        end

      _ ->
        :ok
    end
  end

  defp await_runner_shutdown(_state), do: :ok

  defp stream_cancel_fun(%{cancel: cancel_fun}) when is_function(cancel_fun, 0), do: cancel_fun
  defp stream_cancel_fun(_stream_response), do: nil

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
  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  # Tool call maps may arrive with atom or string keys depending on the
  # provider adapter, so we check both.
  defp tool_call_signature(tool_calls) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(fn tc ->
      name = Map.get(tc, :name) || Map.get(tc, "name") || ""
      args = Map.get(tc, :arguments) || Map.get(tc, "arguments") || ""
      "#{name}:#{inspect(args)}"
    end)
    |> Enum.sort()
    |> Enum.join("|")
  end
end
