defmodule Jido.AI.Session.Runtime do
  @moduledoc false
  use GenServer
  alias Jido.AI.{Authoring, Session}
  alias Jido.AI.PendingInputServer, as: InputQueue
  alias Jido.AI.Request.Stream
  alias Jido.AI.Session.Change
  alias Jido.AI.Session.{Activity, Inspection}

  def start_link(init), do: GenServer.start_link(__MODULE__, init)

  @impl true
  def init(init) do
    Process.flag(:trap_exit, true)

    with {:ok, skills} <-
           Jido.AI.Skill.Source.prepare_all(Keyword.get(init.options, :skills, %{})),
         {:ok, delivery} <- Jido.AI.Session.Delivery.start_link(self(), init.agent_server) do
      {:ok, %{init: init, jobs: %{}, settlements: %{}, delivery: delivery, skills: skills}, {:continue, :recover}}
    else
      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_continue(:recover, state) do
    case Jido.Plugin.state(state.init) do
      {:ok, records} ->
        jobs =
          for {id, %{status: :pending} = record} <- records, into: %{} do
            reason = if record.streamed, do: :stream_interrupted, else: :request_interrupted

            {id,
             %{
               record: record,
               task: nil,
               sink: nil,
               seq: Map.get(record.inspection, :seq, 0),
               inspection: record.inspection,
               iteration: Map.get(record.meta, :model_calls, 0),
               llm_call_id: record.inspection[:llm_call_id],
               meta: record.meta,
               usage: Map.get(record.meta, :usage, %{}),
               outcome: {:error, reason}
             }}
          end

        state = %{state | jobs: jobs}
        {:noreply, Enum.reduce(Map.keys(jobs), state, &settle(&2, &1, :result))}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @impl true
  def handle_call(:ready, _, state), do: {:reply, :ok, state}
  def handle_call(:skill_catalogs, _, state), do: {:reply, state.skills, state}

  def handle_call({:delivery_status, id}, _, state),
    do: {:reply, Jido.AI.Session.Delivery.status(state.delivery, id), state}

  def handle_call({:claim_delivery, id, ticket}, _, state),
    do: {:reply, Jido.AI.Session.Delivery.claim(state.delivery, id, ticket), state}

  def handle_call({:delivery_receipt, id, ticket}, _, state),
    do: {:reply, Jido.AI.Session.Delivery.receipt(state.delivery, id, ticket), state}

  def handle_call({:completion_status, id, run_id}, _, state) do
    failure =
      case state.jobs[id] do
        %{record: %{run_id: ^run_id}, terminal_failure: failure} -> failure
        _ -> nil
      end

    {:reply, failure, state}
  end

  def handle_call({:inspect, id, run_id}, _, state) do
    value =
      case state.jobs[id] do
        %{record: %{run_id: ^run_id}} = job ->
          %{
            request_id: id,
            run_id: run_id,
            inspection: Map.merge(Inspection.empty(), Map.get(job, :inspection, %{})),
            meta: metadata(job),
            reasoning: Map.get(job, :reasoning),
            worker_pid: if(job.task, do: job.task.pid),
            worker_status: if(job.outcome == nil, do: :running, else: :settling),
            terminal_failure: job[:terminal_failure],
            observed_at_ms: System.system_time(:millisecond)
          }

        _ ->
          nil
      end

    {:reply, value, state}
  end

  def handle_call({:metadata_snapshot, id}, _, state) do
    job =
      if id,
        do: state.jobs[id],
        else: Enum.find_value(state.jobs, fn {_, job} -> if job.outcome == nil, do: job end)

    {:reply, %{meta: metadata(job || %{}), inspection: Map.get(job || %{}, :inspection, %{})}, state}
  end

  def handle_call({:stage_selection, id, run_id, selection}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id, method: :adaptive}, outcome: nil} = job ->
        ticket = Jido.Signal.ID.generate!()
        grant = %{request_id: id, run_id: run_id, adaptive: selection}

        with :ok <- Jido.Action.validate_static_data(grant) do
          job = Map.put(job, :selection_grant, {ticket, grant})
          job = Map.put(job, :meta, Map.put(Map.get(job, :meta, %{}), :adaptive, selection))
          {:reply, {:ok, ticket}, put_in(state.jobs[id], job)}
        else
          _ -> {:reply, {:error, :invalid_selection}, state}
        end

      _ ->
        {:reply, {:error, :stale_request}, state}
    end
  end

  def handle_call({:claim_selection, id, run_id, ticket}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}, selection_grant: {^ticket, grant}, outcome: nil} = job ->
        {:reply, grant, put_in(state.jobs[id], Map.delete(job, :selection_grant))}

      _ ->
        {:reply, nil, state}
    end
  end

  def handle_call({:completion, id}, _, state) do
    value =
      case state.jobs[id] do
        %{terminal_sent?: true} ->
          nil

        %{outcome: outcome, record: record} = job when outcome != nil ->
          %{
            run_id: record.run_id,
            outcome: outcome,
            meta: completion_metadata(job),
            inspection: Map.get(job, :inspection, %{})
          }

        _ ->
          nil
      end

    {:reply, value, state}
  end

  def handle_call(
        {:dispatch, %Change{operation: :start, record: record}, directive_context},
        _,
        state
      ) do
    context =
      Map.put(
        directive_context.turn_context,
        :jido_ai_input_source,
        directive_context.effective_signal.source
      )

    resources = Map.get(context, :jido_ai_request, %{})
    {:ok, sink} = Stream.normalize_sink(resources[:stream_to])
    profile = context.jido_ai_profiles[record.profile_id]

    checkpoint = context[:jido_ai_checkpoint]
    {queue, owns_queue?} = input_queue(profile, checkpoint, record.id)

    runtime = self()
    enabled = Map.get(profile.observability, :emit_signals?, true)
    :ok = Jido.AI.Session.Delivery.register(state.delivery, record, enabled)
    saved = if checkpoint, do: checkpoint.state
    resumed? = Jido.AI.Reasoning.ReAct.Checkpoint.resumed?(context)

    job =
      %{
        record: record,
        task: nil,
        sink: sink,
        delivery: state.delivery,
        seq: if(saved, do: saved.seq, else: 0),
        iteration: if(resumed?, do: saved.checkpoint.runtime.model_calls, else: 0),
        llm_call_id: if(saved, do: saved.llm_call_id),
        checkpoint: checkpoint,
        outcome: nil,
        meta: Map.merge(%{model_calls: 0, reasoning_iteration: 1}, record.meta),
        usage: if(saved, do: saved.usage, else: %{}),
        queue: queue,
        owns_queue?: owns_queue?,
        history_batches: %{},
        inspection: record.inspection,
        observability: profile.observability,
        capture_deltas: Map.get(profile.observability, :emit_llm_deltas?, true),
        agent_id: state.init.agent_id
      }
      |> Activity.new(profile, Map.get(context, :jido_ai_tool_defaults, %{}))

    job =
      if resumed? do
        elapsed = max(System.system_time(:millisecond) - saved.started_at_ms, 0)
        Map.put(job, :started_at, System.monotonic_time(:millisecond) - elapsed)
      else
        emit(job, :request_started, %{query: record.query})
      end

    server = state.init.agent_server
    task = Task.async(fn -> execute(record, context, resources, runtime, queue, server) end)
    {:reply, :ok, put_in(state.jobs[record.id], %{job | task: task})}
  end

  def handle_call({:dispatch, %Change{operation: :control}, _}, _, state),
    do: {:reply, :ok, state}

  def handle_call({:dispatch, %Change{operation: :progress}, _}, _, state),
    do: {:reply, :ok, state}

  def handle_call(
        {:dispatch, %Change{operation: :history, record: record, batch_id: batch_id}, _},
        _,
        state
      ) do
    case state.jobs[record.id] do
      nil ->
        {:reply, :ok, state}

      job ->
        {:reply, :ok,
         put_in(state.jobs[record.id], %{
           job
           | history_batches: Map.delete(job.history_batches, batch_id),
             record: record
         })}
    end
  end

  def handle_call({:dispatch, %Change{operation: :finish, record: record}, _}, _, state) do
    case Map.pop(state.jobs, record.id) do
      {nil, _} ->
        {:reply, :ok, state}

      {job, jobs} ->
        stop_task(job.task)
        close_queue(job)

        job =
          if record.status == :failed and not Map.get(job, :terminal_sent?, false),
            do: output_failure(job, record.error),
            else: job

        {kind, data} =
          case record do
            %{status: :completed} ->
              {:request_completed, Map.merge(record.meta, %{result: record.result, meta: record.meta})}

            %{error: :cancelled} ->
              {:request_cancelled, Map.merge(record.meta, %{reason: :cancelled, meta: record.meta})}

            %{error: {:cancelled, reason}} ->
              {:request_cancelled, Map.merge(record.meta, %{reason: reason, meta: record.meta})}

            _ ->
              {:request_failed, Map.merge(record.meta, %{error: record.error, meta: record.meta})}
          end

        unless Map.get(job, :terminal_sent?, false), do: emit(job, kind, data)
        {:reply, :ok, %{state | jobs: jobs}}
    end
  end

  def handle_call({:control, input}, _, state) do
    active = Enum.find(state.jobs, fn {_, job} -> job.outcome == nil end)

    {id, status} =
      case active do
        nil ->
          {nil, {:error, :idle}}

        {id, job} ->
          result =
            cond do
              input.expected_request_id != nil and input.expected_request_id != id ->
                {:error, :request_mismatch}

              job.queue == nil ->
                {:error, :steering_disabled}

              true ->
                InputQueue.enqueue(job.queue, %{
                  id: input.control_id,
                  content: input.content,
                  source: input.source,
                  refs: input.extra_refs
                })
            end

          {id, result}
      end

    base = %{
      control_id: input.control_id,
      input_id: input.control_id,
      request_id: id,
      kind: input.kind,
      at_ms: System.system_time(:millisecond)
    }

    result =
      case status do
        :ok -> Map.put(base, :status, :queued)
        {:error, reason} -> Map.merge(base, %{status: :rejected, reason: reason})
      end

    {:reply, result, state}
  end

  def handle_call({:stage_history, id, run_id, entries}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}} = job ->
        batch_id = Jido.Signal.ID.generate!()

        batch = %{
          run_id: run_id,
          entries: entries,
          inspection: Map.get(job, :inspection, %{}),
          meta: metadata(job)
        }

        {:reply, {:ok, batch_id},
         put_in(state.jobs[id], %{
           job
           | history_batches: Map.put(job.history_batches, batch_id, batch)
         })}

      _ ->
        {:reply, {:error, :stale_history}, state}
    end
  end

  def handle_call({:history_batch, id, batch_id}, _, state) do
    batch = get_in(state, [:jobs, id, :history_batches, batch_id])
    {:reply, batch, state}
  end

  def handle_call({:output, id, run_id, kind, meta, data}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}} = job ->
        job =
          job
          |> Map.put(:meta, Map.put(Map.get(job, :meta, %{}), :output, meta))
          |> Map.put(:output_event, data)
          |> emit(kind, data)

        {:reply, :ok, put_in(state.jobs[id], job)}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:checkpoint, id, run_id, phase, saved}, from, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}, outcome: nil, checkpoint: %{config: config}} = job ->
        saved = %{saved | seq: job.seq + 1}

        case Jido.AI.Error.capture(fn ->
               {:ok, Jido.AI.Reasoning.ReAct.Token.issue(saved, config)}
             end) do
          {:ok, token} ->
            event_id = Jido.Signal.ID.generate!()

            job =
              job
              |> put_in([:meta, :reasoning_iteration], saved.iteration)
              |> emit(:checkpoint, %{reason: phase, token: token}, event_id)
              |> Map.put(:checkpoint_waiter, {from, event_id})

            {:noreply, put_in(state.jobs[id], job)}

          {:error, _} = error ->
            {:reply, error, state}
        end

      _ ->
        {:reply, {:error, :stale_checkpoint}, state}
    end
  end

  def handle_call({:checkpoint_ack, id, event_id}, {caller, _}, state) do
    case state.jobs[id] do
      %{sink: {:pid, ^caller}, checkpoint_waiter: {waiter, ^event_id}, outcome: nil} = job ->
        GenServer.reply(waiter, :ok)
        {:reply, :ok, put_in(state.jobs[id], Map.delete(job, :checkpoint_waiter))}

      _ ->
        {:reply, {:error, :stale_checkpoint}, state}
    end
  end

  def handle_call({:event_state, id, run_id}, _, state) do
    snapshot =
      case state.jobs[id] do
        %{record: %{run_id: ^run_id}} = job -> Map.take(job, [:seq])
        _ -> %{}
      end

    {:reply, snapshot, state}
  end

  def handle_call({:event, id, run_id, kind, data}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}, capture_deltas: false} when kind == :llm_delta ->
        {:reply, :ok, state}

      %{record: %{run_id: ^run_id}, outcome: nil} = job ->
        {:reply, :ok, put_in(state.jobs[id], emit(job, kind, data))}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:activity, id, run_id, value}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}, outcome: nil} = job ->
        job =
          case value do
            :progress -> Activity.touch(job)
            {:tool_finished, call_id} -> Activity.tool_finished(job, call_id)
          end

        {:reply, :ok, put_in(state.jobs[id], job)}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:tool_signature, id, run_id, signature}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}, outcome: nil} = job ->
        job = put_in(job.meta[:prev_tool_signature], signature)
        {:reply, :ok, put_in(state.jobs[id], job)}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:inspect_reasoning, id, run_id, data}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}, outcome: nil} = job ->
        case Jido.Action.validate_static_data(data) do
          :ok -> {:reply, :ok, put_in(state.jobs[id], Map.put(job, :reasoning, data))}
          error -> {:reply, error, state}
        end

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:reasoning_iteration, id, run_id, iteration}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}, outcome: nil} = job
      when is_integer(iteration) and iteration > 0 ->
        job = put_in(job.meta.reasoning_iteration, iteration)
        {:reply, :ok, put_in(state.jobs[id], job)}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:failure_type, id, run_id, type}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}} = job ->
        job = Map.put(job, :meta, Map.put(Map.get(job, :meta, %{}), :error_type, type))
        {:reply, :ok, put_in(state.jobs[id], job)}

      _ ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:usage, id, run_id, usage}, _, state) do
    case state.jobs[id] do
      %{record: %{run_id: ^run_id}} = job ->
        job = Map.put(job, :usage, Jido.AI.Usage.merge(Map.get(job, :usage, %{}), usage))
        {:reply, :ok, put_in(state.jobs[id], job)}

      _ ->
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:ai_activity, id, run_id, kind, token}, state) do
    job = state.jobs[id]

    if match?(%{record: %{run_id: ^run_id}}, job) and Activity.current?(job, kind, token) do
      case kind do
        :heartbeat ->
          job =
            job
            |> Activity.fired(:heartbeat)
            |> emit(:keepalive, %{source: :tool_execution})
            |> Activity.heartbeat()

          {:noreply, put_in(state.jobs[id], job)}

        :idle ->
          stop_task(job.task)

          job =
            Map.put(job, :meta, Map.put(Map.get(job, :meta, %{}), :error_type, :stream_timeout))

          finish(job.task.ref, {:error, :stream_timeout}, put_in(state.jobs[id], job))
      end
    else
      {:noreply, state}
    end
  end

  def handle_info({ref, result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    task_result(ref, result, state)
  end

  def handle_info({:DOWN, ref, :process, _, reason}, state) do
    if Map.has_key?(state.settlements, ref) do
      task_result(ref, {:uncertain, {:settlement_worker_exit, reason}}, state)
    else
      finish(ref, {:error, :worker_crash}, state, %{
        error_type: :worker_task,
        worker_exit_reason: Jido.AI.Error.for_storage(reason)
      })
    end
  end

  def handle_info({:EXIT, pid, reason}, %{delivery: pid} = state),
    do: {:stop, {:signal_delivery_exit, reason}, state}

  def handle_info({:EXIT, _, _}, state), do: {:noreply, state}

  defp task_result(ref, result, state) do
    case Map.pop(state.settlements, ref) do
      {nil, _} ->
        finish(ref, result, state)

      {%{id: id, run_id: run_id, attempt: attempt}, settlements} ->
        state = %{state | settlements: settlements}

        case state.jobs[id] do
          %{record: %{run_id: ^run_id}} ->
            {:noreply, settlement_result(result, id, attempt, state)}

          _ ->
            {:noreply, state}
        end
    end
  end

  # A core call replies after commit, before Directive dispatch. Only a
  # definite rejection permits a new, failure-only completion. Never submit
  # the model work or its original Directive batch again.
  defp settle(state, id, attempt) do
    server = state.init.agent_server
    task = Task.async(fn -> commit(server, Session.settle_signal(id)) end)
    entry = %{id: id, run_id: state.jobs[id].record.run_id, attempt: attempt, task: task}
    put_in(state.settlements[task.ref], entry)
  end

  defp commit(server, signal) do
    commit(server, signal, System.monotonic_time(:millisecond) + 5_000)
  catch
    :exit, reason -> {:uncertain, {:agent_server_exit, reason}}
  end

  defp commit(server, signal, deadline) do
    case Jido.AgentServer.call(server, signal, :infinity) do
      {:error, reason} = error
      when reason in [
             :reentrant_turn,
             :reentrant_admission,
             :reentrant_directive,
             {:plugin_runtime_unavailable, Jido.AI.Session.Plugin, :restarting}
           ] ->
        # Recovery can start before core publishes the replacement owner.
        # This exact refusal occurs before admission; no work was committed.
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(10)
          commit(server, signal, deadline)
        else
          error
        end

      result ->
        result
    end
  end

  defp settlement_result({:ok, _}, _id, _attempt, state), do: state

  defp settlement_result({:error, {:persistence_failed, reason} = error}, id, _, state) do
    # The public storage contract distinguishes a lost reply from a confirmed
    # refusal. Neither case permits overwriting a newer durable revision.
    case reason do
      :indeterminate ->
        terminal_failure(state, id, :completion_uncertain, error, :unknown)

      {:indeterminate, _} ->
        terminal_failure(state, id, :completion_uncertain, error, :unknown)

      %Jido.Error.ExecutionError{details: %{operation: :compare_and_swap}} ->
        terminal_failure(state, id, :completion_uncertain, error, :unknown)

      _ ->
        terminal_failure(state, id, :completion_uncommitted, error, false)
    end
  end

  defp settlement_result({:uncertain, reason}, id, _, state),
    do: terminal_failure(state, id, :completion_uncertain, reason, :unknown)

  defp settlement_result({:error, reason}, id, :result, state) do
    error = {:completion_failed, Jido.AI.Error.for_storage(reason)}
    job = state.jobs[id] |> output_failure(error) |> Map.put(:outcome, {:error, error})
    state |> put_in([:jobs, id], job) |> settle(id, :failure)
  end

  defp settlement_result({:error, _reason}, id, :failure, state) do
    job =
      state.jobs[id]
      |> Map.put(:outcome, {:error, {:completion_failed, :details_elided}})
      |> Map.put(:completion_meta, %{completion: %{details_elided?: true}})

    state |> put_in([:jobs, id], job) |> settle(id, :compact_failure)
  end

  defp settlement_result(result, id, _attempt, state) do
    terminal_failure(state, id, :completion_uncommitted, result, false)
  end

  defp terminal_failure(state, id, kind, reason, committed?) do
    error = {kind, Jido.AI.Error.for_storage(reason)}
    job = state.jobs[id]
    stop_task(job.task)
    close_queue(job)
    job = output_failure(job, error)

    job =
      job
      |> emit(:request_failed, %{error: error, meta: metadata(job), committed?: committed?})
      |> Map.merge(%{
        terminal_failure: error,
        terminal_sent?: true,
        queue: nil,
        outcome: {:error, error}
      })

    put_in(state.jobs[id], job)
  end

  defp finish(ref, result, state, failure_meta \\ %{}) do
    case Enum.find(state.jobs, fn {_, job} -> job.task != nil and job.task.ref == ref end) do
      nil ->
        {:noreply, state}

      {id, job} ->
        job = Map.update(job, :meta, failure_meta, &Map.merge(&1, failure_meta))
        if Map.get(job, :queue), do: InputQueue.seal(job.queue)

        outcome =
          result
          |> portable_result()
          |> Jido.AI.Reasoning.account_failure(job.record.method, Map.get(job, :usage, %{}))

        job =
          case outcome do
            {:error, error} -> output_failure(job, error)
            _ -> job
          end

        state = put_in(state.jobs[id], Activity.stop(%{job | task: nil, outcome: outcome}))
        {:noreply, settle(state, id, :result)}
    end
  end

  defp portable_result({:ok, %{result: _, meta: _}} = result), do: checked_result(result)
  defp portable_result({:error, reason}), do: {:error, Jido.AI.Error.for_storage(reason)}
  defp portable_result(_), do: {:error, :invalid_worker_result}

  defp checked_result(result) do
    # Directives are pending runtime work. Keep their live targets in this owner,
    # outside the portable request record. Core validates them before commit.
    check =
      case result do
        {:ok, %{effect_plan: plan} = value} ->
          {:ok, %{value | effect_plan: %{plan | directives: []}}}

        other ->
          other
      end

    case Jido.Action.validate_static_data(check) do
      :ok -> result
      _ -> {:error, :nonportable_worker_result}
    end
  end

  defp metadata(job), do: Map.put(Map.get(job, :meta, %{}), :usage, Map.get(job, :usage, %{}))

  defp completion_metadata(%{completion_meta: meta}), do: meta
  defp completion_metadata(job), do: metadata(job)

  defp output_failure(job, error) do
    case get_in(job, [:meta, :output]) do
      %{status: status} = output when status != :error ->
        meta = Jido.AI.Output.mark_failed(output, error)
        data = Map.put(meta, :schema_summary, job.output_event.schema_summary)

        job
        |> put_in([:meta, :output], meta)
        |> Map.put(:output_event, data)
        |> emit(:output_failed, data)

      _ ->
        job
    end
  end

  defp execute(record, context, resources, runtime, queue, server) do
    profile = context.jido_ai_profiles[record.profile_id]
    options = get_in(context, [:ai, record.profile_id, :options]) || []
    model = profile.models[profile.reasoning.model].model

    options =
      Jido.AI.Reasoning.ReAct.Config.merge_model_opts(options, resources[:llm_opts], model)

    options =
      Jido.AI.Reasoning.ReAct.Config.merge_http_options(options, resources[:req_http_options])

    ai =
      Map.update(
        Map.get(context, :ai, %{}),
        record.profile_id,
        %{options: options},
        &Map.put(&1, :options, options)
      )

    context =
      context
      |> Map.merge(tool_context(resources))
      |> Map.put(:ai, ai)
      |> Map.put(:agent_state, context.jido_ai_snapshot)
      |> Map.put(:state, context.jido_ai_snapshot)
      |> Map.put(:jido_ai_profiles, context.jido_ai_profiles)
      |> Map.put(:jido_ai_legacy_agent_profile, context[:jido_ai_legacy_agent_profile])
      |> Map.put(:jido_ai_session, true)
      |> Map.put(:jido_ai_events, {runtime, record.id, record.run_id})
      |> Map.put(:jido_ai_server, server)
      |> Map.put(:jido_ai_input_queue, queue)
      |> Map.put(:jido_ai_request_record, record)

    with {:ok, context} <- Jido.AI.Skill.Runtime.bind(context, profile, runtime),
         {:ok, flow} <- Authoring.reasoning_flow(profile),
         do: Jido.Exec.run(flow, %{query: record.query}, context, timeout: profile.controls.timeout)
  end

  defp tool_context(resources) do
    resources
    |> Map.get(:tool_context, %{})
    |> Jido.AI.ToolContext.runtime()
  end

  defp emit(job, kind, data, event_id \\ nil) do
    now = System.monotonic_time(:millisecond)
    job = if kind == :request_started, do: Map.put(job, :started_at, now), else: job

    job =
      if kind == :llm_started,
        do:
          Map.put(
            job,
            :phase_meta,
            Map.take(data, [:reasoning_phase, :phase_call_id, :selected_method])
          ),
        else: job

    job =
      if kind == :llm_started and Map.has_key?(data, :adaptive),
        do: Map.put(job, :meta, Map.put(Map.get(job, :meta, %{}), :adaptive, data.adaptive)),
        else: job

    data =
      if kind in [:llm_delta, :tool_started, :tool_completed],
        do: Map.merge(Map.get(job, :phase_meta, %{}), data),
        else: data

    data =
      if kind == :tool_started and Map.get(job.observability, :redact_tool_args?, true),
        do: Map.update(data, :arguments, %{}, &Jido.AI.Observe.sanitize_sensitive/1),
        else: data

    data =
      if kind in [:request_completed, :request_failed, :request_cancelled] and
           Map.has_key?(job, :started_at),
         do: Map.put(data, :duration_ms, max(now - job.started_at, 0)),
         else: data

    job = Activity.event(job, kind, data)
    seq = job.seq + 1
    iteration = Map.get(job, :iteration, 0) + if(kind == :llm_started, do: 1, else: 0)

    # Count started model operations, not HTTP attempts or Quota charges.
    # Recovery retains committed metadata; it does not invent a zero count.
    job = if kind == :llm_started, do: put_in(job.meta.model_calls, iteration), else: job

    data =
      case if(
             kind in [
               :request_started,
               :llm_started,
               :checkpoint,
               :request_completed,
               :request_failed,
               :request_cancelled
             ],
             do: get_in(job, [:meta, :reasoning_iteration])
           ) do
        position when is_integer(position) -> Map.put(data, :reasoning_iteration, position)
        _ -> data
      end

    call_id =
      if kind == :llm_started,
        do: data[:call_id] || Jido.Signal.ID.generate!(),
        else: Map.get(job, :llm_call_id)

    attrs = %{
      seq: seq,
      method: Map.get(job.record, :method, :react),
      run_id: job.record.run_id,
      request_id: job.record.id,
      iteration: iteration,
      llm_call_id: call_id,
      tool_call_id: data[:tool_call_id],
      tool_name: data[:tool_name],
      kind: kind,
      data: data
    }

    attrs = if event_id, do: Map.put(attrs, :id, event_id), else: attrs
    event = Jido.AI.Runtime.Event.new(attrs)

    job = Map.merge(job, %{seq: seq, iteration: iteration, llm_call_id: call_id})
    deliver(job, event)
  end

  defp deliver(job, event) do
    %{kind: kind, data: data, iteration: iteration, llm_call_id: call_id, seq: seq} = event
    job = Map.put(job, :inspection, Inspection.record(Map.get(job, :inspection, %{}), event))
    Stream.send_event(job.sink, event)
    # Delivery is observational. Its bounded failure report is separate from
    # the committed request result and the caller's canonical event stream.
    Jido.AI.Session.Delivery.enqueue(Map.get(job, :delivery), event)

    job =
      if kind == :llm_completed do
        meta =
          Jido.AI.Request.Metadata.record_turn(
            Map.get(job, :meta, %{}),
            Map.merge(data, %{call_id: call_id, iteration: iteration})
          )

        Map.put(job, :meta, meta)
      else
        job
      end

    model = data[:model] || Map.get(job, :model)

    job =
      if kind == :tool_completed do
        Map.put(job, :meta, Jido.AI.ToolResult.record(Map.get(job, :meta, %{}), data.completed))
      else
        job
      end

    Jido.AI.Runtime.Telemetry.emit(
      event,
      Map.get(job, :observability, %{}),
      Map.get(job, :agent_id),
      model
    )

    Map.merge(job, %{seq: seq, iteration: iteration, llm_call_id: call_id, model: model})
  end

  defp stop_task(nil), do: :ok
  defp stop_task(task), do: Task.shutdown(task, :brutal_kill)
  defp input_queue(%{requests: %{steering: false}}, _, _), do: {nil, false}

  defp input_queue(_, %{config: %{pending_input_server: queue}}, _) when not is_nil(queue),
    do: {queue, false}

  defp input_queue(_, _, id) do
    {:ok, queue} = InputQueue.start(owner: self(), request_id: id)
    {queue, true}
  end

  # A caller-supplied queue keeps its original owner. Closing a run prevents
  # new input but does not stop that process or erase its undrained data.
  defp close_queue(%{queue: nil}), do: :ok
  defp close_queue(%{queue: queue, owns_queue?: false}), do: InputQueue.seal(queue)
  defp close_queue(%{queue: queue}), do: InputQueue.stop(queue)
  defp close_queue(_), do: :ok

  @impl true
  def terminate(_, state) do
    Enum.each(state.jobs, fn {_, job} ->
      Activity.stop(job)
      stop_task(job.task)
      close_queue(job)
    end)

    Enum.each(state.settlements, fn {_, entry} -> stop_task(entry.task) end)

    try do
      GenServer.stop(state.delivery, :normal)
    catch
      :exit, _ -> :ok
    end

    :ok
  end
end
