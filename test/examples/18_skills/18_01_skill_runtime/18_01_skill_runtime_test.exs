defmodule JidoAI.Examples.SkillRuntimeTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Context, Request, Session}
  alias Jido.AI.Actions.Skill.{LoadSkill, RuntimeContext}
  alias Jido.Thread
  alias Jido.AI.Skill.{Activation, AgentIntegration, Registry, Spec}
  alias JidoAI.Examples.SkillRuntime.{Agent, Imposter, Native, Provider}

  setup do
    start_supervised!(Registry)
    :ok
  end

  defp spec(body \\ "Original instructions"),
    do: %Spec{name: "review", description: "Review a document.", body_ref: {:inline, body}}

  defp bind_catalog(context, opts \\ []) do
    integration =
      AgentIntegration.prepare!(Keyword.merge([specs: [spec()], resource_provider: {Provider, :handle}], opts))

    Map.merge(context, integration.tool_context)
  end

  defp skill(id \\ "skill", name \\ "review"),
    do: %{id: id, name: "load_skill", arguments: %{name: name}}

  defp resource(id \\ "resource", selector \\ %{resource_id: "opaque/../guide"}),
    do: %{id: id, name: "load_skill_resource", arguments: Map.put(selector, :name, "review")}

  defp script(calls),
    do: Enum.map(calls, &%{reply: {:tools, List.wrap(&1)}}) ++ [%{reply: {:text, "Done"}}]

  defp entries(server), do: Jido.AI.get_strategy_context(Server.agent(server)).entries
  defp tool_entries(server), do: Enum.filter(entries(server), &(&1.role == :tool))

  defp compact(server),
    do:
      Session.modify_context(server, %{
        type: :replace,
        reason: :compaction,
        result_context: Context.new(system_prompt: "After compaction") |> Context.append_user("Summary")
      })

  defp payload(%{content: content}) when is_binary(content), do: Jason.decode!(content)

  defp payload(%{content: parts}),
    do: parts |> Enum.find(&(&1.type == :text)) |> Map.fetch!(:text) |> Jason.decode!()

  defp wire_text(wire), do: Jason.encode!(wire.body)
  defp owner(server), do: Server.children(server)[{:plugin, Session.Plugin}].pid

  test "a real activation survives compaction and reaches the next HTTP request", %{jido: jido} do
    {mock, context} = mock(script([skill()]) ++ [%{reply: {:text, "Next"}}])
    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context)
    assert {:ok, "Done"} = Agent.ask_sync(server, "Review", context: context, stream_to: self())
    assert_receive {:skill_list, _, provider_context}
    refute Map.has_key?(provider_context, LoadSkill.context_skills_key())
    assert [entry] = tool_entries(server)
    assert entry.refs.durable
    assert entry.refs.kind == :skill_activation
    assert entry.refs.skill_name == "review"
    assert payload(entry)["result"]["instructions"] == "Original instructions"
    request = Server.agent(server).state.last_request_id
    assert entry.refs.request_id == request
    assert {:ok, _} = compact(server)
    assert [^entry] = tool_entries(server)
    assert {:ok, "Next"} = Agent.ask_sync(server, "Continue", context: context)
    assert wire_text(List.last(MockLLM.report(mock).requests)) =~ "Original instructions"
    assert wire_text(List.last(MockLLM.report(mock).requests)) =~ "After compaction"

    assert Thread.filter_by_kind(
             Server.agent(server).state.jido_ai_contexts.assistant.session.thread,
             :ai_message
           )
           |> Enum.any?(&(&1.payload.role == :tool and &1.payload.refs[:durable]))

    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "different Flow workers share activation and fresh resource loads across requests", %{
    jido: jido
  } do
    {mock, context} = mock(script([skill(), resource()]) ++ script([resource("fresh")]))
    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context)
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
    assert_receive {:skill_list, first_pid, first}
    assert_receive {:skill_load, second_pid, "opaque/../guide", second}
    assert first_pid != second_pid
    assert RuntimeContext.session_id(first) == RuntimeContext.session_id(second)

    assert {:ok, "Done"} =
             Agent.ask_sync(server, "Refresh", context: Map.put(context, :resource_content, "Fresh"))

    assert_receive {:skill_load, _, "opaque/../guide", third}
    assert RuntimeContext.session_id(first) == RuntimeContext.session_id(third)
    refute_receive {:skill_list, _, _}, 20
    assert wire_text(List.last(MockLLM.report(mock).requests)) =~ "Fresh"
    assert_script_done(mock)
  end

  test "a scoped miss cannot use the global Registry", %{jido: jido} do
    Registry.register(%{spec("Global") | name: "hidden"})
    {mock, context} = mock(script([skill("missing", "hidden")]))
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: bind_catalog(context))
    assert [entry] = tool_entries(server)
    refute entry.refs[:durable]
    assert payload(entry)["ok"] == false
    refute wire_text(List.last(MockLLM.report(mock).requests)) =~ "Global"
    refute_receive {:skill_list, _, _}, 20
    assert_script_done(mock)
  end

  for catalog <- [%{}, :invalid] do
    test "an empty or invalid scoped catalog #{inspect(catalog)} cannot fall back to the Registry",
         %{jido: jido} do
      Registry.register(spec("Global"))
      {mock, context} = mock(script([skill()]))
      server = start_agent(jido, Agent.new!())
      context = Map.put(context, LoadSkill.context_skills_key(), unquote(Macro.escape(catalog)))
      assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
      assert [entry] = tool_entries(server)
      assert payload(entry)["ok"] == false
      refute entry.refs[:durable]
      assert_script_done(mock)
    end
  end

  for approval <- [:change, :reject, :rename, :invent] do
    test "the #{approval} result callback controls output without granting false skill provenance",
         %{jido: jido} do
      callback_case(unquote(approval), jido)
    end
  end

  defp callback_case(approval, jido) do
    call = if approval == :invent, do: skill("skill", "missing"), else: skill()
    {mock, context} = mock(script([call]) ++ [%{reply: {:text, "Next"}}])
    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context) |> Map.put(:approval, approval)
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
    assert [entry] = tool_entries(server)

    if approval == :change do
      assert entry.refs[:durable]
      assert payload(entry)["result"]["instructions"] == "Approved instructions"
    else
      refute entry.refs[:durable]
    end

    assert {:ok, _} = compact(server)
    assert Enum.count(tool_entries(server)) == if(approval == :change, do: 1, else: 0)
    assert {:ok, "Next"} = Agent.ask_sync(server, "Continue", context: context)
    assert_script_done(mock)
  end

  test "a different Action named load_skill cannot gain durability from extra refs", %{jido: jido} do
    {mock, context} = mock(script([skill()]))
    server = start_agent(jido, Agent.new!())

    assert {:ok, "Done"} =
             Agent.ask_sync(server, "Load",
               context: bind_catalog(context),
               tools: [Imposter],
               extra_refs: %{durable: true, kind: :skill_activation, skill_name: "review"}
             )

    assert [entry] = tool_entries(server)
    assert payload(entry)["ok"]
    refute Enum.any?(entries(server), & &1.refs[:durable])
    assert {:ok, _} = compact(server)
    assert tool_entries(server) == []
    assert_script_done(mock)
  end

  test "request tool context cannot replace the host catalog provider or policy", %{jido: jido} do
    {mock, context} = mock([])
    server = start_agent(jido, Agent.new!())
    before = Server.agent(server).state

    for key <- Jido.AI.Skill.Runtime.reserved_keys(), form <- [key, Atom.to_string(key)] do
      assert {:error, _} =
               Agent.ask(server, "Load",
                 context: bind_catalog(context),
                 tool_context: %{form => %{}}
               )
    end

    assert Server.agent(server).state == before
    assert_script_done(mock)
  end

  test "a new trusted host binding does not reuse an old same-name activation", %{jido: jido} do
    {mock, context} = mock(script([skill("first")]) ++ script([skill("second")]))
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Done"} = Agent.ask_sync(server, "First", context: bind_catalog(context))

    assert {:ok, "Done"} =
             Agent.ask_sync(server, "Second", context: bind_catalog(context, specs: [spec("New instructions")]))

    assert_receive {:skill_list, _, first}
    assert_receive {:skill_list, _, second}
    refute RuntimeContext.session_id(first) == RuntimeContext.session_id(second)
    assert payload(hd(tool_entries(server)))["result"]["instructions"] == "New instructions"
    assert_script_done(mock)
  end

  test "two Agents isolate same-name activations and owner loss clears only its sessions", %{
    jido: jido
  } do
    {mock, context} = mock(script([skill()]) ++ script([skill()]))
    first = start_agent(jido, Agent.new!())
    second = start_agent(jido, Agent.new!())
    assert {:ok, "Done"} = Agent.ask_sync(first, "First", context: bind_catalog(context))

    assert {:ok, "Done"} =
             Agent.ask_sync(second, "Second", context: bind_catalog(context, specs: [spec("Second Agent")]))

    assert_receive {:skill_list, _, first_context}
    assert_receive {:skill_list, _, second_context}
    first_session = RuntimeContext.session_id(first_context)
    second_session = RuntimeContext.session_id(second_context)
    refute first_session == second_session
    assert Activation.activated?("review", session_id: first_session)
    assert Activation.activated?("review", session_id: second_session)
    monitor = Process.monitor(owner(first))
    Process.exit(owner(first), :kill)
    assert_receive {:DOWN, ^monitor, _, _, :killed}
    # The registry monitor message and this call come from different senders.
    assert_cleaned(first_session)
    assert Activation.activated?("review", session_id: second_session)
    assert_script_done(mock)
  end

  defp assert_cleaned(session, attempts \\ 100)

  defp assert_cleaned(session, 0),
    do: refute(Activation.activated?("review", session_id: session))

  defp assert_cleaned(session, attempts) do
    if Activation.activated?("review", session_id: session) do
      Process.sleep(5)
      assert_cleaned(session, attempts - 1)
    end
  end

  test "repeated activation reuses its listing but preserves each complete call pair", %{
    jido: jido
  } do
    {mock, context} = mock(script([skill("one"), skill("two")]))
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Done"} = Agent.ask_sync(server, "Twice", context: bind_catalog(context))
    assert_receive {:skill_list, _, _}
    refute_receive {:skill_list, _, _}, 20
    assert {:ok, _} = compact(server)
    assert Enum.map(tool_entries(server), & &1.tool_call_id) == ["two", "one"]
    assert_script_done(mock)
  end

  test "unlisted resource IDs fail before the provider is called", %{jido: jido} do
    {mock, context} = mock(script([skill(), resource("hidden", %{resource_id: "not-listed"})]))
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: bind_catalog(context))
    assert_receive {:skill_list, _, _}
    refute_receive {:skill_load, _, _, _}, 20
    assert payload(hd(tool_entries(server)))["ok"] == false
    assert_script_done(mock)
  end

  @tag :tmp_dir
  test "trusted filesystem discovery stays lazy and resource paths stay within its root", %{
    jido: jido,
    tmp_dir: dir
  } do
    root = Path.join(dir, "review")
    File.mkdir_p!(Path.join(root, "references"))
    path = Path.join(root, "SKILL.md")
    File.write!(path, "---\nname: review\ndescription: Review a document.\n---\nOld body")
    File.write!(Path.join(root, "references/guide.txt"), "File resource")
    integration = AgentIntegration.prepare!([dir])
    refute integration.index =~ "Old body"
    File.write!(path, "---\nname: review\ndescription: Review a document.\n---\nNew body")

    {mock, context} =
      mock(
        script([
          skill(),
          resource("file", %{relative_path: "references/guide.txt"}),
          resource("escape", %{path: "../outside"})
        ])
      )

    context = Map.merge(context, integration.tool_context)
    server = start_agent(jido, Agent.new!())
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
    [escape, file, loaded] = tool_entries(server)
    assert payload(loaded)["result"]["instructions"] == "New body"
    assert payload(file)["result"]["content"] == "File resource"
    refute payload(escape)["ok"]
    refute_receive {:skill_list, _, _}, 20
    assert_script_done(mock)
  end

  for {kind, content, metadata} <- [
        {:image, <<137, "PNG", 13, 10, 26, 10, 0, 255>>, %{filename: "plot.png", mime_type: "image/png"}},
        {:file, "%PDF-1.7\nExample", %{filename: "report.pdf", mime_type: "application/pdf"}}
      ] do
    test "an allowed #{kind} resource reaches the next model call as an attachment", %{jido: jido} do
      content = unquote(content)
      {mock, context} = mock(script([skill(), resource()]))
      server = start_agent(jido, Agent.new!())

      context =
        bind_catalog(context, resource_policy: [binary: :allow])
        |> Map.put(:resource_content, content)
        |> Map.put(:resource_metadata, unquote(Macro.escape(metadata)))

      assert {:ok, "Done"} =
               Agent.ask_sync(server, "Load",
                 context: context,
                 model: attachment_model(unquote(kind))
               )

      assert wire_text(List.last(MockLLM.report(mock).requests)) =~ Base.encode64(content)
      assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
      assert_script_done(mock)
    end
  end

  defp attachment_model(:image), do: MockLLM.model()

  defp attachment_model(:file),
    do: put_in(MockLLM.model().extra.wire.protocol, "openai_responses")

  test "the default policy rejects a binary resource before it reaches the model", %{jido: jido} do
    {mock, context} = mock(script([skill(), resource()]))
    server = start_agent(jido, Agent.new!())
    bytes = <<137, "PNG", 13, 10, 26, 10, 0, 255>>

    context =
      bind_catalog(context)
      |> Map.put(:resource_content, bytes)
      |> Map.put(:resource_metadata, %{filename: "plot.png", mime_type: "image/png"})

    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
    refute payload(hd(tool_entries(server)))["ok"]
    refute wire_text(List.last(MockLLM.report(mock).requests)) =~ Base.encode64(bytes)
    assert_script_done(mock)
  end

  test "the native Agent DSL runs the same real activation and resource flow", %{jido: jido} do
    {mock, context} = mock(script([skill(), resource()]))
    server = start_agent(jido, Native.new!())

    assert {:ok, request} =
             Request.create_and_send(server, "Load",
               signal_type: "ai.ask",
               source: "/examples/skills",
               context: bind_catalog(context)
             )

    assert {:ok, "Done"} = Request.await(request)
    assert [resource_entry, skill_entry] = tool_entries(server)
    assert payload(resource_entry)["result"]["content"] == "Text"
    assert skill_entry.refs.durable
    assert_script_done(mock)
  end

  test "a failed host callback commits no trusted tool result", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [skill()]}}])
    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context) |> Map.put(:approval, :halt)

    assert {:error, {:tool_interceptor, :after_tool_call, Agent, :callback_failed}} =
             Agent.ask_sync(server, "Load", context: context)

    assert tool_entries(server) == []
    assert {:ok, _} = compact(server)
    assert tool_entries(server) == []
    assert_script_done(mock)
  end

  for failure <- [:list, :load] do
    test "provider #{failure} failure reaches the model as a tool error", %{jido: jido} do
      provider_failure(unquote(failure), jido)
    end
  end

  defp provider_failure(failure, jido) do
    calls = if failure == :list, do: [skill()], else: [skill(), resource()]
    {mock, context} = mock(script(calls))
    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context) |> Map.put(:provider_failure, failure)
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
    assert payload(hd(tool_entries(server)))["ok"] == false
    assert_script_done(mock)
  end

  test "saved instructions survive restore but resource access requires a fresh activation", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        script([skill()]) ++
          script([resource("denied")]) ++ script([skill("reload"), resource("allowed")])
      )

    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context)
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
    assert_receive {:skill_list, _, old_context}
    old_session = RuntimeContext.session_id(old_context)
    assert {:ok, _} = compact(server)
    saved = Server.agent(server)
    portable = :erlang.binary_to_term(:erlang.term_to_binary(saved.state), [:safe])
    :ok = Server.stop(server, :normal)
    assert_cleaned(old_session)
    restored = start_agent(jido, Agent.new!(id: saved.id, state: portable))
    assert {:ok, "Done"} = Agent.ask_sync(restored, "Read", context: context)
    refute payload(hd(tool_entries(restored)))["ok"]
    refute_receive {:skill_load, _, _, _}, 20
    assert {:ok, "Done"} = Agent.ask_sync(restored, "Activate then read", context: context)
    assert_receive {:skill_list, _, new_context}
    assert_receive {:skill_load, _, _, _}
    refute old_session == RuntimeContext.session_id(new_context)
    assert wire_text(List.last(MockLLM.report(mock).requests)) =~ "Original instructions"
    assert payload(hd(tool_entries(restored)))["ok"]
    assert_script_done(mock)
  end

  test "explicit activation cleanup requires reload but preserves the committed instructions", %{
    jido: jido
  } do
    {mock, context} =
      mock(script([skill()]) ++ script([resource("denied")]) ++ script([skill("reload")]))

    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context)
    assert {:ok, "Done"} = Agent.ask_sync(server, "Load", context: context)
    assert_receive {:skill_list, _, provider_context}
    session = RuntimeContext.session_id(provider_context)
    assert :ok = Activation.clear(session_id: session)
    assert {:ok, "Done"} = Agent.ask_sync(server, "Read", context: context)
    refute payload(hd(tool_entries(server)))["ok"]
    assert {:ok, "Done"} = Agent.ask_sync(server, "Reload", context: context)
    assert_receive {:skill_list, _, _}
    assert {:ok, _} = compact(server)
    assert Enum.map(tool_entries(server), & &1.tool_call_id) == ["reload", "skill"]
    assert_script_done(mock)
  end

  test "a model failure retains activation in the same live Agent", %{jido: jido} do
    {mock, context} =
      mock(
        [%{reply: {:tools, [skill()]}}, %{reply: {:error, 503, "Unavailable"}}] ++
          script([resource()])
      )

    server = start_agent(jido, Agent.new!())
    context = bind_catalog(context)
    assert {:error, _} = Agent.ask_sync(server, "Load", context: context)
    assert_receive {:skill_list, _, provider_context}

    assert Activation.activated?("review",
             session_id: RuntimeContext.session_id(provider_context)
           )

    assert {:ok, "Done"} = Agent.ask_sync(server, "Read", context: context)
    assert_receive {:skill_load, _, _, _}
    assert_script_done(mock)
  end

  test "lazy Registry startup survives failure of the first tool caller" do
    stop_supervised!(Registry)
    parent = self()

    {caller, monitor} =
      spawn_monitor(fn ->
        :ok = Registry.ensure_started()
        send(parent, {:lazy_registry, Process.whereis(Registry)})

        receive do
          :fail -> exit(:killed)
        end
      end)

    assert_receive {:lazy_registry, registry}
    on_exit(fn -> if Process.alive?(registry), do: GenServer.stop(registry, :normal) end)
    send(caller, :fail)
    assert_receive {:DOWN, ^monitor, :process, ^caller, :killed}
    assert Process.alive?(registry)
    assert Registry.list() == []
  end
end
