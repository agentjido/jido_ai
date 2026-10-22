defmodule Jido.AI.Orchestration.Start do
  @moduledoc false
  use Jido.Action,
    name: "ai_request_start",
    schema: Zoi.object(%{query: Jido.AI.Query.schema(), request_id: Zoi.string() |> Zoi.min(1)})

  alias Jido.AI.Profile
  alias Jido.AI.Request
  alias Jido.AI.Orchestration.Change

  @impl true
  def on_before_validate_params(params) do
    {:ok, Map.put_new_lazy(params, :request_id, &Jido.Signal.ID.generate!/0)}
  end

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Orchestration.Plugin.context(context),
         do: execute(Jido.AI.Plugins.Retrieval.apply_input(params, context), context)
  end

  defp execute(%{request_id: id, query: query}, context) do
    profile_id = context.jido_ai_admission_profile
    records = context.agent_state.requests
    profile = context.jido_ai_profiles[profile_id]

    context =
      if profile.memory.history && is_nil(context.agent_state[profile.memory.history]),
        do: put_in(context.agent_state[profile.memory.history], Jido.Session.new()),
        else: context

    resources = Map.get(context, :jido_ai_request, %{})
    run_id = Map.get_lazy(resources, :run_id, &Jido.Signal.ID.generate!/0)

    unsupported =
      Map.keys(resources) --
        [
          :stream_to,
          :stream,
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

      unsupported != [] ->
        Profile.error("request", "Request options are not yet ported: #{inspect(unsupported)}")

      true ->
        with {:ok, sink} <- Request.Stream.normalize_sink(resources[:stream_to]),
             :ok <- options(resources),
             :ok <- Jido.AI.Skill.Runtime.request_options(resources),
             :ok <- Jido.AI.Execution.Checkpoint.admission(context, id, run_id) do
          record = %{
            id: id,
            run_id: run_id,
            session_id:
              if(profile.memory.history,
                do:
                  Jido.AI.Thread.Control.session_id(
                    context.agent_state,
                    profile,
                    context.jido_ai_agent.id
                  )
              ),
            profile_id: profile_id,
            method: profile.reasoning.method,
            query: query,
            status: :pending,
            result: nil,
            content: "",
            value: nil,
            error: nil,
            inserted_at: System.system_time(:millisecond),
            completed_at: nil,
            completion_reserve: Jido.AI.Request.Record.completion_reserve(),
            streamed: sink != nil,
            streaming: Map.get(resources, :stream, false),
            max_retained_requests: context.jido_ai_max_retained_requests,
            extra_refs: Map.get(context.signal.data, :extra_refs, %{}),
            meta: checkpoint_metadata(context),
            inspection: %{}
          }

          with {:ok, candidate} <- start_history(context, profile, record) do
            {:ok, candidate, [%Change{operation: :start, record: record}]}
          end
        end
    end
  end

  defp start_history(context, profile, record) do
    if Jido.AI.Execution.Checkpoint.resuming?(context[:jido_ai_checkpoint]),
      do: {:ok, context.agent_state},
      else: Jido.AI.Orchestration.Transcript.start(context.agent_state, profile, record, context.signal.source)
  end

  defp checkpoint_metadata(context) do
    case context[:jido_ai_checkpoint] do
      %{state: state} -> Jido.AI.Execution.Checkpoint.metadata(state)
      _ -> %{}
    end
  end

  defp options(resources) do
    llm = Map.get(resources, :llm_opts, [])
    http = Map.get(resources, :req_http_options, [])

    if is_boolean(Map.get(resources, :stream, false)) and
         (Keyword.keyword?(llm) or (is_map(llm) and not is_struct(llm))) and Keyword.keyword?(http) and
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
