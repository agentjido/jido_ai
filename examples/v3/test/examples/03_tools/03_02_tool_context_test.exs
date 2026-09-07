defmodule JidoAI.Examples.ToolContextTest do
  use JidoAI.Examples.Case
  alias Jido.AI
  alias Jido.AI.{Authoring, Request}
  alias JidoAI.Examples.ToolContext.{Public, Read}

  setup do
    previous = Application.fetch_env(:jido_ai, :model_aliases)
    Application.put_env(:jido_ai, :model_aliases, %{example: MockLLM.model()})

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  defp tool_round(answer \\ "Done") do
    [
      %{reply: {:tools, [%{id: "context", name: "read_context", arguments: %{}}]}},
      %{reply: {:text, answer}}
    ]
  end

  defp native_profile(id, context, mode \\ :session) do
    %{
      id: id,
      models: %{answer: :example},
      reasoning: %{method: :react, model: :answer},
      tool_context: context,
      tools: [
        %{name: "read_context", target: Read, forward_context: [:tenant, :region, :observer]}
      ],
      requests: %{mode: mode},
      result: %{into: :reply},
      routes: ["context.#{id}"]
    }
  end

  defp definition(profiles) do
    base =
      Jido.Agent.new!(
        name: "context_profiles",
        schema: Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})
      )

    {:ok, definition} = Authoring.lower(base, profiles)
    definition
  end

  defp request(server, context, profile \\ :assistant, opts \\ []) do
    with {:ok, handle} <-
           Request.create_and_send(
             server,
             "Read",
             Keyword.merge(
               [
                 context: context,
                 signal_type: "context.#{profile}",
                 source: "/examples/context"
               ],
               opts
             )
           ),
         do: Request.await(handle)
  end

  test "public defaults and callbacks use the profile for wrapper and raw Signal requests", %{
    jido: jido
  } do
    {mock, context} = mock(tool_round("Wrapper") ++ tool_round("Signal"))
    server = start_agent(jido, Public.new!())
    assert {:ok, "Wrapper"} = Public.ask_sync(server, "Read", context: context)
    assert_receive {:before_context, %{tenant: "base", region: "us"}}
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "base", region: "us"}

    assert {:ok, handle} =
             Request.create_and_send(server, "Read",
               context: context,
               signal_type: "ai.react.query",
               source: "/examples/context"
             )

    assert {:ok, "Signal"} = Request.await(handle)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "base", region: "us"}

    assert AI.get_strategy_config(Server.agent(server)).base_tool_context == %{
             tenant: "base",
             region: "us"
           }

    assert_script_done(mock)
  end

  test "live replacement removes old keys and request values override it only once", %{jido: jido} do
    {mock, context} = mock(tool_round("Override") ++ tool_round("Base") ++ tool_round("Empty"))
    server = start_agent(jido, Public.new!())
    assert {:ok, _} = AI.set_tool_context(server, %{tenant: "live"})

    assert {:ok, "Override"} =
             Public.ask_sync(server, "Read",
               context: context,
               tool_context: %{tenant: "request", request_only: true}
             )

    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "request", request_only: true}
    assert {:ok, "Base"} = Public.ask_sync(server, "Read", context: context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "live"}
    assert {:ok, _} = AI.set_tool_context(server, %{})
    assert {:ok, "Empty"} = Public.ask_sync(server, "Read", context: context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{}
    assert AI.get_strategy_config(Server.agent(server)).base_tool_context == %{}
    [_, override_wire, _, base_wire, _, empty_wire] = MockLLM.report(mock).requests

    for {wire, expected} <- [
          {override_wire, %{"tenant" => "request", "request_only" => true}},
          {base_wire, %{"tenant" => "live"}},
          {empty_wire, %{}}
        ] do
      tool = wire.body["messages"] |> Enum.filter(&(&1["role"] == "tool")) |> List.last()
      assert Jason.decode!(tool["content"]) == %{"ok" => true, "result" => expected}
    end

    assert_script_done(mock)
  end

  test "an active request retains its admitted context while the next request uses the replacement",
       %{jido: jido} do
    {mock, context} = mock(tool_round("First") ++ tool_round("Next"))
    server = start_agent(jido, Public.new!())

    assert {:ok, handle} =
             Public.ask(server, "Read", context: Map.put(context, :hold_context, true))

    assert_receive {:context_held, worker}, 2_000
    assert {:ok, changed} = AI.set_tool_context(server, %{tenant: "next"})
    assert AI.get_strategy_config(changed).base_tool_context == %{tenant: "next"}
    send(worker, :release)
    assert {:ok, "First"} = Public.await(handle)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "base", region: "us"}
    assert {:ok, "Next"} = Public.ask_sync(server, "Read", context: context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "next"}
    assert_script_done(mock)
  end

  test "direct changes and the legacy context Signal use the same configuration reducer", %{
    jido: jido
  } do
    {mock, context} = mock(tool_round("Direct") ++ tool_round("Signal"))
    original = Public.new!()
    assert {:ok, changed} = AI.set_tool_context_direct(original, %{tenant: "direct"})
    assert AI.get_strategy_config(original).base_tool_context == %{tenant: "base", region: "us"}
    server = start_agent(jido, changed)
    assert {:ok, "Direct"} = Public.ask_sync(server, "Read", context: context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "direct"}

    assert {:ok, _} =
             Server.call(
               server,
               Jido.Signal.new!(
                 "ai.react.set_tool_context",
                 %{tool_context: %{tenant: "signal"}},
                 source: "/examples/context"
               )
             )

    assert {:ok, "Signal"} = Public.ask_sync(server, "Read", context: context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "signal"}
    assert_script_done(mock)
  end

  test "native DSL Builder and Agent JSON keep base context and tool projection", %{jido: jido} do
    native = JidoAI.Examples.ToolContext.Native.new!()
    definition = JidoAI.Examples.ToolContext.Native.agent()

    built =
      Jido.Agent.Builder.new(Jido.Agent.to_map(definition) |> Map.drop([:id, :state]))
      |> Jido.Agent.Builder.build!()

    assert {:ok, document, registry} = Jido.Agent.Codec.encode(definition)

    assert {:ok, decoded} =
             Jido.Agent.Codec.decode(Jason.decode!(Jason.encode!(document)), registry)

    assert built == decoded
    {mock, context} = mock(tool_round("Native") ++ tool_round("Builder") ++ tool_round("JSON"))

    for {agent, answer} <- [
          {native, "Native"},
          {Jido.Agent.instantiate!(built), "Builder"},
          {Jido.Agent.instantiate!(decoded), "JSON"}
        ] do
      server = start_agent(jido, agent)

      assert {:ok, result} =
               Server.call(
                 server,
                 Jido.Signal.new!(
                   "context.assistant",
                   %{query: "Read"},
                   source: "/examples/context"
                 ),
                 context: context
               )

      assert result.state.reply == answer
      assert_receive {:tool_context, visible, _}
      assert visible == %{tenant: "native"}
    end

    assert_script_done(mock)
  end

  test "profile context changes remain scoped and host context reaches projected tools", %{
    jido: jido
  } do
    {mock, context} = mock(tool_round("First") ++ tool_round("Other") ++ tool_round("Changed"))

    profiles = [
      native_profile(:assistant, %{tenant: "one"}),
      native_profile(:reviewer, %{tenant: "two"})
    ]

    server = start_agent(jido, Jido.Agent.instantiate!(definition(profiles)))
    context = put_in(context, [:ai, :reviewer], context.ai.assistant)
    assert {:ok, "First"} = request(server, Map.merge(context, %{region: "host", tenant: "host"}))
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "one", region: "host"}
    assert {:ok, _} = AI.set_tool_context(server, %{tenant: "changed"}, profile: :assistant)
    assert {:ok, "Other"} = request(server, context, :reviewer)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "two"}
    assert {:ok, "Changed"} = request(server, context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "changed"}
    assert_script_done(mock)
  end

  test "restore retains the replaced map and rebuilds transient request bindings", %{jido: jido} do
    {mock, context} = mock(tool_round("Before") ++ tool_round("After"))
    agent = Public.new!()
    server = start_agent(jido, agent)
    assert {:ok, _} = AI.set_tool_context(server, %{tenant: "saved"})

    assert {:ok, "Before"} =
             Public.ask_sync(server, "Read",
               context: context,
               tool_context: %{request_only: true}
             )

    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "saved", request_only: true}
    saved = Server.agent(server).state
    assert :ok = Jido.Action.validate_static_data(saved)
    monitor = Process.monitor(server)
    GenServer.stop(server)
    assert_receive {:DOWN, ^monitor, :process, ^server, _}
    restored = start_agent(jido, Jido.Agent.instantiate!(Public.agent(), state: saved))
    assert {:ok, "After"} = Public.ask_sync(restored, "Read", context: context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "saved"}
    assert AI.get_strategy_config(Server.agent(restored)).base_tool_context == %{tenant: "saved"}
    assert_script_done(mock)
  end

  test "invalid or reserved base maps fail without changing committed state", %{jido: jido} do
    {mock, _} = mock([])
    server = start_agent(jido, Public.new!())
    before = Server.agent(server)

    invalid = [
      nil,
      false,
      [],
      42,
      %{observer: self()},
      %{callback: fn -> :ok end},
      %{agent_state: %{}},
      %{"state" => %{}},
      %{jido_ai_session: true},
      %{"jido_ai_skill_resource_policy" => %{}}
    ]

    invalid =
      invalid ++
        for key <- Jido.AI.Skill.Runtime.reserved_keys(), form <- [key, Atom.to_string(key)] do
          %{form => %{}}
        end

    for value <- invalid do
      assert {:error, _} = AI.set_tool_context(server, value)
      assert {:error, _} = AI.set_tool_context_direct(before, value)

      assert {:error, _} =
               Jido.AI.Profile.new(native_profile(:assistant, value) |> Map.delete(:routes))

      assert Server.agent(server) == before
    end

    assert {:error, _} = AI.set_tool_context(server, %{tenant: "x"}, profile: :missing)

    assert {:error, _} =
             Server.call(
               server,
               Jido.Signal.new!("ai.react.set_tool_context", %{}, source: "/examples/context")
             )

    assert Server.agent(server) == before
    assert_script_done(mock)
  end

  test "request bindings cannot replace runtime identity and stay out of portable defaults", %{
    jido: jido
  } do
    {mock, context} = mock(tool_round())
    server = start_agent(jido, Public.new!())
    expected_id = Server.agent(server).id

    assert {:ok, "Done"} =
             Public.ask_sync(server, "Read",
               context: context,
               tool_context: %{
                 "agent_id" => "forged",
                 agent_id: "forged",
                 state: %{},
                 jido_ai_profiles: %{},
                 observer: self(),
                 request_only: true
               }
             )

    assert_receive {:tool_context, visible, ^expected_id}
    assert visible == %{tenant: "base", region: "us", request_only: true}

    assert AI.get_strategy_config(Server.agent(server)).base_tool_context == %{
             tenant: "base",
             region: "us"
           }

    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  defp identity_request(:public, module, server, context, forged),
    do: module.ask_sync(server, "Read", context: context, tool_context: forged)

  defp identity_request(:session, _module, server, context, forged),
    do: request(server, context, :assistant, tool_context: forged)

  defp identity_request(:turn, _module, server, context, forged) do
    signal = Jido.Signal.new!("context.assistant", %{query: "Read"}, source: "/examples/context")
    before = Server.agent(server)

    assert {:error, %Jido.Error.ValidationError{details: %{keys: keys}}} =
             Server.call(server, signal, context: Map.merge(context, forged))

    assert MapSet.new(keys) == MapSet.new([:agent_id, :agent_state])
    assert Server.agent(server) == before
    # Core rejects these two keys before AI prepares the request. The remaining
    # supplied state and module values still cannot replace the tool's identity.
    context = Map.merge(context, Map.drop(forged, [:agent_id, :agent_state]))

    with {:ok, result} <- Server.call(server, signal, context: context),
         do: {:ok, result.state.reply}
  end

  for {module, mode, tenant} <- [
        {JidoAI.Examples.ToolContext.SnapshotSession, :session, "native"},
        {JidoAI.Examples.ToolContext.SnapshotTurn, :turn, "native"},
        {JidoAI.Examples.ToolContext.Public, :public, "base"}
      ] do
    test "#{module} tools retain the host state and module under runtime overrides", %{jido: jido} do
      module = unquote(module)
      mode = unquote(mode)
      {mock, context} = mock(tool_round("Protected"))
      context = Map.put(context, :observe_identity, true)
      server = start_agent(jido, module.new!())
      before = Server.agent(server)

      forged = %{
        "state" => %{override: true},
        "agent_module" => __MODULE__,
        state: %{override: true},
        agent_state: %{override: true},
        agent_module: __MODULE__,
        agent_id: "forged"
      }

      assert {:ok, "Protected"} = identity_request(mode, module, server, context, forged)

      assert_receive {:tool_identity, seen}, 1_000
      assert seen.agent_id == before.id and seen.agent_module == module
      assert seen.state == seen.agent_state
      assert is_map(seen.state)
      refute Map.has_key?(seen.state, :override)
      assert Map.get(seen.state, :counter) == Map.get(before.state, :counter)
      assert_receive {:tool_context, visible, _}, 1_000
      assert visible.tenant == unquote(tenant)
      after_request = Server.agent(server)
      assert Jido.Agent.definition(after_request) == Jido.Agent.definition(before)
      assert :ok = Jido.Action.validate_static_data(after_request.state)
      [_, wire] = MockLLM.report(mock).requests
      tool = Enum.find(wire.body["messages"], &(&1["role"] == "tool"))
      assert Jason.decode!(tool["content"])["result"]["tenant"] == unquote(tenant)
      assert_script_done(mock)
    end
  end

  test "AI source JSON preserves explicit base context through the trusted Registry", %{
    jido: jido
  } do
    source = native_profile(:assistant, %{tenant: "source"})
    direct = definition([source])
    {:ok, _, registry} = Jido.Agent.Codec.encode(direct)
    {:ok, {normalized, routes}} = Jido.AI.Profile.source(source)
    values = Map.put(Map.from_struct(normalized), :routes, routes)
    atoms = source_atoms(values) |> Enum.uniq()

    entries =
      Enum.reduce(atoms, registry.entries, fn atom, entries ->
        if Enum.any?(entries, fn {_, value} -> value == {:atom, atom} end),
          do: entries,
          else: Map.put(entries, "context-atom/#{atom}", {:atom, atom})
      end)

    registry = Jido.Agent.Codec.Registry.new!(entries)
    assert {:ok, document} = Authoring.Codec.encode([source], registry)

    base =
      Jido.Agent.new!(
        name: "context_profiles",
        schema: Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})
      )

    assert {:ok, decoded} =
             Authoring.Codec.decode(base, Jason.decode!(Jason.encode!(document)), registry)

    assert decoded == direct
    {mock, context} = mock(tool_round())
    server = start_agent(jido, Jido.Agent.instantiate!(decoded))
    assert {:ok, "Done"} = request(server, context)
    assert_receive {:tool_context, seen, _}
    assert seen == %{tenant: "source"}
    assert_script_done(mock)
  end

  defp source_atoms(value) when value in [true, false, nil], do: []
  defp source_atoms(value) when is_atom(value), do: [value]

  defp source_atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {key, item} -> source_atoms(key) ++ source_atoms(item) end)

  defp source_atoms(value) when is_list(value), do: Enum.flat_map(value, &source_atoms/1)
  defp source_atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> source_atoms()
  defp source_atoms(_), do: []

  test "the native DSL rejects false and nil base contexts instead of treating them as absent" do
    for invalid <- [false, nil] do
      module = Module.concat(__MODULE__, "InvalidContext#{System.unique_integer([:positive])}")

      quoted =
        quote do
          defmodule unquote(module) do
            use Jido.Agent, name: "invalid_context", extensions: [Jido.AI.DSL]

            agent do
              schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

              ai :assistant do
                tool_context(unquote(invalid))

                models do
                  model(:answer, :example)
                end

                reasoning :react do
                  model(:answer)
                end

                result(nil, into: :reply)
              end
            end

            routes do
              route "context.assistant", ai(:assistant)
            end
          end
        end

      assert_raise CompileError, ~r/tool_context/, fn -> Code.compile_quoted(quoted) end
    end
  end
end
