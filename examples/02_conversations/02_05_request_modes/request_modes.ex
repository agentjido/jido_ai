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

  use Jido.Action,
    name: "request_modes_turn",
    description: "Generate and commit one runtime-controlled AI turn",
    schema: Ask.schema(),
    output_schema: Zoi.object(%{session: Jido.Session.schema()})

  @impl Jido.Action
  def run(params, context) do
    with {:ok, _prepared} <- Jido.AI.Turn.prepare(context, state_key: :session),
         {:ok, answer} <- Ask.run(params, context),
         do: Jido.AI.Turn.complete(context, Ask, answer, state_key: :session)
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

    route Ask, Turn, as: :ask
  end
end

defmodule JidoAI.Examples.RequestModes do
  @moduledoc "Starts its own complete AI Agent for AgentServer request modes."

  alias JidoAI.Examples.RequestModes.Agent

  @doc "Starts the request-mode Agent with a new Session."
  def start(jido, opts \\ []) do
    definition = Agent.definition()

    initial_state =
      Map.put(
        definition.initial_state,
        :session,
        Jido.Session.new!(metadata: %{example: "request_modes"})
      )

    Jido.start_agent(jido, %{definition | initial_state: initial_state}, opts)
  end
end
