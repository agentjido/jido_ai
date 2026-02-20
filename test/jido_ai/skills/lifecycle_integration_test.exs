defmodule Jido.AI.Plugins.LifecycleIntegrationTest do
  @moduledoc """
  Integration tests for plugin lifecycle and routing behavior.
  """

  use ExUnit.Case, async: false

  alias Jido.Agent
  alias Jido.AI.Plugins.Chat
  alias Jido.AI.Plugins.Planning

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

    test "Reasoning plugins inject fixed strategy ids" do
      signal = Jido.Signal.new!("reasoning.cot.run", %{prompt: "solve"}, source: "/test")

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               ChainOfThought.handle_signal(signal, %{})

      assert params.strategy == :cot
      assert params.prompt == "solve"
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
