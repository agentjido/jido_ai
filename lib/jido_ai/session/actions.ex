defmodule Jido.AI.Session.Record do
  @moduledoc false
  @schema Zoi.object(
            %{
              id: Zoi.string() |> Zoi.min(1),
              run_id: Zoi.string() |> Zoi.min(1),
              profile_id: Zoi.atom(),
              method: Zoi.atom() |> Zoi.default(:react),
              query: Jido.AI.Query.schema(),
              status: Zoi.enum([:pending, :completed, :failed]),
              result: Zoi.any() |> Zoi.default(nil),
              error: Zoi.any() |> Zoi.default(nil),
              inserted_at: Zoi.integer(),
              completed_at: Zoi.integer() |> Zoi.nullable(),
              streamed: Zoi.boolean(),
              max_requests: Zoi.integer() |> Zoi.min(1),
              extra_refs: Zoi.map() |> Zoi.default(%{}),
              meta: Zoi.map() |> Zoi.default(%{}),
              inspection: Zoi.map() |> Zoi.default(%{}),
              completion_reserve: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
              last_control: Zoi.map() |> Zoi.nullable() |> Zoi.default(nil)
            },
            unrecognized_keys: :error
          )
  def schema, do: @schema

  # Reserve real state bytes while work is pending. A failed completion can
  # release them for a small terminal record, even when other state is full.
  def completion_reserve, do: String.duplicate(" ", 512)

  def records_schema,
    do:
      Zoi.map(Zoi.string() |> Zoi.min(1), @schema)
      |> Zoi.refine({__MODULE__, :portable_records, []})
      |> Zoi.default(%{})

  def portable_records(records, _) do
    with true <- Enum.all?(records, fn {id, record} -> id == record.id end),
         :ok <- Jido.Action.validate_static_data(records) do
      :ok
    else
      _ -> {:error, "Request records must have matching IDs and portable values"}
    end
  end
end

defmodule Jido.AI.Session.Change do
  @moduledoc false
  @schema Zoi.struct(
            __MODULE__,
            %{
              operation: Zoi.enum([:start, :finish, :control, :history, :progress]),
              record: Jido.AI.Session.Record.schema(),
              batch_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil)
            },
            coerce: true
          )
  defstruct Zoi.Struct.struct_fields(@schema)
  def schema, do: @schema
end

defmodule Jido.AI.Session.Start do
  @moduledoc false
  use Jido.Action,
    name: "ai_session_start",
    schema: Zoi.object(%{query: Jido.AI.Query.schema(), request_id: Zoi.string() |> Zoi.min(1)})

  alias Jido.AI.{Profile, Request}
  alias Jido.AI.Session.Change

  def run(%{request_id: id, query: query}, context) do
    profile_id = context.jido_ai_admission_profile
    records = context.agent_state.requests
    profile = context.jido_ai_profiles[profile_id]
    resources = Map.get(context, :jido_ai_request, %{})
    run_id = Map.get_lazy(resources, :run_id, &Jido.Signal.ID.generate!/0)

    unsupported =
      Map.keys(resources) --
        [
          :stream_to,
          :run_id,
          :model,
          :tool_context,
          :llm_opts,
          :req_http_options,
          :tools,
          :allowed_tools,
          :output,
          :max_iterations,
          :stream_timeout_ms,
          :tool_heartbeat_ms,
          :request_transformer
        ]

    cond do
      Map.has_key?(records, id) ->
        {:error, :duplicate_request}

      Enum.any?(records, fn {_, r} -> r.status == :pending end) ->
        {:error, :busy}

      profile.requests.mode != :session ->
        {:error, :not_a_session_profile}

      unsupported != [] ->
        Profile.error("request", "Request options are not yet ported: #{inspect(unsupported)}")

      true ->
        with {:ok, sink} <- Request.Stream.normalize_sink(resources[:stream_to]),
             :ok <- options(resources),
             :ok <- Jido.AI.Skill.Runtime.request_options(resources),
             :ok <- Jido.AI.Reasoning.ReAct.Checkpoint.admission(context, id, run_id) do
          record = %{
            id: id,
            run_id: run_id,
            profile_id: profile_id,
            method: profile.reasoning.method,
            query: query,
            status: :pending,
            result: nil,
            error: nil,
            inserted_at: System.system_time(:millisecond),
            completed_at: nil,
            completion_reserve: Jido.AI.Session.Record.completion_reserve(),
            streamed: sink != nil,
            max_requests: profile.requests.max_requests,
            extra_refs: Map.get(context.signal.data, :extra_refs, %{}),
            meta: checkpoint_metadata(context),
            inspection: %{}
          }

          with {:ok, candidate} <- start_history(context, profile, record) do
            changes = context_changes(context, candidate, profile, record)
            candidate = Jido.AI.Agent.StateProjection.apply(candidate, record, context)
            {:ok, candidate, [%Change{operation: :start, record: record} | changes]}
          end
        end
    end
  end

  defp context_changes(_, _, %{memory: %{history: nil}}, _), do: []

  defp context_changes(context, candidate, profile, record) do
    if Jido.AI.Reasoning.ReAct.Checkpoint.resumed?(context) do
      []
    else
      field = profile.memory.history
      entries = Enum.drop(candidate[field], length(context.agent_state[field]))

      Jido.AI.Context.Operations.capture(
        context.agent_state,
        profile,
        entries,
        context.jido_ai_agent.id,
        record
      )
    end
  end

  defp start_history(context, profile, record) do
    if Jido.AI.Reasoning.ReAct.Checkpoint.resumed?(context),
      do: {:ok, context.agent_state},
      else: Jido.AI.History.start(context.agent_state, profile, record, context.signal.source)
  end

  defp checkpoint_metadata(context) do
    case context[:jido_ai_checkpoint] do
      %{state: state} -> Jido.AI.Reasoning.ReAct.Checkpoint.metadata(state)
      _ -> %{}
    end
  end

  defp options(resources) do
    llm = Map.get(resources, :llm_opts, [])
    http = Map.get(resources, :req_http_options, [])

    if (Keyword.keyword?(llm) or (is_map(llm) and not is_struct(llm))) and Keyword.keyword?(http) and
         is_map(Map.get(resources, :tool_context, %{})) and
         (not Map.has_key?(resources, :run_id) or
            (is_binary(resources.run_id) and resources.run_id != "")),
       do: :ok,
       else:
         Profile.error(
           "request.options",
           "Expected model options, HTTP keyword options, and a tool context map"
         )
  end
