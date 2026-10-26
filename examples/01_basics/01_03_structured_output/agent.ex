defmodule JidoAI.Examples.StructuredOutput.Ask do
  @moduledoc "Asks for one structured assessment."

  use Jido.Action,
    name: "structured_output_ask",
    description: "Ask for one structured assessment",
    schema: Zoi.object(%{question: Zoi.string()}),
    output_schema:
      Zoi.object(%{
        answer: Zoi.string(),
        confidence: Zoi.number() |> Zoi.min(0) |> Zoi.max(1)
      })

  @impl Jido.Action
  def run(%{question: question}, context),
    do:
      Jido.AI.respond(context, question,
        reply: {JidoAI.Examples.StructuredOutput.Agent, "examples.structured_output.ask"}
      )
end

defmodule JidoAI.Examples.StructuredOutput.Agent do
  @moduledoc "An Agent with one structured AI route."

  alias JidoAI.Examples.StructuredOutput.Ask

  use Jido.AI.Agent, name: "structured_output_example"

  ai do
    model :fast
    instructions "Return a concise assessment."

    graph do
      step "model",
        action: Jido.AI.Actions.CallModel,
        params: input(:request)

      step "complete",
        action: Jido.AI.Actions.CompleteResponse,
        params: result("model")

      output result("complete")
    end
  end

  routes do
    signal_source "/examples/structured-output"

    route "examples.structured_output.ask", Ask, as: :ask do
      state(:unchanged)
      reply("examples.structured_output.answered", from: output())
    end
  end
end
