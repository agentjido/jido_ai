defmodule Jido.AI.Reasoning.ChainOfThought.Worker.Strategy do
  @moduledoc false

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ChainOfThought.Machine
  alias Jido.AI.Reasoning.ReAct.Event

  @default_model "anthropic:claude-haiku-4-5"

  @start :cot_worker_start
  @cancel :cot_worker_cancel
  @runtime_event :cot_worker_runtime_event
  @runtime_done :cot_worker_runtime_done
  @runtime_failed :cot_worker_runtime_failed

  @source "/ai/cot/worker"

  @action_specs %{
    @start => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          run_id: Zoi.string(),
          prompt: Zoi.string(),
          config: Zoi.any(),
          context: Zoi.map() |> Zoi.default(%{}),
          task_supervisor: Zoi.any() |> Zoi.optional()
        }),
      doc: "Start a delegated CoT runtime run",
      name: "ai.cot.worker.start"
    },
    @cancel => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom() |> Zoi.default(:cancelled)
        }),
      doc: "Cancel an active delegated CoT runtime run",
      name: "ai.cot.worker.cancel"
    },
    @runtime_event => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          event: Zoi.map()
        }),
      doc: "Internal: runtime event forwarded from worker task",
      name: "ai.cot.worker.runtime.event"
    },
    @runtime_done => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string()
        }),
      doc: "Internal: runtime task completed",
      name: "ai.cot.worker.runtime.done"
    },
    @runtime_failed => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          error: Zoi.any()
        }),
      doc: "Internal: runtime task failed",
      name: "ai.cot.worker.runtime.failed"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.cot.worker.start", {:strategy_cmd, @start}},
      {"ai.cot.worker.cancel", {:strategy_cmd, @cancel}},
      {"ai.cot.worker.runtime.event", {:strategy_cmd, @runtime_event}},
      {"ai.cot.worker.runtime.done", {:strategy_cmd, @runtime_done}},
      {"ai.cot.worker.runtime.failed", {:strategy_cmd, @runtime_failed}}
    ]
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state = StratState.get(agent, %{})

    status =
      case state[:status] do
        :running -> :running
        :error -> :failure
        _ -> :idle
      end

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:idle, :failure],
      result: nil,
      details:
        %{
          phase: state[:status],
          active_request_id: state[:active_request_id],
          run_id: state[:run_id],
          started_at: state[:started_at],
          last_error: state[:last_error]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) or v == %{} end)
        |> Map.new()
    }
  end

  @impl true
  def init(%Agent{} = agent, _ctx) do
    state = %{
      status: :idle,
      active_request_id: nil,
      run_id: nil,
      runtime_task: nil,
      started_at: nil,
      last_error: nil,
      seq: 0
    }

    {StratState.put(agent, state), []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) do
    Enum.reduce(instructions, {agent, []}, fn instruction, {acc_agent, acc_directives} ->
      case process_instruction(acc_agent, instruction) do
        {updated_agent, directives} ->
          {updated_agent, acc_directives ++ directives}

        :noop ->
          {acc_agent, acc_directives}
      end
    end)
  end

  defp process_instruction(agent, %Jido.Instruction{action: @start, params: params}) do
    start_run(agent, params)
  end

  defp process_instruction(agent, %Jido.Instruction{action: @cancel, params: params}) do
    cancel_run(agent, params)
  end

  defp process_instruction(agent, %Jido.Instruction{action: @runtime_event, params: params}) do
    process_runtime_event(agent, params)
  end

  defp process_instruction(agent, %Jido.Instruction{action: @runtime_done, params: params}) do
    process_runtime_done(agent, params)
  end

  defp process_instruction(agent, %Jido.Instruction{action: @runtime_failed, params: params}) do
    process_runtime_failed(agent, params)
  end

  defp process_instruction(_agent, _instruction), do: :noop

  defp start_run(agent, %{request_id: request_id, run_id: run_id, prompt: prompt, config: config_input} = params)
       when is_binary(request_id) and is_binary(run_id) and is_binary(prompt) do
    state = StratState.get(agent, %{})

    if state[:status] == :running and is_binary(state[:active_request_id]) do
      event =
        synthesize_event(state, :request_failed, request_id, run_id, %{
          error: {:busy, state[:active_request_id]},
          error_type: :busy
        })

      directives = List.wrap(emit_parent_event(agent, request_id, event))
      {agent, directives}
    else
      _context = Map.get(params, :context, %{}) || %{}
      task_supervisor = Map.get(params, :task_supervisor)
      config = normalize_config(config_input)
      worker_pid = self()

      case start_task(fn -> run_stream(worker_pid, request_id, run_id, prompt, config) end, task_supervisor) do
        {:ok, runtime_task} ->
          new_state =
            state
            |> Map.put(:status, :running)
            |> Map.put(:active_request_id, request_id)
            |> Map.put(:run_id, run_id)
            |> Map.put(:runtime_task, runtime_task)
            |> Map.put(:started_at, System.monotonic_time(:millisecond))
            |> Map.put(:last_error, nil)
            |> Map.put(:seq, 0)

          {StratState.put(agent, new_state), []}

        {:error, reason} ->
          event =
            synthesize_event(state, :request_failed, request_id, run_id, %{
              error: {:runtime_start_failed, inspect(reason)},
              error_type: :runtime_start
            })

          new_state =
            state
            |> Map.put(:status, :error)
            |> Map.put(:active_request_id, nil)
            |> Map.put(:run_id, nil)
            |> Map.put(:runtime_task, nil)
            |> Map.put(:last_error, reason)

          directives = List.wrap(emit_parent_event(agent, request_id, event))
          {StratState.put(agent, new_state), directives}
      end
    end
  end

  defp start_run(agent, _params), do: {agent, []}

  defp cancel_run(agent, %{request_id: request_id, reason: reason})
       when is_binary(request_id) and is_atom(reason) do
    state = StratState.get(agent, %{})

    should_cancel? =
      state[:status] == :running and state[:active_request_id] == request_id and is_pid(state[:runtime_task]) and
        Process.alive?(state[:runtime_task])

    if should_cancel?, do: send(state[:runtime_task], {:cot_stream_cancel, reason})
    {agent, []}
  end

  defp cancel_run(agent, _params), do: {agent, []}

  defp process_runtime_event(agent, %{request_id: request_id, event: event}) when is_map(event) do
    state = StratState.get(agent, %{})
    event = normalize_event(event)
    kind = event_kind(event)
    seq = event_seq(event, state[:seq])
    run_id = event_run_id(event, state[:run_id] || request_id)

    new_state =
      state
      |> Map.put(:seq, seq)
      |> Map.put(:run_id, run_id)
      |> maybe_finish_run(kind)

    directives = List.wrap(emit_parent_event(agent, request_id, event))
    {StratState.put(agent, new_state), directives}
  end

  defp process_runtime_event(agent, _params), do: {agent, []}

  defp process_runtime_done(agent, %{request_id: request_id}) do
    state = StratState.get(agent, %{})

    new_state =
      if state[:active_request_id] == request_id do
        finish_state(state)
      else
        state
      end

    {StratState.put(agent, new_state), []}
  end

  defp process_runtime_done(agent, _params), do: {agent, []}

  defp process_runtime_failed(agent, %{request_id: request_id, error: error}) do
    state = StratState.get(agent, %{})

    if state[:active_request_id] == request_id do
      run_id = state[:run_id] || request_id

      event =
        synthesize_event(state, :request_failed, request_id, run_id, %{
          error: error,
          error_type: :worker_task
        })

      new_state =
        state
        |> finish_state()
        |> Map.put(:status, :error)
        |> Map.put(:last_error, error)

      directives = List.wrap(emit_parent_event(agent, request_id, event))
      {StratState.put(agent, new_state), directives}
    else
      {agent, []}
    end
  end

  defp process_runtime_failed(agent, _params), do: {agent, []}

  defp run_stream(worker_pid, request_id, run_id, prompt, config) do
    do_run_stream(worker_pid, request_id, run_id, prompt, config, 0)

    done_signal = Jido.Signal.new!("ai.cot.worker.runtime.done", %{request_id: request_id}, source: @source)
    Jido.AgentServer.cast(worker_pid, done_signal)
  rescue
    error ->
      stacktrace = __STACKTRACE__

      fail_signal =
        Jido.Signal.new!(
          "ai.cot.worker.runtime.failed",
          %{
            request_id: request_id,
            error: Exception.format(:error, error, stacktrace)
          },
          source: @source
        )

      Jido.AgentServer.cast(worker_pid, fail_signal)
  end

  defp do_run_stream(worker_pid, request_id, run_id, prompt, config, seq) do
    check_cancel!()
    llm_call_id = "cot_#{Jido.Util.generate_id()}"
    messages = build_messages(config.system_prompt, prompt)

    {seq, _event} =
      emit_runtime_event(worker_pid, request_id, run_id, seq, :request_started, %{
        query: prompt
      })

    {seq, _event} =
      emit_runtime_event(
        worker_pid,
        request_id,
        run_id,
        seq,
        :llm_started,
        %{
          call_id: llm_call_id,
          model: config.model,
          message_count: length(messages)
        },
        llm_call_id: llm_call_id
      )

    llm_opts = build_llm_opts(config)

    case ReqLLM.Generation.stream_text(config.model, messages, llm_opts) do
      {:ok, stream_response} ->
        {seq, chunks} =
          Enum.reduce(stream_response.stream, {seq, []}, fn chunk, {seq_acc, chunks_acc} ->
            check_cancel!()
            {seq_acc, _event} = maybe_emit_delta(worker_pid, request_id, run_id, llm_call_id, chunk, config, seq_acc)
            {seq_acc, [chunk | chunks_acc]}
          end)

        chunks = Enum.reverse(chunks)
        summary = ReqLLM.Response.Stream.summarize(chunks)
        text = summary.text || ""
        usage = ReqLLM.StreamResponse.usage(stream_response) || summary.usage || %{}

        {seq, _event} =
          emit_runtime_event(
            worker_pid,
            request_id,
            run_id,
            seq,
            :llm_completed,
            %{
              call_id: llm_call_id,
              turn_type: :final_answer,
              text: text,
              thinking_content: normalize_blank(summary.thinking),
              tool_calls: [],
              usage: usage
            },
            llm_call_id: llm_call_id
          )

        {_seq, _event} =
          emit_runtime_event(
            worker_pid,
            request_id,
            run_id,
            seq,
            :request_completed,
            %{
              result: text,
              termination_reason: :success,
              usage: usage
            }
          )

        :ok

      {:error, reason} ->
        {_seq, _event} =
          emit_runtime_event(
            worker_pid,
            request_id,
            run_id,
            seq,
            :request_failed,
            %{
              error: reason,
              error_type: :llm_request
            },
            llm_call_id: llm_call_id
          )

        :ok
    end
  catch
    {:cancelled, reason} ->
      {_seq, _event} =
        emit_runtime_event(
          worker_pid,
          request_id,
          run_id,
          seq,
          :request_cancelled,
          %{
            reason: reason
          }
        )

      :ok

    kind, reason ->
      {_seq, _event} =
        emit_runtime_event(
          worker_pid,
          request_id,
          run_id,
          seq,
          :request_failed,
          %{
            error: %{kind: kind, reason: inspect(reason)},
            error_type: :worker_task
          },
          llm_call_id: "cot_error"
        )

      :ok
  end

  defp maybe_emit_delta(
         worker_pid,
         request_id,
         run_id,
         llm_call_id,
         %ReqLLM.StreamChunk{type: type, text: text},
         config,
         seq
       )
       when type in [:content, :thinking] and is_binary(text) and text != "" do
    if config.capture_deltas? do
      emit_runtime_event(
        worker_pid,
        request_id,
        run_id,
        seq,
        :llm_delta,
        %{chunk_type: type, delta: text},
        llm_call_id: llm_call_id
      )
    else
      {seq, nil}
    end
  end

  defp maybe_emit_delta(_worker_pid, _request_id, _run_id, _llm_call_id, _chunk, _config, seq), do: {seq, nil}

  defp emit_runtime_event(worker_pid, request_id, run_id, seq, kind, data, extra \\ []) do
    event =
      Event.new(%{
        seq: seq + 1,
        run_id: run_id,
        request_id: request_id,
        iteration: 1,
        kind: kind,
        llm_call_id: Keyword.get(extra, :llm_call_id),
        tool_call_id: nil,
        tool_name: nil,
        data: data
      })
      |> Map.from_struct()

    signal =
      Jido.Signal.new!(
        "ai.cot.worker.runtime.event",
        %{
          request_id: request_id,
          event: event
        },
        source: @source
      )

    Jido.AgentServer.cast(worker_pid, signal)
    {seq + 1, event}
  end

  defp build_messages(system_prompt, prompt) do
    [
      %{role: :system, content: system_prompt},
      %{role: :user, content: prompt}
    ]
  end

  defp build_llm_opts(config) do
    []
    |> maybe_put_timeout(config.llm_timeout_ms)
  end

  defp maybe_put_timeout(opts, nil), do: opts

  defp maybe_put_timeout(opts, timeout) when is_integer(timeout) and timeout > 0,
    do: Keyword.put(opts, :receive_timeout, timeout)

  defp maybe_put_timeout(opts, _), do: opts

  defp normalize_config(%{} = config_input) do
    %{
      model: fetch_field(config_input, :model, @default_model),
      system_prompt: fetch_field(config_input, :system_prompt, Machine.default_system_prompt()),
      llm_timeout_ms: fetch_field(config_input, :llm_timeout_ms),
      capture_deltas?: fetch_field(config_input, :capture_deltas?, true)
    }
  end

  defp normalize_config(_config_input) do
    %{
      model: @default_model,
      system_prompt: Machine.default_system_prompt(),
      llm_timeout_ms: nil,
      capture_deltas?: true
    }
  end

  defp fetch_field(map, key, default \\ nil) when is_map(map) do
    Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  end

  defp normalize_blank(""), do: nil
  defp normalize_blank(value), do: value

  defp check_cancel! do
    receive do
      {:cot_stream_cancel, reason} -> throw({:cancelled, reason})
    after
      0 -> :ok
    end
  end

  defp maybe_finish_run(state, kind) when kind in [:request_completed, :request_failed, :request_cancelled],
    do: finish_state(state)

  defp maybe_finish_run(state, _kind), do: state

  defp finish_state(state) do
    state
    |> Map.put(:status, :idle)
    |> Map.put(:active_request_id, nil)
    |> Map.put(:run_id, nil)
    |> Map.put(:runtime_task, nil)
  end

  defp emit_parent_event(agent, request_id, event) do
    signal =
      Jido.Signal.new!(
        "ai.cot.worker.event",
        %{
          request_id: request_id,
          event: normalize_event(event)
        },
        source: @source
      )

    AgentDirective.emit_to_parent(agent, signal)
  end

  defp normalize_event(%Event{} = event), do: Map.from_struct(event)
  defp normalize_event(event) when is_map(event), do: event

  defp event_kind(event) do
    case Map.get(event, :kind, Map.get(event, "kind")) do
      kind when is_atom(kind) -> kind
      kind when is_binary(kind) -> runtime_kind_from_string(kind)
      _ -> :unknown
    end
  end

  defp runtime_kind_from_string("request_started"), do: :request_started
  defp runtime_kind_from_string("llm_started"), do: :llm_started
  defp runtime_kind_from_string("llm_delta"), do: :llm_delta
  defp runtime_kind_from_string("llm_completed"), do: :llm_completed
  defp runtime_kind_from_string("request_completed"), do: :request_completed
  defp runtime_kind_from_string("request_failed"), do: :request_failed
  defp runtime_kind_from_string("request_cancelled"), do: :request_cancelled
  defp runtime_kind_from_string(_), do: :unknown

  defp event_seq(event, fallback) do
    case Map.get(event, :seq, Map.get(event, "seq", fallback)) do
      value when is_integer(value) and value > fallback -> value
      _ -> fallback
    end
  end

  defp event_run_id(event, fallback) do
    case Map.get(event, :run_id, Map.get(event, "run_id")) do
      value when is_binary(value) and value != "" -> value
      _ -> fallback
    end
  end

  defp synthesize_event(state, kind, request_id, run_id, data) do
    Event.new(%{
      seq: (state[:seq] || 0) + 1,
      run_id: run_id,
      request_id: request_id,
      iteration: 1,
      kind: kind,
      data: data
    })
    |> Map.from_struct()
  end

  defp start_task(fun, task_supervisor) when is_pid(task_supervisor) do
    Task.Supervisor.start_child(task_supervisor, fun)
  end

  defp start_task(fun, task_supervisor) when is_atom(task_supervisor) and not is_nil(task_supervisor) do
    if Process.whereis(task_supervisor) do
      Task.Supervisor.start_child(task_supervisor, fun)
    else
      Task.start(fun)
    end
  end

  defp start_task(fun, _task_supervisor), do: Task.start(fun)
end
