defmodule JidoAI.Examples.ReasoningCapabilitiesTest do
  use JidoAI.Examples.Case
  alias JidoAI.Examples.{Adaptive, ReasoningCapabilities}
  alias Jido.AI.Plugins.Reasoning

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      reasoning: MockLLM.model(),
      fast: MockLLM.model()
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
      config = [into: :result, timeout: 5_000, options: unquote(Macro.escape(options))]
      assert {:ok, definition} = ReasoningCapabilities.definition([{plugin, config}])
      server = start_agent(jido, definition)
      assert {:ok, original} = Server.plugin_state(server, plugin)
      assert original.strategy == strategy and original.default_model == :reasoning

      signal =
        Jido.Signal.new!(
          "reasoning.#{strategy}.run",
          %{prompt: "Explain this answer", strategy: :forged},
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
    test "capability defaults and route bindings are stable with reverse order #{reverse}", %{
      jido: jido
    } do
      {mock, context} = mock(Adaptive.script(:cot))

      plugins = [
        {Reasoning.ChainOfThought, [timeout: 900, options: %{system_prompt: "Use declared facts"}]},
        {Reasoning.ChainOfDraft, [into: :review, timeout: 500]}
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

      params = %{prompt: "Question", strategy: :cod, into: :review}

      assert {:ok, agent} =
               Server.call(server, signal("reasoning.cot.run", params), context: forged)

      assert agent.state.result.strategy == :cot and agent.state.review == nil
      assert agent.state.result.diagnostics.timeout == 900
      [request] = MockLLM.report(mock).requests
      assert hd(request.body["messages"])["content"] == "Use declared facts"
      assert_script_done(mock)
    end
  end

  test "explicit model timeout and method parameters override capability defaults", %{jido: jido} do
    {mock, context} = mock(Adaptive.script(:cot) ++ Adaptive.script(:cot))

    config = [
      default_model: MockLLM.model("gpt-4o-mini"),
      timeout: 800,
      options: %{system_prompt: "Use declared facts", llm_timeout_ms: 600}
    ]

    assert {:ok, definition} =
             ReasoningCapabilities.definition([{Reasoning.ChainOfThought, config}])

    server = start_agent(jido, definition)
    assert {:ok, first} = Server.call(server, signal("reasoning.cot.run"), context: context)
    assert first.state.result.diagnostics.timeout == 800

    params = %{
      prompt: "Question",
      model: MockLLM.model("gpt-4o"),
      timeout: 900,
      system_prompt: "Use explicit facts",
      options: %{system_prompt: "Use option facts"}
    }

    assert {:ok, second} =
             Server.call(server, signal("reasoning.cot.run", params), context: context)

    assert second.state.result.diagnostics.timeout == 900
    [first_request, second_request] = MockLLM.report(mock).requests
    assert first_request.body["model"] == "gpt-4o-mini"
    assert second_request.body["model"] == "gpt-4o"
    assert hd(second_request.body["messages"])["content"] == "Use explicit facts"
    assert second.state.result.diagnostics.options.llm_timeout_ms == 600
    assert_script_done(mock)
  end

  test "capability options and restored state defaults use the same schema" do
    plugin = Reasoning.ChainOfThought
    config = [default_model: :fast, timeout: 800, options: %{system_prompt: "Restored"}]
    {:reasoning_cot, schema} = Module.concat(plugin, Agent).state_spec(config)
    assert {:ok, state} = Zoi.parse(schema, %{})
    assert state.strategy == :cot and state.default_model == :fast
    assert state.timeout == 800 and state.options.system_prompt == "Restored"
    assert {:error, _} = Zoi.parse(schema, %{state | strategy: :cod})
    assert {:error, _} = Zoi.parse(schema, %{state | timeout: 0})
    assert plugin.actions() == [Jido.AI.Actions.Reasoning.RunStrategy]
    assert plugin.category() == "ai" and plugin.vsn() == "2.0.0"

    for config <- [
          [timeout: 0],
          [options: :invalid],
          [into: nil],
          [typo: 1],
          [timeout: 1, timeout: 2]
        ] do
      assert {:error, _} = ReasoningCapabilities.definition([{plugin, config}])
    end
  end

  test "Plugins require explicit routes and cannot bind an unrelated Signal", %{jido: jido} do
    {mock, context} = mock([])
    plugins = [{Reasoning.ChainOfThought, []}]
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
      plugins = [{Reasoning.ChainOfThought, [into: into]}]
      assert {:ok, definition} = ReasoningCapabilities.definition(plugins)
      server = start_agent(jido, definition)
      assert {:error, error} = Server.call(server, signal("reasoning.cot.run"), context: context)
      assert inspect(error) =~ "Agent Plugin observes unknown Agent fields"
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
    config = [timeout: 100]

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
             Server.call(server, signal("reasoning.cot.run", %{prompt: "Next", timeout: 5_000}), context: context)

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

  defp answer(:aot, result), do: result.answer
  defp answer(:tot, result), do: Jido.AI.Reasoning.TreeOfThoughts.Result.best_answer(result)
  defp answer(_, result), do: result

  defp signal(type, data \\ %{prompt: "Explain this answer"}),
    do: Jido.Signal.new!(type, data, source: "/examples/capabilities")
end
