defmodule JidoAI.Examples.AdaptiveAPITest do
  use JidoAI.Examples.Case
  alias Jido.AI.Reasoning.Adaptive, as: Method
  alias JidoAI.Examples.{Adaptive, AdaptiveAPI, TRM}

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

  defp record(server, handle), do: Server.agent(server).state.requests[handle.id]
  defp answer(:aot, result), do: result.answer
  defp answer(:tot, result), do: Jido.AI.Reasoning.TreeOfThoughts.Result.best_answer(result)
  defp answer(_, result), do: result

  defp assert_generation(method, body) do
    case method do
      :aot ->
        assert body["max_tokens"] == 2048 and body["temperature"] == 0.0

      :react ->
        assert body["max_tokens"] == 4096 and body["temperature"] == 0.2

      m when m in [:tot, :got, :trm] ->
        assert body["max_tokens"] == 1024 and body["temperature"] == 0.2

      _ ->
        :ok
    end
  end

  test "public defaults retain declared options and select a method through the common Agent", %{
    jido: jido
  } do
    assert AdaptiveAPI.Default.strategy_opts() == [
             model: :fast,
             default_strategy: :react,
             available_strategies: [:cod, :cot, :react, :tot, :got, :trm]
           ]

    assert AdaptiveAPI.Default.description() == "Adaptive agent default_adaptive"
    assert profile(AdaptiveAPI.Default).reasoning.method == :adaptive
    refute profile(AdaptiveAPI.Default).requests.steering
    assert profile(AdaptiveAPI.Default).memory.history == nil
    {mock, context} = mock(Adaptive.script(:cod))
    agent = AdaptiveAPI.Default.new!()
    assert agent.state.selected_strategy == nil and agent.state.last_result == ""
    assert Method.get_selected_strategy(agent) == nil
    assert Method.get_complexity_score(agent) == nil
    server = start_agent(jido, agent)

    assert {:ok, "Four"} =
             AdaptiveAPI.Default.ask_sync(server, "What is two plus two?", context: context)

    agent = Server.agent(server)
    assert agent.state.selected_strategy == :cod and agent.state.last_result == "Four"
    assert agent.state.completed and agent.state.last_prompt == "What is two plus two?"
    assert Method.method() == :adaptive
    assert Method.get_selected_strategy(agent) == :cod
    assert is_float(Method.get_complexity_score(agent))
    assert_script_done(mock)
  end

  for {method, module, prompt, expected} <- [
        {:cod, AdaptiveAPI.Public, "What is two plus two?", "Four"},
        {:cot, AdaptiveAPI.CoT, "What is two plus two?", "Four"},
        {:react, AdaptiveAPI.Public, "Search for the answer", "Four"},
        {:aot, AdaptiveAPI.AoT, "Explore the options", "(4 + (8 - 6)) * 4 = 24"},
        {:tot, AdaptiveAPI.Public, "Explore the options", "Better path"},
        {:got, AdaptiveAPI.Public, "Combine these perspectives", "Combined conclusion"},
        {:trm, AdaptiveAPI.Public, "Improve this answer", "Unreviewed improvement"}
      ] do
    test "public #{method} selection preserves its canonical result and printable convenience fields",
         %{jido: jido} do
      method = unquote(method)
      module = unquote(module)
      {mock, context} = mock(Adaptive.script(method))
      server = start_agent(jido, module.new!())
      assert {:ok, handle} = module.ask(server, unquote(prompt), context: context)
      assert {:ok, result} = module.await(handle)

      assert answer(method, result) == unquote(expected)
      agent = Server.agent(server)
      assert Method.get_selected_strategy(agent) == method
      assert agent.state.selected_strategy == method
      assert agent.state.last_result == if(is_binary(result), do: result, else: inspect(result))
      data = record(server, handle)
      assert data.result == result and data.method == :adaptive
      assert data.meta.adaptive.strategy == method
      assert data.meta.usage.total_tokens == length(Adaptive.script(method)) * 15

      for wire <- MockLLM.report(mock).requests do
        assert_generation(method, wire.body)

        if method not in [:react, :tot], do: refute(Map.has_key?(wire.body, "tools"))
      end

      assert_script_done(mock)
    end
  end

  test "a pending request publishes its selection while older completed selections remain available",
       %{jido: jido} do
    {mock, context} =
      mock(
        Adaptive.script(:cod) ++
          [%{reply: {:wait, :next_method, hd(TRM.script()).reply}}] ++ tl(TRM.script())
      )

    server = start_agent(jido, AdaptiveAPI.Public.new!())

    assert {:ok, first} =
             AdaptiveAPI.Public.ask(server, "What is two plus two?", context: context)

    assert {:ok, "Four"} = AdaptiveAPI.Public.await(first)
    old = record(server, first)
    assert {:ok, next} = AdaptiveAPI.Public.ask(server, "Improve the answer", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :next_method, _}, 2_000
    pending = Server.agent(server)
    assert pending.state.last_prompt == "Improve the answer" and pending.state.last_result == ""
    assert pending.state.selected_strategy == :trm
    refute pending.state.completed
    assert Method.get_selected_strategy(pending) == :trm
    assert is_float(Method.get_complexity_score(pending))
    assert Method.get_selected_strategy(pending, first.id) == :cod
    assert Method.get_complexity_score(pending, first.id) == old.meta.adaptive.complexity_score
    assert Method.get_selected_strategy(pending, "missing") == nil
    assert :ok = MockLLM.release(mock, :next_method)
    assert {:ok, "Unreviewed improvement"} = AdaptiveAPI.Public.await(next)
    assert Server.agent(server).state.selected_strategy == :trm
    assert record(server, first) == old
    assert_script_done(mock)
  end

  test "a failed public linear request keeps the raw cause separate from printable state and selects again",
       %{jido: jido} do
    {mock, context} = mock([%{reply: {:stream, [], "length"}}] ++ TRM.script())
    server = start_agent(jido, AdaptiveAPI.Public.new!())

    assert {:ok, handle} =
             AdaptiveAPI.Public.ask(server, "What is two plus two?", context: context)

    assert {:error, {:failed, {:incomplete_response, :length}, details} = error} =
             AdaptiveAPI.Public.await(handle)

    agent = Server.agent(server)
    assert details.diagnostics.cause == {:incomplete_response, :length}
    assert record(server, handle).error == error
    assert agent.state.last_result == inspect({:incomplete_response, :length})
    assert agent.state.completed and agent.state.selected_strategy == :cod
    assert Method.get_selected_strategy(agent) == :cod

    assert {:ok, "Unreviewed improvement"} =
             AdaptiveAPI.Public.ask_sync(server, "Improve the answer", context: context)

    assert Method.get_selected_strategy(Server.agent(server)) == :trm
    assert_script_done(mock)
  end

  test "a failed public recursive request retains method error text and actual phase data", %{
    jido: jido
  } do
    {mock, context} = mock(Enum.take(TRM.script(), 2) ++ [%{reply: {:stream, [], "length"}}])
    server = start_agent(jido, AdaptiveAPI.Public.new!())
    assert {:ok, handle} = AdaptiveAPI.Public.ask(server, "Improve the answer", context: context)

    assert {:error, {:failed, {:incomplete_response, :length}, details}} =
             AdaptiveAPI.Public.await(handle)

    agent = Server.agent(server)

    assert agent.state.last_result == details.result and
             String.starts_with?(details.result, "Error: ")

    assert details.trm.best_answer == "First answer"
    assert record(server, handle).meta.usage.total_tokens == 45
    assert Method.get_selected_strategy(agent) == :trm
    assert_script_done(mock)
  end

  test "custom settings preserve the unused default option and apply an explicit override to six actual calls",
       %{jido: jido} do
    opts = AdaptiveAPI.Custom.strategy_opts()
    assert opts[:default_strategy] == :tot
    assert opts[:available_strategies] == [:cot, :trm]
    assert opts[:strategy_override] == :trm
    assert opts[:complexity_thresholds] == %{simple: 0.1, complex: 0.9}
    assert profile(AdaptiveAPI.Custom).controls.max_model_calls == :method_default

    {:ok, selected, _} =
      Jido.AI.Reasoning.select(profile(AdaptiveAPI.Custom), "What is two plus two?")

    assert selected.controls.max_model_calls == 6
    assert AdaptiveAPI.Custom.description() == "Custom method selection"

    {mock, context} =
      mock(
        TRM.cycle("Initial", 0.3, "Reviewed improvement") ++
          TRM.cycle("Further analysis", 0.7, "Last improvement")
      )

    server = start_agent(jido, AdaptiveAPI.Custom.new!())

    assert {:ok, handle} =
             AdaptiveAPI.Custom.ask(server, "What is two plus two?", context: context)

    assert {:ok, "Last improvement"} = AdaptiveAPI.Custom.await(handle)
    agent = Server.agent(server)

    assert Method.get_selected_strategy(agent) == :trm and
             Method.get_complexity_score(agent) == 0.5

    assert record(server, handle).meta.adaptive.source == :override
    assert record(server, handle).meta.usage.total_tokens == 90

    for wire <- MockLLM.report(mock).requests do
      assert String.starts_with?(
               hd(wire.body["messages"])["content"],
               "Use the supplied facts\n\n"
             )

      assert wire.body["max_tokens"] == 90 and wire.body["temperature"] == 0.4
      refute wire.body["stream"]
    end

    assert_script_done(mock)
  end

  test "the public default call budget permits all fifteen recursive phases", %{jido: jido} do
    script =
      Enum.flat_map(Enum.with_index([0.1, 0.3, 0.5, 0.7, 0.8], 1), fn {score, step} ->
        TRM.cycle("Analysis #{step}", score, "Improvement #{step}")
      end)

    {mock, context} = mock(script)
    server = start_agent(jido, AdaptiveAPI.Default.new!())
    assert profile(AdaptiveAPI.Default).controls.max_model_calls == :method_default

    {:ok, selected, _} =
      Jido.AI.Reasoning.select(profile(AdaptiveAPI.Default), "Improve the answer")

    assert selected.controls.max_model_calls == 15
    assert {:ok, handle} = AdaptiveAPI.Default.ask(server, "Improve the answer", context: context)
    assert {:ok, "Improvement 5"} = AdaptiveAPI.Default.await(handle)
    assert record(server, handle).meta.model_calls == 15
    assert record(server, handle).meta.usage.total_tokens == 225
    assert record(server, handle).meta.reasoning.trm.termination_reason == :max_steps
    assert_script_done(mock)
  end

  test "an explicit public call limit stops the selected method before improvement", %{jido: jido} do
    {mock, context} = mock(Enum.take(TRM.script(), 2))
    server = start_agent(jido, AdaptiveAPI.Bounded.new!())
    assert {:ok, handle} = AdaptiveAPI.Bounded.ask(server, "Improve the answer", context: context)
    assert {:error, {:failed, %{field: "controls"}, details}} = AdaptiveAPI.Bounded.await(handle)
    assert details.trm.best_answer == "First answer" and details.adaptive.strategy == :trm
    assert record(server, handle).meta.usage.total_tokens == 30
    assert_script_done(mock)
  end

  test "public tool callbacks run for selected ReAct and ToT through the common Action path", %{
    jido: jido
  } do
    {mock, context} =
      mock(
        [
          %{reply: {:tools, [%{id: "react_callback", name: "tree_work", arguments: %{n: "4"}}]}},
          %{reply: {:text, "Tool complete"}},
          %{reply: {:tools, [%{id: "tot_callback", name: "tree_work", arguments: %{n: "8"}}]}}
        ] ++ Adaptive.script(:tot)
      )

    server = start_agent(jido, AdaptiveAPI.Hooks.new!())

    assert {:ok, "Tool complete"} =
             AdaptiveAPI.Hooks.ask_sync(server, "Use a tool", context: context)

    assert_receive {:tree_before, "react_callback"}
    assert_receive {:tree_work_finished, 4}
    assert_receive {:tree_after, "react_callback", 4}

    assert {:ok, result} =
             AdaptiveAPI.Hooks.ask_sync(server, "Explore alternatives", context: context)

    assert Jido.AI.Reasoning.TreeOfThoughts.Result.best_answer(result) == "Better path"
    assert_receive {:tree_before, "tot_callback"}
    assert_receive {:tree_work_finished, 8}
    assert_receive {:tree_after, "tot_callback", 8}
    requests = MockLLM.report(mock).requests

    for {index, expected} <- [{1, 104}, {3, 108}] do
      messages = Enum.at(requests, index).body["messages"]
      result = Enum.find(messages, &(&1["role"] == "tool"))
      assert Jason.decode!(result["content"]) == %{"ok" => true, "result" => %{"n" => expected}}
    end

    assert_script_done(mock)
  end

  test "public cancellation keeps selected metadata closes transport and allows a different next method",
       %{jido: jido} do
    {mock, context} =
      mock(
        Enum.take(TRM.script(), 2) ++
          [%{reply: {:stream, [{:wait, :cancel_adaptive}], "stop"}}] ++ Adaptive.script(:cod)
      )

    server = start_agent(jido, AdaptiveAPI.Public.new!())
    assert {:ok, handle} = AdaptiveAPI.Public.ask(server, "Improve the answer", context: context)
    assert_receive {:mock_llm_waiting, ^mock, :cancel_adaptive, provider}, 2_000
    monitor = Process.monitor(provider)
    assert {:error, :busy} = AdaptiveAPI.Public.ask(server, "Busy", context: context)
    assert :ok = AdaptiveAPI.Public.cancel(server, reason: :changed_task)
    assert {:error, {:cancelled, :changed_task}} = AdaptiveAPI.Public.await(handle)
    assert_receive {:DOWN, ^monitor, :process, ^provider, _}, 2_000
    assert record(server, handle).meta.usage.total_tokens == 30
    assert Method.get_selected_strategy(Server.agent(server)) == :trm
    assert Server.agent(server).state.selected_strategy == :trm

    assert {:ok, "Four"} =
             AdaptiveAPI.Public.ask_sync(server, "What is two plus two?", context: context)

    assert_script_done(mock)
  end

  test "public streaming retains outer identity selected phases and one terminal event", %{
    jido: jido
  } do
    {mock, context} = mock(TRM.script())
    server = start_agent(jido, AdaptiveAPI.Public.new!())

    assert {:ok, %{request: handle, events: stream}} =
             AdaptiveAPI.Public.ask_stream(server, "Improve this answer", context: context)

    events = Enum.to_list(stream)
    assert Enum.map(events, & &1.seq) == Enum.to_list(1..length(events))
    assert Enum.all?(events, &(&1.method == :adaptive and &1.request_id == handle.id))
    assert Enum.count(events, &Jido.AI.Request.Stream.terminal_kind?(&1.kind)) == 1
    calls = Enum.filter(events, &(&1.kind == :llm_completed))
    assert Enum.map(calls, & &1.data.reasoning_phase) == [:reasoning, :supervision, :improvement]
    assert Enum.all?(calls, &(&1.data.selected_method == :trm))
    assert {:ok, "Unreviewed improvement"} = AdaptiveAPI.Public.await(handle)
    assert List.last(events).data.result == "Unreviewed improvement"
    assert_script_done(mock)
  end

  test "typed public answers keep canonical objects and printable state across bounded AoT repair",
       %{jido: jido} do
    {mock, context} =
      mock([
        %{reply: {:object, %{value: 4}}},
        %{reply: {:text, "FINAL ANSWER: {\"value\":\"bad\"}"}},
        %{reply: {:text, "FINAL ANSWER: {\"value\":24}"}}
      ])

    server = start_agent(jido, AdaptiveAPI.Typed.new!())

    assert {:ok, handle} =
             AdaptiveAPI.Typed.ask(server, "What is two plus two?", context: context)

    assert {:ok, %{value: 4}} = AdaptiveAPI.Typed.await(handle)
    assert Server.agent(server).state.last_result == "%{value: 4}"
    assert record(server, handle).result == %{value: 4}

    assert {:ok, repaired} =
             AdaptiveAPI.Typed.ask(server, "Explore alternatives", context: context)

    assert {:ok, result} = AdaptiveAPI.Typed.await(repaired)
    assert result.answer == %{value: 24}
    assert record(server, repaired).meta.output.status == :repaired
    assert record(server, repaired).meta.adaptive.strategy == :aot
    assert Server.agent(server).state.last_result == inspect(result)
    assert_script_done(mock)
  end

  test "the common Agent selects Adaptive and namespace inspection filters other methods", %{
    jido: jido
  } do
    {mock, context} = mock(Adaptive.script(:cod) ++ TRM.script())
    common = start_agent(jido, AdaptiveAPI.Common.new!())

    assert {:ok, "Four"} =
             AdaptiveAPI.Common.ask_sync(common, "What is two plus two?", context: context)

    assert Method.get_selected_strategy(Server.agent(common)) == :cod
    other = start_agent(jido, JidoAI.Examples.TRMAPI.Public.new!())

    assert {:ok, handle} =
             JidoAI.Examples.TRMAPI.Public.reason(other, "Improve", context: context)

    assert {:ok, _} = JidoAI.Examples.TRMAPI.Public.await(handle)
    assert Method.get_selected_strategy(Server.agent(other)) == nil
    assert Method.get_selected_strategy(Server.agent(other), handle.id) == nil
    assert Method.get_complexity_score(Server.agent(other), handle.id) == nil
    assert_script_done(mock)
  end

  test "the old Strategy retains analysis and inspection without an execution runtime", %{
    jido: jido
  } do
    {mock, context} = mock(Adaptive.script(:cod))
    server = start_agent(jido, AdaptiveAPI.Public.new!())

    assert {:ok, "Four"} =
             AdaptiveAPI.Public.ask_sync(server, "What is two plus two?", context: context)

    adapter = apply(Method, :strategy_module, [])
    assert Code.ensure_loaded?(adapter)
    agent = Server.agent(server)
    assert apply(adapter, :get_selected_strategy, [agent]) == :cod
    assert apply(adapter, :get_complexity_score, [agent]) == Method.get_complexity_score(agent)

    assert Method.analyze_prompt("Improve this puzzle") ==
             apply(adapter, :analyze_prompt, ["Improve this puzzle"])

    assert {:aot, _, :exploration} =
             Method.analyze_prompt("Explore alternatives", %{available_strategies: [:aot, :tot]})

    for {name, arity} <- [
          init: 2,
          cmd: 3,
          snapshot: 2,
          action_spec: 1,
          signal_routes: 1,
          start_action: 0,
          llm_result_action: 0,
          llm_partial_action: 0,
          request_error_action: 0
        ] do
      refute function_exported?(adapter, name, arity)
    end

    for {name, arity} <- [
          ask: 2,
          ask: 3,
          ask_sync: 2,
          ask_sync: 3,
          await: 1,
          await: 2,
          strategy_opts: 0
        ] do
      assert function_exported?(AdaptiveAPI.Public, name, arity)
    end

    assert_raise FunctionClauseError, fn -> apply(AdaptiveAPI.Public, :ask, [self(), []]) end
    assert_raise FunctionClauseError, fn -> apply(AdaptiveAPI.Public, :ask_sync, [self(), []]) end
    assert_script_done(mock)
  end

  test "invalid public settings fail at authoring before any model work" do
    {mock, _} = mock([])

    for settings <- [
          [available_strategies: []],
          [available_strategies: [:cod, :cod]],
          [available_strategies: [:unknown]],
          [available_strategies: [:cot], strategy_override: :tot],
          [complexity_thresholds: %{simple: 0.8, complex: 0.2}],
          [method_options: %{tot: %{max_nodes: 0}}]
        ] do
      options = [name: "invalid_adaptive", model: :example] ++ settings
      module = Module.concat(__MODULE__, "Invalid#{System.unique_integer([:positive])}")

      assert_raise Jido.AI.Error.Validation.Invalid, fn ->
        Code.compile_quoted(
          quote do
            defmodule unquote(module) do
              use Jido.AI.AdaptiveAgent, unquote(Macro.escape(options))
            end
          end
        )
      end
    end

    assert_script_done(mock)
  end

  test "a real provider error remains structured while the public failure field remains text", %{
    jido: jido
  } do
    {mock, context} = mock([%{reply: {:error, 503, "Provider is busy"}}] ++ Adaptive.script(:cod))
    server = start_agent(jido, AdaptiveAPI.Public.new!())

    assert {:ok, handle} =
             AdaptiveAPI.Public.ask(server, "What is two plus two?", context: context)

    assert {:error, {:failed, cause, details} = error} = AdaptiveAPI.Public.await(handle)
    assert is_map(cause)
    assert details.diagnostics.cause == cause
    agent = Server.agent(server)
    assert record(server, handle).error == error
    assert agent.state.last_result == inspect(cause)
    assert agent.state.selected_strategy == :cod and agent.state.completed
    assert Method.get_selected_strategy(agent) == :cod

    assert {:ok, "Four"} =
             AdaptiveAPI.Public.ask_sync(server, "What is two plus two?", context: context)

    assert_script_done(mock)
  end
end
