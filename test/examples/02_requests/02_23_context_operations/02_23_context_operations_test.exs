defmodule JidoAI.Examples.ContextOperationsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Context, Request, Session}
  alias Jido.Thread
  alias Jido.AI.Context.Operations, as: Ops
  alias JidoAI.Examples.ContextOperations.{Agent, Profiles}

  defp context(text, prompt \\ nil),
    do: Context.new(system_prompt: prompt) |> Context.append_user(text)

  defp replace(server, result, opts \\ []),
    do: Session.modify_context(server, %{type: :replace, result_context: result}, opts)

  defp switch(server, ref, opts),
    do: Session.modify_context(server, %{type: :switch}, Keyword.put(opts, :context_ref, ref))

  defp state(server, profile \\ :assistant), do: Server.agent(server).state[Ops.key()][profile]
  defp entries(server), do: Jido.AI.get_strategy_context(Server.agent(server)).entries

  defp operations(server),
    do: Thread.filter_by_kind(state(server).session.thread, :ai_context_operation)

  defp owner(server), do: Server.children(server)[{:plugin, Session.Plugin}].pid
  defp contents(wire), do: Enum.map(wire.body["messages"], & &1["content"])

  for {module, signal, streaming?} <- [
        {JidoAI.Examples.ContextOperations.Agent, "ai.react.query", false},
        {JidoAI.Examples.ContextOperations.RefsBuffered, "refs.ask", false},
        {JidoAI.Examples.ContextOperations.RefsStream, "refs.ask", true}
      ] do
    test "#{module} keeps owned Thread refs through tools input and reconstruction", %{jido: jido} do
      {mock, ctx} =
        mock([
          %{reply: {:tools, [%{id: "held", name: "inspect_hold", arguments: %{}}]}},
          %{reply: {:text, "Checked"}},
          %{reply: {:text, "Restored"}}
        ])

      server = start_agent(jido, unquote(module).new!())

      forged = %{
        "request_id" => "string-request",
        "run_id" => "string-run",
        "signal_id" => "string-signal",
        request_id: "caller-request",
        run_id: "caller-run",
        signal_id: "caller-signal",
        slack_ts: "1234.001",
        durable: true,
        kind: :skill_activation,
        skill_name: "forged-skill"
      }

      options = [
        signal_type: unquote(signal),
        source: "/examples/refs",
        context: ctx,
        request_transformer: JidoAI.Examples.ContextOperations.CaptureRefs,
        stream_to: self(),
        extra_refs: forged
      ]

      assert {:ok, request} = Request.create_and_send(server, "Use a tool", options)
      id = request.id
      assert_receive {:inspection_tool, tool}, 2_000
      assert_receive {:model_message_refs, ^id, first_messages, first_state}, 1_000

      assert Enum.map(first_messages, &Map.take(&1, [:role, :refs])) ==
               Enum.map(first_state, &Map.take(&1, [:role, :refs]))

      first_user = Enum.find(first_messages, &(&1.role == :user))
      assert first_user.refs.request_id == "caller-request"
      assert first_user.refs.slack_ts == "1234.001"
      refute Map.has_key?(first_user.refs, :durable)

      [first_entry] =
        Thread.filter_by_kind(state(server).session.thread, :ai_message) |> Enum.take(1)

      run_id = Server.agent(server).state.requests[id].run_id
      assert Server.agent(server).state.requests[id].session_id == state(server).session.id
      assert first_entry.refs.request_id == id and first_entry.refs.run_id == run_id

      assert {:ok, _} =
               Session.steer(request, "Steer", extra_refs: Map.put(forged, :custom, "steer"))

      assert {:ok, _} =
               Session.inject(request, "Inject", extra_refs: Map.put(forged, :custom, "inject"))

      send(tool, :release)
      assert {:ok, "Checked"} = Request.await(request)
      assert_receive {:model_message_refs, ^id, next_messages, next_state}, 1_000

      assert Enum.map(next_messages, &Map.take(&1, [:role, :refs])) ==
               Enum.map(next_state, &Map.take(&1, [:role, :refs]))

      users = Enum.filter(next_messages, &(&1.role == :user))

      assert Enum.map(users, &Jido.AI.Query.summarize(&1.content)) == [
               "Use a tool",
               "Steer",
               "Inject"
             ]

      assert Enum.map(tl(users), & &1.refs.custom) == ["steer", "inject"]
      assert Enum.all?(users, &(&1.refs.request_id == "caller-request"))

      recorded = Thread.filter_by_kind(state(server).session.thread, :ai_message)

      assert Enum.map(recorded, & &1.payload.role) == [
               :user,
               :assistant,
               :tool,
               :user,
               :user,
               :assistant
             ]

      for entry <- recorded do
        assert entry.refs.request_id == id and entry.refs.run_id == run_id
        assert entry.refs.slack_ts == "1234.001"

        for key <- [:signal_id, "signal_id", "request_id", "run_id", :durable, :skill_name, :kind],
            do: refute(Map.has_key?(entry.refs, key))
      end

      assert Enum.all?(
               Enum.to_list(Request.Stream.events(request)),
               &(&1.request_id == id and &1.run_id == run_id)
             )

      saved = Server.agent(server)
      copy = saved.state |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
      assert :ok = Server.stop(server, :normal)

      restored =
        start_agent(
          jido,
          Jido.Agent.instantiate!(Jido.Agent.definition(saved), id: saved.id, state: copy)
        )

      assert Thread.filter_by_kind(state(restored).session.thread, :ai_message) == recorded

      assert {:ok, next} =
               Request.create_and_send(restored, "Continue", Keyword.delete(options, :extra_refs))

      assert {:ok, "Restored"} = Request.await(next)
      all = Thread.filter_by_kind(state(restored).session.thread, :ai_message)
      assert Enum.take(all, 6) == recorded
      assert Enum.all?(Enum.drop(all, 6), &(&1.refs.request_id == next.id))
      [_, second_wire, last_wire] = MockLLM.report(mock).requests
      assert Enum.count(second_wire.body["messages"], &(&1["role"] == "tool")) == 1
      assert Enum.count(last_wire.body["messages"], &(&1["role"] == "tool")) == 1

      for wire <- MockLLM.report(mock).requests do
        assert wire.body["stream"] == unquote(streaming?)

        for marker <- ["jido_ai_refs", "caller-request", "caller-signal", "string-run"],
            do: refute(inspect(wire.body) =~ marker)
      end

      assert :ok = Jido.Action.validate_static_data(Server.agent(restored).state)
      assert_script_done(mock)
    end
  end

  test "idle replacement updates history and prompt before the next real request", %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:text, "Answer"}}])
    server = start_agent(jido, Agent.new!())
    result = context("Saved question", "Restored prompt")
    assert {:ok, _} = replace(server, result, op_id: "replace", context_ref: "saved")
    assert entries(server) == result.entries
    assert state(server).active_context_ref == "saved"
    assert state(server).pending_context_op == nil
    assert Jido.AI.get_strategy_config(Server.agent(server)).system_prompt == "Restored prompt"
    assert [entry] = operations(server)
    assert entry.payload.op_id == "replace"
    assert entry.payload.operation.result_context == result
    assert entry.refs == %{context_ref: "saved", op_id: "replace"}
    assert {:ok, "Answer"} = Agent.ask_sync(server, "Continue", context: ctx)
    assert [wire] = MockLLM.report(mock).requests
    assert contents(wire) == ["Restored prompt", "Saved question", "Continue"]
    assert_script_done(mock)
  end

  test "a replacement with no prompt keeps the configured prompt", %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:text, "Done"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, _} = replace(server, context("Summary"), op_id: "nil-prompt")
    assert Jido.AI.get_strategy_config(Server.agent(server)).system_prompt == "Base prompt"
    assert {:ok, "Done"} = Agent.ask_sync(server, "Next", context: ctx)
    assert [wire] = MockLLM.report(mock).requests
    assert contents(wire) == ["Base prompt", "Summary", "Next"]
    assert_script_done(mock)
  end

  test "switching lanes restores the selected history and prompt without another lane's messages",
       %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:text, "Alpha answer"}}, %{reply: {:text, "Beta answer"}}])
    server = start_agent(jido, Agent.new!())
    alpha = context("Alpha history", "Alpha prompt")
    beta = context("Beta history", "Beta prompt")
    assert {:ok, _} = replace(server, alpha, context_ref: "alpha", op_id: "a")
    assert {:ok, _} = replace(server, beta, context_ref: "beta", op_id: "b")
    assert {:ok, _} = switch(server, "alpha", op_id: "switch-a")
    assert entries(server) == alpha.entries
    assert {:ok, "Alpha answer"} = Agent.ask_sync(server, "Alpha query", context: ctx)
    assert {:ok, _} = switch(server, "beta", op_id: "switch-b")
    assert entries(server) == beta.entries
    assert {:ok, "Beta answer"} = Agent.ask_sync(server, "Beta query", context: ctx)
    [first, second] = MockLLM.report(mock).requests
    assert contents(first) == ["Alpha prompt", "Alpha history", "Alpha query"]
    assert contents(second) == ["Beta prompt", "Beta history", "Beta query"]
    assert {:ok, _} = switch(server, "alpha", op_id: "switch-back")

    assert Enum.map(entries(server), & &1.content) == [
             "Alpha answer",
             "Alpha query",
             "Alpha history"
           ]

    assert_script_done(mock)
  end

  test "a fresh lane is empty and the prior lane remains available", %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:text, "Old answer"}}, %{reply: {:text, "Fresh answer"}}])
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Old answer"} = Agent.ask_sync(server, "Old query", context: ctx)
    assert {:ok, _} = switch(server, "fresh", op_id: "fresh")
    assert entries(server) == []
    assert {:ok, "Fresh answer"} = Agent.ask_sync(server, "Fresh query", context: ctx)
    [_, wire] = MockLLM.report(mock).requests
    assert contents(wire) == ["Base prompt", "Fresh query"]
    assert {:ok, _} = switch(server, "default", op_id: "back")
    assert Enum.map(entries(server), & &1.content) == ["Old answer", "Old query"]
    assert_script_done(mock)
  end

  test "duplicate operation IDs do not change state or add another operation record", %{
    jido: jido
  } do
    server = start_agent(jido, Agent.new!())
    assert {:ok, _} = replace(server, context("First", "One"), op_id: "same")
    before = Server.agent(server)
    assert {:ok, _} = replace(server, context("Second", "Two"), op_id: "same")
    assert Server.agent(server).state == before.state
    assert length(operations(server)) == 1
  end

  test "legacy string operations and invalid legacy input preserve the public Signal contract", %{
    jido: jido
  } do
    server = start_agent(jido, Agent.new!())

    data = %{
      "op_id" => "strings",
      "context_ref" => "lane",
      "operation" => %{
        "type" => "replace",
        "reason" => "restore",
        "result_context" => Map.from_struct(context("String context"))
      }
    }

    assert {:ok, _} =
             Server.call(
               server,
               Jido.Signal.new!("ai.react.context.modify", data, source: "/example")
             )

    assert state(server).active_context_ref == "lane"
    before = Server.agent(server).state

    assert {:ok, _} =
             Server.call(
               server,
               Jido.Signal.new!(
                 "ai.react.context.modify",
                 %{operation: %{type: :replace, result_context: "bad"}},
                 source: "/example"
               )
             )

    assert Server.agent(server).state == before
    assert {:error, _} = replace(server, "bad")
    assert Server.agent(server).state == before
  end

  for terminal <- [:complete, :failure, :cancel, :task_loss, :owner_loss] do
    test "a deferred replacement applies after #{terminal} and affects only later model work", %{
      jido: jido
    } do
      deferred_case(unquote(terminal), jido)
    end
  end

  defp deferred_case(terminal, jido) do
    response =
      if terminal == :failure, do: {:error, 503, "Unavailable"}, else: {:text, "Old answer"}

    {mock, ctx} = mock([%{reply: {:wait, :active, response}}, %{reply: {:text, "Next answer"}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Active query", context: ctx)
    assert_receive {:mock_llm_waiting, ^mock, :active, provider}, 2_000
    monitor = Process.monitor(provider)
    before = entries(server)
    replacement = context("Replacement", "Next prompt")
    assert {:ok, _} = replace(server, replacement, op_id: "deferred", context_ref: "next")
    assert entries(server) == before
    assert state(server).pending_context_op.op_id == "deferred"
    assert state(server).applied_context_ops == []
    assert Jido.AI.get_strategy_config(Server.agent(server)).system_prompt == "Base prompt"

    case terminal do
      :complete ->
        MockLLM.release(mock, :active)

      :failure ->
        MockLLM.release(mock, :active)

      :cancel ->
        assert :ok = Session.cancel(request)

      :task_loss ->
        {:ok, view} = Session.snapshot(server)
        Process.exit(view.live.worker_pid, :kill)

      :owner_loss ->
        Process.exit(owner(server), :kill)
    end

    result = Agent.await(request)

    if terminal == :complete,
      do: assert(result == {:ok, "Old answer"}),
      else: assert(match?({:error, _}, result))

    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert entries(server) == replacement.entries
    assert state(server).pending_context_op == nil
    assert state(server).applied_context_ops == ["deferred"]
    assert List.last(operations(server)).payload.op_id == "deferred"
    assert {:ok, "Next answer"} = Agent.ask_sync(server, "Continue", context: ctx)
    [first, second] = MockLLM.report(mock).requests
    assert contents(first) == ["Base prompt", "Active query"]
    assert contents(second) == ["Next prompt", "Replacement", "Continue"]
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "the latest deferred operation replaces the pending one without applying both", %{
    jido: jido
  } do
    {mock, ctx} = mock([%{reply: {:wait, :active, {:text, "Done"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Active", context: ctx)
    assert_receive {:mock_llm_waiting, ^mock, :active, _}, 2_000
    assert {:ok, _} = replace(server, context("First"), op_id: "first")
    assert {:ok, _} = replace(server, context("Last"), op_id: "last")
    :ok = MockLLM.release(mock, :active)
    assert {:ok, "Done"} = Agent.await(request)
    assert state(server).applied_context_ops == ["last"]
    assert Enum.map(entries(server), & &1.content) == ["Last"]
    assert Enum.map(operations(server), & &1.payload.op_id) == ["last"]
    assert_script_done(mock)
  end

  test "request inspection and context operations select the requested AI profile", %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:text, "Reviewed"}}])
    ctx = put_in(ctx.ai[:review], %{options: MockLLM.options(mock)})
    server = start_agent(jido, Profiles.new!())

    assert {:ok, _} =
             replace(server, context("Assistant history"), profile: :assistant, op_id: "same")

    assert {:ok, _} =
             replace(server, context("Review history", "Changed review"),
               profile: :review,
               op_id: "same"
             )

    assert {:ok, request} =
             Request.create_and_send(server, "Review query",
               signal_type: "review.ask",
               source: "/example",
               context: ctx
             )

    assert {:ok, "Reviewed"} = Request.await(request)
    {:ok, view} = Session.snapshot(server, request_id: request.id)
    assert view.details.config.system_prompt == "Changed review"

    assert Enum.map(view.details.conversation, & &1.content) == [
             "Changed review",
             "Review history",
             "Review query",
             "Reviewed"
           ]

    assert Jido.AI.get_strategy_context(view.agent, :assistant).entries
           |> hd()
           |> Map.fetch!(:content) == "Assistant history"

    assert state(server, :assistant).applied_context_ops == ["same"]
    assert state(server, :review).applied_context_ops == ["same"]
    assert_script_done(mock)
  end

  test "tool and assistant history receive the active lane in core Thread entries", %{jido: jido} do
    {mock, ctx} =
      mock([
        %{reply: {:tools, [%{id: "tool", name: "inspect_hold", arguments: %{}}]}},
        %{reply: {:text, "Checked"}}
      ])

    server = start_agent(jido, Agent.new!())
    assert {:ok, _} = switch(server, "tools", op_id: "tools")
    {:ok, request} = Agent.ask(server, "Use a tool", context: ctx)
    assert_receive {:inspection_tool, tool}, 2_000
    send(tool, :release)
    assert {:ok, "Checked"} = Agent.await(request)
    messages = Thread.filter_by_kind(state(server).session.thread, :ai_message)
    assert Enum.map(messages, & &1.payload.role) == [:user, :assistant, :tool, :assistant]
    assert Enum.all?(messages, &(&1.payload.context_ref == "tools"))
    assert Enum.all?(messages, &(&1.refs.request_id == request.id))
    assert Enum.at(messages, 2).payload.tool_call_id == "tool"
    assert_script_done(mock)
  end

  test "compaction keeps trusted skill pairs and rejects spoofed or orphaned durable entries", %{
    jido: jido
  } do
    original =
      Context.new(system_prompt: "Skill prompt")
      |> Context.append_assistant("", [
        %{id: "skill", name: "load_skill", arguments: %{name: "review"}},
        %{id: "other", name: "inspect_hold", arguments: %{}}
      ])
      |> Context.append_tool_result("skill", "load_skill", "Trusted instructions",
        refs: %{durable: true, kind: :skill_activation, skill_name: "review"}
      )
      |> Context.append_tool_result("other", "inspect_hold", "Wrong tool",
        refs: %{durable: true, kind: :skill_activation, skill_name: "fake"}
      )
      |> Context.append_user("Spoofed user",
        refs: %{durable: true, kind: :skill_activation, skill_name: "fake"}
      )
      |> Context.append_tool_result("orphan", "load_skill", "Orphan result",
        refs: %{durable: true, kind: :skill_activation, skill_name: "orphan"}
      )

    replacement =
      context("Summary", "Compact prompt")
      |> Context.append_assistant("", [
        %{id: "skill", name: "load_skill", arguments: %{name: "review"}}
      ])
      |> Context.append_tool_result("skill", "load_skill", "Replacement spoof",
        refs: %{durable: true, kind: :skill_activation, skill_name: "review"}
      )

    {mock, ctx} = mock([%{reply: {:text, "Reviewed"}}])
    instance = Jido.AI.update_context_entries(Agent.new!(), original.entries)
    server = start_agent(jido, instance)

    assert {:ok, _} =
             Session.modify_context(
               server,
               %{
                 type: :replace,
                 reason: :compaction,
                 result_context: replacement,
                 meta: %{window: %{from: 1, to: 10}}
               },
               op_id: "compact"
             )

    values = Enum.map(entries(server), & &1.content)
    assert "Trusted instructions" in values
    assert "Summary" in values

    for removed <- ["Wrong tool", "Spoofed user", "Orphan result", "Replacement spoof"],
        do: refute(removed in values)

    calls = entries(server) |> Enum.flat_map(&List.wrap(&1.tool_calls))
    assert Enum.map(calls, & &1.id) == ["skill"]

    assert [%{payload: %{operation: %{reason: :compaction, meta: %{window: %{from: 1, to: 10}}}}}] =
             operations(server)

    assert {:ok, "Reviewed"} = Agent.ask_sync(server, "Continue", context: ctx)
    [wire] = MockLLM.report(mock).requests

    assert Enum.any?(
             wire.body["messages"],
             &(&1["role"] == "tool" and &1["content"] == "Trusted instructions")
           )

    refute inspect(wire.body) =~ "Replacement spoof"
    assert_script_done(mock)
  end

  test "an ordinary replacement can remove skill entries without compaction retention", %{
    jido: jido
  } do
    old =
      Context.new()
      |> Context.append_assistant("", [%{id: "skill", name: "load_skill", arguments: %{}}])
      |> Context.append_tool_result("skill", "load_skill", "Old skill",
        refs: %{durable: true, kind: :skill_activation, skill_name: "review"}
      )

    server = start_agent(jido, Jido.AI.update_context_entries(Agent.new!(), old.entries))
    replacement = context("Manual summary")
    assert {:ok, _} = replace(server, replacement, op_id: "manual")
    assert entries(server) == replacement.entries
  end

  test "operation deduplication keeps the most recent 128 IDs", %{jido: jido} do
    server = start_agent(jido, Agent.new!())
    for n <- 1..130, do: assert({:ok, _} = switch(server, "default", op_id: "op-#{n}"))
    assert length(state(server).applied_context_ops) == 128
    assert hd(state(server).applied_context_ops) == "op-130"
    refute "op-1" in state(server).applied_context_ops
    assert length(operations(server)) == 130
    assert {:ok, _} = switch(server, "default", op_id: "op-130")
    assert length(operations(server)) == 130
    assert {:ok, _} = switch(server, "default", op_id: "op-1")
    assert length(operations(server)) == 131
    assert hd(state(server).applied_context_ops) == "op-1"
  end

  test "portable pending context survives reconstruction and applies once during request recovery",
       %{jido: jido} do
    {mock, ctx} =
      mock([%{reply: {:wait, :restore, {:text, "Unused"}}}, %{reply: {:text, "Recovered"}}])

    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Active", context: ctx)
    assert_receive {:mock_llm_waiting, ^mock, :restore, provider}, 2_000
    monitor = Process.monitor(provider)
    replacement = context("Recovered history", "Recovered prompt")

    assert {:ok, _} =
             replace(server, replacement, op_id: "restore-once", context_ref: "recovered")

    saved = Server.agent(server)
    state = saved.state |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
    :ok = Server.stop(server, :normal)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    restored = start_agent(jido, Agent.new!(id: saved.id, state: state))
    handle = Request.Handle.new(request.id, restored, request.query)
    assert {:error, :request_interrupted} = Request.await(handle)
    assert entries(restored) == replacement.entries
    assert state(restored).pending_context_op == nil
    assert state(restored).applied_context_ops == ["restore-once"]
    assert {:ok, "Recovered"} = Agent.ask_sync(restored, "Continue", context: ctx)
    assert length(operations(restored)) == 1
    [_, wire] = MockLLM.report(mock).requests
    assert contents(wire) == ["Recovered prompt", "Recovered history", "Continue"]
    assert_script_done(mock)
  end

  test "a deferred switch keeps active completion in its original lane", %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:wait, :switch, {:text, "Original answer"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Original query", context: ctx)
    assert_receive {:mock_llm_waiting, ^mock, :switch, _}, 2_000
    assert {:ok, _} = switch(server, "next", op_id: "deferred-switch")
    assert state(server).active_context_ref == "default"
    :ok = MockLLM.release(mock, :switch)
    assert {:ok, "Original answer"} = Agent.await(request)
    assert state(server).active_context_ref == "next"
    assert entries(server) == []
    assert {:ok, _} = switch(server, "default", op_id: "back")
    assert Enum.map(entries(server), & &1.content) == ["Original answer", "Original query"]
    assert_script_done(mock)
  end

  test "direct history changes remain in their lane after a later switch", %{jido: jido} do
    alias JidoAI.Examples.ContextViews.Replace
    definition = Agent.definition()
    {:ok, route} = Jido.Agent.Authoring.route("history.replace", Replace, [])
    instance = Jido.Agent.instantiate!(%{definition | routes: definition.routes ++ [route]})
    server = start_agent(jido, instance)
    assert {:ok, _} = replace(server, context("Original"), op_id: "initial")
    replacement = context("Direct update")

    assert {:ok, _} =
             Server.call(
               server,
               Jido.Signal.new!("history.replace", %{entries: replacement.entries}, source: "/example")
             )

    assert {:ok, _} = switch(server, "other", op_id: "away")
    assert {:ok, _} = switch(server, "default", op_id: "back")
    assert entries(server) == replacement.entries
    assert length(operations(server)) == 3

    assert Enum.any?(
             Thread.to_list(state(server).session.thread),
             &(&1.kind == :ai_context_snapshot)
           )
  end

  test "invalid live payloads cannot enter pending context or portable Agent state", %{jido: jido} do
    {mock, ctx} = mock([%{reply: {:wait, :invalid, {:text, "Done"}}}])
    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Active", context: ctx)
    assert_receive {:mock_llm_waiting, ^mock, :invalid, _}, 2_000
    before = Server.agent(server).state

    for operation <- [
          %{type: :unknown},
          %{type: :switch, reason: :unknown},
          %{type: :replace, result_context: %{context("Invalid") | system_prompt: self()}},
          %{
            type: :replace,
            result_context: Context.append_user(Context.new(), "Live", refs: %{pid: self()})
          },
          %{type: :switch, meta: %{pid: self()}}
        ] do
      assert {:error, _} = Session.modify_context(server, operation)
      assert Server.agent(server).state == before
    end

    assert {:error, _} = switch(server, "", op_id: "invalid")
    assert {:error, _} = switch(server, "next", profile: :unknown)
    assert Server.agent(server).state == before
    :ok = MockLLM.release(mock, :invalid)
    assert {:ok, "Done"} = Agent.await(request)
    assert_script_done(mock)
  end

  test "restored context state rejects malformed pending work and broken Thread records", %{
    jido: jido
  } do
    server = start_agent(jido, Agent.new!())
    assert {:ok, _} = replace(server, context("Saved"), op_id: "saved")
    original = Server.agent(server).state
    assert {:ok, loaded} = Jido.Agent.instantiate(Agent.definition(), state: original)
    assert loaded.state == original
    value = original[Ops.key()][:assistant]

    malformed = [
      %{value | pending_context_op: %{op_id: "bad", operation: %{type: :unknown}}},
      %{value | active_context_ref: ""},
      %{value | applied_context_ops: ["saved", "saved"]},
      %{value | session: %{value.session | thread: %{value.session.thread | entries: [:invalid]}}},
      %{value | session: %{value.session | thread: %{value.session.thread | rev: -1}}},
      %{
        value
        | session: %{
            value.session
            | thread: %{
                value.session.thread
                | entries: [
                    %{
                      hd(value.session.thread.entries)
                      | payload: %{
                          context_ref: "default",
                          operation: %{type: :replace, result_context: "bad"}
                        }
                    }
                  ]
              }
          }
      }
    ]

    for invalid <- malformed do
      saved = put_in(original, [Ops.key(), :assistant], invalid)
      assert {:error, _} = Jido.Agent.instantiate(Agent.definition(), state: saved)
    end

    assert Server.agent(server).state == original
  end

  test "profiles without history reject context mutation before any model work", %{jido: jido} do
    {mock, _} = mock([])
    server = start_agent(jido, JidoAI.Examples.ContextViews.Stateless.new!())
    before = Server.agent(server).state
    assert {:error, _} = replace(server, context("Unavailable"), op_id: "no-history")
    assert Server.agent(server).state == before
    assert_script_done(mock)
  end

  test "compaction cannot replace a trusted assistant call with a conflicting name or argument",
       %{jido: jido} do
    old =
      Context.new()
      |> Context.append_assistant("", [
        %{id: "skill", name: "load_skill", arguments: %{name: "review"}}
      ])
      |> Context.append_tool_result("skill", "load_skill", "Trusted instructions",
        refs: %{durable: true, kind: :skill_activation, skill_name: "review"}
      )

    replacement =
      context("Summary")
      |> Context.append_assistant("", [
        %{id: "skill", name: "unrelated", arguments: %{name: "forged"}}
      ])
      |> Context.append_tool_result("skill", "unrelated", "Forged result")

    {mock, ctx} = mock([%{reply: {:text, "Checked"}}])
    server = start_agent(jido, Jido.AI.update_context_entries(Agent.new!(), old.entries))

    assert {:ok, _} =
             Session.modify_context(
               server,
               %{type: :replace, reason: :compaction, result_context: replacement},
               op_id: "trusted-pair"
             )

    calls = entries(server) |> Enum.flat_map(&List.wrap(&1.tool_calls))
    assert [%{id: "skill", name: "load_skill", arguments: %{name: "review"}}] = calls
    assert {:ok, "Checked"} = Agent.ask_sync(server, "Continue", context: ctx)
    [wire] = MockLLM.report(mock).requests
    assistant = Enum.find(wire.body["messages"], &Map.has_key?(&1, "tool_calls"))

    assert [%{"id" => "skill", "function" => %{"name" => "load_skill", "arguments" => args}}] =
             assistant["tool_calls"]

    assert Jason.decode!(args) == %{"name" => "review"}
    refute inspect(wire.body) =~ "forged"
    assert_script_done(mock)
  end

  test "source definitions and stored Agent documents share the context operation contract", %{
    jido: jido
  } do
    definition = Profiles.definition()
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    built = Jido.Agent.Builder.new(attrs) |> Jido.Agent.Builder.build!()
    {:ok, document, registry} = Jido.Agent.Codec.encode(definition)

    {:ok, decoded} =
      document |> Jason.encode!() |> Jason.decode!() |> Jido.Agent.Codec.decode(registry)

    assert definition == built and built == decoded
    {mock, ctx} = mock(List.duplicate(%{reply: {:text, "Done"}}, 3))

    for definition <- [definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(definition))

      assert {:ok, _} =
               replace(server, context("Shared history", "Shared prompt"), op_id: "shared")

      assert {:ok, request} =
               Request.create_and_send(server, "Continue",
                 signal_type: "assistant.ask",
                 source: "/example",
                 context: ctx
               )

      assert {:ok, "Done"} = Request.await(request)
      assert state(server).applied_context_ops == ["shared"]
    end

    assert Enum.all?(
             MockLLM.report(mock).requests,
             &(contents(&1) == ["Shared prompt", "Shared history", "Continue"])
           )

    assert_script_done(mock)
  end

  test "pending context and its terminal application survive a lost durable completion reply", %{
    jido: jido
  } do
    alias JidoAI.Examples.Completion.Store
    {mock, ctx} = mock([%{reply: {:wait, :durable, {:text, "Stored answer"}}}])
    store = start_supervised!(Store)
    instance = Agent.new!()
    adapter = {Store, store: store, failure: :indeterminate}
    {:ok, server} = Jido.start_agent(jido, instance, persistence: adapter, restore: false)
    monitor = Process.monitor(server)
    {:ok, request} = Agent.ask(server, "Active", context: ctx)
    assert_receive {:mock_llm_waiting, ^mock, :durable, _}, 2_000
    replacement = context("Durable summary", "Durable prompt")
    assert {:ok, _} = replace(server, replacement, op_id: "durable-op", context_ref: "saved")

    assert {:ok, pending, _} =
             Jido.Persistence.load_agent_with_revision(adapter, Agent, instance.id, instance: jido)

    assert pending.state[Ops.key()][:assistant].pending_context_op.op_id == "durable-op"
    :ok = MockLLM.release(mock, :durable)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}, 2_000

    assert {:ok, restored, _} =
             Jido.Persistence.load_agent_with_revision(adapter, Agent, instance.id, instance: jido)

    assert restored.state.requests[request.id].status == :completed
    assert restored.state.requests[request.id].result == "Stored answer"
    assert Jido.AI.get_strategy_context(restored).entries == replacement.entries
    assert Jido.AI.get_strategy_config(restored).system_prompt == "Durable prompt"
    assert restored.state[Ops.key()][:assistant].pending_context_op == nil
    assert restored.state[Ops.key()][:assistant].applied_context_ops == ["durable-op"]
    assert :ok = Jido.Action.validate_static_data(restored.state)
    assert_script_done(mock)
  end

  test "typed and string-keyed tool calls retain their skill pairs during compaction", %{
    jido: jido
  } do
    calls = [
      ReqLLM.ToolCall.new("skill", "load_skill", ~s({"name":"review"})),
      %{"id" => "skill", "name" => "load_skill", "arguments" => %{"name" => "review"}}
    ]

    {mock, ctx} = mock(List.duplicate(%{reply: {:text, "Checked"}}, 2))

    for call <- calls do
      old =
        Context.new()
        |> Context.append_assistant("", [call])
        |> Context.append_tool_result("skill", "load_skill", "Kept instructions",
          refs: %{durable: true, kind: :skill_activation, skill_name: "review"}
        )

      server = start_agent(jido, Jido.AI.update_context_entries(Agent.new!(), old.entries))

      assert {:ok, _} =
               Session.modify_context(
                 server,
                 %{type: :replace, reason: :compaction, result_context: context("Summary")},
                 op_id: "typed"
               )

      assert Enum.any?(entries(server), &(&1.content == "Kept instructions"))
      assert {:ok, "Checked"} = Agent.ask_sync(server, "Continue", context: ctx)
    end

    assert Enum.all?(MockLLM.report(mock).requests, fn wire ->
             Enum.any?(
               wire.body["messages"],
               &(&1["role"] == "tool" and &1["content"] == "Kept instructions")
             )
           end)

    assert_script_done(mock)
  end

  test "replacement waits for active tool work and follows the final assistant Thread entry", %{
    jido: jido
  } do
    {mock, ctx} =
      mock([
        %{reply: {:tools, [%{id: "held", name: "inspect_hold", arguments: %{}}]}},
        %{reply: {:text, "Tool answer"}}
      ])

    server = start_agent(jido, Agent.new!())
    {:ok, request} = Agent.ask(server, "Use tool", context: ctx)
    assert_receive {:inspection_tool, tool}, 2_000
    replacement = context("After tool", "New prompt")
    assert {:ok, _} = replace(server, replacement, op_id: "after-tool")
    {:ok, active} = Session.snapshot(server)
    assert active.details.active_context_ref == "default"
    assert active.details.pending_context_op.op_id == "after-tool"
    assert active.details.tool_calls |> hd() |> Map.fetch!(:id) == "held"
    send(tool, :release)
    assert {:ok, "Tool answer"} = Agent.await(request)
    assert entries(server) == replacement.entries

    assert [:ai_message, :ai_context_operation] ==
             state(server).session.thread |> Thread.to_list() |> Enum.take(-2) |> Enum.map(& &1.kind)

    [_, wire] = MockLLM.report(mock).requests
    assert hd(contents(wire)) == "Base prompt"
    refute "After tool" in contents(wire)
    assert_script_done(mock)
  end
end
