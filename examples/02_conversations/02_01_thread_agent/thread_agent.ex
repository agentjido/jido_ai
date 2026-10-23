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
  @moduledoc "Generates an answer and commits one complete Thread turn."

  alias JidoAI.Examples.ThreadAgent.Ask

  use Jido.Flow,
    name: "thread_agent_turn",
    description: "Generate an answer and commit one Thread turn",
    schema: Ask.schema(),
    output_schema: Zoi.object(%{thread: Jido.Thread.schema()}),
    extensions: [Jido.AI.Flow.Extension]

  flow do
    step "prepare",
      action: Jido.AI.Actions.PrepareTurn,
      params: %{state_key: :thread}

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
           description: "Complete one typed Thread turn",
           schema: Zoi.object(%{answer: Ask.output_schema(), state_key: Zoi.atom()}),
           context: context
         ] do
      Jido.AI.Turn.complete(context, Ask, answer, state_key: state_key)
    end

    output result("commit")
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

    route Ask,
      via: Turn,
      as: :ask,
      emits: ["examples.thread_agent.answered"]
  end
end

defmodule JidoAI.Examples.ThreadAgent do
  @moduledoc "Builds the complete Thread-backed AI Agent."

  alias JidoAI.Examples.ThreadAgent.Agent

  @doc "Builds an Agent value with a new portable Thread."
  def new(opts \\ []) do
    opts =
      Keyword.put_new_lazy(opts, :state, fn ->
        %{thread: Jido.Thread.new!(metadata: %{example: "thread_agent"})}
      end)

    Agent.instantiate(opts)
  end
end
