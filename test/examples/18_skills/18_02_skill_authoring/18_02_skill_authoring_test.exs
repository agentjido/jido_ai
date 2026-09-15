defmodule JidoAI.Examples.SkillAuthoringTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Profile, Request, Orchestration}
  alias Jido.AI.Skill.{Registry, Spec}
  alias JidoAI.Examples.SkillAuthoring.{Echo, Public, Review, Trust}
  alias JidoAI.Examples.SkillRuntime.Provider

  setup do
    start_supervised!(Registry)
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

  defp spec(name \\ "review", body \\ "Runtime instructions"),
    do: %Spec{name: name, description: "Review a document.", body_ref: {:inline, body}}

  defp base,
    do:
      Jido.Agent.new!(
        name: "source_skills",
        schema:
          Zoi.object(%{
            reply: Zoi.any() |> Zoi.default(nil),
            messages: Jido.AI.Thread.Projection.schema()
          })
      )

  defp profile(skills) do
    %{
      id: :assistant,
      instructions: "Base prompt",
      models: %{answer: :example},
      reasoning: %{method: :react, model: :answer},
      requests: %{mode: :session},
      memory: %{history: :messages},
      result: %{into: :reply},
      skills: skills,
      routes: ["ai.ask"]
    }
  end

  defp definition(skills) do
    {:ok, definition} = Authoring.lower(base(), [profile(skills)])
    definition
  end

  defp start(jido, skills), do: start_agent(jido, Jido.Agent.instantiate!(definition(skills)))

  defp request(server, context, opts \\ []) do
    with {:ok, request} <-
           Request.create_and_send(
             server,
             "Review",
             Keyword.merge(
               [signal_type: "ai.ask", source: "/examples/skill-authoring", context: context],
               opts
             )
           ),
         do: Request.await(request)
  end

  defp load(name \\ "review", id \\ "load"),
    do: %{id: id, name: "load_skill", arguments: %{name: name}}

  defp names(wire), do: Enum.map(wire.body["tools"] || [], & &1["function"]["name"])
  defp first_prompt(wire), do: hd(wire.body["messages"])["content"]
  defp text(wire), do: Jason.encode!(wire.body)

  defp write_skill(root, name, body) do
    dir = Path.join(root, name)
    File.mkdir_p!(dir)
    path = Path.join(dir, "SKILL.md")
    File.write!(path, "---\nname: #{name}\ndescription: Review a document.\n---\n#{body}")
    path
  end

  test "the skills block adds the index loading tools and native module actions", %{
    jido: jido
  } do
    calls = [load(), %{id: "echo", name: "skill_echo", arguments: %{text: "Checked"}}]
    {mock, context} = mock([%{reply: {:tools, calls}}, %{reply: {:text, "Done"}}])
    server = start_agent(jido, Public.new!())
    assert {:ok, %{specs: [loaded], index: index}} = Orchestration.skill_catalog(server)
    assert loaded.source == {:module, Review}
    assert loaded.metadata == %{owner: :native_module}
    assert index =~ "review"
    refute index =~ "Module review instructions"
    assert {:ok, "Done"} = Public.ask_sync(server, "Review", context: context)
    [first, final] = MockLLM.report(mock).requests
    echo_result = Enum.find(final.body["messages"], &(&1["tool_call_id"] == "echo"))
    assert Jason.decode!(echo_result["content"]) == %{"ok" => true, "result" => %{"text" => "Checked"}}
    assert first_prompt(first) =~ "Base prompt"
    assert first_prompt(first) =~ index
    refute first_prompt(first) =~ "Module review instructions"
    assert Enum.sort(names(first)) == ["load_skill", "load_skill_resource", "skill_echo"]
    assert text(final) =~ "Module review instructions"
    assert {:ok, _} = Jido.AI.register_tool(server, Echo)
    assert {:ok, effective} = Jido.AI.Configuration.profile(Server.agent(server))

    for tool <- effective.tools do
      assert tool.timeout == 5_000
      assert Map.get(tool, :max_retries, 0) == 0
      assert Map.get(tool, :retry_backoff, 0) == 0
    end

    assert :ok = Jido.Action.validate_static_data(Server.agent(server).state)
    assert_script_done(mock)
  end

  test "the native skills block uses the same catalogue and actual loading Action", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [load()]}}, %{reply: {:text, "Done"}}])
    server = start_agent(jido, Public.new!())
    assert {:ok, "Done"} = request(server, context)
    assert {:ok, %{specs: [%{name: "review"}]}} = Orchestration.skill_catalog(server)
    assert text(List.last(MockLLM.report(mock).requests)) =~ "Module review instructions"
    assert_script_done(mock)
  end

  test "source data Builder and JSON retain automatic skill behavior", %{jido: jido} do
    source =
      profile(%{
        specs: [spec()],
        resource_provider: {Provider, :handle},
        resource_policy: [max_text_bytes: 10]
      })

    assert {:ok, direct} = Authoring.lower(base(), [source])

    built =
      Jido.Agent.Builder.new(Map.from_struct(direct) |> Map.drop([:id, :state]))
      |> Jido.Agent.Builder.build!()

    assert {:ok, document, registry} = Jido.Agent.Codec.encode(direct)

    assert {:ok, decoded} =
             Jido.Agent.Codec.decode(document |> Jason.encode!() |> Jason.decode!(), registry)

    source_registry = source_registry(source, registry)
    assert {:ok, source_doc} = Authoring.Codec.encode([source], source_registry)

    assert {:ok, source_decoded} =
             Authoring.Codec.decode(
               base(),
               source_doc |> Jason.encode!() |> Jason.decode!(),
               source_registry
             )

    {mock, context} =
      mock(
        List.duplicate([%{reply: {:tools, [load()]}}, %{reply: {:text, "Done"}}], 4)
        |> List.flatten()
      )

    for definition <- [direct, built, decoded, source_decoded] do
      assert definition == direct
      server = start_agent(jido, Jido.Agent.instantiate!(definition))
      assert {:ok, "Done"} = request(server, context)
      assert {:ok, %{index: index}} = Orchestration.skill_catalog(server)
      assert index =~ "review"
    end

    assert_script_done(mock)
  end

  @tag :tmp_dir
  test "compilation and static construction do not capture the build directory catalogue", %{
    jido: jido,
    tmp_dir: tmp
  } do
    build = Path.join(tmp, "build")
    runtime = Path.join(tmp, "runtime")
    write_skill(Path.join(build, "skills"), "build-only", "Build body")
    runtime_path = write_skill(Path.join(runtime, "skills"), "runtime-only", "Old runtime body")
    module = Module.concat(__MODULE__, "RuntimeLocation#{System.unique_integer([:positive])}")

    code = """
    defmodule #{inspect(module)} do
      use Jido.AI.Agent, name: "runtime_location"

      agent do
        schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil), messages: Jido.AI.Thread.Projection.schema()})

        ai :assistant do
          model(:example)
          reasoning(:react)
          skills(paths: ["skills"], trust: true)
          requests(mode: :session)
          memory(history: :messages)
          result(into: :reply)
        end
      end

      routes do
        route("ai.ask", ai: :assistant)
      end
    end
    """

    agent =
      File.cd!(build, fn ->
        Code.compile_string(code)
        module.new!()
      end)

    assert :ok = Jido.Action.validate_static_data(agent.state)
    server = File.cd!(runtime, fn -> start_agent(jido, agent) end)

    assert {:ok, %{specs: [%{name: "runtime-only"}], index: index}} =
             Orchestration.skill_catalog(server)

    refute index =~ "Build body"

    File.write!(
      runtime_path,
      "---\nname: runtime-only\ndescription: Review a document.\n---\nLatest body"
    )

    {mock, context} =
      mock([%{reply: {:tools, [load("runtime-only")]}}, %{reply: {:text, "Done"}}])

    assert {:ok, "Done"} = module.ask_sync(server, "Review", context: context)
    assert text(List.last(MockLLM.report(mock).requests)) =~ "Latest body"
    refute text(List.last(MockLLM.report(mock).requests)) =~ "Build body"
    assert_script_done(mock)
  end

  for disabled <- [nil, false, []] do
    test "disabled source #{inspect(disabled)} adds no tools or index", %{jido: jido} do
      {mock, context} = mock([%{reply: {:text, "Done"}}])
      server = start(jido, unquote(Macro.escape(disabled)))
      assert {:error, :automatic_skills_disabled} = Orchestration.skill_catalog(server)
      assert {:ok, "Done"} = request(server, context)
      assert [wire] = MockLLM.report(mock).requests
      assert names(wire) == []
      assert first_prompt(wire) == "Base prompt"
      assert_script_done(mock)
    end
  end

  test "an enabled empty catalogue has no automatic tools and cannot use global skills", %{
    jido: jido
  } do
    Registry.register(spec("global", "Global body"))
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido, %{paths: []})
    assert {:ok, %{specs: [], index: ""}} = Orchestration.skill_catalog(server)
    assert {:ok, "Done"} = request(server, context)
    assert [wire] = MockLLM.report(mock).requests
    assert names(wire) == []
    assert first_prompt(wire) == "Base prompt"
    assert_script_done(mock)
  end

  test "request tool selection applies after the automatic tools are added", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Done"}}, %{reply: {:text, "Again"}}])
    server = start_agent(jido, Public.new!())

    assert {:ok, "Done"} =
             Public.ask_sync(server, "Review", context: context, allowed_tools: ["load_skill"])

    assert {:ok, "Again"} = Public.ask_sync(server, "Review", context: context, tools: [Echo])
    [first, second] = MockLLM.report(mock).requests
    assert names(first) == ["load_skill"]
    assert names(second) == ["skill_echo"]
    assert_script_done(mock)
  end

  test "declared sources own their catalogue provider and resource policy", %{jido: jido} do
    {mock, context} = mock([%{reply: {:tools, [load()]}}, %{reply: {:text, "Done"}}])

    server =
      start(jido, %{
        specs: [spec()],
        resource_provider: {Provider, :handle},
        resource_policy: [max_text_bytes: 5]
      })

    poisoned =
      Jido.AI.Skill.AgentIntegration.prepare!(
        specs: [spec("other", "Injected body")],
        resource_provider: fn _, _ -> flunk("request provider replaced source") end
      )

    context = Map.merge(context, poisoned.tool_context)
    assert {:ok, "Done"} = request(server, context)
    assert_receive {:skill_list, _, provider_context}
    assert provider_context.observer == self()
    assert text(List.last(MockLLM.report(mock).requests)) =~ "Runtime instructions"
    refute text(List.last(MockLLM.report(mock).requests)) =~ "Injected body"
    assert_script_done(mock)
  end

  @tag :tmp_dir
  test "trust and discovery limits fail at live startup before any model call", %{
    jido: jido,
    tmp_dir: tmp
  } do
    write_skill(tmp, "review", "Body")
    {mock, _} = mock([])

    for source <- [
          %{paths: [tmp]},
          %{paths: [tmp], trust: false},
          %{paths: [tmp], trust: true, max_directories: 1}
        ] do
      assert {:ok, definition} = Authoring.lower(base(), [profile(source)])
      assert {:error, _} = Jido.start_agent(jido, Jido.Agent.instantiate!(definition))
    end

    assert_script_done(mock)
  end

  @tag :tmp_dir
  test "a static trust callback preserves explicit runtime discovery", %{
    jido: jido,
    tmp_dir: tmp
  } do
    write_skill(tmp, "review", "Trusted body")
    source = %{paths: [tmp], trust: {Trust, :allow, [Path.basename(tmp)]}}
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start(jido, source)
    assert {:ok, %{specs: [%{name: "review"}]}} = Orchestration.skill_catalog(server)
    assert {:ok, "Done"} = request(server, context)
    assert_script_done(mock)
  end

  test "invalid source shapes fail without invoking a provider or reading paths" do
    callback = fn _ -> flunk("validation invoked a callback") end

    for source <- [
          %{unknown: true},
          %{paths: [1]},
          %{specs: [spec(), spec()]},
          %{specs: [:invalid]},
          %{resource_policy: [max_text_bytes: 0]},
          %{trust: callback},
          %{resource_provider: fn _, _ -> flunk("called") end},
          %{modules: [String]},
          [paths: [], paths: []]
        ] do
      assert {:error, _} = Authoring.lower(base(), [profile(source)])
    end

    assert {:error, _} =
             Profile.new(
               profile(%{specs: [spec()]})
               |> Map.delete(:routes)
               |> put_in([:requests, :mode], :turn)
             )
  end

  test "automatic skills reject pure Orchestration admission without a live owner" do
    agent = Jido.Agent.instantiate!(definition(%{specs: [spec()]}))

    assert {:error, _} =
             Jido.Agent.cmd(
               agent,
               Jido.Signal.new!("ai.ask", %{query: "Review", request_id: "pure"}, source: "/example")
             )
  end

  defp source_registry(source, registry) do
    {:ok, {profile, routes}} = Profile.source(source)
    values = static_values(Map.put(Map.from_struct(profile), :routes, routes))

    entries =
      Enum.reduce(Enum.uniq(values), registry.entries, fn {kind, value} = entry, entries ->
        if Enum.any?(entries, fn {_, existing} -> existing == entry end) do
          entries
        else
          id =
            "skills/#{kind}/" <>
              Base.encode16(:crypto.hash(:sha256, :erlang.term_to_binary(value)))

          Map.put(entries, id, entry)
        end
      end)

    Jido.Codec.Registry.new!(entries)
  end

  defp static_values(value) when value in [nil, true, false], do: []
  defp static_values(value) when is_atom(value), do: [{:atom, value}]
  defp static_values(%_{} = value), do: [{:value, value}]

  defp static_values(value) when is_map(value),
    do: Enum.flat_map(value, fn {key, value} -> static_values(key) ++ static_values(value) end)

  defp static_values(value) when is_list(value), do: Enum.flat_map(value, &static_values/1)
  defp static_values(value) when is_tuple(value), do: value |> Tuple.to_list() |> static_values()
  defp static_values(_), do: []

  @tag :tmp_dir
  test "the load_path DSL resolves lazy files only when the live Agent starts", %{
    jido: jido,
    tmp_dir: tmp
  } do
    module = Module.concat(__MODULE__, "Paths#{System.unique_integer([:positive])}")

    quoted =
      quote do
        defmodule unquote(module) do
          use Jido.Agent, name: "skill_paths", extensions: [Jido.AI.DSL]

          agent do
            schema Zoi.object(%{
                     reply: Zoi.any() |> Zoi.default(nil),
                     messages: Jido.AI.Thread.Projection.schema()
                   })

            ai :assistant do
              models do
                model(:answer, :example)
              end

              reasoning :react do
                model(:answer)
              end

              skills do
                load_path(unquote(tmp))
              end

              requests do
                mode(:session)
              end

              memory do
                history(:messages)
              end

              result(nil, into: :reply)
            end
          end

          routes do
            route("ai.ask", ai(:assistant))
          end
        end
      end

    Code.compile_quoted(quoted)
    agent = module.new!()
    write_skill(tmp, "review", "Created after compilation")
    {mock, context} = mock([%{reply: {:tools, [load()]}}, %{reply: {:text, "Done"}}])
    server = start_agent(jido, agent)
    assert {:ok, "Done"} = request(server, context)
    assert text(List.last(MockLLM.report(mock).requests)) =~ "Created after compilation"
    assert_script_done(mock)
  end

  test "separate profiles keep their automatic catalogues and instructions separate", %{
    jido: jido
  } do
    base =
      Jido.Agent.new!(
        name: "two_skill_profiles",
        schema:
          Zoi.object(%{
            reply: Zoi.any() |> Zoi.default(nil),
            messages: Jido.AI.Thread.Projection.schema(),
            review_reply: Zoi.any() |> Zoi.default(nil),
            review_messages: Jido.AI.Thread.Projection.schema()
          })
      )

    first = profile(%{specs: [spec("review", "Assistant instructions")]})

    second =
      profile(%{specs: [spec("review", "Reviewer instructions")]})
      |> Map.merge(%{
        id: :review,
        memory: %{history: :review_messages},
        result: %{into: :review_reply},
        routes: ["review.ask"]
      })

    assert {:ok, definition} = Authoring.lower(base, [first, second])

    {mock, context} =
      mock([
        %{reply: {:tools, [load()]}},
        %{reply: {:text, "First"}},
        %{reply: {:tools, [load()]}},
        %{reply: {:text, "Second"}}
      ])

    context = put_in(context, [:ai, :review], %{options: MockLLM.options(mock)})
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, "First"} = request(server, context)
    assert {:ok, "Second"} = request(server, context, signal_type: "review.ask")

    assert {:ok, %{specs: [%{body_ref: {:inline, "Assistant instructions"}}]}} =
             Orchestration.skill_catalog(server)

    assert {:ok, %{specs: [%{body_ref: {:inline, "Reviewer instructions"}}]}} =
             Orchestration.skill_catalog(server, :review)

    assert {:error, _} = Orchestration.skill_catalog(server, :missing)
    [_, first_wire, _, second_wire] = MockLLM.report(mock).requests
    assert text(first_wire) =~ "Assistant instructions"
    refute text(first_wire) =~ "Reviewer instructions"
    assert text(second_wire) =~ "Reviewer instructions"
    refute text(second_wire) =~ "Assistant instructions"
    assert_script_done(mock)
  end

  @tag :tmp_dir
  test "restore rebuilds the automatic catalogue and uses current file content", %{
    jido: jido,
    tmp_dir: tmp
  } do
    path = write_skill(tmp, "review", "Old instructions")

    {mock, context} =
      mock([
        %{reply: {:tools, [load()]}},
        %{reply: {:text, "First"}},
        %{reply: {:tools, [load("review", "fresh")]}},
        %{reply: {:text, "Second"}}
      ])

    definition = definition([tmp])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    assert {:ok, "First"} = request(server, context)
    saved = Server.agent(server)
    bytes = :erlang.term_to_binary(saved.state)
    :ok = Server.stop(server, :normal)
    File.write!(path, "---\nname: review\ndescription: New description.\n---\nNew instructions")

    restored =
      Jido.Agent.instantiate!(definition,
        id: saved.id,
        state: :erlang.binary_to_term(bytes, [:safe])
      )
      |> then(&start_agent(jido, &1))

    assert {:ok, %{index: index}} = Orchestration.skill_catalog(restored)
    assert index =~ "New description."
    assert {:ok, "Second"} = request(restored, context)
    assert text(List.last(MockLLM.report(mock).requests)) =~ "New instructions"
    assert length(MockLLM.report(mock).requests) == 4
    assert_script_done(mock)
  end

  @tag :tmp_dir
  test "activation strictly validates a file changed after automatic catalogue setup", %{
    jido: jido,
    tmp_dir: tmp
  } do
    path = write_skill(tmp, "review", "Body")
    server = start(jido, [tmp])

    File.write!(
      path,
      "---\nname: different-name\ndescription: Invalid layout.\n---\nBad instructions"
    )

    {mock, context} = mock([%{reply: {:tools, [load()]}}, %{reply: {:text, "Could not load"}}])
    assert {:ok, "Could not load"} = request(server, context)
    [_, wire] = MockLLM.report(mock).requests
    tool = Enum.find(wire.body["messages"], &(&1["role"] == "tool"))
    assert Jason.decode!(tool["content"])["ok"] == false
    refute text(wire) =~ "Bad instructions"
    refute Enum.any?(conversation(Server.agent(server)), & &1.refs[:durable])
    assert_script_done(mock)
  end

  @tag :tmp_dir
  test "runtime specs win over module and filesystem sources with visible diagnostics", %{
    jido: jido,
    tmp_dir: tmp
  } do
    write_skill(tmp, "review", "File instructions")
    {mock, context} = mock([%{reply: {:tools, [load()]}}, %{reply: {:text, "Done"}}])
    server = start(jido, %{paths: [tmp], trust: true, specs: [spec()], modules: [Review]})
    assert {:ok, %{specs: [chosen], diagnostics: diagnostics}} = Orchestration.skill_catalog(server)
    assert chosen.body_ref == {:inline, "Runtime instructions"}
    assert Enum.count(diagnostics.warnings, &(&1.type == :shadowed_skill)) == 2
    assert {:ok, "Done"} = request(server, context)
    [first, final] = MockLLM.report(mock).requests
    refute "skill_echo" in names(first)
    assert text(final) =~ "Runtime instructions"
    refute text(final) =~ "File instructions"
    refute text(final) =~ "Module review instructions"
    assert_script_done(mock)
  end

  test "a live prompt replacement retains its text and the skill index", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Done"}}])
    server = start_agent(jido, Public.new!())
    assert {:ok, _} = Jido.AI.set_system_prompt(server, "Exact replacement")
    assert {:ok, "Done"} = Public.ask_sync(server, "Review", context: context)
    assert [wire] = MockLLM.report(mock).requests
    assert first_prompt(wire) =~ "Exact replacement"
    assert first_prompt(wire) =~ "## Skills"
    assert Enum.sort(names(wire)) == ["load_skill", "load_skill_resource", "skill_echo"]
    assert_script_done(mock)
  end
end
