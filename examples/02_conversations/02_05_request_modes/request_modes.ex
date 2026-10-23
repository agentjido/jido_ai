defmodule JidoAI.Examples.RequestModes.Ask do
  @moduledoc "Defines the request and reply Signals for the runtime example."

  use Jido.SignalAction,
    name: "request_modes_ask",
    description: "Ask the runtime Agent one question",
    vsn: 1,
    input: [
      type: "examples.request_modes.ask",
      default_source: "/examples/request-modes/client",
      schema: Zoi.object(%{question: Zoi.string() |> Zoi.min(1)})
    ],
    output: [
      type: "examples.request_modes.answered",
      default_source: "/examples/request-modes",
      schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})
    ]

  @impl Jido.Action
  def run(%{question: question}, context),
    do: Jido.AI.respond(context, question, reply: __MODULE__)
end

defmodule JidoAI.Examples.RequestModes.Turn do
  @moduledoc "Runs and commits one complete runtime-controlled AI turn."

  alias JidoAI.Examples.RequestModes.Ask

  use Jido.Flow,
    name: "request_modes_turn",
    description: "Generate and commit one runtime-controlled AI turn",
    schema: Ask.schema(),
    output_schema: Zoi.object(%{session: Jido.Session.schema()}),
    extensions: [Jido.AI.Flow.Extension]

  flow do
    step "prepare",
      action: Jido.AI.Actions.PrepareTurn,
      params: %{}

    reason("answer",
      prompt: input(:question),
      reply: Ask,
      needs: ["prepare"]
    )

    step "commit",
         [
           answer <- result("answer", :output),
           state_key <- result("prepare", :state_key)
         ],
         inline: [
           description: "Complete one typed runtime turn",
           schema: Zoi.object(%{answer: Ask.output_schema(), state_key: Zoi.atom()}),
           context: context
         ] do
      Jido.AI.Turn.complete(context, Ask, answer, state_key: state_key)
    end

    output result("commit")
  end
end

defmodule JidoAI.Examples.RequestModes.Agent do
  @moduledoc "A complete AI Agent used to compare AgentServer request modes."

  alias JidoAI.Examples.RequestModes.{Ask, Turn}

  use Jido.AI.Agent, name: "request_modes_example"

  agent do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  ai do
    model :fast
    instructions "Answer in one short sentence."
  end

  routes do
    signal_source "/examples/request-modes"

    route Ask,
      via: Turn,
      as: :ask,
      emits: ["examples.request_modes.answered"]
  end
end

defmodule JidoAI.Examples.RequestModes do
  @moduledoc "Starts its own complete AI Agent for AgentServer request modes."

  alias JidoAI.Examples.RequestModes.Agent

  @doc "Starts the request-mode Agent with a new Session."
  def start(jido, opts \\ []) do
    opts =
      Keyword.put_new_lazy(opts, :state, fn ->
        %{session: Jido.Session.new!(metadata: %{example: "request_modes"})}
      end)

    Jido.start_agent(jido, Agent, opts)
  end
end
