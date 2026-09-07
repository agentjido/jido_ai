defmodule JidoAI.Examples.CallableReasoningTest do
  use JidoAI.Examples.Case
  alias Jido.AI.Actions.Reasoning.RunStrategy
  alias JidoAI.Examples.{Adaptive, CallableReasoning}

  setup do
    saved = Application.fetch_env(:jido_ai, :model_aliases)

    Application.put_env(:jido_ai, :model_aliases, %{
      fast: MockLLM.model(),
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

  for {strategy, method, options, answer} <- [
        {:cot, :cot, %{}, "Four"},
        {:cod, :cod, %{}, "Four"},
        {:aot, :aot, %{profile: :short}, "(4 + (8 - 6)) * 4 = 24"},
        {:tot, :tot, %{branching_factor: 2, max_depth: 1}, "Better path"},
        {:got, :got, %{}, "Combined conclusion"},
        {:trm, :trm, %{max_supervision_steps: 1}, "First answer"},
        {:adaptive, :cot, %{available_strategies: [:cot]}, "Four"}
      ] do
    test "callable #{strategy} uses the same reasoning from direct Exec and an Agent", %{
      jido: jido
    } do
      strategy = unquote(strategy)
      script = Adaptive.script(unquote(method))
      {mock, context} = mock_on(jido, script ++ script)

      params = %{
        strategy: strategy,
        prompt: "Explain this answer",
        timeout: 5_000,
        options: unquote(Macro.escape(options))
      }

      assert {:ok, payload} = Jido.Exec.run(RunStrategy, params, context, timeout: 8_000)
      assert payload.strategy == strategy and payload.status == :success
      assert answer(strategy, payload.output) == unquote(answer)
      assert payload.usage.total_tokens == length(script) * 15
      assert payload.diagnostics.snapshot_done == true
      assert payload.diagnostics.snapshot_status == :success
      refute Map.has_key?(payload.diagnostics, :recovered_error)

      server = start_agent(jido, CallableReasoning.Agent.new!())
      signal = Jido.Signal.new!("reasoning.run", params, source: "/examples/reasoning")
      assert {:ok, agent} = Server.call(server, signal, context: context, timeout: 8_000)
      assert answer(strategy, agent.state.result.output) == unquote(answer)
      assert_result_shape(strategy, payload.output)
      assert_result_shape(strategy, agent.state.result.output)
      assert agent.state.result.usage == payload.usage
      assert agent.state.calls == 1 and agent.state.case_id == "case-17"
      assert_script_done(mock)
    end
  end

  test "callable defaults and explicit parameters reach the actual model request", %{jido: jido} do
    {mock, context} = mock_on(jido, Adaptive.script(:cot) ++ Adaptive.script(:cot))

    defaults = %{
      default_model: :fast,
      timeout: 800,
      options: %{system_prompt: "Use plugin facts", llm_timeout_ms: 600}
    }

    context =
      Map.merge(context, %{
        provided_params: [:strategy, :prompt],
        plugin_state: %{reasoning_cot: defaults}
      })

    assert {:ok, first} = RunStrategy.run(%{strategy: :cot, prompt: "Question"}, context)
    assert first.diagnostics.timeout == 800
    assert first.diagnostics.options.system_prompt == "Use plugin facts"

    params = %{
      strategy: :cot,
      prompt: "Question",
      timeout: 900,
      system_prompt: "Use explicit facts",
      options: %{system_prompt: "Use option facts"}
    }

    explicit = Map.put(context, :provided_params, Map.keys(params))
    assert {:ok, second} = RunStrategy.run(params, explicit)
    assert second.diagnostics.timeout == 900
    [first, second] = MockLLM.report(mock).requests
    assert hd(first.body["messages"])["content"] == "Use plugin facts"
    assert hd(second.body["messages"])["content"] == "Use explicit facts"
    assert_script_done(mock)
  end

  test "a selected graph limit changes the actual call count", %{jido: jido} do
    {mock, context} = mock_on(jido, [%{reply: {:text, "Only root analysis"}}])
    params = %{strategy: :got, prompt: "Task", options: %{"max_nodes" => 2, "max_depth" => 1}}
    assert {:ok, result} = RunStrategy.run(params, context)
    assert result.output == "Only root analysis"
    assert result.usage.total_tokens == 15
    assert result.diagnostics.snapshot_details.graph.max_depth == 1
    assert_script_done(mock)
  end

  test "invalid requests fail before model work and catalog accessors remain available", %{
    jido: jido
  } do
    {mock, context} = mock_on(jido, [])

    for params <- [
          %{},
          %{strategy: :cot},
          %{prompt: "Missing method"},
          %{strategy: :unknown, prompt: "Task"},
          %{strategy: :cot, prompt: ""}
        ] do
      assert {:error, :invalid_strategy_request} = RunStrategy.run(params, context)
    end

    for params <- [
          %{strategy: :cot, prompt: "Task", timeout: 0},
          %{strategy: :tot, prompt: "Task", max_depth: 0}
        ] do
      assert {:error, _} = RunStrategy.run(params, context)
    end

    assert RunStrategy.name() == "reasoning_run_strategy"
    assert RunStrategy.category() == "ai" and RunStrategy.vsn() == "1.0.0"
    assert "reasoning" in RunStrategy.tags()
    assert {:ok, _} = Zoi.parse(RunStrategy.schema(), %{strategy: :cot, prompt: "Task"})
    assert_script_done(mock)
  end

  test "parent AI bindings cannot replace the isolated runner's request or profile", %{jido: jido} do
    {mock, context} = mock_on(jido, Adaptive.script(:cot))

    context =
      Map.merge(context, %{
        agent_state: %{case_id: "parent"},
        agent_id: "parent",
        jido_ai_events: {self(), "parent", "parent-run"},
        jido_ai_profiles: %{assistant: :forged},
        jido_ai_progress: :forged
      })

    assert {:ok, result} = RunStrategy.run(%{strategy: :cot, prompt: "Task"}, context)
    assert result.output == "Four"
    refute_receive {:"$gen_call", _, {:event, "parent", _, _, _}}
    assert_script_done(mock)
  end

  test "provider failure retains the failure envelope and stops the private Agent", %{jido: jido} do
    {mock, context} = mock_on(jido, [%{reply: {:error, 503, "Private provider detail"}}])
    assert {:error, result} = RunStrategy.run(%{strategy: :cot, prompt: "Task"}, context)
    assert result.strategy == :cot and result.status == :failure
    assert result.output == nil and result.usage == %{}
    assert result.diagnostics.snapshot_done == true
    assert is_binary(result.diagnostics.error)
    refute result.diagnostics.error =~ "Private provider detail"
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  test "a failed later phase retains completed usage and method diagnostics", %{jido: jido} do
    {mock, context} =
      mock_on(jido, [
        %{reply: {:text, "First analysis"}},
        %{reply: {:error, 503, "Review unavailable"}}
      ])

    params = %{strategy: :trm, prompt: "Improve", max_supervision_steps: 1}
    assert {:error, result} = RunStrategy.run(params, context)
    assert result.status == :failure
    assert result.usage.total_tokens == 15
    assert result.diagnostics.snapshot_details.trm != nil
    assert result.diagnostics.snapshot_details.diagnostics.phase == :supervision
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  test "Exec cancellation stops the runner Session and active provider work", %{jido: jido} do
    {mock, context} = mock_on(jido, [%{reply: {:wait, :held, {:text, "Late answer"}}}])

    execution =
      Jido.Exec.run_async(
        RunStrategy,
        %{strategy: :cot, prompt: "Task", timeout: 5_000},
        context,
        timeout: 8_000
      )

    assert_receive {:mock_llm_waiting, ^mock, :held, provider}, 2_000
    [server] = runner_pids(jido)
    session = Server.children(server)[{:plugin, Jido.AI.Session.Plugin}].pid
    refs = for pid <- [server, session, provider], do: {Process.monitor(pid), pid}
    assert :ok = Jido.Exec.cancel(execution)
    for {ref, pid} <- refs, do: assert_receive({:DOWN, ^ref, :process, ^pid, _}, 2_000)
    assert runner_pids(jido) == []
  end

  test "a timed out call closes its provider and permits a later call", %{jido: jido} do
    {mock, context} =
      mock_on(
        jido,
        [%{reply: {:wait, :timeout, {:text, "Late answer"}}}] ++ Adaptive.script(:cot)
      )

    call =
      Task.async(fn ->
        RunStrategy.run(%{strategy: :cot, prompt: "Task", timeout: 100}, context)
      end)

    assert_receive {:mock_llm_waiting, ^mock, :timeout, provider}, 2_000
    ref = Process.monitor(provider)
    assert {:error, result} = Task.await(call, 2_000)
    assert result.strategy == :cot and result.status in [:failure, :running]
    assert is_binary(result.diagnostics.error)
    assert_receive {:DOWN, ^ref, :process, ^provider, _}, 2_000
    assert runner_pids(jido) == []
    assert {:ok, next} = RunStrategy.run(%{strategy: :cot, prompt: "Task"}, context)
    assert next.output == "Four" and next.usage.total_tokens == 15
    assert_script_done(mock)
  end

  test "standalone calls need no implicit global Jido instance" do
    {mock, context} = mock(Adaptive.script(:cot) ++ Adaptive.script(:cot))
    before = Process.whereis(Jido.AI.InternalReasoningRunner)

    for _ <- 1..2 do
      assert {:ok, result} = RunStrategy.run(%{strategy: :cot, prompt: "Task"}, context)
      assert result.output == "Four" and result.usage.total_tokens == 15
    end

    assert Process.whereis(Jido.AI.InternalReasoningRunner) == before
    assert_script_done(mock)
  end

  test "two calls share a host runtime and retain separate requests and cleanup", %{jido: jido} do
    {mock, context} =
      mock_on(jido, [
        %{reply: {:wait, :one, {:text, "Conclusion: One"}}},
        %{reply: {:wait, :two, {:text, "Conclusion: Two"}}}
      ])

    runtime = Process.whereis(jido)
    params = %{strategy: :cot, prompt: "Same input"}
    first = Task.async(fn -> RunStrategy.run(params, context) end)
    assert_receive {:mock_llm_waiting, ^mock, :one, _}, 2_000
    second = Task.async(fn -> RunStrategy.run(params, context) end)
    assert_receive {:mock_llm_waiting, ^mock, :two, _}, 2_000
    servers = runner_pids(jido)
    assert length(servers) == 2

    ids =
      for server <- servers do
        {:ok, records} = Server.plugin_state(server, Jido.AI.Session.Plugin)
        [record] = Map.values(records)
        assert record.status == :pending
        {record.id, record.run_id}
      end

    assert length(Enum.uniq(ids)) == 2
    MockLLM.release(mock, :one)
    assert {:ok, %{output: "One"}} = Task.await(first, 2_000)
    assert length(runner_pids(jido)) == 1
    assert Task.yield(second, 20) == nil
    MockLLM.release(mock, :two)
    assert {:ok, %{output: "Two"}} = Task.await(second, 2_000)
    assert runner_pids(jido) == [] and Process.whereis(jido) == runtime
    assert_script_done(mock)
  end

  test "the callable default TRM policy completes all five supervision cycles", %{jido: jido} do
    script =
      Enum.flat_map(Enum.with_index([0.1, 0.3, 0.5, 0.7, 0.8], 1), fn {score, n} ->
        JidoAI.Examples.TRM.cycle("Analysis #{n}", score, "Improvement #{n}")
      end)

    {mock, context} = mock_on(jido, script)
    assert {:ok, result} = RunStrategy.run(%{strategy: :trm, prompt: "Improve"}, context)
    assert result.output == "Improvement 4"
    assert result.usage.total_tokens == 225
    assert result.diagnostics.snapshot_details.model_calls == 15
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  test "AoT failure retains its structured result and cannot become a recovered success", %{
    jido: jido
  } do
    {mock, context} = mock_on(jido, [%{reply: {:text, "No explicit answer is available."}}])
    assert {:error, result} = RunStrategy.run(%{strategy: :aot, prompt: "Task"}, context)
    assert result.status == :failure
    assert result.output.found_solution? == false
    assert result.output.raw_response == "No explicit answer is available."
    assert result.output.usage.total_tokens == 15
    refute Map.has_key?(result.diagnostics, :recovered_error)
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  test "ToT evaluation failure retains the method result and completed usage", %{jido: jido} do
    first = hd(Adaptive.script(:tot))
    {mock, context} = mock_on(jido, [first, %{reply: {:error, 503, "Score unavailable"}}])
    params = %{strategy: :tot, prompt: "Task", branching_factor: 2, max_depth: 1}
    assert {:error, result} = RunStrategy.run(params, context)
    assert result.status == :failure
    assert result.output.termination.status == "error"
    assert map_size(result.output.diagnostics.nodes) == 1
    assert hd(Map.values(result.output.diagnostics.nodes)).content == "Task"
    assert result.output.tree.max_depth == 1
    assert result.output.usage.total_tokens == 15 and result.usage.total_tokens == 15
    refute Map.has_key?(result.diagnostics, :recovered_error)
    assert runner_pids(jido) == []
    assert_script_done(mock)
  end

  defp mock_on(jido, script) do
    {server, context} = mock(script)
    {server, Map.put(context, :jido, jido)}
  end

  defp runner_pids(jido) do
    for {_id, pid} <- Jido.list_agents(jido), do: pid
  end

  test "callable reasoning reads configured defaults from a current Agent struct", %{jido: jido} do
    {mock, context} = mock_on(jido, Adaptive.script(:cot))
    config = [timeout: 800, options: %{system_prompt: "Use the host defaults"}]

    assert {:ok, definition} =
             JidoAI.Examples.ReasoningCapabilities.definition([
               {Jido.AI.Plugins.Reasoning.ChainOfThought, config}
             ])

    caller = Jido.Agent.instantiate!(definition)

    assert {:ok, result} =
             RunStrategy.run(
               %{strategy: :cot, prompt: "Question"},
               Map.put(context, :agent, caller)
             )

    assert result.diagnostics.timeout == 800
    [request] = MockLLM.report(mock).requests
    assert hd(request.body["messages"])["content"] == "Use the host defaults"
    assert_script_done(mock)
  end

  defp answer(:aot, output), do: output.answer
  defp answer(:tot, output), do: Jido.AI.Reasoning.TreeOfThoughts.Result.best_answer(output)
  defp answer(_, output), do: output

  defp assert_result_shape(:aot, output) do
    assert output.found_solution? and output.backtracking_steps == 3
    assert output.diagnostics.explicit_answer_found
    assert output.termination.reason == :success
    assert is_binary(output.raw_response)
  end

  defp assert_result_shape(:tot, output) do
    assert Enum.map(output.candidates, &{&1.content, &1.score}) ==
             [{"Better path", 0.8}, {"First path", 0.4}]

    assert output.best.node_id == hd(output.candidates).node_id
    assert output.tree.max_depth == 1 and output.termination.node_count == 3
  end

  defp assert_result_shape(_, output), do: assert(is_binary(output))
end
