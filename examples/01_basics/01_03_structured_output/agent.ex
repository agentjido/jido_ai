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
  @moduledoc "Runs the AI Action and emits its typed reply."

  alias JidoAI.Examples.StructuredOutput.Ask

  use Jido.Action,
    name: "structured_output_handle_ask",
    description: "Run one structured AI request",
    schema: Ask.schema()

  @impl Jido.Action
  def run(params, context) do
    with {:ok, answer} <- Jido.Exec.run(Ask, params, context),
         {:ok, reply} <- Ask.reply(context.signal, answer) do
      {:ok, context.agent_state, [Jido.Agent.Directive.emit(reply)]}
    end
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
