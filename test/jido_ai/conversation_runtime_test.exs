defmodule Jido.AI.ConversationRuntimeTest do
  use Jido.AI.Test.ReasoningCase, async: false

  test "one canonical Session stores successive requests without a synchronized copy", %{jido: jido} do
    mock = mock([%{reply: {:text, "First"}}, %{reply: {:text, "Second"}}])
    server = start_reasoning(jido, :react, tools: [])
    assert {:ok, first} = request(server, mock, :react, "One")
    assert {:ok, "First"} = Request.await(first)
    initial = Server.agent(server).state.messages
    assert %Jido.Session{thread: %Jido.Thread{rev: 2}} = initial
    assert {:ok, second} = request(server, mock, :react, "Two")
    assert {:ok, "Second"} = Request.await(second)
    state = Server.agent(server).state
    assert state.messages.id == initial.id
    assert state.messages.thread.rev == 4
    assert state[Jido.AI.Context.Operations.key()] == %{}
    assert {:ok, messages} = Jido.AI.Conversation.messages(state.messages)
    assert Enum.map(messages, &Jido.AI.Query.summarize(&1.content)) == ["One", "First", "Two", "Second"]
    assert_script_done(mock)
  end

  test "replacement stores a canonical Thread and the next request uses it", %{jido: jido} do
    mock = mock([%{reply: {:text, "First"}}, %{reply: {:text, "After replacement"}}])
    server = start_reasoning(jido, :react, tools: [])
    assert {:ok, first} = request(server, mock, :react, "One")
    assert {:ok, "First"} = Request.await(first)
    original = Server.agent(server).state.messages
    {:ok, replacement} = Jido.AI.Conversation.append(Jido.Thread.new(), [ReqLLM.Context.user("Saved question")])
    assert {:ok, _} = Session.modify_context(server, %{type: :replace, result_context: replacement}, op_id: "replace-1")
    state = Server.agent(server).state
    assert state.messages.id == original.id
    operation = List.last(state.messages.thread.entries)
    assert {:ok, %{operation: %{result_context: %Jido.Thread{}}}} = Jido.AI.Conversation.Operation.decode(operation)

    assert {:ok, decoded} =
             state.messages |> Jido.Session.encode() |> Jason.encode!() |> Jason.decode!() |> Jido.Session.decode()

    {:ok, profile} = Configuration.profile(Server.agent(server))
    assert {:ok, [%{content: saved}]} = Jido.AI.History.read(%{messages: decoded}, profile)
    assert Jido.AI.Query.summarize(saved) == "Saved question"
    refute Map.has_key?(state[Jido.AI.Context.Operations.key()].assistant, :session)
    assert {:ok, second} = request(server, mock, :react, "Continue")
    assert {:ok, "After replacement"} = Request.await(second)
    [_, wire] = MockLLM.report(mock).requests
    assert [%{"role" => "system", "content" => prompt} | conversation] = wire.body["messages"]
    assert prompt =~ "ReAct"
    assert Enum.map(conversation, & &1["content"]) == ["Saved question", "Continue"]
    assert_script_done(mock)
  end
end
