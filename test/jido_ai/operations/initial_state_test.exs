defmodule Jido.AI.InitialStateTest do
  use Jido.AI.Test.ReasoningCase, async: false
  alias Jido.AI.{Agent, Conversation, History, Profile}

  defp source, do: definition(:react, tools: [], model: MockLLM.model(), system_prompt: "Configured")

  defp saved(prompt \\ "Saved", messages \\ [%{role: :user, content: "Previous"}]) do
    thread = Jido.Thread.new(metadata: %{system_prompt: prompt})
    {:ok, session} = Conversation.append(Jido.Session.new(thread: thread), messages)
    session
  end

  test "import preserves the canonical value and required domain fields" do
    source = source()
    fields = source.schema.fields |> Keyword.put(:messages, Jido.Session.schema()) |> Keyword.put(:count, Zoi.integer())
    source = %{source | schema: %{source.schema | fields: fields}}
    session = saved()
    assert {:ok, agent} = Agent.from_initial_state(source, %{messages: session, count: 7}, id: "restored")
    assert agent.id == "restored" and agent.state.count == 7
    assert agent.state.messages == session
    assert source.state == nil
    assert {:error, _} = Agent.from_initial_state(source, %{messages: session, count: "invalid"})
    assert {:error, _} = Agent.from_initial_state(source, %{count: 7})
  end

  test "missing conversation uses defaults and an empty saved prompt remains explicit" do
    assert {:ok, agent} = Agent.from_initial_state(source(), %{})
    assert is_nil(agent.state.messages)
    assert {:ok, %Profile{instructions: "Configured"} = profile} = Configuration.profile(agent)
    assert {:ok, []} = History.read(agent.state, profile)
    assert {:ok, empty} = Agent.from_initial_state(source(), %{messages: saved("")})
    assert {:ok, %Profile{instructions: ""}} = Configuration.profile(empty)
  end

  test "import rejects runtime fields, legacy context, and duplicate aliases" do
    for state <- [
          %{__strategy__: %{}},
          %{requests: %{}},
          %{jido_ai_config: %{}},
          %{unknown: 1},
          %{context: saved()},
          %{:messages => saved(), "messages" => saved()}
        ] do
      assert {:error, _} = Agent.from_initial_state(source(), state)
    end
  end

  test "import rejects invalid options and existing instances" do
    for opts <- [[profile: :absent], [id: "a", id: "b"], [unknown: true], %{}] do
      assert {:error, _} = Agent.from_initial_state(source(), %{messages: saved()}, opts)
    end

    assert {:error, _} = Agent.from_initial_state(Jido.Agent.instantiate!(source()), %{messages: saved()})
    assert {:error, _} = Agent.from_initial_state(:not_an_agent, %{})
  end

  test "malformed and process-local Session data is rejected" do
    session = saved()
    [entry] = session.thread.entries

    for invalid <- [
          %{session | id: nil},
          %{session | thread: %{session.thread | entries: [42]}},
          %{session | thread: %{session.thread | metadata: %{system_prompt: false}}},
          %{session | thread: %{session.thread | entries: [%{entry | refs: %{pid: self()}}]}}
        ] do
      assert {:error, _} = Agent.from_initial_state(source(), %{messages: invalid})
    end
  end

  test "import requires a complete and correctly ordered tool exchange" do
    call = ReqLLM.ToolCall.new("one", "echo", ~s({"value":5}))
    assistant = %ReqLLM.Message{role: :assistant, content: [], tool_calls: [call]}
    result = ReqLLM.Context.tool_result("one", "echo", "5")

    for messages <- [
          [assistant],
          [result],
          [assistant, result, result],
          [assistant, ReqLLM.Context.user("Interrupted")]
        ] do
      assert {:error, _} = Agent.from_initial_state(source(), %{messages: saved(nil, messages)})
    end

    assert {:ok, agent} = Agent.from_initial_state(source(), %{messages: saved(nil, [assistant, result])})
    assert Jido.Thread.entry_count(agent.state.messages.thread) == 2
  end

  test "encoded Session imports without copying entries or losing references" do
    {:ok, session} = Conversation.append(saved(), [ReqLLM.Context.assistant("Old answer")], %{case: "one"})
    input = session |> Jido.Session.encode() |> Jason.encode!() |> Jason.decode!()
    assert {:ok, agent} = Agent.from_initial_state(source(), %{"messages" => input})
    assert agent.state.messages.id == session.id
    assert Enum.map(agent.state.messages.thread.entries, & &1.id) == Enum.map(session.thread.entries, & &1.id)
    assert List.last(agent.state.messages.thread.entries).refs["case"] == "one"
    assert {:ok, projected} = Conversation.messages(agent.state.messages)
    assert Enum.map(projected, &Jido.AI.Query.summarize(&1.content)) == ["Previous", "Old answer"]
    assert {:ok, %Profile{instructions: "Saved"}} = Configuration.profile(agent)
    assert {:error, _} = Agent.from_initial_state(source(), %{messages: Map.put(input, "version", 999)})
  end

  test "final state size includes the imported prompt" do
    assert {:ok, source} = Jido.AI.Authoring.with_state_size_limit(source(), 8_000)
    assert {:ok, _} = Agent.from_initial_state(source, %{messages: saved()})
    assert {:error, _} = Agent.from_initial_state(source, %{messages: saved(String.duplicate("x", 9_000))})
  end
end
