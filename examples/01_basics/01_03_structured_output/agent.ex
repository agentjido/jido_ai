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
  @moduledoc "Reasons and emits one typed reply as a Flow."

  alias JidoAI.Examples.StructuredOutput.Ask

  use Jido.Flow,
    name: "structured_output_handle_ask",
    description: "Run one structured AI request",
    schema: Ask.schema(),
    extensions: [Jido.AI.Flow.Extension]

  flow do
    reason("answer",
      prompt: input(:question),
      reply: Ask
    )

    step "reply",
         answer <- result("answer", :output),
         inline: [
           description: "Emit one typed structured reply",
           schema: Zoi.object(%{answer: Ask.output_schema()}),
           context: context
         ] do
      Jido.AI.Turn.complete_reply(context, Ask, answer)
    end

    output result("reply")
  end
end

defmodule JidoAI.Examples.StructuredOutput.Agent do
  @moduledoc "An Agent with one structured AI route."

  alias JidoAI.Examples.StructuredOutput.{Ask, HandleAsk}

  use Jido.AI.Agent, name: "structured_output_example"

  ai do
    model :fast
    instructions "Return a concise assessment."
  end

  routes do
    signal_source "/examples/structured-output"

    route Ask,
      via: HandleAsk,
      as: :ask,
      emits: ["examples.structured_output.answered"]
  end
end
