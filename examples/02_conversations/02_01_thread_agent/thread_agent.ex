defmodule JidoAI.Examples.ThreadAgent.Ask do
  @moduledoc "Defines the Thread Agent request and reply Signals."

  use Jido.SignalAction,
    name: "thread_agent_ask",
    description: "Ask the Thread Agent one question",
    vsn: 1,
    input: [
      type: "examples.thread_agent.ask",
      default_source: "/examples/thread-agent/client",
      schema: Zoi.object(%{question: Zoi.string() |> Zoi.min(1)})
    ],
    output: [
      type: "examples.thread_agent.answered",
      default_source: "/examples/thread-agent",
      schema: Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})
    ]

  @impl Jido.Action
  def run(%{question: question}, context),
    do: Jido.AI.respond(context, question, reply: __MODULE__)
end

defmodule JidoAI.Examples.ThreadAgent.Turn do
  @moduledoc "Runs and commits one complete Thread turn."

  alias JidoAI.Examples.ThreadAgent.Ask

  use Jido.Action,
    name: "thread_agent_turn",
    description: "Generate an answer and commit one Thread turn",
    schema: Ask.schema(),
    output_schema: Zoi.object(%{thread: Jido.Thread.schema()})

  @impl Jido.Action
  def run(params, context) do
    with {:ok, _prepared} <- Jido.AI.Turn.prepare(context, state_key: :thread),
         {:ok, answer} <- Ask.run(params, context),
         do: Jido.AI.Turn.complete(context, Ask, answer, state_key: :thread)
  end
end

defmodule JidoAI.Examples.ThreadAgent.Agent do
  @moduledoc "An AI Agent that owns one portable Thread value."

  alias JidoAI.Examples.ThreadAgent.{Ask, Turn}

  use Jido.AI.Agent, name: "thread_agent_example"

  agent do
    schema Zoi.object(%{thread: Jido.Thread.schema()})
  end

  ai do
    model :fast
    instructions "Answer in one short sentence."
  end

  routes do
    signal_source "/examples/thread-agent"

    route Ask, Turn, as: :ask
  end
end

defmodule JidoAI.Examples.ThreadAgent do
  @moduledoc "Builds the complete Thread-backed AI Agent."

  alias JidoAI.Examples.ThreadAgent.Agent

  @doc "Builds an Agent value with a new portable Thread."
  def new(opts \\ []) do
    definition = Agent.definition()

    initial_state =
      Map.put(
        definition.initial_state,
        :thread,
        Jido.Thread.new!(metadata: %{example: "thread_agent"})
      )

    Jido.Agent.instantiate(%{definition | initial_state: initial_state}, opts)
  end
end
