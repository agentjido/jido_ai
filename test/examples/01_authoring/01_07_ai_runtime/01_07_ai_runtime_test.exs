defmodule JidoAI.Examples.AIRuntimeTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.AIRuntime
  alias Jido.AI.Authoring
  alias Jido.AI.Profile

  defp base do
    Jido.Agent.new!(
      name: "ai_runtime_data",
      schema: AIRuntime.Agent.definition().schema,
      plugins: [JidoAI.Examples.Support.CommitCounter],
      routes: [{"case.close", JidoAI.Examples.Support.CloseCase}]
    )
  end

  defp profile do
    profile = Jido.AI.Agent.profile(AIRuntime.Agent, :assistant) |> Map.from_struct()

    controls =
      Map.merge(profile.controls, %{
        input: [AIRuntime.Record],
        model: [AIRuntime.Record],
        operation: [AIRuntime.Record],
        output: [AIRuntime.Record]
      })

    %{profile | controls: controls} |> Map.put(:routes, ["ai.ask"])
  end

  defp start(jido, profile) do
    {:ok, definition} = Authoring.lower(base(), [profile])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))
    observe_tools()
    server
  end

  test "DSL helper executes Action and Flow tools and preserves Plugin ownership", %{jido: jido} do
    calls = [
      %{id: "one", name: "multiply", arguments: %{a: 2, b: 3}},
      %{id: "two", name: "quote", arguments: %{a: 4, b: 5}}
    ]

    {mock, context} =
      mock([%{reply: {:tools, calls}}, %{reply: {:object, %{answer: "6 and 20"}}}])

    server = start_agent(jido, AIRuntime.Agent.new!())
    observe_tools()

    assert {:ok, %{state: %{reply: %{answer: "6 and 20"}, case_id: "case-42", commits: commits}}} =
             ask_and_await(AIRuntime.Agent, server, "Calculate", context: context)

    assert commits >= 2

    assert_receive {:example_tool_started, "multiply"}
    assert_receive {:example_tool_started, "quote"}

    assert {:ok, %{state: %{case_id: "closed", commits: next_commits}}} =
             AIRuntime.Agent.close(server, "closed")

    assert next_commits > commits

    assert [first, second] = MockLLM.report(mock).requests
    assert first.body["temperature"] == 0.2
    assert Enum.count(second.body["messages"], &(&1["role"] == "system")) == 1
    results = Enum.filter(second.body["messages"], &(&1["role"] == "tool"))
    assert Enum.map(results, & &1["tool_call_id"]) == ["one", "two"]

    assert Enum.map(results, &Jason.decode!(&1["content"])) == [
             %{"ok" => true, "result" => %{"value" => 6}},
             %{"ok" => true, "result" => %{"value" => 20}}
           ]

    assert_script_done(mock)
  end

  test "source JSON and trusted registry lower to the same Agent before execution", %{jido: jido} do
    profile = profile()
    {:ok, direct} = Authoring.lower(base(), [profile])
    registry = source_registry(profile)
    assert {:ok, source} = Authoring.Codec.encode([profile], registry)
    source = source |> Jason.encode!() |> Jason.decode!()
    assert {:ok, ^direct} = Authoring.Codec.decode(base(), source, registry)
    {mock, context} = mock([%{reply: {:object, %{answer: "Imported"}}}])
    {:ok, imported} = Authoring.Codec.decode(base(), source, registry)
    server = start_agent(jido, Jido.Agent.instantiate!(imported))
    assert {:ok, %{state: %{reply: %{answer: "Imported"}, commits: commits}}} = ask(server, context)
    assert commits >= 2
    assert {:error, _} = Authoring.Codec.decode(base(), Map.put(source, "extra", true), registry)
    assert {:error, _} = Authoring.Codec.decode(base(), source, %{})
    assert_script_done(mock)
  end

  test "a host can assign stable IDs to the AI boundary and execute a stored Agent", %{
    jido: jido
  } do
    {:ok, definition} = Authoring.lower(base(), [profile()])

    {target, %{profile_id: :assistant}} =
      Enum.find(definition.routes, &(&1.path == "ai.ask")).target

    {Jido.AI.Configuration.Plugin, options} =
      Enum.find(definition.plugins, fn {module, _options} ->
        module == Jido.AI.Configuration.Plugin
      end)

    registry =
      Jido.Codec.Registry.new!(%{
        "agents/core" => {:agent, Jido.Agent},
        "schemas/domain" => {:schema, definition.schema},
        "plugins/audit" => {:plugin, JidoAI.Examples.Support.CommitCounter},
        "plugins/ai" => {:plugin, Jido.AI.Configuration.Plugin},
        "plugins/session" => {:plugin, Jido.AI.Orchestration.Plugin},
        "actions/assistant-v1" => {:action, target},
        "actions/close" => {:action, JidoAI.Examples.Support.CloseCase},
        "actions/configure" => {:action, Jido.AI.Configuration.Apply},
        "atoms/operation" => {:atom, :operation},
        "atoms/register" => {:atom, :register},
        "atoms/unregister" => {:atom, :unregister},
        "atoms/prompt" => {:atom, :prompt},
        "atoms/tool_context" => {:atom, :tool_context},
        "atoms/profiles" => {:atom, :profiles},
        "atoms/profile_id" => {:atom, :profile_id},
        "atoms/assistant" => {:atom, :assistant},
        "profiles/assistant-v1" => {:value, options[:profiles].assistant}
      })

    {:ok, _, discovered} = Jido.Agent.Codec.encode(definition)
    additional = Map.reject(discovered.entries, fn {_, value} -> value in Map.values(registry.entries) end)
    registry = Jido.Codec.Registry.new!(Map.merge(additional, registry.entries))
    assert {:ok, document} = Jido.Agent.Codec.encode(definition, registry)
    assert Enum.any?(document["routes"], &(&1["target"] == "actions/assistant-v1"))

    assert {:ok, ^definition} =
             document |> Jason.encode!() |> Jason.decode!() |> Jido.Agent.Codec.decode(registry)

    {mock, context} = mock([%{reply: {:object, %{answer: "Stored"}}}])
    {:ok, restored} = Jido.Agent.Codec.decode(document, registry)
    server = start_agent(jido, Jido.Agent.instantiate!(restored))
    assert {:ok, %{state: %{reply: %{answer: "Stored"}}}} = ask(server, context)
    assert_script_done(mock)
  end

  test "repair uses the same model controls and sends schema feedback", %{jido: jido} do
    {mock, context} =
      mock([%{reply: {:object, %{answer: ""}}}, %{reply: {:object, %{answer: "Fixed"}}}])

    profile = %{profile() | tools: []}
    server = start(jido, profile)
    assert {:ok, %{state: %{reply: %{answer: "Fixed"}, commits: commits}}} = ask(server, context)
    assert commits >= 2
    assert [_, repair] = MockLLM.report(mock).requests
    feedback = List.last(repair.body["messages"])["content"]
    assert feedback =~ "Validation error:"
    assert feedback =~ "Original user message:"
    assert feedback =~ "Help with this case"
    assert feedback =~ "answer"
    assert repair.body["response_format"]["type"] == "json_schema"
    checks = drain_checks([])
    assert Enum.count(checks, &is_map_key(&1, :options)) == 2
    assert_script_done(mock)
  end

  test "repair cannot exceed the model call budget", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{answer: ""}}}])
    profile = %{profile() | tools: []} |> put_in([:controls, :max_model_calls], 1)
    server = start(jido, profile)
    before = Server.snapshot(server)
    assert {:error, _} = ask(server, context)
    assert_domain_unchanged(server, before)
    assert_script_done(mock)
  end

  test "multiple model and tool rounds retain the complete transcript", %{jido: jido} do
    first = %{id: "first", name: "multiply", arguments: %{a: 2, b: 3}}
    second = %{id: "second", name: "quote", arguments: %{a: 6, b: 5}}

    {mock, context} =
      mock([
        %{reply: {:tools, [first]}},
        %{reply: {:tools, [second]}},
        %{reply: {:object, %{answer: "30"}}}
      ])

    server = start(jido, profile())
    assert {:ok, %{state: %{reply: %{answer: "30"}, commits: commits}}} = ask(server, context)
    assert commits >= 2
    assert [_, _, final] = MockLLM.report(mock).requests

    assert Enum.map(final.body["messages"], & &1["role"]) == [
             "system",
             "user",
             "assistant",
             "tool",
             "assistant",
             "tool"
           ]

    results = Enum.filter(final.body["messages"], &(&1["role"] == "tool"))
    assert Enum.map(results, & &1["tool_call_id"]) == ["first", "second"]

    assert Enum.map(results, &Jason.decode!(&1["content"])) == [
             %{"ok" => true, "result" => %{"value" => 6}},
             %{"ok" => true, "result" => %{"value" => 30}}
           ]

    assert_script_done(mock)
  end

  test "string option fields keep imported JSON schema keys intact", %{jido: jido} do
    schema = %{
      "type" => "object",
      "properties" => %{"answer" => %{"type" => "string"}},
      "required" => ["answer"]
    }

    profile = %{
      "id" => :assistant,
      "models" => %{answer: %{"model" => MockLLM.model(), "generation" => []}},
      "reasoning" => %{"method" => :react, "model" => :answer},
      "result" => %{"schema" => schema, "into" => :reply},
      "routes" => ["ai.ask"]
    }

    {mock, context} = mock([%{reply: {:object, %{"answer" => "Imported schema"}}}])
    server = start(jido, profile)
    assert {:ok, %{state: %{reply: %{"answer" => "Imported schema"}}}} = ask(server, context)
    assert [request] = MockLLM.report(mock).requests

    assert get_in(request.body, [
             "response_format",
             "json_schema",
             "schema",
             "properties",
             "answer",
             "type"
           ]) == "string"

    assert_script_done(mock)
  end

  for stage <- [:input, :model, :output] do
    script = if stage == :output, do: [%{reply: {:object, %{answer: "Reject me"}}}], else: []

    test "#{stage} rejection preserves live state", %{jido: jido} do
      stage = unquote(stage)
      script = unquote(Macro.escape(script))
      {mock, context} = mock(script)
      profile = put_in(profile(), [:controls, stage], [AIRuntime.Reject])
      server = start(jido, profile)
      before = Server.snapshot(server)
      assert {:error, _} = ask(server, context)
      assert_domain_unchanged(server, before)
      assert_script_done(mock)
    end
  end

  for invalid <- [
        %{id: "two", name: "unknown", arguments: %{a: 1, b: 2}},
        %{id: "two", name: "quote", arguments: %{a: "wrong", b: 2}},
        %{id: "one", name: "quote", arguments: %{a: 1, b: 2}}
      ] do
    test "full-batch preflight rejects #{inspect(invalid)} before effects", %{jido: jido} do
      calls = [
        %{id: "one", name: "multiply", arguments: %{a: 2, b: 3}},
        unquote(Macro.escape(invalid))
      ]

      script = [%{reply: {:tools, calls}}]

      script =
        if unquote(invalid.name == "unknown"),
          do: script ++ [%{reply: {:object, %{answer: "Batch rejected"}}}],
          else: script

      {mock, context} = mock(script)
      server = start(jido, profile())
      before = Server.snapshot(server)
      outcome = ask(server, context)

      if unquote(invalid.name == "unknown") do
        assert {:ok, _} = outcome
      else
        assert {:error, _} = outcome
        assert_domain_unchanged(server, before)
      end

      refute_received {:example_tool_started, _}
      assert_script_done(mock)
    end
  end

  test "operation rejection applies before any tool starts", %{jido: jido} do
    calls = [%{id: "one", name: "multiply", arguments: %{a: 2, b: 3}}]
    {mock, context} = mock([%{reply: {:tools, calls}}])
    server = start(jido, put_in(profile(), [:controls, :operation], [AIRuntime.Reject]))
    assert {:error, _} = ask(server, context)
    refute_received {:example_tool_started, _}
    assert_script_done(mock)
  end

  test "concurrency one starts the second tool only after the first completes", %{jido: jido} do
    calls = for n <- 1..2, do: %{id: "call-#{n}", name: "wait", arguments: %{n: n}}
    {mock, context} = mock([%{reply: {:tools, calls}}, %{reply: {:object, %{answer: "Done"}}}])
    tool = %{name: "wait", target: AIRuntime.WaitTool, forward_context: [:observer]}
    profile = %{profile() | tools: [tool]} |> put_in([:reasoning, :tool_concurrency], 1)
    server = start(jido, profile)
    task = Task.async(fn -> ask(server, context) end)
    assert_receive {:tool_waiting, first, 1}, 2_000
    refute_received {:tool_waiting, _, 2}
    send(first, :release)
    assert_receive {:tool_waiting, second, 2}, 2_000
    send(second, :release)
    assert {:ok, _} = Task.await(task)
    assert_script_done(mock)
  end

  test "Signal data cannot replace a host profile", %{jido: jido} do
    {mock, context} = mock([%{reply: {:object, %{answer: "Host policy"}}}])
    server = start(jido, profile())

    signal =
      Jido.Signal.new!(
        "ai.ask",
        %{
          query: "Help",
          profile_id: :other,
          jido_ai_profiles: %{assistant: %{controls: %{input: []}}}
        },
        source: "/test"
      )

    assert {:ok, _} =
             Jido.AI.Test.Requests.call_and_await(server, signal, context: Map.put(context, :jido_ai_profiles, %{}))

    assert_receive {:control_checked, %{query: "Help"}}
    assert_script_done(mock)
  end

  test "live cancellation stops owned tool work and preserves the commit", %{jido: jido} do
    calls = [%{id: "wait-1", name: "wait", arguments: %{n: 1}}]
    {mock, context} = mock([%{reply: {:tools, calls}}])

    profile = %{
      profile()
      | tools: [%{name: "wait", target: AIRuntime.WaitTool, forward_context: [:observer]}]
    }

    server = start(jido, profile)
    before = Server.snapshot(server)
    task = Task.async(fn -> ask(server, context) end)
    assert_receive {:tool_waiting, worker, 1}, 2_000
    monitor = Process.monitor(worker)
    assert {:ok, _} = Server.call(server, Jido.Signal.new!(Jido.AI.Orchestration.cancel_type(), %{}, source: "/test"))
    assert {:error, _} = Task.await(task)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert_domain_unchanged(server, before)
    assert_script_done(mock)
  end

  test "the request deadline stops a blocked input control before model work", %{jido: jido} do
    {mock, context} = mock([])

    profile =
      profile()
      |> put_in([:controls, :input], [AIRuntime.WaitControl])
      |> put_in([:controls, :timeout], 200)

    server = start(jido, profile)
    before = Server.snapshot(server)
    task = Task.async(fn -> ask(server, context) end)
    assert_receive {:control_waiting, worker}, 2_000
    monitor = Process.monitor(worker)
    assert {:error, _} = Task.await(task, 2_000)
    assert_receive {:DOWN, ^monitor, :process, ^worker, _}, 2_000
    assert_domain_unchanged(server, before)
    assert_script_done(mock)
  end

  test "the iteration limit prevents another model call after tool results", %{jido: jido} do
    calls = [%{id: "one", name: "multiply", arguments: %{a: 2, b: 3}}]
    {mock, context} = mock([%{reply: {:tools, calls}}])
    server = start(jido, put_in(profile(), [:controls, :max_iterations], 1))
    before = Server.snapshot(server)
    assert {:error, _} = ask(server, context)
    assert_receive {:example_tool_started, "multiply"}
    assert_domain_unchanged(server, before)
    assert_script_done(mock)
  end

  test "provider errors preserve state and cannot enter object repair", %{jido: jido} do
    {mock, context} = mock([%{reply: {:error, 400, "Invalid request"}}])
    server = start(jido, %{profile() | tools: []})
    before = Server.snapshot(server)
    assert {:error, _} = ask(server, context)
    assert_domain_unchanged(server, before)
    assert_script_done(mock)
  end

  test "route defaults survive lowering and conflict with duplicate bindings" do
    profile = Map.delete(profile(), :routes)

    route =
      Jido.Agent.Authoring.route("ai.ask", Authoring.ai(:assistant), defaults: %{query: "Default"})
      |> elem(1)

    agent = %{name: "default_route", schema: base().schema, routes: [route]}
    # AI source attributes lower references before core executable validation.
    assert {:ok, lowered} = Authoring.lower(agent, [profile])

    assert %{target: {Jido.AI.Orchestration.Start, %{query: "Default", profile_id: :assistant}}} =
             Enum.find(lowered.routes, &(&1.path == "ai.ask"))

    assert Enum.any?(lowered.routes, &(&1.path == Jido.AI.Orchestration.settle_type()))

    assert %{target: Jido.AI.Configuration.Apply} =
             Enum.find(lowered.routes, &(&1.path == "jido.ai.configure"))

    assert {:error, _} = Authoring.lower(agent, [Map.put(profile, :routes, ["ai.ask"])])
  end

  test "unknown and conflicting fields and duplicate catalogs fail before work" do
    {mock, _} = mock([])
    profile = profile()

    for bad <- [
          Map.put(profile, :surprise, true),
          Map.put(profile, "id", :assistant),
          %{profile | tools: profile.tools ++ profile.tools},
          put_in(profile, [:result, :into], :missing)
        ] do
      assert {:error, error} = Authoring.lower(base(), [bad])
      assert is_exception(error)
    end

    assert {:error, _} = Authoring.lower(base(), [profile, profile])
    assert {:error, _} = Profile.new(%{id: :assistant, models: %{}})
    assert MockLLM.report(mock).requests == []
  end

  test "output error previews accept provider structs and redact sensitive fields" do
    response = %ReqLLM.Response{
      id: "test",
      model: "test",
      context: ReqLLM.Context.new(),
      provider_meta: %{api_key: "secret"}
    }

    preview = Jido.AI.Output.raw_preview(response)
    refute preview =~ "secret"
    assert is_binary(preview)
  end

  defp drain_checks(acc) do
    receive do
      {:control_checked, value} -> drain_checks([value | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp source_registry(profile) do
    atoms = [
      :id,
      :instructions,
      :result,
      :routes,
      :reasoning,
      :models,
      :controls,
      :tools,
      :assistant,
      :answer,
      :model,
      :generation,
      :method,
      :react,
      :tool_concurrency,
      :requests,
      :mode,
      :turn,
      :on_busy,
      :reject,
      :max_retained_requests,
      :streaming,
      :steering,
      :memory,
      :observability,
      :effect_policy,
      :history,
      :input,
      :operation,
      :output,
      :max_model_calls,
      :max_iterations,
      :max_tool_calls,
      :timeout,
      :into,
      :reply,
      :schema,
      :max_repairs,
      :name,
      :target,
      :description,
      :forward_context,
      :observer,
      :temperature,
      JidoAI.Examples.Support.Multiply,
      JidoAI.Examples.Authoring.Support.Quote,
      AIRuntime.Record
    ]

    entries =
      atoms
      |> Kernel.++(profile_atoms(profile))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})

    entries =
      Map.merge(entries, %{
        "schemas/reply-v1" => {:value, profile.result.schema},
        "models/answer-v1" => {:value, profile.models.answer.model}
      })

    Jido.Codec.Registry.new!(entries)
  end
end
