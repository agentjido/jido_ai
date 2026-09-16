defmodule Jido.AI.Reasoning.ReAct.Runner do
  @moduledoc """
  A lazy standalone stream backed by a private v3 Agent and its Orchestration.

  Enumeration owns the Agent lifetime. The shared Agent/Flow runtime executes
  all model and tool work. Terminal tokens contain AI data, never Exec values.
  Model and tool checkpoints resume through the shared Flow with fresh runtime
  resources.
  """
  alias Jido.AI.{Request, Orchestration}
  alias Jido.AI.Reasoning.ReAct.{Authoring, Checkpoint, Config, State, Token}
  alias Jido.AI.Runtime.Event
  alias Jido.AgentServer, as: Server

  @terminal [:completed, :failed, :cancelled]

  def stream(query, %Config{} = config, opts \\ []) when is_binary(query) or is_list(query) do
    state = Keyword.get_lazy(opts, :state, fn -> State.new(query, config.system_prompt, opts) end)
    build_stream(state, config, Keyword.delete(opts, :query))
  end

  def stream_from_state(%State{} = state, %Config{} = config, opts \\ []) do
    build_stream(state, config, opts)
  end

  defp build_stream(state, config, opts) do
    messages = if opts[:query], do: [%{role: :user, content: opts[:query]}], else: State.messages(state.context)

    model_options = Jido.AI.Model.Transport.bind_options(messages, config.llm.llm_opts)
    opts = Keyword.put(opts, :model_call_options, model_options)

    Stream.resource(
      fn ->
        owner = self()
        ref = make_ref()
        work = fn -> coordinate(owner, ref, state, config, opts) end

        started =
          case opts[:task_supervisor] do
            nil -> Task.start(work)
            supervisor -> Task.Supervisor.start_child(supervisor, work)
          end

        case started do
          {:ok, pid} ->
            %{
              pid: pid,
              monitor: Process.monitor(pid),
              ref: ref,
              done?: false,
              policy: config.observability,
              checkpoint_ack: nil
            }

          {:error, reason} ->
            raise "Failed to start ReAct stream: #{inspect(reason)}"
        end
      end,
      &next_event/1,
      &cleanup/1
    )
  end

  defp next_event(%{done?: true} = stream), do: {:halt, stream}

  defp next_event(%{checkpoint_ack: id, pid: pid, ref: ref} = stream) when not is_nil(id) do
    send(pid, {:react_checkpoint_ack, ref, id})
    next_event(%{stream | checkpoint_ack: nil})
  end

  defp next_event(%{ref: ref, monitor: monitor, pid: pid} = stream) do
    receive do
      {:react_runner, ^ref, :done} ->
        {:halt, %{stream | done?: true}}

      {:react_runner, ^ref, %Event{} = event} ->
        ack = if event.kind == :checkpoint and event.data.reason != :terminal, do: event.id
        {[Jido.AI.Observe.Content.event(event, stream.policy, :stream)], %{stream | checkpoint_ack: ack}}

      {:DOWN, ^monitor, :process, ^pid, reason} ->
        raise "ReAct stream owner stopped: #{inspect(reason)}"
    end
  end

  defp cleanup(%{pid: pid, monitor: monitor, ref: ref}) do
    send(pid, {:react_cancel, ref})

    if Process.alive?(pid) do
      receive do
        {:DOWN, ^monitor, :process, ^pid, _} -> :ok
      after
        5_000 -> Process.exit(pid, :kill)
      end
    end

    Process.demonitor(monitor, [:flush])
    flush(ref)
  end

  defp flush(ref) do
    receive do
      {:react_runner, ^ref, _} -> flush(ref)
    after
      0 -> :ok
    end
  end

  defp coordinate(owner, ref, state, config, opts) do
    monitor = Process.monitor(owner)

    try do
      with {:ok, state} <- append_query(state, config, opts) do
        cond do
          state.status in @terminal ->
            terminal(owner, ref, state, config)

          not initial?(state) and state.checkpoint == nil ->
            fail(owner, ref, state, config, :checkpoint_phase_not_ported)

          true ->
            run(owner, monitor, ref, state, config, opts)
        end
      else
        {:error, reason} -> fail(owner, ref, state, config, reason)
      end
    rescue
      error -> fail(owner, ref, state, config, Jido.AI.Error.for_storage(error))
    after
      if config.pending_input_server,
        do: Jido.AI.PendingInputServer.seal(config.pending_input_server)

      Process.demonitor(monitor, [:flush])
    end

    send(owner, {:react_runner, ref, :done})
  end

  defp append_query(state, config, opts) do
    case opts[:query] do
      query when (is_binary(query) and query != "") or is_list(query) ->
        with {:ok, limits} <- limits(config, opts),
             do:
               Checkpoint.append_query(
                 state,
                 query,
                 config,
                 Keyword.get(opts, :context, %{}),
                 limits.timeout
               )

      _ ->
        {:ok, state}
    end
  end

  defp initial?(state),
    do:
      state.status == :running and state.iteration == 1 and state.seq == 0 and
        state.pending_tool_calls == []

  defp run(owner, monitor, ref, state, config, opts) do
    context = Keyword.get(opts, :context, %{})

    with {:ok, context} <- Jido.Agent.Command.normalize_context(context),
         :ok <- Checkpoint.verify(state, config),
         {:ok, limits} <- limits(config, opts),
         {:ok, base} <- base(context, state),
         {:ok, definition, model_context} <- Authoring.lower(config, limits, base, tool_interceptor(context)),
         model_context =
           update_in(model_context, [:ai, :assistant, :options], &Keyword.merge(&1, opts[:model_call_options] || [])),
         {:ok, server} <-
           Server.start_link([agent: definition] ++ Map.to_list(Map.take(context, [:jido]))) do
      server_monitor = Process.monitor(server)

      try do
        with :ok <- Server.await_ready(server, 5_000),
             {:ok, query} <- query(state),
             {:ok, request} <-
               Request.create_and_send(server, query,
                 signal_type: "ai.react.query",
                 source: "/ai/react/standalone",
                 request_id: state.request_id,
                 run_id: state.run_id,
                 stream_to: self(),
                 context:
                   context
                   |> Orchestration.caller_context()
                   |> Map.merge(Map.take(context, [:jido_ai_quota]))
                   |> Map.merge(model_context)
                   |> Map.put(:jido_ai_checkpoint, %{
                     adapter: Checkpoint,
                     result_key: :react_checkpoint,
                     state: state,
                     config: config
                   })
               ) do
          relay(owner, monitor, ref, state, config, request, server_monitor)
        else
          {:error, reason} -> fail(owner, ref, state, config, reason)
        end
      after
        stop(server)
        Process.demonitor(server_monitor, [:flush])
      end
    else
      {:error, reason} -> fail(owner, ref, state, config, reason)
    end
  end

  defp limits(config, opts) do
    case Keyword.fetch(opts, :limits) do
      {:ok, limits} -> {:ok, limits}
      :error -> Authoring.default_limits(config)
    end
  end

  # Standalone callers supplied this callback module before the private Agent
  # existed. Bind it to the profile; the Agent retains its own runtime identity.
  defp tool_interceptor(%{agent_module: module}) when is_atom(module) and not is_nil(module) do
    if Code.ensure_loaded?(module) and
         (function_exported?(module, :before_tool_call, 2) or function_exported?(module, :after_tool_call, 3)),
       do: module
  end

  defp tool_interceptor(_), do: nil

  defp base(context, state) do
    saved = state.checkpoint
    domain = if saved, do: Map.drop(saved.domain, [:result]), else: Map.get(context, :state, %{})
    history = if saved, do: saved.runtime.history_delta, else: []
    result = if saved, do: saved.domain[:result]

    reserved = [
      :result,
      :messages,
      :requests,
      Jido.AI.Configuration.key(),
      Jido.AI.Thread.Control.key()
    ]

    with true <- is_map(domain) and not is_struct(domain),
         true <- Enum.all?(Map.keys(domain), &(is_atom(&1) and &1 not in reserved)),
         :ok <- Jido.Action.validate_static_data(domain) do
      fields = Map.new(domain, fn {key, value} -> {key, Zoi.any() |> Zoi.default(value)} end)

      {:ok,
       %{
         schema:
           Zoi.object(
             Map.merge(fields, %{
               result: Zoi.any() |> Zoi.default(result),
               messages: Jido.AI.Thread.Projection.schema() |> Zoi.default(history_session(history))
             })
           )
       }}
    else
      _ -> {:error, :invalid_standalone_domain_state}
    end
  end

  defp query(%{checkpoint: nil, context: %Jido.Thread{entries: [entry]}}) do
    with {:ok, %{role: :user, content: content}} <- Jido.AI.Thread.Projection.message(entry),
         do: {:ok, content}
  end

  defp query(%{checkpoint: %{runtime: %{history_delta: entries}}}) do
    case Enum.find(entries, &(&1.role == :user)) do
      %{content: query} -> {:ok, query}
      _ -> {:error, :invalid_react_checkpoint}
    end
  end

  defp query(_), do: {:error, :checkpoint_phase_not_ported}

  defp relay(owner, monitor, ref, state, config, request, server_monitor) do
    id = request.id

    receive do
      {:jido_ai_request_event, %Event{request_id: ^id} = event} ->
        state = observe(state, event)
        data = Map.delete(event.data, :react_checkpoint)

        data =
          if is_map(data[:meta]),
            do: Map.update!(data, :meta, &Map.delete(&1, :react_checkpoint)),
            else: data

        send(owner, {:react_runner, ref, %{event | data: data}})

        if Request.Stream.terminal_kind?(event.kind) do
          state = snapshot(state, config, request.server, event)
          checkpoint(owner, ref, state, config)
        else
          relay(owner, monitor, ref, state, config, request, server_monitor)
        end

      {:DOWN, ^server_monitor, :process, _, reason} ->
        fail(owner, ref, state, config, {:standalone_agent_stopped, reason})

      {:react_checkpoint_ack, ^ref, event_id} ->
        case Server.children(request.server)[{:plugin, Jido.AI.Orchestration.Plugin}] do
          %{pid: runtime} ->
            # Completion can win the race with the consumer's next pull.
            # Its terminal event is already queued; a stale ack must not
            # replace that outcome with a second failure event.
            GenServer.call(runtime, {:checkpoint_ack, id, event_id})
            relay(owner, monitor, ref, state, config, request, server_monitor)

          _ ->
            fail(owner, ref, state, config, :standalone_agent_stopped)
        end

      {:react_cancel, ^ref} ->
        cancel(request, :consumer_halt)

      {:DOWN, ^monitor, :process, ^owner, _} ->
        cancel(request, :consumer_down)
    end
  end

  # A token's expiry controls later continuation, not the current live Flow.
  # Do not decode our own output to observe an event from the Orchestration.
  defp observe(state, event) do
    state = %{
      state
      | seq: event.seq,
        llm_call_id: event.llm_call_id,
        iteration: Map.get(event.data, :reasoning_iteration, state.iteration)
    }

    case event do
      %{kind: :llm_started} ->
        State.clear_streaming(state)

      %{kind: :llm_delta, data: %{chunk_type: :content, delta: text}} when is_binary(text) ->
        %{state | streaming_text: state.streaming_text <> text}

      %{kind: :llm_delta, data: %{chunk_type: :thinking, delta: text}} when is_binary(text) ->
        %{state | streaming_thinking: state.streaming_thinking <> text}

      %{kind: :llm_completed} ->
        %{
          state
          | llm_response_id: event.data.response_id,
            usage: Jido.AI.Usage.merge(state.usage, event.data.usage)
        }

      _ ->
        state
    end
  end

  defp history_session([]), do: nil

  defp history_session(history) do
    Jido.AI.Thread.Projection.append_entries(Jido.Session.new(), history)
  end

  defp snapshot(state, config, server, event) do
    agent = Server.agent(server)
    record = agent.state.requests[state.request_id]

    {:ok, profile} = Jido.AI.Configuration.profile(agent)
    # Native work can complete even when retention policy excludes part of its
    # history. Keep the omission marker; token export must then be withheld.
    {:ok, entries} = Jido.AI.Thread.Projection.project(agent.state[profile.memory.history] || Jido.Session.new())

    context = State.conversation(entries, config.system_prompt)

    status =
      case event.kind do
        :request_completed -> :completed
        :request_cancelled -> :cancelled
        :request_failed -> :failed
      end

    checkpoint =
      case record.meta[:react_checkpoint] do
        nil ->
          nil

        data ->
          %{
            data
            | domain:
                Map.drop(agent.state, [
                  :messages,
                  :requests,
                  Jido.AI.Configuration.key(),
                  Jido.AI.Thread.Control.key()
                ])
          }
      end

    %{
      state
      | status: status,
        checkpoint: checkpoint,
        iteration:
          if(checkpoint,
            do: Jido.AI.Runtime.State.iteration(checkpoint.runtime, checkpoint.phase),
            else: Map.get(record.meta, :reasoning_iteration, state.iteration)
          ),
        context: context,
        result: record.result,
        termination_reason:
          Map.get(
            record.meta,
            :termination_reason,
            if(status == :completed, do: :final_answer, else: status)
          ),
        error: record.error,
        output: Map.get(record.meta, :output, %{}),
        usage: Map.get(record.meta, :usage, state.usage),
        prev_tool_signature: Map.get(record.meta, :prev_tool_signature, state.prev_tool_signature),
        pending_tool_calls: []
    }
  end

  defp terminal(owner, ref, state, config) do
    {kind, data} =
      case state.status do
        :completed ->
          {:request_completed,
           %{
             result: state.result,
             usage: state.usage,
             output: state.output,
             termination_reason: state.termination_reason || :final_answer
           }}

        :failed ->
          {:request_failed, %{error: state.error, usage: state.usage}}

        :cancelled ->
          {:request_cancelled, %{reason: state.error || :cancelled, usage: state.usage}}
      end

    {state, event} = event(state, kind, data)
    send(owner, {:react_runner, ref, event})
    checkpoint(owner, ref, state, config)
  end

  defp fail(owner, ref, state, config, reason),
    do:
      terminal(
        owner,
        ref,
        state
        |> State.put_status(:failed)
        |> State.put_error(Jido.AI.Error.for_storage(reason))
        |> Map.put(:checkpoint, nil),
        config
      )

  defp checkpoint(owner, ref, state, config) do
    {state, event} = event(state, :checkpoint, %{reason: :terminal})

    token =
      if Jido.AI.Observe.Content.retainable?(state, config.observability),
        do: Token.issue(state, config)

    send(owner, {:react_runner, ref, %{event | data: Map.put(event.data, :token, token)}})
  end

  defp event(state, kind, data) do
    {state, seq} = State.bump_seq(state)

    {state,
     Event.new(%{
       seq: seq,
       run_id: state.run_id,
       request_id: state.request_id,
       iteration: state.iteration,
       llm_call_id: state.llm_call_id,
       kind: kind,
       data: Map.put(data, :reasoning_iteration, state.iteration)
     })}
  end

  defp stop(server) do
    if Process.alive?(server), do: Server.stop(server, :normal)
  catch
    :exit, _ -> :ok
  end

  defp cancel(request, reason) do
    Orchestration.cancel(request, reason: reason)
  catch
    :exit, _ -> :ok
  end
end
