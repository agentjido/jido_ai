defmodule JidoAI.Examples.SessionAgent.Ask do
  @moduledoc "Defines the Session Agent request and reply Signals."

  use Jido.SignalAction,
    name: "session_agent_ask",
    description: "Ask the Session Agent one question",
    vsn: 1,
    input: [
      type: "examples.session_agent.ask",
      default_source: "/examples/session-agent/client",
      schema: Zoi.object(%{question: Zoi.string() |> Zoi.min(1)})
    ],
    output: [
      type: "examples.session_agent.answered",
      default_source: "/examples/session-agent",
      schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})
    ]

  @impl Jido.Action
  def run(%{question: question}, context),
    do: Jido.AI.respond(context, question, reply: __MODULE__)
end

defmodule JidoAI.Examples.SessionAgent.Turn do
  @moduledoc "Runs and commits one complete Session turn."

  alias JidoAI.Examples.SessionAgent.Ask

  use Jido.Action,
    name: "session_agent_turn",
    description: "Generate an answer and commit one Session turn",
    schema: Ask.schema(),
    output_schema: Zoi.object(%{session: Jido.Session.schema()})

  @impl Jido.Action
  def run(%{question: question}, context) do
    with {:ok, _prepared} <- Jido.AI.Turn.prepare(context, state_key: :session),
         {:ok, result} <- Jido.AI.respond_result(context, question, reply: Ask),
         do: Jido.AI.Turn.complete(context, Ask, result, state_key: :session)
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

    route Ask, Turn, as: :ask
  end
end

defmodule JidoAI.Examples.SessionAgent do
  @moduledoc "Builds the complete Session-backed AI Agent."

  alias JidoAI.Examples.SessionAgent.Agent

  @doc "Builds an Agent value with a new open Session."
  def new(opts \\ []), do: Agent.instantiate(opts)
end
