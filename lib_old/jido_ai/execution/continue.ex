defmodule Jido.AI.Execution.Continue do
  @moduledoc false
  use Jido.Action, name: "ai_continue"

  @impl Jido.Action
  def run(params, context), do: Jido.AI.Error.capture(fn -> execute(params, context) end)

  defp execute(%{state: state, results: [%{call: _} | _] = results}, _),
    do: {:ok, %{state | tool_results: state.tool_results ++ results}}

  defp execute(%{state: state, results: results}, context),
    do: apply_results(state, results, context)

  @doc false
  def apply_results(state, results, context) do
    with {:ok, plan} <-
           Enum.reduce_while(results, {:ok, state.effect_plan}, fn result, {:ok, plan} ->
             case Jido.AI.Effects.Candidate.stage(
                    plan,
                    result.agent_state,
                    elem(result.result, 2),
                    context.jido_ai_agent
                  ) do
               {:ok, next} -> {:cont, {:ok, next}}
               error -> {:halt, error}
             end
           end) do
      meta =
        Enum.reduce(
          results,
          Map.get(state, :tool_meta, %{}),
          &Jido.AI.ToolResult.record(&2, &1.completed)
        )

      {:ok,
       state
       |> Map.put(:tool_results, state.tool_results ++ results)
       |> Map.put(:tool_meta, meta)
       |> Map.put(:effect_plan, plan)}
    end
  end
end
