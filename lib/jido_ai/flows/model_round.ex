defmodule Jido.AI.Flows.ModelRound do
  @moduledoc "Projects context and runs one guarded provider attempt."

  use Jido.Flow,
    name: "jido_ai_model_round",
    schema: Zoi.object(%{turn: Zoi.any()}),
    output_schema: Zoi.map()

  flow do
    step "project",
      action: Jido.AI.Actions.ProjectConversation,
      params: %{turn: input(:turn)}

    step "model",
      action: Jido.AI.Actions.CallModel,
      params: %{
        turn: result("project", :turn),
        messages: result("project", :messages)
      }

    step "output_guard",
      action: Jido.AI.Actions.CheckOutput,
      params: %{
        turn: result("model", :turn),
        outcome: result("model", :outcome)
      }

    step "record_attempt",
      action: Jido.AI.Actions.RecordModelAttempt,
      params: %{
        turn: result("model", :turn),
        outcome: result("model", :outcome),
        output_allowed: result("output_guard", :allowed),
        output_reason: result("output_guard", :reason)
      }

    invoke "next",
      decision: Jido.AI.Actions.DecideModelNext,
      expander: Jido.AI.Actions.ExpandNext,
      params: %{turn: result("record_attempt", :turn)}

    output result("next")
  end
end
