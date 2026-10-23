defmodule JidoAI.Examples.ConversationHistory.Projector do
  @moduledoc "Projects committed example Signals into a ReqLLM context."

  alias Jido.Signal
  alias JidoAI.Examples.ConversationHistory.Ask

  def project(%Jido.Thread{signals: signals}) do
    {_pending, pairs} = Enum.reduce(signals, {%{}, []}, &project_signal/2)

    messages = pairs |> Enum.reverse() |> Enum.flat_map(&pair_messages/1)

    ReqLLM.Context.new(messages)
  end

  defp project_signal(%Signal{type: type} = signal, {pending, pairs}) do
    cond do
      type == Ask.type() ->
        case Ask.validate_data(signal.data) do
          {:ok, data} -> {Map.put(pending, signal.id, data.question), pairs}
          {:error, _issues} -> {pending, pairs}
        end

      type == Ask.answer_type() ->
        project_reply(signal, pending, pairs)

      true ->
        {pending, pairs}
    end
  end

  defp project_signal(_signal, state), do: state

  defp project_reply(reply, pending, pairs) do
    request_id = Signal.get_context(reply, "jidocausationid")

    with {:ok, question} <- Map.fetch(pending, request_id),
         {:ok, data} <- Ask.validate_answer(reply.data) do
      {Map.delete(pending, request_id), [{question, data.answer} | pairs]}
    else
      _not_a_complete_pair -> {pending, pairs}
    end
  end

  defp pair_messages({question, answer}) do
    [ReqLLM.Context.user(question), ReqLLM.Context.assistant(answer)]
  end
end

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

  @doc "Returns the reply Signal type used by the local projector."
  def answer_type, do: @answer_type

  @doc "Validates reply data before the local projector reads it."
  def validate_answer(data), do: Zoi.parse(@answer_schema, data)

  @impl Jido.Action
  def run(%{question: question}, context) do
    conversation =
      JidoAI.Examples.ConversationHistory.Projector.project(context.agent_state.session.thread)

    Jido.AI.respond(context, question,
      reply: __MODULE__,
      conversation: conversation
    )
  end
end

defmodule JidoAI.Examples.ConversationHistory.LoadConversation do
  @moduledoc "Projects committed Session history for one reasoning request."

  use Jido.Action,
    name: "conversation_history_load",
    description: "Project committed Session history"

  @impl Jido.Action
  def run(%{session: %Jido.Session{} = session}, _context) do
    conversation =
      JidoAI.Examples.ConversationHistory.Projector.project(session.thread)

    {:ok, %{conversation: conversation}}
  end
end

defmodule JidoAI.Examples.ConversationHistory.Turn do
  @moduledoc "Generates an answer from committed history and commits the new turn."

  alias JidoAI.Examples.ConversationHistory.Ask

  use Jido.Flow,
    name: "conversation_history_turn",
    description: "Generate an answer from history and commit the new turn",
    schema: Ask.schema(),
    output_schema: Zoi.object(%{session: Jido.Session.schema()}),
    extensions: [Jido.AI.Flow.Extension]

  flow do
    step "prepare",
      action: Jido.AI.Actions.PrepareTurn,
      params: %{}

    step "conversation",
      action: JidoAI.Examples.ConversationHistory.LoadConversation,
      params: %{session: result("prepare", :turn_state)}

    reason("answer",
      prompt: input(:question),
      reply: Ask,
      conversation: result("conversation", :conversation)
    )

    step "commit",
         [
           answer <- result("answer", :output),
           state_key <- result("prepare", :state_key)
         ],
         inline: [
           description: "Complete one typed conversation turn",
           schema: Zoi.object(%{answer: Ask.output_schema(), state_key: Zoi.atom()}),
           context: context
         ] do
      Jido.AI.Turn.complete(context, Ask, answer, state_key: state_key)
    end

    output result("commit")
  end
end

defmodule JidoAI.Examples.ConversationHistory.Agent do
  @moduledoc "An Agent that projects only committed conversation pairs."

  alias JidoAI.Examples.ConversationHistory.{Ask, Turn}

  use Jido.AI.Agent, name: "conversation_history_example"

  agent do
    schema Zoi.object(%{session: Jido.Session.schema()})
  end

  ai do
    model :fast
    instructions "Use the committed conversation and answer briefly."
  end

  routes do
    signal_source "/examples/conversation"

    route Ask,
      via: Turn,
      as: :ask,
      emits: ["examples.conversation.answered"]
  end
end

defmodule JidoAI.Examples.ConversationHistory do
  @moduledoc "Builds the complete AI Agent that projects committed history."

  alias JidoAI.Examples.ConversationHistory.Agent

  @doc "Builds an Agent with a new Session for committed conversation history."
  def new(opts \\ []) do
    opts =
      Keyword.put_new_lazy(opts, :state, fn ->
        %{session: Jido.Session.new!(metadata: %{example: "conversation_history"})}
      end)

    Agent.instantiate(opts)
  end
end
