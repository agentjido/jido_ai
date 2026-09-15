defmodule JidoAI.Examples.Controls.Agent do
  @moduledoc "Input policy runs before model work; output policy runs before the answer commits."
  use Jido.AI.Agent, name: "v3_example_controls_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("case-42")
           })

    ai :assistant do
      model "openai:gpt-4o-mini"
      instructions "Include the evidence marker in your answer."

      controls do
        timeout 5_000
        max_model_calls 1
        input JidoAI.Examples.Controls.Access
        output JidoAI.Examples.Controls.Evidence
      end

      result into: :answer
    end
  end

  routes do
    signal_source "/examples/ai/01_authoring/01_04"

    route "examples.ai.01_04.answer", ai: :assistant do
      define :answer, args: [:query]
    end
  end
end
