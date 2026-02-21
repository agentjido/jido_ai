defmodule Jido.AI.Reasoning.ReAct.Worker.Strategy do
  @moduledoc false

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Directive, as: AgentDirective
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.Reasoning.ReAct
  alias Jido.AI.Reasoning.ReAct.Event
  alias Jido.AI.Reasoning.ReAct.Signal

  @start :react_worker_start
  @cancel :react_worker_cancel
  @runtime_event :react_worker_runtime_event
  @runtime_done :react_worker_runtime_done
  @runtime_failed :react_worker_runtime_failed

  @source "/ai/react/worker"

  @action_specs %{
    @start => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          run_id: Zoi.string(),
          query: Zoi.string(),
          config: Zoi.any(),
          state: Zoi.any() |> Zoi.optional(),
          context: Zoi.map() |> Zoi.default(%{}),
          task_supervisor: Zoi.any() |> Zoi.optional()
        }),
      doc: "Start a delegated ReAct runtime run",
      name: "ai.react.worker.start"
    },
    @cancel => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          reason: Zoi.atom() |> Zoi.default(:cancelled)
        }),
      doc: "Cancel an active delegated ReAct runtime run",
      name: "ai.react.worker.cancel"
    },
    @runtime_event => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          event: Zoi.map()
        }),
      doc: "Internal: runtime event forwarded from worker task",
      name: "ai.react.worker.runtime.event"
    },
    @runtime_done => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string()
        }),
      doc: "Internal: runtime task completed",
      name: "ai.react.worker.runtime.done"
    },
    @runtime_failed => %{
      schema:
        Zoi.object(%{
          request_id: Zoi.string(),
          error: Zoi.any()
        }),
      doc: "Internal: runtime task failed",
      name: "ai.react.worker.runtime.failed"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"ai.react.worker.start", {:strategy_cmd, @start}},
      {"ai.react.worker.cancel", {:strategy_cmd, @cancel}},
      {"ai.react.worker.runtime.event", {:strategy_cmd, @runtime_event}},
      {"ai.react.worker.runtime.done", {:strategy_cmd, @runtime_done}},
      {"ai.react.worker.runtime.failed", {:strategy_cmd, @runtime_failed}}
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

    {put_strategy_state(agent, state), []}
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

  defp start_run(agent, %{request_id: request_id, run_id: run_id, query: query, config: config_input} = params)
       when is_binary(request_id) and is_binary(run_id) and is_binary(query) do
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
      config = ReAct.build_config(config_input)
      context = Map.get(params, :context, %{}) || %{}
      runtime_state = Map.get(params, :state)
      task_supervisor = Map.get(params, :task_supervisor)
      worker_pid = self()

      stream_opts =
        []
        |> Keyword.put(:request_id, request_id)
        |> Keyword.put(:run_id, run_id)
        |> Keyword.put(:context, context)
        |> maybe_put_runtime_state(runtime_state)
        |> maybe_put_task_supervisor(task_supervisor)

      case start_task(fn -> run_stream(worker_pid, request_id, query, config, stream_opts) end, task_supervisor) do
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

          {put_strategy_state(agent, new_state), []}

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
          {put_strategy_state(agent, new_state), directives}
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

    if should_cancel? do
      send(state[:runtime_task], {:react_stream_cancel, reason})
    end

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
    {put_strategy_state(agent, new_state), directives}
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

    {put_strategy_state(agent, new_state), []}
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
      {put_strategy_state(agent, new_state), directives}
    else
      {agent, []}
    end
  end

  defp process_runtime_failed(agent, _params), do: {agent, []}

  defp run_stream(worker_pid, request_id, query, config, stream_opts) do
    ReAct.stream(query, config, stream_opts)
    |> Enum.each(fn event ->
      signal =
        Jido.Signal.new!(
          "ai.react.worker.runtime.event",
          %{
            request_id: request_id,
            event: Map.from_struct(event)
          },
          source: @source
        )

      Jido.AgentServer.cast(worker_pid, signal)
    end)

    done_signal = Jido.Signal.new!("ai.react.worker.runtime.done", %{request_id: request_id}, source: @source)
    Jido.AgentServer.cast(worker_pid, done_signal)
  rescue
    error ->
      stacktrace = __STACKTRACE__

      fail_signal =
        Jido.Signal.new!(
          "ai.react.worker.runtime.failed",
          %{
            request_id: request_id,
            error: Exception.format(:error, error, stacktrace)
          },
          source: @source
        )

      Jido.AgentServer.cast(worker_pid, fail_signal)
  catch
    kind, reason ->
      fail_signal =
        Jido.Signal.new!(
          "ai.react.worker.runtime.failed",
          %{
            request_id: request_id,
            error: %{kind: kind, reason: inspect(reason)}
          },
          source: @source
        )

      Jido.AgentServer.cast(worker_pid, fail_signal)
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
      Signal.new!(
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
      kind when is_atom(kind) ->
        kind

      kind when is_binary(kind) ->
        try do
          String.to_existing_atom(kind)
        rescue
          ArgumentError -> :unknown
        end

      _ ->
        :unknown
    end
  end

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
      iteration: 0,
      kind: kind,
      data: data
    })
    |> Map.from_struct()
  end

  defp maybe_put_task_supervisor(opts, nil), do: opts
  defp maybe_put_task_supervisor(opts, task_supervisor), do: Keyword.put(opts, :task_supervisor, task_supervisor)

  defp maybe_put_runtime_state(opts, nil), do: opts
  defp maybe_put_runtime_state(opts, runtime_state), do: Keyword.put(opts, :state, runtime_state)

  defp put_strategy_state(%Agent{} = agent, state) when is_map(state) do
    %{agent | state: Map.put(agent.state, StratState.key(), state)}
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
