defmodule JidoAI.Examples.DynamicCatalogTest do
  use JidoAI.Examples.Case
  alias Jido.AI
  alias JidoAI.Examples.DynamicCatalog.{Agent, Lookup, Conflict}

  setup do
    old = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{fast: MockLLM.model()})

    on_exit(fn ->
      case old do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)
  end

  test "direct catalog and prompt changes reach a real first request", %{jido: jido} do
    original = Agent.new!()
    assert {:ok, changed} = AI.register_tool_direct(original, Lookup)
    changed = AI.set_system_prompt_direct(changed, "Use current case facts.")
    assert AI.list_tools(original) == []
    assert AI.list_tools(changed) == [Lookup]
    assert AI.has_tool?(changed, "lookup")
    assert {:ok, ^changed} = AI.register_tool_direct(changed, Lookup)
    assert {:error, _} = AI.register_tool_direct(changed, Conflict)
    assert {:ok, empty} = AI.unregister_tool_direct(changed, "lookup")
    assert AI.list_tools(empty) == []
    assert AI.get_strategy_config(empty).reqllm_tools == []
    {mock, context} = mock([lookup(), %{reply: {:text, "Case is open"}}])
    server = start_agent(jido, changed)
    assert {:ok, request} = Agent.ask(server, "Review", context: context)
    assert {:ok, "Case is open"} = Agent.await(request)
    [wire, _] = MockLLM.report(mock).requests
    assert hd(wire.body["messages"])["content"] == "Use current case facts."
    assert hd(wire.body["tools"])["function"]["name"] == "lookup"
    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "live configuration commits before the next request", %{jido: jido} do
    server = start_agent(jido, Agent.new!())
    assert {:ok, changed} = AI.register_tool(server, Lookup)
    assert AI.has_tool?(changed, "lookup")
    assert {:ok, [Lookup]} = AI.list_tools(server)
    assert {:ok, true} = AI.has_tool?(server, "lookup")
    assert {:ok, _} = AI.set_system_prompt(server, "Updated.")
    {mock, context} = mock([lookup(), %{reply: {:text, "Open"}}, %{reply: {:text, "No lookup"}}])
    assert {:ok, first} = Agent.ask(server, "Review", context: context)
    assert {:ok, "Open"} = Agent.await(first)
    assert {:ok, _} = AI.unregister_tool(server, "lookup")
    assert {:ok, _} = AI.set_system_prompt(server, "")
    assert {:ok, next} = Agent.ask(server, "Again", context: context)
    assert {:ok, "No lookup"} = Agent.await(next)
    [wire, _, final] = MockLLM.report(mock).requests
    assert hd(wire.body["messages"])["content"] == "Updated."
    assert Map.get(final.body, "tools", []) == []
    refute Enum.any?(final.body["messages"], &(&1["role"] == "system"))
    assert_script_done(mock)
  end

  test "registration from a real Action uses direct validation and a core configuration directive",
       %{jido: jido} do
    {mock, context} = mock([lookup(), %{reply: {:text, "Open"}}])
    server = start_agent(jido, Agent.new!())
    signal = Jido.Signal.new!("case.register", %{}, source: "/examples/catalog")
    assert {:ok, changed} = Server.call(server, signal, context: context)
    assert changed.state.last_answer == "tools ready"
    assert_receive {:registered_from_work, [Lookup], action_pid}
    refute action_pid == server
    assert AI.list_tools(changed) == [Lookup]
    assert {:ok, request} = Agent.ask(server, "Review", context: context)
    assert {:ok, "Open"} = Agent.await(request)
    assert_script_done(mock)
  end

  test "active requests retain their tool identity and prompt until the next admission", %{
    jido: jido
  } do
    {mock, context} =
      mock([
        lookup(),
        %{reply: {:text, "Original finished"}},
        lookup(),
        %{reply: {:text, "Replacement finished"}}
      ])

    assert {:ok, original} = AI.register_tool_direct(Agent.new!(), Lookup)
    server = start_agent(jido, original)

    assert {:ok, first} =
             Agent.ask(server, "Review", context: Map.put(context, :hold_lookup, true))

    assert_receive {:lookup_held, worker}, 2_000
    assert {:ok, _} = AI.unregister_tool(server, "lookup")
    assert {:ok, _} = AI.register_tool(server, Conflict)
    assert {:ok, _} = AI.set_system_prompt(server, "New case instructions.")
    send(worker, :release)
    assert {:ok, "Original finished"} = Agent.await(first)
    assert AI.get_strategy_config(Server.agent(server)).system_prompt == "New case instructions."
    assert {:ok, next} = Agent.ask(server, "Again", context: context)
    assert {:ok, "Replacement finished"} = Agent.await(next)
    assert_receive :conflict_called
    assert_receive {:lookup, "case-1"}
    refute_receive {:lookup, _}, 20
    [_, old_final, new_first, _] = MockLLM.report(mock).requests
    assert hd(old_final.body["messages"])["content"] == "Original case instructions."
    assert hd(new_first.body["messages"])["content"] == "New case instructions."

    assert [%{action_module: Lookup}] =
             Server.agent(server).state.requests[first.id].meta.tool_results

    assert [%{action_module: Conflict}] =
             Server.agent(server).state.requests[next.id].meta.tool_results

    assert_script_done(mock)
  end

  test "invalid catalogs and forged domain changes cannot change the committed configuration", %{
    jido: jido
  } do
    alias JidoAI.Examples.DynamicCatalog.NotATool
    server = start_agent(jido, Agent.new!())
    assert {:ok, _} = AI.register_tool(server, Lookup)
    original = Server.agent(server)
    assert {:error, :not_a_tool} = AI.register_tool(server, NotATool)

    assert {:error, {:not_loaded, MissingDynamicTool}} =
             AI.register_tool(server, MissingDynamicTool)

    assert {:error, _} = AI.register_tool(server, Conflict)
    assert {:error, _} = AI.register_tool(server, NotATool, validate: false)
    assert {:error, _} = AI.set_system_prompt(server, "Unknown", profile: :missing)

    assert {:error, _} =
             Server.call(server, Jido.Signal.new!("case.forge", %{}, source: "/examples/catalog"))

    assert Server.agent(server) == original
    assert {:error, _} = Jido.Agent.set(original, %{jido_ai_config: %{}})
    assert {:ok, same} = AI.unregister_tool(server, "absent")
    assert AI.list_tools(same) == [Lookup]
  end

  test "legacy configuration Signals retain their names and input fields", %{jido: jido} do
    server = start_agent(jido, Agent.new!())

    for {type, data} <- [
          {"ai.react.register_tool", %{tool_module: Lookup}},
          {"ai.react.set_system_prompt", %{system_prompt: "Signal instructions."}}
        ] do
      assert {:ok, _} =
               Server.call(server, Jido.Signal.new!(type, data, source: "/examples/catalog"))
    end

    assert {:ok, [Lookup]} = AI.list_tools(server)
    assert AI.get_strategy_config(Server.agent(server)).system_prompt == "Signal instructions."

    assert {:ok, _} =
             Server.call(
               server,
               Jido.Signal.new!("ai.react.unregister_tool", %{tool_name: "lookup"},
                 source: "/examples/catalog"
               )
             )

    assert {:ok, []} = AI.list_tools(server)
  end

  test "native profile updates preserve aliases and isolate the other profile", %{jido: jido} do
    alias JidoAI.Examples.DynamicCatalog.Native
    {mock, context} = mock([%{reply: {:text, "Main"}}, %{reply: {:text, "Other"}}])

    context =
      Map.put(context, :ai, %{
        main: %{options: MockLLM.options(mock)},
        other: %{options: MockLLM.options(mock)}
      })

    server = start_agent(jido, Native.new!())
    assert {:error, _} = AI.set_system_prompt(server, "Ambiguous")
    assert {:ok, changed} = AI.set_system_prompt(server, "Main policy.", profile: :main)
    assert {:ok, main} = AI.Configuration.profile(changed, :main)
    assert Enum.map(main.tools, & &1.name) == ["case_lookup"]
    assert {:ok, changed} = AI.register_tool(server, Lookup, profile: :main)
    assert {:ok, main} = AI.Configuration.profile(changed, :main)
    assert Enum.map(main.tools, & &1.name) == ["case_lookup"]
    assert {:ok, changed} = AI.unregister_tool(server, "case_lookup", profile: :main)
    assert {:ok, other} = AI.Configuration.profile(changed, :other)
    assert other.instructions == nil and other.tools == []

    for {id, route, answer} <- [{:main, "case.main", "Main"}, {:other, "case.other", "Other"}] do
      assert {:ok, request} =
               AI.Request.create_and_send(server, "Review",
                 signal_type: route,
                 source: "/examples/catalog",
                 context: context
               )

      assert {:ok, ^answer} = AI.Request.await(request)
      assert Server.agent(server).state.requests[request.id].profile_id == id
    end

    [main_wire, other_wire] = MockLLM.report(mock).requests
    assert hd(main_wire.body["messages"])["content"] == "Main policy."
    refute Enum.any?(other_wire.body["messages"], &(&1["role"] == "system"))
    assert_script_done(mock)
  end

  test "portable overrides survive reconstruction and invalid restored overrides are rejected", %{
    jido: jido
  } do
    assert {:ok, value} = AI.register_tool_direct(Agent.new!(), Lookup)
    value = AI.set_system_prompt_direct(value, "Restored policy.")
    state = value.state |> :erlang.term_to_binary() |> :erlang.binary_to_term([:safe])
    restored = Agent.new!(state: state)
    assert AI.list_tools(restored) == [Lookup]
    assert AI.get_strategy_config(restored).system_prompt == "Restored policy."

    assert {:error, _} =
             Agent.new(
               state: %{
                 state
                 | jido_ai_config: %{assistant: %{tools: [%{name: "bad", target: :missing_tool}]}}
               }
             )

    {mock, context} = mock([lookup(), %{reply: {:text, "Restored"}}])
    server = start_agent(jido, restored)
    assert {:ok, request} = Agent.ask(server, "Review", context: context)
    assert {:ok, "Restored"} = Agent.await(request)
    assert_script_done(mock)
  end

  test "the public context view uses committed history and accepts its reverse entry order", %{
    jido: jido
  } do
    context =
      AI.Context.new()
      |> AI.Context.append_user("Earlier")
      |> AI.Context.append_assistant("Earlier answer")

    agent = AI.update_context_entries(Agent.new!(), context.entries)
    view = AI.get_strategy_context(agent)

    assert AI.Context.to_messages(view) ==
             AI.Context.to_messages(%{context | system_prompt: "Original case instructions."})

    assert AI.get_strategy_context(agent).id == view.id
    agent = AI.set_system_prompt_direct(agent, "New history policy.")
    {mock, bindings} = mock([%{reply: {:text, "Next answer"}}])
    server = start_agent(jido, agent)
    assert {:ok, request} = Agent.ask(server, "Next", context: bindings)
    assert {:ok, "Next answer"} = Agent.await(request)
    [wire] = MockLLM.report(mock).requests

    assert Enum.map(wire.body["messages"], & &1["content"]) == [
             "New history policy.",
             "Earlier",
             "Earlier answer",
             "Next"
           ]

    assert_script_done(mock)
  end

  test "native definition source forms retain mutable configuration through real calls", %{
    jido: jido
  } do
    alias JidoAI.Examples.DynamicCatalog.Native
    definition = Native.agent()
    attrs = definition |> Jido.Agent.to_map() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()
    assert {:ok, document, registry} = Jido.Agent.Codec.encode(definition)

    assert {:ok, decoded} =
             Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(document)), registry)

    assert built == decoded and decoded == definition
    {_, config} = Enum.find(definition.plugins, &(elem(&1, 0) == AI.Runtime.Plugin))
    sources = Enum.map(config[:profiles], fn {_, profile} -> Map.from_struct(profile) end)

    source_registry =
      sources
      |> atoms()
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("atoms/routes", {:atom, :routes})
      |> Map.put("models/example", {:value, MockLLM.model()})

    base = %{
      name: definition.name,
      module: Native,
      schema: Native.domain_schema(),
      routes: [{"case.main", AI.Authoring.ai(:main)}, {"case.other", AI.Authoring.ai(:other)}]
    }

    assert {:ok, source_json} = AI.Authoring.Codec.encode(sources, source_registry)

    assert {:ok, from_source} =
             AI.Authoring.Codec.decode(
               base,
               Jason.decode!(Jason.encode!(source_json)),
               source_registry
             )

    assert from_source == definition
    {mock, context} = mock(List.duplicate(%{reply: {:text, "Updated"}}, 4))
    context = Map.put(context, :ai, %{main: %{options: MockLLM.options(mock)}})

    for value <- [definition, built, decoded, from_source] do
      server = start_agent(jido, value)
      assert {:ok, _} = AI.set_system_prompt(server, "Converted policy.", profile: :main)

      assert {:ok, request} =
               AI.Request.create_and_send(server, "Review",
                 signal_type: "case.main",
                 source: "/examples/catalog",
                 context: context
               )

      assert {:ok, "Updated"} = AI.Request.await(request)
    end

    for wire <- MockLLM.report(mock).requests,
        do: assert(hd(wire.body["messages"])["content"] == "Converted policy.")

    assert_script_done(mock)
  end

  test "the compiled public generation facade uses the same model transport" do
    {mock, _} =
      mock([
        %{reply: {:text, "Text"}},
        %{reply: {:object, %{answer: "Object"}}},
        %{reply: {:text, "Stream"}},
        %{reply: {:text, "Ask"}}
      ])

    opts = Keyword.put(MockLLM.options(mock), :model, :fast)
    assert {:ok, response} = AI.generate_text("Text", opts)
    assert ReqLLM.Response.text(response) == "Text"

    assert {:ok, response} =
             AI.generate_object("Object", Zoi.object(%{answer: Zoi.string()}), opts)

    assert response.object == %{"answer" => "Object"}
    assert {:ok, stream} = AI.stream_text("Stream", opts)
    assert {:ok, response} = ReqLLM.StreamResponse.process_stream(stream)
    assert ReqLLM.Response.text(response) == "Stream"
    ReqLLM.StreamResponse.close(stream)
    assert {:ok, "Ask"} = AI.ask("Ask", opts)
    assert AI.resolve_model(:fast) == MockLLM.model()
    assert_script_done(mock)
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(_), do: []

  defp lookup,
    do: %{reply: {:tools, [%{id: "lookup-1", name: "lookup", arguments: %{id: "case-1"}}]}}
end
