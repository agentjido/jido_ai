defmodule JidoAI.Examples.ConversationHistoryTest do
  use ExUnit.Case, async: false

  import Mimic

  alias Jido.Agent.Directive.Emit
  alias JidoAI.Examples.ConversationHistory
  alias JidoAI.Examples.ConversationHistory.{Agent, Ask, Projector, Turn}

  @moduletag :example

  setup :verify_on_exit!

  setup do
    original = Application.get_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: "openai:gpt-4o-mini"})
    on_exit(fn -> restore_aliases(original) end)
  end

  test "the routed turn projects history, reasons, and commits" do
    assert [%{handler: %{kind: :flow, target: Turn}}] = Agent.definition().routes
    assert %Jido.Flow{components: components} = Turn.flow()
    assert components |> Map.keys() |> Enum.sort() == ["answer", "commit", "conversation", "prepare"]
    assert components["prepare"].call.target == Jido.AI.Actions.PrepareTurn
    assert components["conversation"].call.target == JidoAI.Examples.ConversationHistory.LoadConversation
    assert components["commit"].call.target == Turn.step_action("commit")
    commit = Turn.step_action("commit")
    assert {Turn, _path} = apply(commit, :__jido_inline_action__, [])
    assert {:ok, _flow} = Jido.Flow.validate(Turn.flow())
  end

  test "the second turn receives only the first committed request and reply" do
    expect(ReqLLM, :generate_text, 2, fn model, context, _options ->
      case message_texts(context) do
        ["Use the committed conversation and answer briefly.", "My name is Ana."] ->
          {:ok, response(model, context, %{"answer" => "Hello Ana."})}

        [
          "Use the committed conversation and answer briefly.",
          "My name is Ana.",
          "Hello Ana.",
          "What is my name?"
        ] ->
          {:ok, response(model, context, %{"answer" => "Your name is Ana."})}
      end
    end)

    assert {:ok, %Jido.Agent{module: Agent} = agent} =
             ConversationHistory.new(id: "conversation-history")

    first = Ask.new!(%{question: "My name is Ana."})
    assert {:ok, agent, [%Emit{}]} = Agent.cmd(agent, first)

    thread_before_projection = agent.state.session.thread
    second = Ask.new!(%{question: "What is my name?"})
    assert {:ok, agent, [%Emit{signal: reply}]} = Agent.cmd(agent, second)

    assert reply.data == %{answer: "Your name is Ana."}
    assert thread_before_projection.signals == Enum.take(agent.state.session.thread.signals, 2)
    assert agent.state.session.thread.rev == 4
    assert agent.state.session.metadata == %{example: "conversation_history"}
  end

  test "projection uses correlation and excludes unrelated and incomplete Signals" do
    request = Ask.new!(%{question: "Keep this."})
    {:ok, reply} = Ask.reply(request, %{answer: "Kept."})

    {:ok, reply} = Jido.Signal.put_context(reply, "diagnostic", "trace-1")

    unrelated =
      Jido.Signal.new!(
        "examples.conversation.note",
        %{text: "This is not a model message."},
        source: "/examples/conversation"
      )

    incomplete = Ask.new!(%{question: "Do not include this."})
    thread = Jido.Thread.new!()

    {:ok, thread} =
      Jido.Thread.append_many(thread, [unrelated, request, reply, incomplete])

    original = thread

    context = Projector.project(thread)

    assert message_texts(context) == ["Keep this.", "Kept."]
    assert Enum.all?(context.messages, &(&1.metadata == %{}))
    assert Enum.all?(context.messages, &(&1.reasoning_details in [nil, []]))
    assert thread == original
  end

  test "projection ignores malformed request and reply data" do
    request = Ask.new!(%{question: "Valid question"})
    {:ok, reply} = Ask.reply(request, %{answer: "Valid answer"})
    malformed_request = %{request | data: %{question: 123}}
    malformed_reply = %{reply | data: %{answer: 123}}
    thread = Jido.Thread.new!()

    {:ok, thread} =
      Jido.Thread.append_many(thread, [malformed_request, reply, request, malformed_reply])

    assert Projector.project(thread).messages == []
  end

  defp message_texts(context) do
    Enum.map(ReqLLM.Context.to_list(context), fn message ->
      message.content |> List.first() |> Map.fetch!(:text)
    end)
  end

  defp response(model, context, object) do
    %ReqLLM.Response{
      id: "conversation-response",
      model: model,
      context: context,
      message: ReqLLM.Context.assistant(""),
      object: object
    }
  end

  defp restore_aliases(nil), do: Application.delete_env(:jido_ai, :model_aliases)
  defp restore_aliases(aliases), do: Application.put_env(:jido_ai, :model_aliases, aliases)
end
