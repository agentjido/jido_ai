defmodule Jido.AI.Orchestration do
  @moduledoc """
  Live request admission, control, inspection, and completion.

  `Jido.Session` is the portable interaction value. This module manages active
  work through core Agent and Plugin APIs; it does not define a Session value.
  `Jido.AI.Orchestration.Coordinator` keeps worker lifetime and ordered commits
  together. `Jido.AI.Execution` executes each prepared request.

  Agent topology and child process ownership belong to core Jido. Future
  delegation must link requests without treating a peer as a supervised child
  or sharing mutable conversation state. This module does not yet provide a
  delegation API.
  """
  alias Jido.AI.Request.{Handle, Stream}
  alias Jido.AI.Orchestration.Plugin

  @settle "jido.ai.request.settle"
  @cancel "jido.ai.request.cancel"
  @control "jido.ai.request.control"
  @history "jido.ai.request.history"
  @publish "jido.ai.request.publish"
  @ignore "jido.ai.request.ignore"
  @progress "jido.ai.request.progress"
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

  Content is excluded by default, including content in the returned Agent view.
  Both the Profile's `observability.diagnostics_content` permission and the
  caller option `include_content: true` are required to include it. This view
  is for inspection; use core AgentServer APIs to obtain a native checkpoint.
  `details.context` contains completed conversation, not pending input.

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
      {:ok, Jido.AI.Orchestration.Inspection.snapshot(snapshot, request, live, opts)}
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
    do: Jido.Signal.new!(@settle, %{request_id: id}, source: "/jido/ai/request")

  @doc false
  def routes([]), do: {:ok, []}

  def routes(_) do
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
  def caller_context(context) do
    # A fresh core Turn owns these fields. Keep caller policy/context, but do
    # not carry the old Turn's state snapshot or private AI runtime bindings.
    context
    |> Map.drop([:agent_id, :agent_state, :plugin_inputs, :signal, :state])
    |> Map.reject(fn {key, _} ->
      is_atom(key) and String.starts_with?(Atom.to_string(key), "jido_ai_")
    end)
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
  def admission_target(profile) do
    {:ok, {Jido.AI.Orchestration.Start, %{profile_id: profile.id}}}
  end

  @doc false
  def submit(server, signal, sink, opts) do
    id = signal.data.request_id
    timeout = Keyword.get(opts, :admission_timeout, 5_000)
    deadline = Keyword.get(opts, :admission_deadline)
    agent = Jido.AgentServer.agent(server, admission_remaining(deadline, timeout))
    method = Jido.AI.Orchestration.Binding.method(agent, signal)
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
    if Jido.AI.Execution.StateSize.error?(reason) do
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

    signal = Jido.Signal.new!(@cancel, data, source: "/jido/ai/request")

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
  def failed_metadata(meta, error) do
    if Map.has_key?(meta, :output),
      do: Map.update!(meta, :output, &Jido.AI.Output.mark_failed(&1, error)),
      else: meta
  end
end
