defmodule JidoAI.Examples.ConversationHistory.Ask do
  @moduledoc "Defines a stateful conversation request and reply."

  @answer_type "examples.conversation.answered"
  @answer_schema Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})

  use Jido.SignalAction,
    name: "conversation_history_ask",
    description: "Ask one question with committed history",
    vsn: 1,
    input: [
      type: "examples.conversation.ask",
      default_source: "/examples/conversation/client",
      schema: Zoi.object(%{question: Zoi.string() |> Zoi.min(1)})
    ],
    output: [
      type: @answer_type,
      default_source: "/examples/conversation",
      schema: @answer_schema
    ]

  @impl Jido.Action
  def run(%{question: question}, context) do
    Jido.AI.respond(context, question,
      reply: __MODULE__,
      context: context.agent_state.session,
      projection: [signal_action: __MODULE__, input: :question, output: :answer]
    )
  end
end

defmodule JidoAI.Examples.ConversationHistory.Turn do
  @moduledoc "Runs and commits one complete conversation turn."

  alias JidoAI.Examples.ConversationHistory.Ask

  use Jido.Action,
    name: "conversation_history_turn",
    description: "Generate an answer from history and commit the new turn",
    schema: Ask.schema(),
    output_schema: Zoi.object(%{session: Jido.Session.schema()})

  @impl Jido.Action
  def run(%{question: question}, context) do
    with {:ok, _prepared} <- Jido.AI.Turn.prepare(context, state_key: :session),
         {:ok, result} <-
           Jido.AI.respond_result(context, question,
             reply: Ask,
             context: context.agent_state.session,
             projection: [signal_action: Ask, input: :question, output: :answer]
           ),
         do: Jido.AI.Turn.complete(context, Ask, result, state_key: :session)
  end
end

defmodule JidoAI.Examples.ConversationHistory.Agent do
  @moduledoc "An Agent that projects only committed conversation pairs."

  alias JidoAI.Examples.ConversationHistory.{Ask, Turn}

  use Jido.AI.Agent, name: "conversation_history_example"

  state do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  @impl Jido.Agent
  def initialize(state, _context) do
    {:ok,
     Map.put_new_lazy(state, :session, fn ->
       Jido.Session.new!(metadata: %{example: "conversation_history"})
     end)}
  end

  ai do
    model :fast
    instructions "Use the committed conversation and answer briefly."
  end

  routes do
    signal_source "/examples/conversation"

    route Ask, Turn, as: :ask
  end
end

defmodule JidoAI.Examples.ConversationHistory do
  @moduledoc "Builds the complete AI Agent that projects committed history."

  alias JidoAI.Examples.ConversationHistory.Agent

  @doc "Builds an Agent with a new Session for committed conversation history."
  def new(opts \\ []), do: Agent.instantiate(opts)
end
