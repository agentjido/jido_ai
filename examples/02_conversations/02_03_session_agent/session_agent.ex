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
  @moduledoc "Generates an answer and commits one complete Session turn."

  alias JidoAI.Examples.SessionAgent.Ask

  use Jido.Flow,
    name: "session_agent_turn",
    description: "Generate an answer and commit one Session turn",
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
           description: "Complete one typed Session turn",
           schema: Zoi.object(%{answer: Ask.output_schema(), state_key: Zoi.atom()}),
           context: context
         ] do
      Jido.AI.Turn.complete(context, Ask, answer, state_key: state_key)
    end

    output result("commit")
  end
end

defmodule JidoAI.Examples.SessionAgent.Agent do
  @moduledoc "An AI Agent with one Session in declared state."

  alias JidoAI.Examples.SessionAgent.{Ask, Turn}

  use Jido.AI.Agent, name: "session_agent_example"

  agent do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  ai do
    model :fast
    instructions "Answer in one short sentence."
  end

  routes do
    signal_source "/examples/session-agent"

    route Ask,
      via: Turn,
      as: :ask,
      emits: ["examples.session_agent.answered"]
  end
end

defmodule JidoAI.Examples.SessionAgent do
  @moduledoc "Builds the complete Session-backed AI Agent."

  alias JidoAI.Examples.SessionAgent.Agent

  @doc "Builds an Agent value with a new open Session."
  def new(opts \\ []) do
    opts =
      Keyword.put_new_lazy(opts, :state, fn ->
        %{session: Jido.Session.new!(metadata: %{example: "session_agent"})}
      end)

    Agent.instantiate(opts)
  end
end
