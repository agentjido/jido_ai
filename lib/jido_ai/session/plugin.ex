defmodule Jido.AI.Session.Plugin do
  @moduledoc "Owns portable request records and starts work only after an admission commit."
  use Jido.Plugin
  alias Jido.AI.Session.{Change, Runtime}

  def child_spec(init), do: Supervisor.child_spec({Runtime, init}, id: __MODULE__)
  def await_ready(runtime, _), do: GenServer.call(runtime, :ready)
  def state_spec(_), do: {:requests, Jido.AI.Session.Record.records_schema()}
  def directives(_), do: [Change, Jido.AI.Session.DeliveryReceipt]

  def validate_directive(%Change{} = change, _) do
    with {:ok, change} <- Zoi.parse(Change.schema(), change),
         :ok <- Jido.Action.validate_static_data(change),
         do: {:ok, change}
  end

  def validate_directive(%Jido.AI.Session.DeliveryReceipt{} = receipt, _),
    do: Zoi.parse(Jido.AI.Session.DeliveryReceipt.schema(), receipt)

  def admit(runtime, command, opts) do
    catalogs = if opts[:skills], do: GenServer.call(runtime, :skill_catalogs), else: %{}
    command = %{command | context: Map.put(command.context, :jido_ai_skill_catalogs, catalogs)}

    grant =
      if command.signal.type == Jido.AI.Session.publish_type() do
        case GenServer.call(
               runtime,
               {:claim_delivery, command.signal.data[:batch_id], command.context[:jido_ai_delivery_ticket]}
             ) do
          {:ok, grant} -> grant
          _ -> nil
        end
      end

    command = %{command | context: Map.put(command.context, :jido_ai_delivery_grant, grant)}

    completion =
      if command.signal.type == Jido.AI.Session.settle_type(),
        do: GenServer.call(runtime, {:completion, command.signal.data[:request_id]}),
        else: nil

    metadata =
      if command.signal.type in [
           Jido.AI.Session.cancel_type(),
           "ai.react.cancel",
           "ai.cot.cancel",
           "ai.cod.cancel",
           "ai.aot.cancel",
           "ai.tot.cancel",
           "ai.got.cancel",
           "ai.trm.cancel",
           "ai.adaptive.cancel"
         ],
         do: GenServer.call(runtime, {:metadata_snapshot, command.signal.data[:request_id]}),
         else: %{meta: %{}, inspection: %{}}

    progress =
      if command.signal.type == Jido.AI.Session.progress_type(),
        do:
          GenServer.call(runtime, {
            :claim_selection,
            command.signal.data[:request_id],
            command.signal.data[:run_id],
            command.signal.data[:ticket]
          }),
        else: nil

    context =
      command.context
      |> Map.put(:jido_ai_completion, completion)
      |> Map.put(:jido_ai_request_metadata, metadata.meta)
      |> Map.put(:jido_ai_request_inspection, metadata.inspection)
      |> Map.put(:jido_ai_progress, progress)

    batch =
      if command.signal.type == Jido.AI.Session.history_type(),
        do:
          GenServer.call(
            runtime,
            {:history_batch, command.signal.data[:request_id], command.signal.data[:batch_id]}
          ),
        else: nil

    context =
      context
      |> Map.put(:jido_ai_history_batch, batch)
      |> Map.put(:jido_ai_session_runtime, runtime)

    {:ok, %{command | context: context}}
  end

  def prepare(command, _) do
    command = ignore_unhandled_observation(command)
    # A work task gets the admission snapshot, never a caller-supplied snapshot.
    # Read the declared route binding, not profile_id supplied in Signal data.
    binding = Jido.AI.Authoring.request_binding(command.agent, command.signal)
    profile_id = if match?(%{mode: :session}, binding), do: binding.id

    context =
      command.context
      |> Map.put(:jido_ai_snapshot, command.agent.state)
      |> Map.put(:jido_ai_domain_schema, command.agent.schema)
      |> Map.put(:jido_ai_admission_profile, profile_id)

    if profile_id do
      resources = Map.get(context, :jido_ai_request, %{})

      with {:ok, profile} <-
             Jido.AI.Session.RequestScope.profile(
               context.jido_ai_profiles[profile_id],
               resources,
               context
             ) do
        {:ok, %{command | context: put_in(context.jido_ai_profiles[profile_id], profile)}}
      end
    else
      {:ok, %{command | context: context}}
    end
  end

  def update_state(records, changes, _) do
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

  def dispatch(runtime, %Jido.AI.Session.DeliveryReceipt{batch_id: id}, context, _) do
    case context.turn_context[:jido_ai_delivery_grant] do
      %{id: ^id, ticket: ticket} -> GenServer.call(runtime, {:delivery_receipt, id, ticket})
      _ -> {:error, :invalid_delivery_grant}
    end
  end

  def dispatch(runtime, change, context, _),
    do: GenServer.call(runtime, {:dispatch, change, context})

  # Core Emit defaults to the same Agent when no dispatch target is set. Give
  # unhandled AI observations a no-op target without overriding host routes.
  defp ignore_unhandled_observation(command) do
    if command.signal.type in [
         "ai.request.started",
         "ai.request.completed",
         "ai.request.failed",
         "ai.llm.delta",
         "ai.llm.response",
         "ai.usage",
         "ai.tool.started",
         "ai.tool.result"
       ] do
      with {:ok, router} <- Jido.Signal.Router.new(command.agent.routes),
           {:error, _} <- Jido.Signal.Router.route(router, command.signal) do
        %{command | signal: %{command.signal | type: Jido.AI.Session.ignore_type()}}
      else
        _ -> command
      end
    else
      command
    end
  end
end
