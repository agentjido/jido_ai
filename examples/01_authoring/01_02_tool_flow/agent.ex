defmodule JidoAI.Examples.ToolFlow.Agent do
  @moduledoc "The AI runtime calls declared Action and Flow tools, then uses their results."
  use Jido.AI.Agent, name: "v3_example_tools_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("case-42")
           })

    ai :assistant do
      model "openai:gpt-4o-mini"
      instructions "Use the calculation tools and answer from their results."

      observability do
        store_content true
      end

      tools do
        action JidoAI.Examples.Support.Multiply, as: :multiply
        flow JidoAI.Examples.Authoring.Support.Quote, as: :quote
      end

      controls do
        timeout 5_000
        max_iterations 2
        max_model_calls 2
        max_tool_calls 4
      end

      result into: :answer
    end
  end

  routes do
    signal_source "/examples/ai/01_authoring/01_02"

    route "examples.ai.01_02.calculate", ai: :assistant do
      define :calculate, args: [:query]
    end
  end
end
