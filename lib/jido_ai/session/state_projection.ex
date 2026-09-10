defmodule Jido.AI.Session.StateProjection do
  @moduledoc false

  # This adapter supplies the old public convenience fields. Session Actions
  # call it while building the complete domain candidate. It owns no process
  # or request store, and the core validates the resulting candidate.
  def apply(state, record, context) do
    if context[:jido_ai_legacy_agent_profile] == record.profile_id do
      projected =
        case record.status do
          :pending ->
            Map.merge(state, %{
              last_request_id: record.id,
              last_query: record.query,
              last_answer: "",
              last_result: nil,
              completed: false
            })

          :completed ->
            Map.merge(state, %{
              last_answer: Jido.AI.Request.compat_text(record.result),
              completed: true
            })

          :failed ->
            Map.put(state, :completed, true)
        end

      projected =
        if Map.get(record, :method) == :adaptive,
          do: Map.put(projected, :selected_strategy, get_in(record, [:meta, :adaptive, :strategy])),
          else: projected

      if Jido.AI.Reasoning.Linear.linear?(Map.get(record, :method, :react)) or
           Map.get(record, :method) in [:graph_of_thoughts, :trm, :adaptive] do
        case record.status do
          :pending -> Map.merge(projected, %{last_prompt: record.query, last_result: ""})
          :completed -> Map.put(projected, :last_result, printable(record.result))
          :failed -> Map.put(projected, :last_result, printable(project_error(record)))
        end
      else
        if Map.get(record, :method) in [:algorithm_of_thoughts, :tree_of_thoughts] do
          case record.status do
            :pending ->
              Map.put(projected, :last_prompt, record.query)

            :completed ->
              projected

            :failed ->
              result =
                case record.error do
                  {:failed, _, result} -> result
                  _other -> nil
                end

              Map.put(projected, :last_result, result)
          end
        else
          projected
        end
      end
    else
      state
    end
  end

  defp project_error(%{method: :adaptive, error: {:failed, reason, details}})
       when is_map(details),
       do: Map.get(details, :result, reason)

  defp project_error(%{method: :graph_of_thoughts, error: {:failed, reason, _details}}),
    do: {:error, reason}

  defp project_error(%{method: :trm, error: {:failed, _reason, %{result: result}}}),
    do: result

  defp project_error(%{method: :trm, error: reason}),
    do: Jido.AI.Reasoning.TRM.Helpers.safe_error_message(reason)

  defp project_error(record), do: record.error

  defp printable(nil), do: ""
  defp printable(value) when is_binary(value), do: value
  defp printable(value), do: inspect(value)
end
