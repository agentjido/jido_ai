defmodule Jido.AI.Orchestration do
  @moduledoc """
  Live request admission, control, inspection, and completion.

  `Jido.Session` is the portable interaction value. This module manages active
  work through core Agent and Plugin APIs; it does not define a Session value.
  `Jido.AI.Orchestration.Coordinator` keeps worker lifetime and ordered commits
  together. `Jido.AI.Runtime` executes each prepared request.

  Agent topology and child process ownership belong to core Jido. Future
  delegation must link requests without treating a peer as a supervised child
  or sharing mutable conversation state. This module does not yet provide a
  delegation API.
  """
  alias Jido.AI.Request.{Handle, Stream}
  alias Jido.AI.Orchestration.Plugin

  @settle "jido.ai.session.settle"
  @cancel "jido.ai.session.cancel"
  @control "jido.ai.session.control"
  @history "jido.ai.session.history"
  @publish "jido.ai.session.publish"
  @ignore "jido.ai.session.ignore"
  @progress "jido.ai.session.progress"
  @observations [
    "ai.request.started",
    "ai.request.completed",
    "ai.request.failed",
    "ai.llm.delta",
    "ai.llm.response",
    "ai.usage",
    "ai.tool.started",
    "ai.tool.result"
  ]

  @doc """
  Reads a committed Agent revision and the selected request's inspection data.

  `:request_id` selects a retained request. The default selects pending work,
  then the latest retained request. `:live` contains a later sample from the
  matching Session run; it does not change the committed request record.
  Live process identifiers are never stored in Agent state.

  `details.trace` is an observed event prefix. Its `seq` is the last sampled
  sequence, including events omitted by the 2,000-event cap. History commits
  save active prefixes; completion saves the final sampled prefix. The request
  record proves the committed outcome. Its later terminal stream event need
  not be in that prefix. State-size limits can omit trace data and set
  `truncated?`. This API does not provide a durable event log or delivery receipt.
  """
  def snapshot(server, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    snapshot = Jido.AgentServer.snapshot(server, timeout)
    request = Jido.AI.Orchestration.Inspection.selected(snapshot.agent, opts[:request_id])

    if opts[:request_id] && is_nil(request) do
      {:error, :request_not_found}
    else
      live = live_inspection(server, request, timeout)
      {:ok, Jido.AI.Orchestration.Inspection.snapshot(snapshot, request, live)}
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :agent_server_unavailable}
  end

  defp live_inspection(server, %{status: :pending} = request, timeout) do
    case Jido.AgentServer.children(server, timeout)[{:plugin, Plugin}] do
      %{pid: runtime} -> GenServer.call(runtime, {:inspect, request.id, request.run_id}, timeout)
      _ -> nil
    end
  catch
    :exit, _ -> nil
  end

  defp live_inspection(_, _, _), do: nil

  @doc "Applies a context replace or switch operation, or defers it until the active request finishes."
  def modify_context(server, operation, opts \\ []),
    do: Jido.AI.Thread.Control.live(server, operation, opts)

  @doc "Reads the live automatic skill catalogue and discovery diagnostics for one profile."
  def skill_catalog(server, profile_id \\ nil) do
    with {:ok, profile} <-
           Jido.AI.Configuration.profile(Jido.AgentServer.agent(server), profile_id),
         %{pid: runtime} <- Jido.AgentServer.children(server)[{:plugin, Plugin}],
         %{specs: _} = catalog <- GenServer.call(runtime, :skill_catalogs)[profile.id] do
      {:ok, Map.take(catalog, [:specs, :index, :diagnostics]) |> Map.put(:profile_id, profile.id)}
    else
      {:error, _} = error -> error
      _ -> {:error, :automatic_skills_disabled}
    end
  catch
    :exit, _ -> {:error, :agent_server_unavailable}
  end

  @doc false
  def publish_type, do: @publish
  @doc false
  def ignore_type, do: @ignore
  @doc false
  def observation_type?(type), do: type in @observations

  @doc "Reads transient Signal delivery status. A committed answer does not prove delivery."
  def delivery_status(server, request_id) do
    case Jido.AgentServer.children(server)[{:plugin, Plugin}] do
      %{pid: runtime} -> GenServer.call(runtime, {:delivery_status, request_id})
      _ -> {:error, :signal_delivery_unavailable}
    end
  catch
    :exit, _ -> {:error, :signal_delivery_unavailable}
  end

  @doc false
  def settle_signal(id),
    do: Jido.Signal.new!(@settle, %{request_id: id}, source: "/jido/ai/session")

  @doc false
  def routes([]), do: {:ok, []}

  def routes(_) do
    Enum.each(
      [
        Jido.AI.Orchestration.Settle,
        Jido.AI.Orchestration.Cancel,
        Jido.AI.Orchestration.ControlAction,
        Jido.AI.Orchestration.HistoryAction,
        Jido.AI.Orchestration.Publish,
        Jido.AI.Orchestration.IgnoreSignal,
        Jido.AI.Orchestration.Progress,
        Plugin
      ],
      &Code.ensure_compiled!/1
    )

    with {:ok, settle} <- Jido.Agent.Authoring.route(@settle, Jido.AI.Orchestration.Settle, []),
         {:ok, cancel} <- Jido.Agent.Authoring.route(@cancel, Jido.AI.Orchestration.Cancel, []),
         {:ok, control} <- Jido.Agent.Authoring.route(@control, Jido.AI.Orchestration.ControlAction, []),
         {:ok, history} <- Jido.Agent.Authoring.route(@history, Jido.AI.Orchestration.HistoryAction, []),
         {:ok, publish} <- Jido.Agent.Authoring.route(@publish, Jido.AI.Orchestration.Publish, []),
         {:ok, ignore} <- Jido.Agent.Authoring.route(@ignore, Jido.AI.Orchestration.IgnoreSignal, []),
         {:ok, progress} <- Jido.Agent.Authoring.route(@progress, Jido.AI.Orchestration.Progress, []),
         {:ok, observations} <-
           Jido.AI.Profile.traverse(
             @observations,
             &Jido.Agent.Authoring.route(&1, Jido.AI.Orchestration.IgnoreSignal, [])
           ),
         do: {:ok, [settle, cancel, control, history, publish, ignore, progress] ++ observations}
  end

  @doc false
  def settle_type, do: @settle
  @doc false
  def cancel_type, do: @cancel
  @doc false
  def history_type, do: @history
  @doc false
  def progress_type, do: @progress

  @doc false
  def publish_selection(_, nil, _), do: :ok

  def publish_selection(
        %{jido_ai_events: {runtime, id, run_id}, jido_ai_server: server} = context,
        selection,
        deadline
      ) do
    with {:ok, ticket} <- GenServer.call(runtime, {:stage_selection, id, run_id, selection}),
         signal =
           Jido.Signal.new!(@progress, %{request_id: id, run_id: run_id, ticket: ticket}, source: "/jido/ai/session"),
         {:ok, _} <- commit_progress(server, signal, caller_context(context), deadline) do
      :ok
    end
  catch
    :exit, {:timeout, _} -> {:error, :progress_commit_timeout}
    :exit, _ -> {:error, :progress_owner_unavailable}
  end

  def publish_selection(_, _, _), do: :ok

  @doc false
  def caller_context(context) do
    # A fresh core Turn owns these fields. Keep caller policy/context, but do
    # not carry the old Turn's state snapshot or private AI runtime bindings.
    context
    |> Map.drop([:agent_id, :agent_state, :plugin_inputs, :signal, :state])
    |> Map.reject(fn {key, _} ->
      is_atom(key) and String.starts_with?(Atom.to_string(key), "jido_ai_")
    end)
  end

  defp commit_progress(server, signal, context, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      case Jido.AgentServer.call(server, signal, context: context, timeout: remaining) do
        {:error, reason}
        when reason in [:busy, :reentrant_turn, :reentrant_admission, :reentrant_directive] ->
          Process.sleep(min(10, remaining))
          commit_progress(server, signal, context, deadline)

        result ->
          result
      end
    else
      {:error, :progress_commit_timeout}
    end
  end

  @doc "Queues visible user text for the active request. A queued result does not prove consumption."
  def steer(server, content, opts \\ []), do: control(server, content, :steer, opts, :ack)
  @doc "Queues visible peer input with the same rules as steer/3."
  def inject(server, content, opts \\ []), do: control(server, content, :inject, opts, :ack)

  @doc false
  def control_agent(server, content, kind, opts) when kind in [:steer, :inject],
    do: control(server, content, kind, opts, :agent)

  defp control(%Handle{server: server, id: id}, content, kind, opts, format),
    do: control(server, content, kind, Keyword.put_new(opts, :expected_request_id, id), format)

  defp control(server, content, kind, opts, format) when is_binary(content) do
    id = Jido.Signal.ID.generate!()

    data = %{
      control_id: id,
      kind: kind,
      content: content,
      expected_request_id: opts[:expected_request_id],
      source: Keyword.get(opts, :source, "/ai/react"),
      extra_refs: Keyword.get(opts, :extra_refs, %{})
    }

    signal = Jido.Signal.new!(@control, data, source: "/ai/react")

    case Jido.AgentServer.call(server, signal, Keyword.get(opts, :timeout, 5_000)) do
      {:ok, agent} ->
        case Enum.find_value(agent.state.requests, fn {_, r} ->
               if r.last_control && r.last_control.control_id == id, do: r.last_control
             end) do
          nil -> {:error, :unknown_control_result}
          result -> {:ok, if(format == :agent, do: agent, else: result)}
        end

      {:error, %{details: %{control: result}}} ->
        {:error, if(format == :agent, do: {:rejected, result.reason}, else: result)}

      {:error, _} = error ->
        error
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :agent_server_unavailable}
  end

  defp control(_, _, _, _, _), do: {:error, :invalid_content}

  @doc false
  def publish_history(%{jido_ai_events: {runtime, id, run_id}, jido_ai_server: server}, entries) do
    with {:ok, batch_id} <- GenServer.call(runtime, {:stage_history, id, run_id, entries}),
         signal =
           Jido.Signal.new!(@history, %{request_id: id, batch_id: batch_id}, source: "/jido/ai/session"),
         {:ok, _} <- commit_history(server, signal, System.monotonic_time(:millisecond) + 5_000),
         do: :ok
  end

  # History comes from an independent session task. The core's monitor-graph
  # reentry guard can relate that task to an unrelated active Turn. These three
  # errors reject before execution, so the same history batch can be retried.
  # A timeout has an unknown commit result and must not be retried here.
  defp commit_history(server, signal, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining > 0 do
      case Jido.AgentServer.call(server, signal, remaining) do
        {:error, reason}
        when reason in [:reentrant_turn, :reentrant_admission, :reentrant_directive] ->
          Process.sleep(min(10, remaining))
          commit_history(server, signal, deadline)

        result ->
          result
      end
    else
      {:error, :history_commit_timeout}
    end
  end

  @doc false
  def admission_target(profile) do
    Code.ensure_compiled!(Jido.AI.Orchestration.Start)
    {:ok, {Jido.AI.Orchestration.Start, %{profile_id: profile.id}}}
  end

  @doc false
  def submit(server, signal, sink, opts) do
    id = signal.data.request_id
    timeout = Keyword.get(opts, :admission_timeout, 5_000)
    deadline = Keyword.get(opts, :admission_deadline)
    agent = Jido.AgentServer.agent(server, admission_remaining(deadline, timeout))
    method = Jido.AI.Runtime.Binding.method(agent, signal)
    # These values can contain runtime resources. They do not enter Signal data.
    {portable, resources} = Map.split(signal.data, [:request_id, :query, :prompt, :extra_refs])

    with {:ok, context} <- Jido.Agent.Command.normalize_context(Keyword.get(opts, :context, %{})),
         context = Map.put(context, :jido_ai_request, resources),
         :ok <- session_declared(agent),
         :ok <- admission_open(deadline),
         {:ok, agent} <-
           Jido.AgentServer.call(server, %{signal | data: portable},
             context: context,
             timeout: admission_remaining(deadline, timeout)
           ),
         %{id: ^id} <- get_in(agent.state, [:requests, id]) do
      {:ok, Handle.new(id, server, signal.data.query)}
    else
      {:error, reason} ->
        reason = admission_error(reason)
        # A repeated ID belongs to the original stream. Do not terminate it.
        unless duplicate?(reason),
          do: Stream.send_event(sink, Stream.failed_event(id, reason, method: method))

        {:error, reason}

      _ ->
        Stream.send_event(sink, Stream.failed_event(id, :request_not_admitted, method: method))
        {:error, :request_not_admitted}
    end
  end

  defp admission_open(nil), do: :ok

  defp admission_open(deadline),
    do: if(deadline > System.monotonic_time(:millisecond), do: :ok, else: {:error, :timeout})

  defp admission_remaining(nil, timeout), do: timeout

  defp admission_remaining(deadline, _timeout),
    do: max(deadline - System.monotonic_time(:millisecond), 0)

  defp session_declared(agent) do
    if Enum.any?(agent.plugins, &(elem(&1, 0) == Plugin)),
      do: :ok,
      else: {:error, {:plugin_not_declared, Plugin}}
  end

  # Busy can be refused by core before a turn, or by Start after a pending
  # request is read. Both are the same request-admission result for callers.
  defp admission_error(%Jido.Action.Error.ExecutionFailureError{details: %{reason: :busy}}),
    do: :busy

  defp admission_error(reason) do
    if Jido.AI.Runtime.StateSize.error?(reason) do
      Jido.Error.validation_error("Agent state exceeds max_state_size", kind: :state_size)
    else
      reason
    end
  end

  defp duplicate?(:duplicate_request), do: true

  defp duplicate?(%Jido.Action.Error.ExecutionFailureError{
         details: %{reason: :duplicate_request}
       }),
       do: true

  defp duplicate?(_), do: false

  @doc "Cancels an accepted request. The cancellation Turn commits before its task stops."
  def cancel(%Handle{id: id, server: server}, opts \\ []) do
    data =
      if Keyword.has_key?(opts, :reason),
        do: %{request_id: id, reason: opts[:reason]},
        else: %{request_id: id}

    signal = Jido.Signal.new!(@cancel, data, source: "/jido/ai/session")

    case Jido.AgentServer.call(server, signal, Keyword.get(opts, :timeout, 5_000)) do
      {:ok, _} -> :ok
      {:error, _} = error -> error
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :agent_server_unavailable}
  end

  @doc false
  def await(server, id, timeout)
      when timeout == :infinity or (is_integer(timeout) and timeout >= 0) do
    deadline =
      if timeout == :infinity, do: :infinity, else: System.monotonic_time(:millisecond) + timeout

    poll(server, id, deadline)
  end

  def await(_, _, _), do: {:error, :invalid_timeout}

  defp poll(server, id, deadline) do
    remaining =
      if deadline == :infinity,
        do: 5_000,
        else: max(deadline - System.monotonic_time(:millisecond), 0)

    with {:ok, records} <- Jido.AgentServer.plugin_state(server, Plugin, max(remaining, 1)) do
      case Map.get(records, id) do
        nil ->
          {:error, :request_not_found}

        %{status: :pending, run_id: run_id} ->
          case completion_failure(server, id, run_id, max(remaining, 1)) do
            nil when remaining == 0 ->
              {:error, :timeout}

            nil ->
              Process.sleep(min(remaining, 20))
              poll(server, id, deadline)

            failure ->
              {:error, failure}
          end

        record ->
          {:ok, record}
      end
    end
  catch
    :exit, {:timeout, _} -> {:error, :timeout}
    :exit, _ -> {:error, :agent_server_unavailable}
  end

  # An owner cannot commit through a Plugin that rejects every completion.
  # Keep the real record pending, but expose the observed terminal failure.
  # A restarting owner is transient; the next poll reads its recovered state.
  defp completion_failure(server, id, run_id, timeout) do
    case Jido.AgentServer.children(server, timeout)[{:plugin, Plugin}] do
      %{pid: runtime} when is_pid(runtime) ->
        GenServer.call(runtime, {:completion_status, id, run_id}, timeout)

      _ ->
        nil
    end
  catch
    :exit, _ -> nil
  end

  @doc false
  def inspect_reasoning(_context, nil), do: :ok

  def inspect_reasoning(context, data) do
    case context[:jido_ai_events] do
      {runtime, id, run_id} -> GenServer.call(runtime, {:inspect_reasoning, id, run_id, data})
      _ -> :ok
    end
  end

  @doc false
  def reasoning_iteration(context, iteration) do
    case context[:jido_ai_events] do
      {runtime, id, run_id} ->
        GenServer.call(runtime, {:reasoning_iteration, id, run_id, iteration})

      _ ->
        :ok
    end
  end

  @doc false
  def failure_type(context, type) do
    case context[:jido_ai_events] do
      {runtime, id, run_id} -> GenServer.call(runtime, {:failure_type, id, run_id, type})
      _ -> :ok
    end
  end

  @doc false
  def account(context, usage) do
    case Map.get(context, :jido_ai_events) do
      {runtime, id, run_id} -> GenServer.call(runtime, {:usage, id, run_id, usage})
      nil -> :ok
    end
  end

  @doc false
  def failed_metadata(meta, error) do
    if Map.has_key?(meta, :output),
      do: Map.update!(meta, :output, &Jido.AI.Output.mark_failed(&1, error)),
      else: meta
  end

  @doc false
  def output(context, kind, meta, data) do
    case Map.get(context, :jido_ai_events) do
      {runtime, id, run_id} ->
        GenServer.call(runtime, {:output, id, run_id, kind, meta, data})

      nil ->
        event = Map.merge(context.jido_ai_output_event, %{kind: kind, data: data})

        Jido.AI.Runtime.Telemetry.emit(
          event,
          event.observability,
          context[:jido_ai_agent_id],
          event.model
        )
    end
  end

  @doc false
  def event_state(context) do
    case Map.get(context, :jido_ai_events) do
      {runtime, id, run_id} -> GenServer.call(runtime, {:event_state, id, run_id})
      nil -> %{}
    end
  end

  @doc false
  def activity(context, value \\ :progress) do
    case Map.get(context, :jido_ai_events) do
      {runtime, id, run_id} -> GenServer.call(runtime, {:activity, id, run_id, value})
      nil -> :ok
    end
  end

  @doc false
  def tool_signature(context, signature) do
    case Map.get(context, :jido_ai_events) do
      {runtime, id, run_id} -> GenServer.call(runtime, {:tool_signature, id, run_id, signature})
      nil -> :ok
    end
  end

  @doc false
  def emit(context, kind, data \\ %{}) do
    case Map.get(context, :jido_ai_events) do
      {runtime, id, run_id} -> GenServer.call(runtime, {:event, id, run_id, kind, data})
      nil -> :ok
    end
  end
end
