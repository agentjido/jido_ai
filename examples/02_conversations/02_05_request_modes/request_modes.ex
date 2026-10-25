defmodule JidoAI.Examples.RequestModes.Ask do
  @moduledoc "Defines the request and reply Signals for the runtime example."

  use Jido.Action,
    name: "request_modes_ask",
    description: "Ask the runtime Agent one question",
    schema: Zoi.object(%{question: Zoi.string() |> Zoi.min(1)}),
    output_schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})

  @impl Jido.Action
  def run(%{question: question}, context),
    do: Jido.AI.respond(context, question, reply: {JidoAI.Examples.RequestModes.Agent, "examples.request_modes.ask"})
end

defmodule JidoAI.Examples.RequestModes.Turn do
  @moduledoc "Runs and commits one complete runtime-controlled AI turn."

  alias JidoAI.Examples.RequestModes.Ask

  use Jido.Action,
    name: "request_modes_turn",
    description: "Generate and commit one runtime-controlled AI turn",
    schema: Ask.schema(),
    output_schema:
      Zoi.object(%{
        state: Zoi.object(%{session: Jido.Session.schema()}),
        reply: Ask.output_schema()
      })

  @impl Jido.Action
  def run(%{question: question}, context) do
    with {:ok, _prepared} <- Jido.AI.Turn.prepare(context, state_key: :session),
         {:ok, result} <-
           Jido.AI.respond_result(context, question,
             reply: {JidoAI.Examples.RequestModes.Agent, "examples.request_modes.ask"}
           ),
         do:
           Jido.AI.Turn.complete(
             context,
             {JidoAI.Examples.RequestModes.Agent, "examples.request_modes.ask"},
             result,
             state_key: :session
           )
  end
end

defmodule JidoAI.Examples.RequestModes.Agent do
  @moduledoc "A complete AI Agent used to compare AgentServer request modes."

  alias JidoAI.Examples.RequestModes.{Ask, Turn}

  use Jido.AI.Agent, name: "request_modes_example"

  state do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  @impl Jido.Agent
  def initialize(state, _context) do
    {:ok,
     Map.put_new_lazy(state, :session, fn ->
       Jido.Session.new!(metadata: %{example: "request_modes"})
     end)}
  end

  ai do
    model :fast
    instructions "Answer in one short sentence."
  end

  routes do
    signal_source "/examples/request-modes"

    route "examples.request_modes.ask", Turn, as: :ask do
      state(from: output(:state))
      reply("examples.request_modes.answered", from: output(:reply))
    end
  end
end

defmodule JidoAI.Examples.RequestModes do
  @moduledoc "Starts its own complete AI Agent for AgentServer request modes."

  alias JidoAI.Examples.RequestModes.Agent

  @doc "Starts the request-mode Agent with a new Session."
  def start(jido, opts \\ []), do: Jido.start_agent(jido, Agent, opts)
end
