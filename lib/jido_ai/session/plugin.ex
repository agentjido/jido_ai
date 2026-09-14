defmodule Jido.AI.Session.Plugin do
  @moduledoc "Owns portable request records and starts work only after an admission commit."
  use Jido.Plugin,
    agent: Jido.AI.Session.Plugin.Agent,
    agent_server: Jido.AI.Session.Plugin.AgentServer

  alias Jido.AI.Session.Change

  @doc false
  def prepare_admission(runtime, admission, opts) do
    with :ok <- validate_request(admission, opts),
         do: read_admission(runtime, admission, opts)
  end

  defp validate_request(admission, opts) do
    resources = admission.caller_context[:jido_ai_request] || %{}
    allowed = resources[:allowed_tools]
    agent = struct(Jido.Agent, %{routes: Keyword.fetch!(opts, :routes)})
    binding = Jido.AI.Runtime.Binding.request(agent, admission.signal)

    if match?(%{mode: :session}, binding) and not is_nil(allowed) and is_nil(opts[:skills]) do
      with {:ok, profiles} <-
             Jido.AI.Configuration.profiles(
               Keyword.fetch!(opts, :profiles),
               admission.prepared_input.configuration
             ),
           profile = profiles[binding.id],
           {:ok, selected} <-
             if(is_nil(resources[:tools]),
               do: {:ok, profile.tools},
               else: Jido.AI.ToolCatalog.from_input(resources.tools, %{})
             ),
           {:ok, _} <-
             selected
             |> Map.new(&{&1.name, &1})
             |> Jido.AI.Reasoning.ReAct.ToolSelection.filter_allowed(allowed) do
        :ok
      end
    else
      :ok
    end
  end

  defp read_admission(runtime, admission, opts) do
    catalogs = if opts[:skills], do: GenServer.call(runtime, :skill_catalogs), else: %{}
    signal = admission.signal
    caller_context = admission.caller_context

    grant =
      if signal.type == Jido.AI.Session.publish_type() do
        case GenServer.call(
               runtime,
               {:claim_delivery, signal.data[:batch_id], caller_context[:jido_ai_delivery_ticket]}
             ) do
          {:ok, grant} -> grant
          _ -> nil
        end
      end

    completion =
      if signal.type == Jido.AI.Session.settle_type(),
        do: GenServer.call(runtime, {:completion, signal.data[:request_id]}),
        else: nil

    metadata =
      if signal.type == Jido.AI.Session.cancel_type(),
        do: GenServer.call(runtime, {:metadata_snapshot, signal.data[:request_id]}),
        else: %{meta: %{}, inspection: %{}}

    progress =
      if signal.type == Jido.AI.Session.progress_type(),
        do:
          GenServer.call(runtime, {
            :claim_selection,
            signal.data[:request_id],
            signal.data[:run_id],
            signal.data[:ticket]
          }),
        else: nil

    batch =
      if signal.type == Jido.AI.Session.history_type(),
        do:
          GenServer.call(
            runtime,
            {:history_batch, signal.data[:request_id], signal.data[:batch_id]}
          ),
        else: nil

    {:ok,
     %{
       jido_ai_skill_catalogs: catalogs,
       jido_ai_delivery_grant: grant,
       jido_ai_completion: completion,
       jido_ai_request_metadata: metadata.meta,
       jido_ai_request_inspection: metadata.inspection,
       jido_ai_progress: progress,
       jido_ai_history_batch: batch,
       jido_ai_session_runtime: runtime
     }}
  end

  @doc false
  def context(context) do
    with {:ok, context} <- Jido.AI.Runtime.Plugin.context(context) do
      case get_in(context, [:plugin_inputs, __MODULE__]) do
        %Jido.Plugin.Input{runtime: input} when is_map(input) ->
          context = Map.merge(context, input)
          command = %Jido.Agent.Command{agent: context.jido_ai_agent, signal: context.signal, context: context}

          case prepare_command(command) do
            {:ok, prepared} -> {:ok, prepared.context}
            {:error, _} = error -> error
          end

        _ ->
          {:ok, context}
      end
    end
  end

  @doc false
  def prepare_command(command) do
    # A work task gets the admission snapshot, never a caller-supplied snapshot.
    # Read the declared route binding, not profile_id supplied in Signal data.
    binding = Jido.AI.Runtime.Binding.request(command.agent, command.signal)
    profile_id = if match?(%{mode: :session}, binding), do: binding.id

    context =
      command.context
      |> Map.put(:jido_ai_snapshot, command.agent.state)
      |> Map.put(:jido_ai_domain_schema, command.agent.schema)
      |> Map.put(:jido_ai_admission_profile, profile_id)

    if profile_id do
      resources = Map.get(context, :jido_ai_request, %{})
      catalogs = Map.get(context, :jido_ai_skill_catalogs, %{})

      with {:ok, profiles} <-
             Jido.AI.Skill.Source.profiles(
               context.jido_ai_profiles,
               catalogs,
               Map.get(context, :jido_ai_tool_defaults, %{})
             ),
           context =
             context
             |> Map.put(:jido_ai_profiles, profiles)
             |> Jido.AI.Skill.Source.context(binding, catalogs),
           {:ok, profile} <-
             Jido.AI.Session.RequestScope.profile(
               profiles[profile_id],
               resources,
               context
             ) do
        {:ok, %{command | context: put_in(context.jido_ai_profiles[profile_id], profile)}}
      end
    else
      {:ok, %{command | context: context}}
    end
  end

  @doc false
  def reduce_records(records, changes) do
    changes = Enum.filter(changes, &match?(%Change{}, &1))

    Enum.reduce_while(changes, {:ok, records}, fn %Change{operation: op, record: record}, {:ok, records} ->
      current = records[record.id]

      valid =
        case op do
          :start ->
            is_nil(current) and not Enum.any?(records, fn {_, r} -> r.status == :pending end)

          op when op in [:finish, :control, :history, :progress] ->
            match?(%{status: :pending}, current) and current.run_id == record.run_id
        end

      if valid do
        records = Map.put(records, record.id, record)
        # Never evict pending work. Stable ID order breaks equal-clock ties.
        {pending, terminal} = Enum.split_with(records, fn {_, r} -> r.status == :pending end)

        retained =
          Enum.sort_by(terminal, fn {id, r} -> {r.inserted_at, id} end, :desc)
          |> Enum.take(max(record.max_requests - length(pending), 0))

        {:cont, {:ok, Map.new(pending ++ retained)}}
      else
        {:halt, {:error, :stale_request}}
      end
    end)
  end

  @doc false
  def dispatch_directive(
        runtime,
        %Jido.AI.Session.DeliveryReceipt{batch_id: id, ticket: receipt_ticket},
        context
      ) do
    ticket = receipt_ticket || get_in(context.turn_context, [:jido_ai_delivery_grant, :ticket])

    if is_binary(ticket) do
      GenServer.call(runtime, {:delivery_receipt, id, ticket})
    else
      {:error, :invalid_delivery_grant}
    end
  end

  def dispatch_directive(runtime, %Change{operation: :start, record: record} = change, context) do
    server = GenServer.call(runtime, :agent_server)
    committed = Jido.AgentServer.agent(server)

    with {:ok, profile} <- Jido.AI.Configuration.profile(committed, record.profile_id),
         snapshot = %{committed | state: start_snapshot(committed.state, profile, record)},
         {Jido.AI.Runtime.Plugin, opts} <-
           Enum.find(snapshot.plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin)),
         command = %Jido.Agent.Command{
           agent: snapshot,
           signal: context.effective_signal,
           context: context.turn_context
         },
         {:ok, command} <- Jido.AI.Runtime.Plugin.prepare_command(command, opts),
         catalogs = GenServer.call(runtime, :skill_catalogs),
         command = %{command | context: Map.put(command.context, :jido_ai_skill_catalogs, catalogs)},
         {:ok, command} <- prepare_command(command) do
      turn_context =
        command.context
        |> Map.put(:jido_ai_session_runtime, runtime)

      turn_context =
        case Jido.AI.Plugins.Quota.binding_for_agent(snapshot, context.effective_signal) do
          nil -> turn_context
          binding -> Map.put(turn_context, :jido_ai_quota, binding)
        end

      GenServer.call(runtime, {:dispatch, change, %{context | turn_context: turn_context}})
    else
      nil -> {:error, :missing_ai_runtime_plugin}
      {:error, _} = error -> error
    end
  end

  def dispatch_directive(runtime, change, context),
    do: GenServer.call(runtime, {:dispatch, change, context})

  defp start_snapshot(state, profile, record) do
    state = update_in(state, [:requests], &Map.delete(&1, record.id))

    case profile.memory.history do
      nil ->
        state

      field ->
        update_in(state, [field], fn entries ->
          entries
          |> Enum.reverse()
          |> Enum.drop_while(&(get_in(&1, [:refs, :request_id]) == record.id))
          |> Enum.reverse()
        end)
    end
  end
end
