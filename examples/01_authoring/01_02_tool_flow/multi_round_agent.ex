defmodule JidoAI.Examples.ToolFlow.MultiRoundAgent do
  @moduledoc "Three dependent tool rounds through the native ReAct runtime."
  use Jido.AI.Agent, name: "multi_round_quote"

  agent do
    schema Zoi.object(%{
             answer: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("quote-42"),
             history: Jido.AI.Thread.Projection.schema()
           })

    ai :assistant do
      model :fast, max_tokens: 512
      reasoning :react

      instructions "Use exactly one tool per round. Wait for its result before the next calculation. " <>
                     "Use quote for the first calculation, then multiply for each remaining calculation. " <>
                     "Do not calculate the results yourself. Finish with a short summary of all three results."

      tools do
        flow JidoAI.Examples.Authoring.Support.Quote, as: :quote
        action JidoAI.Examples.Support.Multiply, as: :multiply
      end

      controls do
        timeout 60_000
        max_iterations 4
        max_model_calls 4
        max_tool_calls 3
      end

      memory history: :history
      result into: :answer
    end
  end

  routes do
    signal_source "/examples/ai/01_authoring/01_02/multi_round"

    route "examples.ai.01_02.multi_round", ai: :assistant do
      define :calculate, args: [:query]
    end
  end

  def prompt do
    "A box has 7 items at 13 cents each. First use quote to find the box subtotal. " <>
      "Then use multiply on that returned subtotal for 6 boxes. " <>
      "Then use multiply on that returned shipment total for 4 shipments. " <>
      "Report the box, shipment, and complete order totals in cents."
  end
end
