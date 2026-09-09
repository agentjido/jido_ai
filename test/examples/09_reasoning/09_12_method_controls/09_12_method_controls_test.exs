defmodule JidoAI.Examples.MethodControlsTest do
  use JidoAI.Examples.Case
  alias Jido.AI.{Authoring, Profile, Request}
  alias JidoAI.Examples.{AdaptiveAPI, MethodControls, TRM}

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      example: MockLLM.model(),
      fast: MockLLM.model()
    })

    on_exit(fn ->
      case saved do
        {:ok, value} -> Application.put_env(:jido_ai, :model_aliases, value)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  defp profile(module) do
    {_, config} = Enum.find(module.definition().plugins, &(elem(&1, 0) == Jido.AI.Runtime.Plugin))
    config[:profiles].assistant
  end

  defp rounds(n) do
    for i <- 1..n,
        do: %{reply: {:tools, [%{id: "round_#{i}", name: "tree_work", arguments: %{n: i}}]}}
  end

  test "public Adaptive keeps ten ReAct calls while a later TRM request can use fifteen", %{
    jido: jido
  } do
    recursive =
      Enum.flat_map(Enum.with_index([0.1, 0.3, 0.5, 0.7, 0.8], 1), fn {score, n} ->
        TRM.cycle("Analysis #{n}", score, "Improvement #{n}")
      end)

    {mock, context} = mock(rounds(10) ++ recursive)
    server = start_agent(jido, AdaptiveAPI.Public.new!())
    assert {:ok, first} = AdaptiveAPI.Public.ask(server, "Use a tool", context: context)

    assert {:ok, "Maximum iterations reached without a final answer."} =
             AdaptiveAPI.Public.await(first)

    assert Server.agent(server).state.requests[first.id].meta.model_calls == 10
    assert_receive {:tree_work_finished, 10}
    refute_receive {:tree_work_finished, 11}
    assert {:ok, next} = AdaptiveAPI.Public.ask(server, "Improve this answer", context: context)
    assert {:ok, "Improvement 5"} = AdaptiveAPI.Public.await(next)
    assert Server.agent(server).state.requests[next.id].meta.model_calls == 15
    assert_script_done(mock)
  end

  for {name, limit} <- [cod: 1, cot: 1, react: 10, aot: 1, tot: 802, got: 40, trm: 15] do
    test "selected #{name} resolves the declared default count limits" do
      source = Map.from_struct(profile(AdaptiveAPI.Public))

      options = %{
        source.reasoning.options
        | available_strategies: [unquote(name)],
          strategy_override: nil
      }

      assert {:ok, base} =
               Profile.new(%{source | reasoning: %{source.reasoning | options: options}})

      assert base.controls.max_iterations == :method_default
      assert {:ok, selected, _} = Jido.AI.Reasoning.select(base, "Task")
      assert selected.controls.max_iterations == unquote(limit)
      assert selected.controls.max_model_calls == unquote(limit)
      assert selected.controls.max_tool_calls == unquote(if(name == :tot, do: 10_000, else: 16))
      assert selected.controls.timeout == 60_000
      assert {:ok, ^base} = Profile.new(base)
      assert {:ok, ^selected} = Profile.new(selected)
    end
  end

  test "an explicit Agent limit permits a longer selected ReAct loop", %{jido: jido} do
    {mock, context} = mock(rounds(11) ++ [%{reply: {:text, "Finished within twelve calls"}}])
    server = start_agent(jido, MethodControls.Explicit.new!())
    assert {:ok, handle} = MethodControls.Explicit.ask(server, "Use a tool", context: context)
    assert {:ok, "Finished within twelve calls"} = MethodControls.Explicit.await(handle)
    assert_receive {:tree_work_finished, 11}
    assert Server.agent(server).state.requests[handle.id].meta.model_calls == 12
    assert_script_done(mock)
  end

  test "a per-request limit can replace the selected public default", %{jido: jido} do
    {mock, context} = mock(rounds(11) ++ [%{reply: {:text, "Request override applied"}}])
    server = start_agent(jido, AdaptiveAPI.Public.new!())

    assert {:ok, handle} =
             AdaptiveAPI.Public.ask(server, "Use a tool", context: context, max_iterations: 12)

    assert {:ok, "Request override applied"} = AdaptiveAPI.Public.await(handle)
    assert Server.agent(server).state.requests[handle.id].meta.model_calls == 12
    assert_script_done(mock)
  end

  test "a selected public tool-count default stops an oversized batch before execution", %{
    jido: jido
  } do
    calls = for n <- 1..17, do: %{id: "tool_#{n}", name: "tree_work", arguments: %{n: n}}
    {mock, context} = mock([%{reply: {:tools, calls}}])
    server = start_agent(jido, AdaptiveAPI.Public.new!())
    assert {:ok, handle} = AdaptiveAPI.Public.ask(server, "Use a tool", context: context)
    assert {:error, {:failed, cause, details}} = AdaptiveAPI.Public.await(handle)
    assert inspect(cause) =~ "limit"
    assert details.adaptive.strategy == :react
    refute_receive {:tree_work_finished, _}
    assert length(MockLLM.report(mock).requests) == 1
    assert Server.agent(server).state.requests[handle.id].meta.usage.total_tokens == 15
    assert_script_done(mock)
  end

  test "explicit tool-count policy permits the same batch", %{jido: jido} do
    calls = for n <- 1..17, do: %{id: "tool_#{n}", name: "tree_work", arguments: %{n: n}}
    {mock, context} = mock([%{reply: {:tools, calls}}, %{reply: {:text, "Batch complete"}}])
    server = start_agent(jido, MethodControls.Explicit.new!())

    assert {:ok, "Batch complete"} =
             MethodControls.Explicit.ask_sync(server, "Use tools", context: context)

    for n <- 1..17, do: assert_receive({:tree_work_finished, ^n})
    assert_script_done(mock)
  end

  test "typed repair gets its own call allowance after the selected default is resolved", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:object, %{value: "bad"}}}, %{reply: {:object, %{value: 4}}}])

    server = start_agent(jido, AdaptiveAPI.Typed.new!())

    assert {:ok, selected, _} =
             Jido.AI.Reasoning.select(profile(AdaptiveAPI.Typed), "What is two plus two?")

    assert selected.controls.max_iterations == 1 and selected.controls.max_model_calls == 2

    assert {:ok, handle} =
             AdaptiveAPI.Typed.ask(server, "What is two plus two?", context: context)

    assert {:ok, %{value: 4}} = AdaptiveAPI.Typed.await(handle)
    record = Server.agent(server).state.requests[handle.id]
    assert record.meta.output.status == :repaired and record.meta.model_calls == 2
    assert record.meta.usage.total_tokens == 30
    assert_script_done(mock)
  end

  test "fixed native methods also resolve default controls without an Adaptive wrapper" do
    source = MethodControls.source()

    for {method, settings, expected} <- [
          {:react, %{}, 10},
          {:trm, %{max_supervision_steps: 3}, 9},
          {:tree_of_thoughts, %{max_nodes: 3}, 26},
          {:graph_of_thoughts, %{max_nodes: 4}, 8}
        ] do
      source = %{
        source
        | reasoning: %{source.reasoning | method: method, options: settings},
          tools: []
      }

      assert {:ok, p} = Profile.new(source)
      assert p.controls.max_iterations == :method_default
      assert {:ok, p, nil} = Jido.AI.Reasoning.select(p, "Task")
      assert p.controls.max_iterations == expected and p.controls.max_model_calls == expected
    end
  end

  test "default controls keep field validation and reject an automatic timeout" do
    source = MethodControls.source()

    for changes <- [
          %{timeout: :method_default},
          %{max_iterations: :unknown},
          %{max_iterations: 10_001},
          %{max_iterations: 0},
          %{max_model_calls: -1},
          %{max_tool_calls: 1.5},
          %{unrecognized: :method_default}
        ] do
      assert {:error, _} = Profile.new(%{source | controls: Map.merge(source.controls, changes)})
    end
  end

  test "explicit native counts remain exact through method selection" do
    source = MethodControls.source()
    controls = %{source.controls | max_iterations: 12, max_model_calls: 7, max_tool_calls: 9}
    assert {:ok, p} = Profile.new(%{source | controls: controls})
    assert {:ok, selected, _} = Jido.AI.Reasoning.select(p, "Use tools")
    assert selected.controls == controls
  end

  test "native ReAct uses the selected count limit without the public completion text", %{
    jido: jido
  } do
    {mock, context} = mock(rounds(10))
    server = start_agent(jido, MethodControls.Agent.new!())

    assert {:ok, handle} =
             Request.create_and_send(server, "Use a tool",
               signal_type: "work.query",
               source: "/examples/limits",
               context: context
             )

    assert {:error, {:failed, %{field: "controls"}, details}} = Request.await(handle)
    assert details.adaptive.strategy == :react
    assert Server.agent(server).state.reply == nil
    assert length(MockLLM.report(mock).requests) == 10
    assert Server.agent(server).state.requests[handle.id].meta.usage.total_tokens == 150
    assert_script_done(mock)
  end

  test "DSL data Builder source JSON direct Flow and ordinary turns resolve the same method defaults",
       %{jido: jido} do
    recursive =
      Enum.flat_map(Enum.with_index([0.1, 0.3, 0.5, 0.7, 0.8], 1), fn {score, n} ->
        TRM.cycle("Analysis #{n}", score, "Improvement #{n}")
      end)

    {mock, context} = mock(List.duplicate(recursive, 6) |> List.flatten())
    source = MethodControls.source()
    assert {:ok, definition} = Authoring.lower(MethodControls.base(), [source])
    assert definition == MethodControls.Agent.definition()
    attrs = definition |> Map.from_struct() |> Map.drop([:id, :state])
    assert {:ok, built} = attrs |> Jido.Agent.Builder.new() |> Jido.Agent.Builder.build()

    registry =
      source
      |> Map.put(:routes, [])
      |> atoms()
      |> Kernel.++(profile_atoms(source))
      |> Enum.uniq()
      |> Map.new(&{"atoms/#{&1}", {:atom, &1}})
      |> Map.put("models/answer", {:value, source.models.answer.model})

    assert {:ok, document} = Authoring.Codec.encode([source], registry)

    assert {:ok, decoded} =
             Authoring.Codec.decode(
               MethodControls.base(),
               Jason.decode!(Jason.encode!(document)),
               registry
             )

    assert decoded == built and built == definition

    for value <- [MethodControls.Agent.definition(), definition, built, decoded] do
      server = start_agent(jido, Jido.Agent.instantiate!(value))

      assert {:ok, handle} =
               Request.create_and_send(server, "Improve the answer",
                 signal_type: "work.query",
                 source: "/examples/limits",
                 context: context
               )

      assert {:ok, "Improvement 5"} = Request.await(handle)
      assert Server.agent(server).state.requests[handle.id].meta.model_calls == 15
    end

    assert {:ok, p} = Profile.new(source)
    assert {:ok, flow} = Authoring.reasoning_flow(p)
    ctx = Map.merge(context, %{agent_state: %{reply: nil}, jido_ai_profiles: %{assistant: p}})

    assert {:ok, %{result: "Improvement 5", meta: meta}} =
             Jido.Exec.run(flow, %{query: "Improve the answer"}, ctx)

    assert meta.model_calls == 15

    assert {:ok, turn} =
             Authoring.lower(MethodControls.base(), [%{source | requests: %{mode: :turn}}])

    server = start_agent(jido, Jido.Agent.instantiate!(turn))

    signal =
      Jido.Signal.new!("work.query", %{query: "Improve the answer"}, source: "/examples/limits")

    assert {:ok, agent} = Server.call(server, signal, context: context, timeout: 5_000)
    assert agent.state.reply == "Improvement 5"
    assert_script_done(mock)
  end

  test "a fixed native method resolves default calls after a per-request output contract", %{
    jido: jido
  } do
    {mock, context} =
      mock([%{reply: {:object, %{value: "bad"}}}, %{reply: {:object, %{value: 4}}}])

    source = MethodControls.source()

    source = %{
      source
      | reasoning: %{source.reasoning | method: :chain_of_thought, options: %{}},
        tools: []
    }

    assert {:ok, definition} = Authoring.lower(MethodControls.base(), [source])
    server = start_agent(jido, Jido.Agent.instantiate!(definition))

    output = [
      schema: Zoi.object(%{value: Zoi.integer()}),
      on_validation_error: :repair,
      retries: 1
    ]

    assert {:ok, handle} =
             Request.create_and_send(server, "What is two plus two?",
               signal_type: "work.query",
               source: "/examples/limits",
               context: context,
               output: output
             )

    assert {:ok, %{value: 4}} = Request.await(handle)
    assert Server.agent(server).state.reply == %{value: 4}
    assert Server.agent(server).state.requests[handle.id].meta.model_calls == 2
    assert_script_done(mock)
  end

  defp atoms(value) when is_atom(value), do: [value]
  defp atoms(value) when is_list(value), do: Enum.flat_map(value, &atoms/1)
  defp atoms(value) when is_tuple(value), do: value |> Tuple.to_list() |> atoms()
  defp atoms(%_{}), do: []

  defp atoms(value) when is_map(value),
    do: Enum.flat_map(value, fn {k, v} -> atoms(k) ++ atoms(v) end)

  defp atoms(_), do: []
end
