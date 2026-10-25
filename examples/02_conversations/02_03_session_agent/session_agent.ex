defmodule JidoAI.Examples.SessionAgent.Ask do
  @moduledoc "Defines the Session Agent request and reply Signals."

  use Jido.Action,
    name: "session_agent_ask",
    description: "Ask the Session Agent one question",
    schema: Zoi.object(%{question: Zoi.string() |> Zoi.min(1)}),
    output_schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})

  @impl Jido.Action
  def run(%{question: question}, context),
    do: Jido.AI.respond(context, question, reply: {JidoAI.Examples.SessionAgent.Agent, "examples.session_agent.ask"})
end

defmodule JidoAI.Examples.SessionAgent.Turn do
  @moduledoc "Runs and commits one complete Session turn."

  alias JidoAI.Examples.SessionAgent.Ask

  use Jido.Action,
    name: "session_agent_turn",
    description: "Generate an answer and commit one Session turn",
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
             reply: {JidoAI.Examples.SessionAgent.Agent, "examples.session_agent.ask"}
           ),
         do:
           Jido.AI.Turn.complete(
             context,
             {JidoAI.Examples.SessionAgent.Agent, "examples.session_agent.ask"},
             result,
             state_key: :session
           )
  end
end

defmodule JidoAI.Examples.SessionAgent.Agent do
  @moduledoc "An AI Agent with one Session in declared state."

  alias JidoAI.Examples.SessionAgent.{Ask, Turn}

  use Jido.AI.Agent, name: "session_agent_example"

  state do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  @impl Jido.Agent
  def initialize(state, _context) do
    {:ok,
     Map.put_new_lazy(state, :session, fn ->
       Jido.Session.new!(metadata: %{example: "session_agent"})
     end)}
  end

  ai do
    model :fast
    instructions "Answer in one short sentence."
  end

  routes do
    signal_source "/examples/session-agent"

    route "examples.session_agent.ask", Turn, as: :ask do
      state(from: output(:state))
      reply("examples.session_agent.answered", from: output(:reply))
    end
  end
end

defmodule JidoAI.Examples.SessionAgent do
  @moduledoc "Builds the complete Session-backed AI Agent."

  alias JidoAI.Examples.SessionAgent.Agent

  @doc "Builds an Agent value with a new open Session."
  def new(opts \\ []), do: Agent.instantiate(opts)
end
