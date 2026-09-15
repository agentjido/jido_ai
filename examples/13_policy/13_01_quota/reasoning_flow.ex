defmodule JidoAI.Examples.Quota.ReasoningFlow do
  use Jido.Flow, name: "quota_reasoning", schema: Zoi.object(%{prompt: Zoi.string()})

  flow do
    step "reason",
      action: Jido.AI.Actions.Reasoning.RunStrategy,
      params: %{strategy: :cot, prompt: input(:prompt)}

    output result("reason")
  end
end
