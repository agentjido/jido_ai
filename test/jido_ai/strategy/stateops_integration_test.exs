defmodule Jido.AI.Strategy.StateOpsIntegrationTest do
  use Jido.AI.Test.ReasoningCase, async: false
  alias Jido.AI.{Authoring, Context}
  alias Jido.AI.Test.StateMigration.{Agent, Change, Double, Update}

  # See docs/v3-spike/state-test-transfer.md for all old case mappings.
  defp start(jido, opts \\ []) do
    {:ok, profile} = Configuration.profile(Agent.agent())
    profile = %{profile | requests: %{profile.requests | streaming: Keyword.get(opts, :streaming, false)}}

    base = %{
      name: "state_transfer",
      schema: Agent.domain_schema(),
      routes: [{"ai.react.query", Authoring.ai(:assistant)}, {"state.change", Change}]
    }

    assert {:ok, definition} = Authoring.lower(base, [Map.from_struct(profile)])
    start_agent(jido, Jido.Agent.instantiate!(definition))
  end

  defp ask(server, mock, query \\ "Work"),
    do: request(server, mock, :react, query, context: %{observer: self()})

  defp call(id, kind, value \\ 1), do: %{id: id, name: "state_update", arguments: %{kind: kind, value: value}}

  test "new ReAct state has a profile and an idle session with no live handles", %{jido: jido} do
    server = start(jido)
    assert {:ok, view} = Session.snapshot(server)
    assert view.details.phase == :idle
    assert view.request == nil and view.live == nil
    assert view.details.tool_calls == []
    assert {:ok, profile} = Configuration.profile(view.agent)
    assert profile.reasoning.method == :react
    assert view.agent.state.requests == %{} and view.agent.state.count == 0
    assert :ok = Jido.Action.validate_static_data(view.agent.state)
  end

  test "admission records the query and live iteration without a Strategy state field", %{jido: jido} do
    mock = mock([%{reply: {:wait, :model, {:text, "Done"}}}])
    server = start(jido)
    assert {:ok, handle} = ask(server, mock, "test query")
    assert_receive {:mock_llm_waiting, ^mock, :model, _}, 2_000
    assert {:ok, view} = Session.snapshot(server)
    assert view.request.query == "test query" and view.request.status == :pending
    assert view.details.phase == :awaiting_llm and view.details.iteration == 1
    assert view.details.model_calls == 1 and view.details.active_request_id == handle.id
    assert is_binary(view.details.current_llm_call_id)
    assert Process.alive?(view.live.worker_pid)
    assert List.last(view.details.conversation).content == "test query"
    refute Map.has_key?(view.agent.state, :__strategy__)
    assert :ok = MockLLM.release(mock, :model)
    assert {:ok, "Done"} = Request.await(handle)
    assert_script_done(mock)
  end

  test "pending tools are tracked by ID and each completed tool leaves the pending set", %{jido: jido} do
    mock =
      mock([
        %{reply: {:tools, [call("one", "hold", 1), call("two", "hold", 2)]}},
        %{reply: {:wait, :answer, {:text, "Done"}}}
      ])

    server = start(jido)
    assert {:ok, handle} = ask(server, mock)
    assert_receive {:state_tool, first, "hold", 1, _}, 2_000
    assert_receive {:state_tool, second, "hold", 2, _}, 2_000
    assert {:ok, view} = Session.snapshot(server)
    assert view.details.phase == :executing_tool
    assert Enum.sort(Enum.map(view.details.tool_calls, & &1.id)) == ["one", "two"]
    send(first, :release)

    eventually(fn ->
      {:ok, live} = Session.snapshot(server)
      Enum.map(live.details.tool_calls, & &1.id) == ["two"]
    end)

    send(second, :release)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert {:ok, ready} = Session.snapshot(server)
    assert ready.details.tool_calls == []
    assert Enum.sort(Enum.map(ready.details.tool_results, & &1.id)) == ["one", "two"]
    assert ready.details.model_calls == 2 and ready.details.iteration == 2
    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Request.await(handle)
    assert_script_done(mock)
  end

  test "stream text appends in order and the terminal answer retains the whole text", %{jido: jido} do
    mock =
      mock([%{reply: {:stream, [%{content: "Hello"}, %{content: " "}, %{content: "world"}, {:wait, :text}], "stop"}}])

    server = start(jido, streaming: true)
    assert {:ok, handle} = ask(server, mock)
    assert_receive {:mock_llm_waiting, ^mock, :text, _}, 2_000

    eventually(fn ->
      {:ok, view} = Session.snapshot(server)
      view.details.streaming_text == "Hello world"
    end)

    assert :ok = MockLLM.release(mock, :text)
    assert {:ok, "Hello world"} = Request.await(handle)
    deltas = Enum.filter(events(handle), &(&1.kind == :llm_delta and &1.data.chunk_type == :content))
    assert Enum.map(deltas, & &1.data.delta) == ["Hello", " ", "world"]
    assert record(server, handle).result == "Hello world"
    assert_script_done(mock)
  end

  test "tool candidates commit with the answer and preserve unrelated live changes", %{jido: jido} do
    mock = mock([%{reply: {:tools, [call("set", "update", 5)]}}, %{reply: {:wait, :answer, {:text, "Done"}}}])
    server = start(jido)
    assert {:ok, handle} = ask(server, mock)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert Server.agent(server).state.count == 0
    signal = Jido.Signal.new!("state.change", %{label: "outside"}, source: "/test")
    assert {:ok, _} = Server.call(server, signal)
    assert :ok = MockLLM.release(mock, :answer)
    assert {:ok, "Done"} = Request.await(handle)

    assert %{count: 5, label: "outside", data: %{status: :running, iteration: 5}, answer: "Done"} =
             Server.agent(server).state

    assert [%{effects: %{allowed_count: 1}}] = record(server, handle).meta.tool_results
    assert_script_done(mock)
  end

  test "later tools read the staged candidate before the final Agent commit", %{jido: jido} do
    mock =
      mock([
        %{reply: {:tools, [call("set", "update", 5)]}},
        %{reply: {:tools, [call("read", "read")]}},
        %{reply: {:text, "Done"}}
      ])

    server = start(jido)
    assert {:ok, handle} = ask(server, mock)
    assert {:ok, "Done"} = Request.await(handle)
    assert_receive {:state_tool, _, "read", _, %{count: 5, data: %{iteration: 5}}}
    [_, _, wire] = MockLLM.report(mock).requests
    tool = Enum.find(wire.body["messages"], &(&1["tool_call_id"] == "read"))
    assert Jason.decode!(tool["content"])["result"]["count"] == 5
    assert Server.agent(server).state.count == 5
    assert_script_done(mock)
  end

  for kind <- ["invalid", "protected"] do
    test "#{kind} candidate cannot change committed domain or request state", %{jido: jido} do
      mock = mock([%{reply: {:tools, [call("bad", unquote(kind))]}}])
      server = start(jido)
      assert {:ok, handle} = ask(server, mock)
      assert {:error, _} = Request.await(handle)
      assert Server.agent(server).state.count == 0 and Server.agent(server).state.data == %{}
      assert Server.agent(server).state.answer == nil
      assert record(server, handle).status == :failed
      assert map_size(Server.agent(server).state.requests) == 1
      assert_script_done(mock)
    end
  end

  test "cancellation discards staged domain changes and clears live work", %{jido: jido} do
    mock = mock([%{reply: {:tools, [call("set", "update", 5)]}}, %{reply: {:wait, :answer, {:text, "unused"}}}])
    server = start(jido)
    assert {:ok, handle} = ask(server, mock)
    assert_receive {:mock_llm_waiting, ^mock, :answer, _}, 2_000
    assert :ok = Session.cancel(handle, reason: :stop)
    assert {:error, {:cancelled, :stop}} = Request.await(handle)
    assert Server.agent(server).state.count == 0 and Server.agent(server).state.data == %{}
    assert {:ok, view} = Session.snapshot(server)
    assert view.details.active_request_id == nil and view.details.tool_calls == [] and view.live == nil
    assert view.details.cancel_reason == :stop
    eventually(fn -> MockLLM.report(mock).waiting == [] end)
    assert_script_done(mock)
  end

  test "a later request resets usage and active fields while keeping prior results", %{jido: jido} do
    mock =
      mock([
        %{reply: {:tools, [call("set", "update", 2)]}},
        %{reply: {:text, "First"}},
        %{reply: {:wait, :next, {:text, "Next"}}}
      ])

    server = start(jido)
    assert {:ok, first} = ask(server, mock)
    assert {:ok, "First"} = Request.await(first)
    assert record(server, first).meta.usage.total_tokens == 30
    assert {:ok, next} = ask(server, mock, "Again")
    assert_receive {:mock_llm_waiting, ^mock, :next, _}, 2_000
    assert {:ok, view} = Session.snapshot(server)
    assert view.details.iteration == 1 and view.details.model_calls == 1
    assert view.details.usage == %{} and view.details.streaming_text == ""
    assert view.details.tool_calls == [] and view.details.tool_results == []
    assert view.details.active_request_id == next.id
    assert Server.agent(server).state.count == 2
    assert :ok = MockLLM.release(mock, :next)
    assert {:ok, "Next"} = Request.await(next)
    assert record(server, next).meta.usage.total_tokens == 15
    assert record(server, first).result == "First"
    assert {:ok, done} = Session.snapshot(server)
    assert done.details.active_request_id == nil and done.live == nil
    assert done.details.termination_reason == :final_answer
    assert_script_done(mock)
  end

  test "tool registration rebuilds all catalog views in the same order and can clear them", %{jido: jido} do
    server = start(jido)
    assert {:ok, _} = Jido.AI.register_tool(server, Double)
    assert {:ok, _} = Jido.AI.register_tool(server, Double)
    config = Jido.AI.get_strategy_config(Server.agent(server))
    assert config.tools == [Double, Update]
    assert config.actions_by_name == %{"state_update" => Update, "state_double" => Double}
    assert Enum.map(config.reqllm_tools, & &1.name) == ["state_double", "state_update"]

    mock =
      mock([
        %{reply: {:tools, [%{id: "double", name: "state_double", arguments: %{value: 5}}]}},
        %{reply: {:text, "10"}},
        %{reply: {:text, "Empty"}}
      ])

    assert {:ok, first} = ask(server, mock)
    assert {:ok, "10"} = Request.await(first)
    [wire, result] = MockLLM.report(mock).requests
    assert Enum.map(wire.body["tools"], & &1["function"]["name"]) == ["state_double", "state_update"]
    tool = Enum.find(result.body["messages"], &(&1["tool_call_id"] == "double"))
    assert Jason.decode!(tool["content"])["result"] == %{"result" => 10}
    assert {:ok, _} = Jido.AI.unregister_tool(server, "state_update")
    assert {:ok, _} = Jido.AI.unregister_tool(server, "state_double")
    empty = Jido.AI.get_strategy_config(Server.agent(server))
    assert empty.tools == [] and empty.actions_by_name == %{} and empty.reqllm_tools == []
    assert {:ok, next} = ask(server, mock, "No tools")
    assert {:ok, "Empty"} = Request.await(next)
    assert Map.get(List.last(MockLLM.report(mock).requests).body, "tools", []) == []
    assert_script_done(mock)
  end

  test "model generation and tool options come from the normalized profile", %{jido: jido} do
    mock = mock([%{reply: {:text, "Done"}}])
    server = start_reasoning(jido, :react, tools: [], max_tokens: 40, temperature: 0.2)
    config = Jido.AI.get_strategy_config(Server.agent(server))
    assert config.max_tokens == 40 and config.temperature == 0.2
    assert config.tools == [] and config.actions_by_name == %{} and config.reqllm_tools == []
    assert {:ok, handle} = ask(server, mock)
    assert {:ok, "Done"} = Request.await(handle)
    assert [wire] = MockLLM.report(mock).requests
    assert wire.body["max_tokens"] == 40 and wire.body["temperature"] == 0.2
    assert wire.body["model"] == "gpt-4o-mini"
    assert_script_done(mock)
  end

  test "history replacement preserves message order and empty replacement clears it", %{jido: jido} do
    mock = mock([%{reply: {:text, "Answer"}}, %{reply: {:text, "Fresh answer"}}])
    server = start(jido)

    context =
      Context.new(system_prompt: "History prompt") |> Context.append_user("Hello") |> Context.append_assistant("Hi")

    assert {:ok, _} = Session.modify_context(server, %{type: :replace, result_context: context})
    assert {:ok, first} = ask(server, mock, "Continue")
    assert {:ok, "Answer"} = Request.await(first)
    assert [wire] = MockLLM.report(mock).requests
    assert Enum.map(wire.body["messages"], & &1["content"]) == ["History prompt", "Hello", "Hi", "Continue"]
    assert {:ok, _} = Session.modify_context(server, %{type: :replace, result_context: Context.new()})
    assert {:ok, next} = ask(server, mock, "Fresh")
    assert {:ok, "Fresh answer"} = Request.await(next)
    last = List.last(MockLLM.report(mock).requests)
    assert Enum.map(last.body["messages"], & &1["content"]) == ["History prompt", "Fresh"]
    assert_script_done(mock)
  end

  test "history prepend and append use committed context entries without losing a sibling", %{jido: jido} do
    mock = mock([%{reply: {:text, "Done"}}])
    initial = Agent.new!(state: %{label: "keep"})
    context = Context.new() |> Context.append_user("first") |> Context.append_assistant("second")
    changed = Jido.AI.update_context_entries(initial, context.entries)
    assert initial.state.messages == [] and changed.state.label == "keep"
    server = start_agent(jido, changed)
    assert {:ok, handle} = ask(server, mock, "third")
    assert {:ok, "Done"} = Request.await(handle)
    assert [wire] = MockLLM.report(mock).requests
    assert Enum.map(wire.body["messages"], & &1["content"]) == ["State test", "first", "second", "third"]
    assert Server.agent(server).state.label == "keep"
    assert_script_done(mock)
  end
end
