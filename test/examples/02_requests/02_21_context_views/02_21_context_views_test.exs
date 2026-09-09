defmodule JidoAI.Examples.ContextViewsTest do
  use JidoAI.Examples.Case
  alias Jido.AI
  alias Jido.AI.{Context, Request}
  alias JidoAI.Examples.ContextViews.{Agent, Stateless}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{context_example: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  test "context entries retain time, thinking, tool identity and refs through the public view", %{
    jido: jido
  } do
    entries = rich_context().entries
    instance = AI.update_context_entries(Agent.new!(), entries)
    assert AI.get_strategy_context(instance).entries == entries
    assert AI.get_strategy_context(instance).entries == AI.get_strategy_context(instance).entries
    {mock, context} = mock([%{reply: {:text, "Reviewed"}}])
    server = start_agent(jido, instance)
    assert {:ok, "Reviewed"} = Agent.ask_sync(server, "Continue", context: context)
    [wire] = MockLLM.report(mock).requests
    [_, user, assistant, tool, query] = wire.body["messages"]
    assert user["content"] == "Earlier question"
    assert assistant["tool_calls"] |> hd() |> Map.fetch!("id") == "saved-tool"
    assert tool["tool_call_id"] == "saved-tool"
    assert tool["content"] == "Saved result"
    assert query["content"] == "Continue"
    view = AI.get_strategy_context(Server.agent(server))
    assert Enum.take(view.entries, -3) == entries
    assert_script_done(mock)
  end

  test "decoded thinking survives a committed history read and the next provider request", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: thinking_reply()}, %{reply: {:text, "Next"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, "First"} = Agent.ask_sync(server, "First", context: context)
    [assistant, user] = AI.get_strategy_context(Server.agent(server)).entries
    assert assistant.thinking == "Synthetic case thought"
    assert assistant.refs.request_id == user.refs.request_id
    assert [%{signature: "case-signature"}] = assistant.reasoning_details
    assert {:ok, messages} = AI.History.messages(Server.agent(server).state.messages)
    assert Enum.any?(List.last(messages).content, &(&1.type == :thinking))
    assert {:ok, "Next"} = Agent.ask_sync(server, "Next", context: context)
    [_, wire] = MockLLM.report(mock).requests
    saved = Enum.find(wire.body["messages"], &(&1["role"] == "assistant"))
    assert saved["reasoning_content"] == "Synthetic case thought"
    assert_script_done(mock)
  end

  test "missing history remains absent and a declared empty history gives a stable empty view", %{
    jido: jido
  } do
    plain = Jido.Agent.new!(name: "plain_context") |> Jido.Agent.instantiate!()
    assert AI.get_strategy_context(plain) == nil
    assert AI.get_strategy_config(plain) == %{}
    assert AI.list_tools(plain) == []
    refute AI.has_tool?(plain, "absent")
    assert AI.update_context_entries(plain, []) == plain
    assert {:error, _} = AI.register_tool_direct(plain, JidoAI.Examples.DynamicCatalog.Lookup)
    instance = Agent.new!()

    assert %Context{entries: [], system_prompt: "Review the case."} =
             AI.get_strategy_context(instance)

    assert AI.get_strategy_context(Agent.definition()) == nil
    stateless = Stateless.new!()
    assert AI.get_strategy_context(stateless) == nil
    assert AI.update_context_entries(stateless, rich_context().entries) == stateless
    {mock, context} = mock([%{reply: {:text, "Fresh"}}])
    server = start_agent(jido, stateless)

    assert {:ok, request} =
             Request.create_and_send(server, "Fresh",
               signal_type: "case.ask",
               source: "/examples/context",
               context: context
             )

    assert {:ok, "Fresh"} = Request.await(request)
    assert AI.get_strategy_context(Server.agent(server)) == nil
    assert_script_done(mock)
  end

  test "a history change during active work affects the next request and preserves later completion",
       %{
         jido: jido
       } do
    {mock, context} =
      mock([
        %{reply: {:wait, :active_context, {:text, "Active answer"}}},
        %{reply: {:text, "Next answer"}}
      ])

    instance =
      AI.update_context_entries(Agent.new!(), Context.append_user(Context.new(), "Old").entries)

    server = start_agent(jido, instance)
    assert {:ok, request} = Agent.ask(server, "Active", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :active_context, _}, 2_000
    before = Server.agent(server)
    view = AI.get_strategy_context(before)
    assert Enum.map(view.entries, & &1.content) == ["Active", "Old"]
    replacement = Context.append_user(Context.new(), "Summary").entries
    assert {:ok, changed} = replace(server, replacement)
    assert changed.state.requests == before.state.requests
    assert Enum.map(AI.get_strategy_context(changed).entries, & &1.content) == ["Summary"]
    :ok = MockLLM.release(mock, :active_context)
    assert {:ok, "Active answer"} = Agent.await(request)

    assert Enum.map(AI.get_strategy_context(Server.agent(server)).entries, & &1.content) ==
             ["Active answer", "Summary"]

    assert {:ok, "Next answer"} = Agent.ask_sync(server, "Next", context: context)
    [active, next] = MockLLM.report(mock).requests

    assert Enum.map(active.body["messages"], & &1["content"]) == [
             "Review the case.",
             "Old",
             "Active"
           ]

    assert Enum.map(next.body["messages"], & &1["content"]) ==
             ["Review the case.", "Summary", "Active answer", "Next"]

    assert_script_done(mock)
  end

  test "invalid or live history entries cannot commit or reach the provider", %{jido: jido} do
    server = start_agent(jido, Agent.new!())
    {mock, context} = mock([%{reply: {:text, "Valid"}}])
    original = Server.agent(server)

    for entries <- [
          [%{role: :unknown, content: "Bad"}],
          [%{role: :tool, content: "Missing ID"}],
          [%{role: :assistant, content: "", tool_calls: [%{id: "invalid"}]}],
          [%{role: :user, content: "Live", refs: %{pid: self()}}],
          [:invalid]
        ] do
      assert {:error, _} = replace(server, entries)
      assert Server.agent(server) == original
    end

    assert {:ok, "Valid"} = Agent.ask_sync(server, "Valid", context: context)
    [wire] = MockLLM.report(mock).requests
    assert Enum.map(wire.body["messages"], & &1["content"]) == ["Review the case.", "Valid"]
    assert_script_done(mock)
  end

  test "real tool and assistant entries retain request refs across later requests", %{jido: jido} do
    alias JidoAI.Examples.DynamicCatalog.Lookup

    {mock, context} =
      mock([
        %{reply: {:tools, [%{id: "live-tool", name: "lookup", arguments: %{id: "case-1"}}]}},
        %{reply: {:text, "Tool answer"}},
        %{reply: {:text, "Later answer"}}
      ])

    assert {:ok, instance} = AI.register_tool_direct(Agent.new!(), Lookup)
    server = start_agent(jido, instance)

    assert {:ok, first} =
             Agent.ask(server, "Tool question",
               context: context,
               extra_refs: %{case_id: "case-1"}
             )

    assert {:ok, "Tool answer"} = Agent.await(first)
    before = AI.get_strategy_context(Server.agent(server))
    assert Enum.map(before.entries, & &1.role) == [:assistant, :tool, :assistant, :user]

    for entry <- before.entries do
      assert entry.refs == %{
               request_id: first.id,
               run_id: Server.agent(server).state.requests[first.id].run_id,
               case_id: "case-1",
               source: "/ai/react/agent"
             }
    end

    assert Enum.find(before.entries, &(&1.role == :tool)).tool_call_id == "live-tool"
    assert {:ok, next} = Agent.ask(server, "Later question", context: context)
    assert {:ok, "Later answer"} = Agent.await(next)
    after_context = AI.get_strategy_context(Server.agent(server))
    assert Enum.drop(after_context.entries, 2) == before.entries
    assert Enum.take(after_context.entries, 2) |> Enum.all?(&(&1.refs.request_id == next.id))
    assert_script_done(mock)
  end

  test "string keyed stored entries keep thinking and references through context conversion", %{
    jido: jido
  } do
    entries = [
      %{
        "role" => "assistant",
        "content" => "Saved answer",
        "thinking" => "Saved thinking",
        "timestamp" => "2026-01-01T00:00:00Z",
        "refs" => %{"source_id" => "saved-1"}
      },
      %{"role" => "user", "content" => "Saved question", "timestamp" => "2026-01-01T00:00:00Z"}
    ]

    instance = AI.update_context_entries(Agent.new!(), entries)
    view = AI.get_strategy_context(instance)
    assert [assistant, user] = view.entries
    assert assistant.thinking == "Saved thinking"
    assert assistant.timestamp == "2026-01-01T00:00:00Z"
    assert assistant.refs == %{"source_id" => "saved-1"}
    assert user.role == :user
    {mock, context} = mock([%{reply: {:text, "Continued"}}])
    server = start_agent(jido, instance)
    assert {:ok, "Continued"} = Agent.ask_sync(server, "Continue", context: context)
    [wire] = MockLLM.report(mock).requests
    assistant = Enum.find(wire.body["messages"], &(&1["role"] == "assistant"))
    assert assistant["reasoning_content"] == "Saved thinking"
    assert_script_done(mock)
  end

  test "malformed stored thinking cannot replace valid content or break the next request", %{
    jido: jido
  } do
    entries =
      Enum.map([42, false, %{"invalid" => "thinking"}], fn value ->
        %{"role" => "assistant", "content" => "Kept answer", "thinking" => value}
      end)

    instance = AI.update_context_entries(Agent.new!(), entries)

    assert Enum.all?(
             AI.get_strategy_context(instance).entries,
             &(&1.thinking == nil and &1.content == "Kept answer")
           )

    {mock, context} = mock([%{reply: {:text, "Valid"}}])
    server = start_agent(jido, instance)
    assert {:ok, "Valid"} = Agent.ask_sync(server, "Continue", context: context)
    [wire] = MockLLM.report(mock).requests

    assert Enum.map(wire.body["messages"], & &1["content"]) ==
             ["Review the case.", "Kept answer", "Kept answer", "Kept answer", "Continue"]

    assert_script_done(mock)
  end

  test "restored v3 history retains its entries while pending work fails without replay", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        %{reply: {:wait, :restore_context, {:text, "Unused"}}},
        %{reply: {:text, "Restored"}}
      ])

    instance = AI.update_context_entries(Agent.new!(id: "saved-context"), rich_context().entries)
    server = start_agent(jido, instance)
    assert {:ok, pending} = Agent.ask(server, "Interrupted", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :restore_context, provider}, 2_000
    snapshot = Server.agent(server)
    provider_ref = Process.monitor(provider)
    saved = snapshot.state |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
    :ok = Server.stop(server)
    assert_receive {:DOWN, ^provider_ref, :process, ^provider, _}, 2_000
    restored = Agent.new!(id: snapshot.id, state: saved)
    assert AI.get_strategy_context(restored) == AI.get_strategy_context(snapshot)
    server = start_agent(jido, restored)
    handle = Request.Handle.new(pending.id, server, pending.query)
    assert {:error, :request_interrupted} = Request.await(handle)
    assert AI.get_strategy_context(Server.agent(server)) == AI.get_strategy_context(snapshot)
    assert {:ok, "Restored"} = Agent.ask_sync(server, "Continue", context: context)
    [_, wire] = MockLLM.report(mock).requests

    assert Enum.take(Enum.map(wire.body["messages"], & &1["content"]), -2) == [
             "Interrupted",
             "Continue"
           ]

    assert_script_done(mock)
  end

  defp replace(server, entries),
    do:
      Server.call(
        server,
        Jido.Signal.new!("case.history", %{entries: entries}, source: "/examples/context")
      )

  defp rich_context do
    timestamp = ~U[2026-01-01 00:00:00Z]

    Context.new()
    |> Context.append(%Context.Entry{
      role: :user,
      content: "Earlier question",
      timestamp: timestamp,
      refs: %{case_id: "case-1"}
    })
    |> Context.append(%Context.Entry{
      role: :assistant,
      content: "",
      thinking: "Saved thought",
      timestamp: timestamp,
      tool_calls: [ReqLLM.ToolCall.new("saved-tool", "lookup", ~s({"id":"case-1"}))],
      reasoning_details: [],
      refs: %{case_id: "case-1"}
    })
    |> Context.append(%Context.Entry{
      role: :tool,
      content: "Saved result",
      name: "lookup",
      tool_call_id: "saved-tool",
      timestamp: timestamp,
      refs: %{case_id: "case-1"}
    })
  end

  defp thinking_reply do
    {:raw,
     %{
       id: "thinking-context",
       object: "chat.completion",
       model: "gpt-4o-mini",
       choices: [
         %{
           index: 0,
           finish_reason: "stop",
           message: %{
             role: "assistant",
             content: "First",
             reasoning_content: "Synthetic case thought",
             reasoning_details: [%{signature: "case-signature", format: "openai", index: 0}]
           }
         }
       ],
       usage: %{prompt_tokens: 10, completion_tokens: 5, total_tokens: 15}
     }}
  end
end
