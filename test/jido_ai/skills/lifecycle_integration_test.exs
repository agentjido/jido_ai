defmodule Jido.AI.Plugins.LifecycleIntegrationTest do
  @moduledoc """
  Integration tests for plugin lifecycle and routing behavior.
  """

  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AI.Directive.Helpers
  alias Jido.AI.Plugins.Chat
  alias Jido.AI.Plugins.Planning
  alias Jido.AI.Plugins.TaskSupervisor

  alias Jido.AI.Plugins.Reasoning.{
    Adaptive,
    AlgorithmOfThoughts,
    ChainOfDraft,
    ChainOfThought,
    GraphOfThoughts,
    TRM,
    TreeOfThoughts
  }

  require Jido.AI.Plugins.Chat
  require Jido.AI.Plugins.Planning
  require Jido.AI.Plugins.Reasoning.Adaptive
  require Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts
  require Jido.AI.Plugins.Reasoning.ChainOfDraft
  require Jido.AI.Plugins.Reasoning.ChainOfThought
  require Jido.AI.Plugins.Reasoning.GraphOfThoughts
  require Jido.AI.Plugins.Reasoning.TRM
  require Jido.AI.Plugins.Reasoning.TreeOfThoughts

  describe "Plugin Mount/2 Initialization" do
    test "Chat plugin mount/2 returns defaults" do
      assert {:ok, state} = Chat.mount(%Agent{}, %{})
      assert state.default_model == :capable
      assert state.default_max_tokens == 4096
      assert state.auto_execute == true
      assert state.max_turns == 10
      assert is_map(state.tools)
    end

    test "Planning plugin mount/2 returns defaults" do
      assert {:ok, state} = Planning.mount(%Agent{}, %{})
      assert state.default_model == :planning
      assert state.default_max_tokens == 4096
      assert state.default_temperature == 0.7
    end

    test "TaskSupervisor plugin mount/2 stores a per-agent supervisor under internal state key" do
      spec = TaskSupervisor.plugin_spec(%{})
      assert spec.state_key == :__task_supervisor_skill__

      assert {:ok, state} = TaskSupervisor.mount(%Agent{}, %{})
      assert is_pid(state.supervisor)
      assert Process.alive?(state.supervisor)

      assert Helpers.get_task_supervisor(%{__task_supervisor_skill__: state}) == state.supervisor
    end

    test "TaskSupervisor plugin supervisor lifecycle follows owning process lifecycle" do
      parent = self()

      {owner_pid, owner_ref} =
        spawn_monitor(fn ->
          assert {:ok, state} = TaskSupervisor.mount(%Agent{}, %{})
          send(parent, {:task_supervisor_pid, state.supervisor})
          Process.sleep(:infinity)
        end)

      assert_receive {:task_supervisor_pid, supervisor_pid}, 1_000
      assert Process.alive?(supervisor_pid)

      supervisor_ref = Process.monitor(supervisor_pid)
      Process.exit(owner_pid, :kill)

      assert_receive {:DOWN, ^owner_ref, :process, ^owner_pid, :killed}, 1_000
      assert_receive {:DOWN, ^supervisor_ref, :process, ^supervisor_pid, :killed}, 1_000
    end

    test "Reasoning strategy plugins mount with fixed strategy ids" do
      assert {:ok, cod} = ChainOfDraft.mount(%Agent{}, %{})
      assert {:ok, cot} = ChainOfThought.mount(%Agent{}, %{})
      assert {:ok, aot} = AlgorithmOfThoughts.mount(%Agent{}, %{})
      assert {:ok, tot} = TreeOfThoughts.mount(%Agent{}, %{})
      assert {:ok, got} = GraphOfThoughts.mount(%Agent{}, %{})
      assert {:ok, trm} = TRM.mount(%Agent{}, %{})
      assert {:ok, adaptive} = Adaptive.mount(%Agent{}, %{})

      assert cod.strategy == :cod
      assert cot.strategy == :cot
      assert aot.strategy == :aot
      assert tot.strategy == :tot
      assert got.strategy == :got
      assert trm.strategy == :trm
      assert adaptive.strategy == :adaptive
    end
  end

  describe "Plugin Schemas" do
    test "all public plugins define schema/0" do
      plugins = [
        Chat,
        Planning,
        ChainOfDraft,
        ChainOfThought,
        AlgorithmOfThoughts,
        TreeOfThoughts,
        GraphOfThoughts,
        TRM,
        Adaptive
      ]

      for plugin <- plugins do
        assert function_exported?(plugin, :schema, 0)
        assert is_map(plugin.schema()) or is_struct(plugin.schema())
      end
    end
  end

  describe "signal_routes/1 Callback" do
    test "Chat plugin exposes chat namespace routes" do
      routes = Chat.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["chat.message"] == Jido.AI.Actions.ToolCalling.CallWithTools
      assert route_map["chat.execute_tool"] == Jido.AI.Actions.ToolCalling.ExecuteTool
      assert route_map["chat.list_tools"] == Jido.AI.Actions.ToolCalling.ListTools
      assert route_map["chat.embed"] == Jido.AI.Actions.LLM.Embed
      assert route_map["chat.generate_object"] == Jido.AI.Actions.LLM.GenerateObject
    end

    test "Planning plugin exposes planning namespace routes" do
      routes = Planning.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["planning.plan"] == Jido.AI.Actions.Planning.Plan
      assert route_map["planning.decompose"] == Jido.AI.Actions.Planning.Decompose
      assert route_map["planning.prioritize"] == Jido.AI.Actions.Planning.Prioritize
    end

    test "Reasoning strategy plugins expose reasoning.*.run routes" do
      assert Map.new(ChainOfDraft.signal_routes(%{}))["reasoning.cod.run"] ==
               Jido.AI.Actions.Reasoning.RunStrategy

      assert Map.new(ChainOfThought.signal_routes(%{}))["reasoning.cot.run"] ==
               Jido.AI.Actions.Reasoning.RunStrategy

      assert Map.new(AlgorithmOfThoughts.signal_routes(%{}))["reasoning.aot.run"] ==
               Jido.AI.Actions.Reasoning.RunStrategy

      assert Map.new(TreeOfThoughts.signal_routes(%{}))["reasoning.tot.run"] ==
               Jido.AI.Actions.Reasoning.RunStrategy

      assert Map.new(GraphOfThoughts.signal_routes(%{}))["reasoning.got.run"] ==
               Jido.AI.Actions.Reasoning.RunStrategy

      assert Map.new(TRM.signal_routes(%{}))["reasoning.trm.run"] ==
               Jido.AI.Actions.Reasoning.RunStrategy

      assert Map.new(Adaptive.signal_routes(%{}))["reasoning.adaptive.run"] ==
               Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "Handle Signal/2 Callback" do
    test "Chat plugin passes through signals" do
      signal = Jido.Signal.new!("chat.message", %{prompt: "hello"}, source: "/test")
      assert {:ok, :continue} = Chat.handle_signal(signal, %{})
    end

    test "Planning plugin passes through signals" do
      signal = Jido.Signal.new!("planning.plan", %{goal: "Ship v1"}, source: "/test")
      assert {:ok, :continue} = Planning.handle_signal(signal, %{})
    end

    test "Reasoning plugins inject fixed strategy ids" do
      cod_signal = Jido.Signal.new!("reasoning.cod.run", %{prompt: "quick solve", strategy: :cot}, source: "/test")
      cot_signal = Jido.Signal.new!("reasoning.cot.run", %{prompt: "solve"}, source: "/test")
      tot_signal = Jido.Signal.new!("reasoning.tot.run", %{prompt: "explore options", strategy: :got}, source: "/test")
      got_signal = Jido.Signal.new!("reasoning.got.run", %{prompt: "connect signals", strategy: :tot}, source: "/test")

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, cod_params}}} =
               ChainOfDraft.handle_signal(cod_signal, %{})

      assert cod_params.strategy == :cod
      assert cod_params.prompt == "quick solve"

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               ChainOfThought.handle_signal(cot_signal, %{})

      assert params.strategy == :cot
      assert params.prompt == "solve"

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, tot_params}}} =
               TreeOfThoughts.handle_signal(tot_signal, %{})

      assert tot_params.strategy == :tot
      assert tot_params.prompt == "explore options"

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, got_params}}} =
               GraphOfThoughts.handle_signal(got_signal, %{})

      assert got_params.strategy == :got
      assert got_params.prompt == "connect signals"
    end
  end

  describe "Transform Result/3 Callback" do
    test "plugins pass through results unchanged" do
      result = %{ok: true}

      assert Chat.transform_result(nil, result, %{}) == result
      assert Planning.transform_result(nil, result, %{}) == result
      assert ChainOfThought.transform_result(nil, result, %{}) == result
    end
  end

  describe "Signal Patterns" do
    test "plugins expose signal_patterns/0" do
      assert "chat.message" in Chat.signal_patterns()
      assert "planning.plan" in Planning.signal_patterns()
      assert "planning.decompose" in Planning.signal_patterns()
      assert "planning.prioritize" in Planning.signal_patterns()
      assert "reasoning.cod.run" in ChainOfDraft.signal_patterns()
      assert "reasoning.cot.run" in ChainOfThought.signal_patterns()
      assert "reasoning.aot.run" in AlgorithmOfThoughts.signal_patterns()
      assert "reasoning.tot.run" in TreeOfThoughts.signal_patterns()
      assert "reasoning.got.run" in GraphOfThoughts.signal_patterns()
      assert "reasoning.trm.run" in TRM.signal_patterns()
      assert "reasoning.adaptive.run" in Adaptive.signal_patterns()
    end
  end
end
