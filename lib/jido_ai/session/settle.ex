defmodule Jido.AI.Session.Settle do
  @moduledoc false
  use Jido.Action, name: "ai_session_settle", schema: Zoi.object(%{request_id: Zoi.string()})
  alias Jido.AI.Session.Change

  def run(params, context) do
    with {:ok, context} <- Jido.AI.Session.Plugin.context(context),
         do: execute(params, context)
  end

  defp execute(%{request_id: id}, context) do
    with %{status: :pending, run_id: run_id} = record <- context.agent_state.requests[id],
         %{run_id: ^run_id, outcome: outcome, meta: failure_meta} = completion <-
           context[:jido_ai_completion] do
      profile = context.jido_ai_profiles[record.profile_id]

      {candidate, update, directives} =
        case outcome do
          {:ok, %{result: result, meta: meta, effect_plan: plan} = outcome} ->
            content = Map.get(outcome, :content, Jido.AI.Runtime.OutputState.content(result))
            value = Map.get(outcome, :value, if(profile.result.schema, do: result, else: nil))

            with {:ok, candidate} <-
                   Jido.AI.Effects.Candidate.assemble(
                     context.agent_state,
                     plan,
                     context.jido_ai_agent
                   ),
                 candidate = Map.put(candidate, profile.result.into, result),
                 {:ok, _} <- domain(candidate, context) do
              {candidate,
               %{
                 status: :completed,
                 result: result,
                 content: content,
                 value: value,
                 meta: meta
               }, plan.directives}
            else
              {:error, reason} ->
                meta =
                  meta
                  |> Jido.AI.Session.failed_metadata(reason)
                  |> compact_failure_metadata(reason)

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

      with {:ok, candidate, changes} <-
             Jido.AI.Thread.Control.finish(candidate, record, context),
           do: {:ok, candidate, [%Change{operation: :finish, record: record} | changes ++ directives]}
    else
      _ -> {:error, :stale_request}
    end
  end

  defp domain(candidate, context) do
    case Zoi.parse(context.jido_ai_domain_schema, candidate) do
      {:ok, _} = result ->
        result

      {:error, errors} ->
        if Jido.AI.Runtime.StateSize.error?(errors),
          do: {:error, :state_size},
          else: {:error, :invalid_domain_result}
    end
  end

  defp compact_failure_metadata(meta, :state_size),
    do: Map.put(meta, :completion, %{details_elided?: true})

  defp compact_failure_metadata(meta, _reason), do: meta
end
