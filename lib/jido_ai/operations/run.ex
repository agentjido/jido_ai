defmodule Jido.AI.Runtime.Run do
  @moduledoc "Assembles one complete Agent result from the shared reasoning Flow."
  use Jido.Action, name: "ai_agent_run", schema: Zoi.object(%{query: Jido.AI.Query.schema()})

  def run(params, context),
    do:
      Jido.AI.Error.capture(fn ->
        with {:ok, context} <- Jido.AI.Session.Plugin.context(context),
             do: execute(Jido.AI.Plugins.Retrieval.apply_input(params, context), context)
      end)

  defp execute(%{query: query}, context) do
    profile = context.jido_ai_profiles[context.jido_ai_turn_profile]

    with {:ok, flow} <- Jido.AI.Runtime.Flow.build(profile),
         {:ok, output} <-
           Jido.Exec.run(flow, %{query: query}, context, timeout: profile.controls.timeout),
         {:ok, candidate} <-
           Jido.AI.Effects.Candidate.assemble(
             context.agent_state,
             output.effect_plan,
             context.jido_ai_agent
           ) do
      candidate =
        candidate
        |> Jido.AI.History.append(profile, output.history_delta)
        |> Map.put(profile.result.into, output.result)

      {:ok, candidate, output.effect_plan.directives}
    end
  end
end
