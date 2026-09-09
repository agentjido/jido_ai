defmodule JidoAI.Examples.NumericInputs.Read do
  @moduledoc "Reports the typed arguments received by a real tool Action."
  use Jido.Action,
    name: "numeric_input",
    schema:
      Zoi.object(%{
        count: Zoi.integer() |> Zoi.default(1),
        factor: Zoi.float(),
        items: Zoi.array(Zoi.object(%{count: Zoi.integer(), factor: Zoi.float()}))
      })

  def run(params, context) do
    send(context.observer, {:numeric_input, params})
    {:ok, params}
  end
end

defmodule JidoAI.Examples.NumericInputs.Flow do
  @moduledoc "The same tool input contract applies to a callable Flow."
  use Jido.Flow,
    name: "numeric_input_flow",
    schema: JidoAI.Examples.NumericInputs.Read.schema()

  flow do
    step "read", action: JidoAI.Examples.NumericInputs.Read, params: input()
    output result("read")
  end
end

defmodule JidoAI.Examples.NumericInputs.Agent do
  @moduledoc "Normalizes model tool numbers before the batch starts."
  use Jido.Agent, name: "numeric_inputs", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model(:answer, Jido.AI.Test.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action JidoAI.Examples.NumericInputs.Read,
          as: :numeric_input,
          forward_context: [:observer]

        flow(JidoAI.Examples.NumericInputs.Flow, as: :numeric_flow, forward_context: [:observer])
      end

      requests do
        mode(:session)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.numeric", ai(:assistant)
  end
end
