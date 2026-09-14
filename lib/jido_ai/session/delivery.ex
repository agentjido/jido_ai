defmodule Jido.AI.Session.Delivery do
  @moduledoc false
  use GenServer
  require Logger
  alias Jido.AI.Session

  @defaults [queue_limit: 256, byte_limit: 8_388_608, batch_size: 16, timeout: 15_000]

  def start_link(owner, server), do: GenServer.start_link(__MODULE__, {owner, server})

  def register(pid, record, enabled),
    do: safe_call(pid, {:register, record.id, record.run_id, enabled})

  def enqueue(nil, _), do: :ok
  def enqueue(pid, event), do: safe_call(pid, {:enqueue, event})
  def claim(pid, id, ticket), do: safe_call(pid, {:claim, id, ticket})
  def consume(pid, id, ticket), do: safe_call(pid, {:consume, id, ticket})
  def receipt(pid, id, ticket), do: safe_call(pid, {:receipt, id, ticket})
  def status(pid, id), do: safe_call(pid, {:status, id})

  defp safe_call(pid, message) do
    GenServer.call(pid, message)
  catch
    :exit, _ -> {:error, :signal_delivery_unavailable}
  end

  def init({owner, server}) do
    Process.flag(:trap_exit, true)
    Process.monitor(owner)
    Process.monitor(server)
    opts = Application.get_env(:jido_ai, :signal_delivery, [])

    if Keyword.keyword?(opts) and Keyword.keys(opts) -- Keyword.keys(@defaults) == [] do
      opts = Map.new(Keyword.merge(@defaults, opts))

      if opts.queue_limit in 1..4096 and opts.byte_limit in 1..67_108_864 and
           opts.batch_size in 1..64 and opts.timeout in 1..60_000 do
        {:ok,
         %{
           owner: owner,
           server: server,
           opts: opts,
           pending: [],
           active: nil,
           bytes: 0,
           reports: %{},
           serial: 0
         }}
      else
        {:stop, :invalid_signal_delivery_limits}
      end
    else
      {:stop, :invalid_signal_delivery_options}
    end
  end

  def handle_call({:register, id, run_id, enabled}, _, state) do
    report = %{
      request_id: id,
      run_id: run_id,
      status: if(enabled, do: :pending, else: :disabled),
      enqueued: 0,
      delivered: 0,
      dropped: 0,
      unconfirmed: 0,
      last_seq: 0,
      terminal?: false,
      reason: nil,
      serial: state.serial + 1
    }

    state = %{
      state
      | reports: Map.put(state.reports, {id, run_id}, report),
        serial: report.serial
    }

    {:reply, :ok, prune(state)}
  end

  def handle_call({:status, id}, _, state) do
    report =
      state.reports
      |> Map.values()
      |> Enum.filter(&(&1.request_id == id))
      |> Enum.max_by(& &1.serial, fn -> nil end)

    {:reply, if(report, do: {:ok, Map.delete(report, :serial)}, else: {:error, :unknown_delivery}), state}
  end

  def handle_call({:enqueue, event}, _, state) do
    key = {event.request_id, event.run_id}

    if report = state.reports[key] do
      state =
        put_in(
          state.reports[key].terminal?,
          report.terminal? or Jido.AI.Request.Stream.terminal_kind?(event.kind)
        )

      case {report.status, project(event)} do
        {:disabled, _} ->
          {:reply, :ok, prune(state)}

        {_, {:ok, []}} ->
          {:reply, :ok, state}

        {status, _} when status != :pending ->
          {:reply, {:error, :signal_delivery_closed}, state |> bump(key, :dropped, 1) |> prune()}

        {_, {:ok, signals}} ->
          enqueue_item(state, event, signals)

        {_, {:error, reason}} ->
          state =
            fail(state, [key], :failed, {:projection_failed, reason}) |> bump(key, :dropped, 1)

          {:reply, {:error, :signal_projection_failed}, prune(state)}
      end
    else
      {:reply, {:error, :unknown_delivery}, state}
    end
  end

  def handle_call(
        {:claim, id, ticket},
        _,
        %{active: %{id: id, ticket: ticket, claimed?: false} = batch} = state
      ) do
    grant = %{owner: self(), id: id, ticket: ticket}
    {:reply, {:ok, grant}, %{state | active: %{batch | claimed?: true}}}
  end

  def handle_call({:claim, _, _}, _, state),
    do: {:reply, {:error, :invalid_delivery_grant}, state}

  def handle_call(
        {:consume, id, ticket},
        _,
        %{active: %{id: id, ticket: ticket, claimed?: true, consumed?: false} = batch} = state
      ) do
    {:reply, {:ok, Enum.flat_map(batch.items, & &1.signals)}, %{state | active: %{batch | consumed?: true}}}
  end

  def handle_call({:consume, _, _}, _, state),
    do: {:reply, {:error, :invalid_delivery_grant}, state}

  def handle_call(
        {:receipt, id, ticket},
        _,
        %{active: %{id: id, ticket: ticket, consumed?: true} = batch} = state
      ) do
    state = Enum.reduce(batch.items, state, fn item, acc -> delivered(acc, item.key) end)
    {:reply, :ok, state |> clear_active() |> next() |> prune()}
  end

  def handle_call({:receipt, _, _}, _, state),
    do: {:reply, {:error, :stale_delivery_receipt}, state}

  def handle_info({:delivery_timeout, id}, %{active: %{id: id} = batch} = state) do
    state =
      Enum.reduce(batch.items, state, fn item, acc -> bump(acc, item.key, :unconfirmed, 1) end)

    state = fail(state, Enum.map(batch.items, & &1.key), :unconfirmed, :receipt_timeout)
    {:noreply, state |> clear_active() |> next() |> prune()}
  end

  def handle_info({:delivery_timeout, _}, state), do: {:noreply, state}

  def handle_info({ref, result}, %{active: %{task: %{ref: ref}} = batch} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, _} ->
        {:noreply, %{state | active: %{batch | task: nil}}}

      {:error, reason} ->
        state =
          Enum.reduce(batch.items, state, fn item, acc -> bump(acc, item.key, :dropped, 1) end)

        state = fail(state, Enum.map(batch.items, & &1.key), :failed, {:commit_rejected, reason})
        {:noreply, state |> clear_active() |> next() |> prune()}

      {:uncertain, reason} ->
        state =
          Enum.reduce(batch.items, state, fn item, acc -> bump(acc, item.key, :unconfirmed, 1) end)

        state = fail(state, Enum.map(batch.items, & &1.key), :unconfirmed, reason)
        {:noreply, state |> clear_active() |> next() |> prune()}
    end
  end

  def handle_info({:DOWN, _, :process, pid, _}, %{owner: pid} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, _, :process, pid, _}, %{server: pid} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, ref, :process, _, reason}, %{active: %{task: %{ref: ref}}} = state),
    do: handle_info({ref, {:uncertain, {:delivery_worker_exit, reason}}}, state)

  def handle_info(_, state), do: {:noreply, state}

  def terminate(_, state) do
    clear_active(state)
    :ok
  end

  defp enqueue_item(state, event, signals) do
    key = {event.request_id, event.run_id}
    bytes = :erlang.external_size(signals)
    count = length(state.pending) + if(state.active, do: length(state.active.items), else: 0)

    cond do
      count >= state.opts.queue_limit ->
        state = fail(state, [key], :failed, :queue_limit) |> bump(key, :dropped, 1)
        {:reply, {:error, :signal_queue_full}, state}

      state.bytes + bytes > state.opts.byte_limit ->
        state = fail(state, [key], :failed, :byte_limit) |> bump(key, :dropped, 1)
        {:reply, {:error, :signal_queue_full}, state}

      true ->
        item = %{key: key, signals: signals, bytes: bytes}
        report = state.reports[key]

        report = %{
          report
          | enqueued: report.enqueued + 1,
            last_seq: event.seq,
            terminal?: Jido.AI.Request.Stream.terminal_kind?(event.kind)
        }

        state = %{
          state
          | pending: state.pending ++ [item],
            bytes: state.bytes + bytes,
            reports: Map.put(state.reports, key, report)
        }

        {:reply, :ok, next(state)}
    end
  end

  defp next(%{active: nil, pending: [_ | _]} = state) do
    {items, rest} = Enum.split(state.pending, state.opts.batch_size)
    id = Jido.Signal.ID.generate!()
    ticket = Jido.Signal.ID.generate!()
    server = state.server
    timeout = state.opts.timeout

    task =
      Task.async(fn ->
        commit(server, id, ticket, System.monotonic_time(:millisecond) + timeout)
      end)

    timer = Process.send_after(self(), {:delivery_timeout, id}, timeout)

    batch = %{
      id: id,
      ticket: ticket,
      items: items,
      task: task,
      timer: timer,
      claimed?: false,
      consumed?: false
    }

    %{state | pending: rest, active: batch}
  end

  defp next(state), do: state

  defp commit(server, id, ticket, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      signal =
        Jido.Signal.new!(Session.publish_type(), %{batch_id: id}, source: "/jido/ai/session")

      case Jido.AgentServer.call(server, signal,
             timeout: remaining,
             context: %{jido_ai_delivery_ticket: ticket}
           ) do
        {:error, reason}
        when reason in [:reentrant_turn, :reentrant_admission, :reentrant_directive] ->
          Process.sleep(min(10, remaining))
          commit(server, id, ticket, deadline)

        {:error, {:persistence_failed, reason} = error} = result ->
          case reason do
            :indeterminate ->
              {:uncertain, error}

            {:indeterminate, _} ->
              {:uncertain, error}

            %Jido.Error.ExecutionError{details: %{operation: :compare_and_swap}} ->
              {:uncertain, error}

            _ ->
              result
          end

        result ->
          result
      end
    else
      {:error, :admission_timeout}
    end
  catch
    :exit, reason -> {:uncertain, {:delivery_call_exit, reason}}
  end

  defp clear_active(%{active: nil} = state), do: state

  defp clear_active(%{active: batch} = state) do
    Process.cancel_timer(batch.timer)
    if batch.task, do: Task.shutdown(batch.task, :brutal_kill)
    %{state | active: nil, bytes: state.bytes - Enum.sum(Enum.map(batch.items, & &1.bytes))}
  end

  defp fail(state, keys, status, reason) do
    keys = Enum.uniq(keys)
    {dropped, pending} = Enum.split_with(state.pending, &(&1.key in keys))

    state = %{
      state
      | pending: pending,
        bytes: state.bytes - Enum.sum(Enum.map(dropped, & &1.bytes))
    }

    state = Enum.reduce(dropped, state, fn item, acc -> bump(acc, item.key, :dropped, 1) end)

    Enum.reduce(keys, state, fn key, acc ->
      case acc.reports[key] do
        %{status: :pending} = report ->
          Logger.warning("AI Signal delivery incomplete",
            request_id: report.request_id,
            run_id: report.run_id,
            reason: inspect(reason)
          )

          put_in(acc.reports[key], %{report | status: status, reason: reason})

        _ ->
          acc
      end
    end)
  end

  defp bump(state, key, field, n), do: update_in(state.reports[key][field], &(&1 + n))

  defp delivered(state, key) do
    state = bump(state, key, :delivered, 1)
    report = state.reports[key]

    if report.status == :pending and report.terminal? and report.delivered == report.enqueued,
      do: put_in(state.reports[key].status, :delivered),
      else: state
  end

  defp prune(state) do
    active_keys = if state.active, do: Enum.map(state.active.items, & &1.key), else: []
    queued_keys = Enum.map(state.pending, & &1.key)
    retained_keys = MapSet.new(active_keys ++ queued_keys)

    {pending, terminal} =
      Enum.split_with(state.reports, fn {key, r} ->
        not r.terminal? or MapSet.member?(retained_keys, key)
      end)

    retained = terminal |> Enum.sort_by(fn {_, r} -> r.serial end, :desc) |> Enum.take(100)
    %{state | reports: Map.new(pending ++ retained)}
  end

  defp project(event) do
    Jido.AI.Signal.from_event(event)
  rescue
    error -> {:error, Exception.message(error)}
  end
end

defmodule Jido.AI.Session.DeliveryReceipt do
  @moduledoc false
  use Jido.Agent.Directive

  @schema Zoi.struct(
            __MODULE__,
            %{batch_id: Zoi.string(), ticket: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)},
            coerce: true
          )
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.AI.Session.Publish do
  @moduledoc false
  use Jido.Action, name: "ai_session_publish", schema: Zoi.object(%{batch_id: Zoi.string()})

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Session.Plugin.context(context),
         do: execute(params, context)
  end

  defp execute(%{batch_id: id}, context) do
    with %{id: ^id, owner: owner, ticket: ticket} <- context[:jido_ai_delivery_grant],
         {:ok, signals} <- Jido.AI.Session.Delivery.consume(owner, id, ticket) do
      directives = Enum.map(signals, &%Jido.Agent.Directive.Emit{signal: &1})
      {:ok, context.agent_state, directives ++ [%Jido.AI.Session.DeliveryReceipt{batch_id: id, ticket: ticket}]}
    else
      _ -> {:error, :invalid_delivery_grant}
    end
  end
end

defmodule Jido.AI.Session.IgnoreSignal do
  @moduledoc false
  use Jido.Action, name: "ai_ignore_unhandled_observation"
  def run(_, context), do: {:ok, context.agent_state}
end
