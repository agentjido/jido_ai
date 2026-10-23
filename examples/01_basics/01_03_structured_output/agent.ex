defmodule JidoAI.Examples.StructuredOutput.Ask do
  @moduledoc "Asks for one structured assessment."

  use Jido.SignalAction,
    name: "structured_output_ask",
    description: "Ask for one structured assessment",
    vsn: 1,
    input: [
      type: "examples.structured_output.ask",
      default_source: "/examples/structured-output/client",
      schema: Zoi.object(%{question: Zoi.string()})
    ],
    output: [
      type: "examples.structured_output.answered",
      default_source: "/examples/structured-output",
      schema:
        Zoi.object(%{
          answer: Zoi.string(),
          confidence: Zoi.number() |> Zoi.min(0) |> Zoi.max(1)
        })
    ]

  @impl Jido.Action
  def run(%{question: question}, context),
    do: Jido.AI.respond(context, question, reply: __MODULE__)
end

defmodule JidoAI.Examples.StructuredOutput.HandleAsk do
  @moduledoc "Converts typed answer data to an Agent Reply Directive."

  alias JidoAI.Examples.StructuredOutput.Ask

  use Jido.Action,
    name: "structured_output_handle_ask",
    description: "Handle one structured AI request",
    schema: Ask.schema()

  @impl Jido.Action
  def run(params, context) do
    with {:ok, answer} <- Ask.run(params, context),
         do: Jido.AI.Turn.complete_reply(context, Ask, answer)
  end
end

defmodule JidoAI.Examples.StructuredOutput.Agent do
  @moduledoc "An Agent with one structured AI route."

  alias JidoAI.Examples.StructuredOutput.{Ask, HandleAsk}

  use Jido.AI.Agent, name: "structured_output_example"

  ai do
    model :fast
    instructions "Return a concise assessment."

    reasoning do
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

    route Ask, HandleAsk, as: :ask
  end
end