end

defmodule Jido.AI.Session.Settle do
  @moduledoc false
  use Jido.Action, name: "ai_session_settle", schema: Zoi.object(%{request_id: Zoi.string()})
  alias Jido.AI.Session.Change

  def run(%{request_id: id}, context) do
    with %{status: :pending, run_id: run_id} = record <- context.agent_state.requests[id],
         %{run_id: ^run_id, outcome: outcome, meta: failure_meta} = completion <-
           context[:jido_ai_completion] do
      profile = context.jido_ai_profiles[record.profile_id]

      {candidate, update, directives} =
        case outcome do
          {:ok, %{result: result, meta: meta, effect_plan: plan}} ->
            completed = Map.merge(record, %{status: :completed, result: result})

            with {:ok, candidate} <-
                   Jido.AI.Effects.Candidate.assemble(
                     context.agent_state,
                     plan,
                     context.jido_ai_agent
                   ),
                 candidate =
                   candidate
                   |> Map.put(profile.result.into, result)
                   |> Jido.AI.Agent.StateProjection.apply(completed, context),
                 {:ok, _} <- domain(candidate, context) do
              {candidate, %{status: :completed, result: result, meta: meta}, plan.directives}
            else
              {:error, reason} ->
                meta = Jido.AI.Session.failed_metadata(meta, reason)

                {context.agent_state, %{status: :failed, error: Jido.AI.Error.for_storage(reason), meta: meta}, []}
            end

          {:error, error} ->
            {context.agent_state, %{status: :failed, error: error, meta: failure_meta}, []}
        end

      record =
        record
        |> Map.merge(update)
        |> Map.put(:completion_reserve, nil)
        |> Map.put(:completed_at, System.system_time(:millisecond))

      record =
        Jido.AI.Session.Inspection.complete(record, completion[:inspection], candidate, context)

      candidate = Jido.AI.Agent.StateProjection.apply(candidate, record, context)

      with {:ok, candidate, changes} <-
             Jido.AI.Context.Operations.finish(candidate, record, context),
           do: {:ok, candidate, [%Change{operation: :finish, record: record} | changes ++ directives]}
    else
      _ -> {:error, :stale_request}
    end
  end

  defp domain(candidate, context) do
    case Zoi.parse(context.jido_ai_domain_schema, candidate) do
      {:ok, _} = result -> result
      {:error, _} -> {:error, :invalid_domain_result}
    end
  end
end

defmodule Jido.AI.Session.Cancel do
  @moduledoc false
  use Jido.Action,
    name: "ai_session_cancel",
    schema:
      Zoi.object(%{
        request_id: Zoi.string() |> Zoi.nullable() |> Zoi.default(nil),
        reason: Zoi.any() |> Zoi.default(nil)
      })

  alias Jido.AI.Session.Change

  def run(%{request_id: id, reason: reason}, context) do
    id =
      id ||
        Enum.find_value(context.agent_state.requests, fn {id, r} ->
          if r.status == :pending, do: id
        end)

    case context.agent_state.requests[id] do
      %{status: :pending} = record ->
        record = %{
          record
          | status: :failed,
            completion_reserve: nil,
            error: if(is_nil(reason), do: :cancelled, else: {:cancelled, reason}),
            meta:
              Jido.AI.Session.failed_metadata(
                Map.get(context, :jido_ai_request_metadata, %{}),
                if(is_nil(reason), do: :cancelled, else: {:cancelled, reason})
              ),
            completed_at: System.system_time(:millisecond)
        }

        record =
          Jido.AI.Session.Inspection.complete(
            record,
            context[:jido_ai_request_inspection],
            context.agent_state,
            context
          )

        candidate = Jido.AI.Agent.StateProjection.apply(context.agent_state, record, context)

        with {:ok, candidate, changes} <-
               Jido.AI.Context.Operations.finish(candidate, record, context),
             do: {:ok, candidate, [%Change{operation: :finish, record: record} | changes]}

      nil ->
        {:error, :request_not_found}

      _ ->
        {:error, :request_already_finished}
    end
  end
end
