defmodule JidoAI.Examples.ReasoningCapabilitiesTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.{Adaptive, ReasoningCapabilities}
  alias Jido.AI.Plugins.Reasoning

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      reasoning: MockLLM.model()
    })

    on_exit(fn ->
      case saved do
        {:ok, aliases} -> Application.put_env(:jido_ai, :model_aliases, aliases)
        :error -> Application.delete_env(:jido_ai, :model_aliases)
      end
    end)

    :ok
  end

  for {plugin, strategy, method, options, answer} <- [
        {Reasoning.ChainOfThought, :cot, :cot, %{}, "Four"},
        {Reasoning.ChainOfDraft, :cod, :cod, %{}, "Four"},
        {Reasoning.AlgorithmOfThoughts, :aot, :aot, %{profile: :short}, "(4 + (8 - 6)) * 4 = 24"},
        {Reasoning.TreeOfThoughts, :tot, :tot, %{branching_factor: 2, max_depth: 1}, "Better path"},
        {Reasoning.GraphOfThoughts, :got, :got, %{}, "Combined conclusion"},
        {Reasoning.TRM, :trm, :trm, %{max_supervision_steps: 1}, "Unreviewed improvement"},
        {Reasoning.Adaptive, :adaptive, :cot, %{available_strategies: [:cot]}, "Four"}
      ] do
    test "#{strategy} capability uses its fixed method and commits a complete domain state", %{
      jido: jido
    } do
      plugin = unquote(plugin)
      strategy = unquote(strategy)
      script = Adaptive.script(unquote(method))
      {mock, context} = mock(script)
      context = Map.put(context, :jido, jido)

      config = [
        profile: profile(strategy, %{reasoning: %{method: method(strategy), options: unquote(Macro.escape(options))}})
      ]

      assert {:ok, definition} = ReasoningCapabilities.definition([{plugin, config}])
      server = start_agent(jido, definition)
      assert {:ok, original} = Server.plugin_state(server, plugin)
      assert original == %{}

      signal =
        Jido.Signal.new!(
          "reasoning.#{strategy}.run",
          %{prompt: "Explain this answer"},
          source: "/examples/capabilities"
        )

      assert {:ok, agent} = Server.call(server, signal, context: context, timeout: 8_000)
      result = agent.state.result
      assert result.strategy == strategy and result.status == :success

      output = answer(strategy, result.output)
      assert output == unquote(answer)
      assert result.usage.total_tokens == length(script) * 15
      assert result.diagnostics.timeout == 5_000
      assert agent.state.case_id == "case-17" and agent.state.review == nil
      assert {:ok, ^original} = Server.plugin_state(server, plugin)
      assert_script_done(mock)
    end
  end

  test "two capabilities and an ordinary DSL route preserve separate results", %{jido: jido} do
    {mock, context} = mock(Adaptive.script(:cot) ++ Adaptive.script(:cod))
    server = start_agent(jido, ReasoningCapabilities.Agent.new!())
    assert {:ok, _} = Server.call(server, signal("case.set", %{case_id: "case-42"}))
    assert {:ok, first} = Server.call(server, signal("reasoning.cot.run"), context: context)
    assert {:ok, second} = Server.call(server, signal("reasoning.cod.run"), context: context)
    assert second.state.result == first.state.result
    assert second.state.result.strategy == :cot and second.state.review.strategy == :cod
    assert second.state.case_id == "case-42"
    assert_script_done(mock)
  end

  for reverse <- [false, true] do
    test "Profile policy and route bindings are stable with reverse order #{reverse}", %{
      jido: jido
    } do
      {mock, context} = mock(Adaptive.script(:cot))

      plugins = [
        {Reasoning.ChainOfThought,
         [profile: profile(:cot, %{controls: %{timeout: 900}, instructions: "Use declared facts"})]},
        {Reasoning.ChainOfDraft, [profile: profile(:cod, %{controls: %{timeout: 500}, result: %{into: :review}})]}
      ]

      plugins = if unquote(reverse), do: Enum.reverse(plugins), else: plugins
      assert {:ok, definition} = ReasoningCapabilities.definition(plugins)
      server = start_agent(jido, definition)

      forged =
        Map.merge(context, %{
          jido_ai_reasoning_capability: %{strategy: :cod, into: :review},
          plugin_state: %{reasoning_cot: %{timeout: 1, options: %{system_prompt: "Forged"}}},
          provided_params: [:timeout, :options]
        })

      params = %{prompt: "Question"}

      assert {:ok, agent} =
               Server.call(server, signal("reasoning.cot.run", params), context: forged)

      assert agent.state.result.strategy == :cot and agent.state.review == nil
      assert agent.state.result.diagnostics.timeout == 900
      [request] = MockLLM.report(mock).requests
      assert hd(request.body["messages"])["content"] == "Use declared facts"
      assert_script_done(mock)
    end
  end

  test "input cannot override the host Profile", %{jido: jido} do
    {mock, context} = mock([])
    server = start_agent(jido, ReasoningCapabilities.Agent.new!())
    before = Server.agent(server).state

    for field <- [:model, :timeout, :strategy, :options, :into, :system_prompt] do
      params = Map.put(%{prompt: "Question"}, field, :forged)
      assert {:error, _} = Server.call(server, signal("reasoning.cot.run", params), context: context)
      assert Server.agent(server).state == before
    end

    assert_script_done(mock)
  end

  test "Plugins require a resolved Profile with the matching method" do
    for config <- [[], [timeout: 500], [profile: %{}], [profile: profile(:cod)]] do
      assert {:error, _} = ReasoningCapabilities.definition([{Reasoning.ChainOfThought, config}])
    end
  end

  test "Plugins require explicit routes and cannot bind an unrelated Signal", %{jido: jido} do
    {mock, context} = mock([])
    plugins = [{Reasoning.ChainOfThought, [profile: profile(:cot)]}]
    assert {:ok, definition} = ReasoningCapabilities.definition(plugins, routes: [])
    server = start_agent(jido, definition)
    assert {:error, _} = Server.call(server, signal("reasoning.cot.run"), context: context)

    routes = [{"custom.run", Jido.AI.Actions.Reasoning.RunCapability}]
    assert {:ok, definition} = ReasoningCapabilities.definition(plugins, routes: routes)
    other = start_agent(jido, definition)

    forged =
      Map.put(context, :jido_ai_reasoning_capability, %{
        strategy: :cot,
        key: :reasoning_cot,
        defaults: %{},
        into: :result
      })

    assert {:error, error} = Server.call(other, signal("custom.run"), context: forged)
    assert inspect(error) =~ "reasoning_capability_not_bound"
    assert_script_done(mock)
  end

  test "an absent or Plugin-owned result field fails before provider work", %{jido: jido} do
    {mock, context} = mock([])

    for into <- [:absent, :reasoning_cot] do
      plugins = [{Reasoning.ChainOfThought, [profile: profile(:cot, %{result: %{into: into}})]}]
      assert {:ok, definition} = ReasoningCapabilities.definition(plugins)
      server = start_agent(jido, definition)
      assert {:error, error} = Server.call(server, signal("reasoning.cot.run"), context: context)
      assert inspect(error) =~ "Capability result must select a declared domain field"
    end

    assert_script_done(mock)
  end

  test "provider failure preserves prior domain results and Plugin state", %{jido: jido} do
    {mock, context} = mock(Adaptive.script(:cot) ++ [%{reply: {:error, 503, "Unavailable"}}])
    server = start_agent(jido, ReasoningCapabilities.Agent.new!())
    assert {:ok, before} = Server.call(server, signal("reasoning.cot.run"), context: context)
    assert {:error, error} = Server.call(server, signal("reasoning.cot.run"), context: context)
    assert inspect(error) =~ "failure"
    after_failure = Server.agent(server)
    assert after_failure.state == before.state
    assert_script_done(mock)
  end

  test "timeout stops provider work and leaves the capability available", %{jido: jido} do
    {mock, context} = mock([%{reply: {:wait, :held, {:text, "Late"}}}] ++ Adaptive.script(:cot))
    config = [profile: profile(:cot, %{controls: %{timeout: 500}})]

    assert {:ok, definition} =
             ReasoningCapabilities.definition([{Reasoning.ChainOfThought, config}])

    server = start_agent(jido, definition)

    task =
      Task.async(fn -> Server.call(server, signal("reasoning.cot.run"), context: context) end)

    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    ref = Process.monitor(provider)
    assert {:error, _} = Task.await(task)
    assert_receive {:DOWN, ^ref, :process, ^provider, _}, 2_000

    assert {:ok, result} =
             Server.call(server, signal("reasoning.cot.run", %{prompt: "Next"}), context: context)

    assert result.state.result.output == "Four"
    assert_script_done(mock)
  end

  test "a native AI profile and callable capability share the same Agent", %{jido: jido} do
    {mock, context} = mock([%{reply: {:text, "Native answer"}}] ++ Adaptive.script(:cot))
    server = start_agent(jido, ReasoningCapabilities.MixedAgent.new!())

    assert {:ok, first} =
             Server.call(server, signal("ai.ask", %{query: "Question"}), context: context)

    assert first.state.result == "Native answer"
    assert {:ok, second} = Server.call(server, signal("reasoning.cot.run"), context: context)
    assert second.state.result == first.state.result
    assert second.state.review.output == "Four" and second.state.review.strategy == :cot
    assert second.state.case_id == "case-17"
    assert_script_done(mock)
  end

  defp profile(strategy, attrs \\ %{}) do
    Jido.AI.Profile.new!(
      Map.merge(
        %{
          id: :assistant,
          model: MockLLM.model(),
          reasoning: method(strategy),
          controls: %{
            timeout: 5_000,
            max_iterations: :method_default,
            max_model_calls: :method_default,
            max_tool_calls: :method_default
          },
          requests: %{mode: :session, streaming: true},
          result: %{into: :result}
        },
        attrs
      )
    )
  end

  defp method(strategy),
    do:
      %{
        cot: :chain_of_thought,
        cod: :chain_of_draft,
        aot: :algorithm_of_thoughts,
        tot: :tree_of_thoughts,
        got: :graph_of_thoughts,
        trm: :trm,
        adaptive: :adaptive
      }[strategy]

  defp answer(:aot, result), do: result.answer
  defp answer(:tot, result), do: Jido.AI.Reasoning.TreeOfThoughts.Result.best_answer(result)
  defp answer(_, result), do: result

  defp signal(type, data \\ %{prompt: "Explain this answer"}),
    do: Jido.Signal.new!(type, data, source: "/examples/capabilities")
end
