defmodule JidoAI.Examples.ConversationHistory.Ask do
  @moduledoc "Defines a stateful conversation request and reply."

  @answer_schema Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)})

  use Jido.Action,
    name: "conversation_history_ask",
    description: "Ask one question with committed history",
    schema: Zoi.object(%{question: Zoi.string() |> Zoi.min(1)}),
    output_schema: @answer_schema

  @impl Jido.Action
  def run(%{question: question}, context) do
    Jido.AI.respond(context, question,
      reply: {JidoAI.Examples.ConversationHistory.Agent, "examples.conversation.ask"},
      context: context.agent_state.session,
      projection: [
        route: {JidoAI.Examples.ConversationHistory.Agent, "examples.conversation.ask"},
        input: :question,
        output: :answer
      ]
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
             reply: {JidoAI.Examples.ConversationHistory.Agent, "examples.conversation.ask"},
             context: context.agent_state.session,
             projection: [
               route: {JidoAI.Examples.ConversationHistory.Agent, "examples.conversation.ask"},
               input: :question,
               output: :answer
             ]
           ),
         do:
           Jido.AI.Turn.complete(
             context,
             {JidoAI.Examples.ConversationHistory.Agent, "examples.conversation.ask"},
             result,
             state_key: :session
           )
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

    route "examples.conversation.ask", Turn, as: :ask do
      state(from: output(:state))
      reply("examples.conversation.answered", from: output(:reply))
    end
  end
end

defmodule JidoAI.Examples.ConversationHistory do
  @moduledoc "Builds the complete AI Agent that projects committed history."

  alias JidoAI.Examples.ConversationHistory.Agent

  @doc "Builds an Agent with a new Session for committed conversation history."
  def new(opts \\ []), do: Agent.instantiate(opts)
end
