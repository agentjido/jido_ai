defmodule JidoAI.Examples.NumericInputs.Agent do
  @moduledoc "Normalizes model tool numbers before the batch starts."
  use Jido.AI.Agent, name: "numeric_inputs"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model(:answer, Jido.AI.Test.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      observability do
        store_content true
      end

      tools do
        action JidoAI.Examples.NumericInputs.Read,
          as: :numeric_input

        flow(JidoAI.Examples.NumericInputs.Flow, as: :numeric_flow)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    signal_source "/examples/ai/03_tools/03_03"

    route "ai.numeric", ai(:assistant) do
      define :read_numbers, args: [:query]
    end
  end
end
