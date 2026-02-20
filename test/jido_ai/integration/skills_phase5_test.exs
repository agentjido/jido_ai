defmodule Jido.AI.Integration.SkillsPhase5Test do
  @moduledoc """
  Integration tests for the production plugin surface.

  These tests verify that:
  - Public plugin capabilities compose correctly
  - Plugin action inventories are coherent
  - Strategy plugins map to isolated strategy execution action
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Plugins.Chat
  alias Jido.AI.Actions.LLM.Chat, as: ChatAction
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

  alias Jido.AI.Actions.Reasoning.RunStrategy

  describe "Plugin Composition" do
    test "public plugins expose stable names and state keys" do
      chat_spec = Chat.plugin_spec(%{})
      planning_spec = Planning.plugin_spec(%{})
      cod_spec = ChainOfDraft.plugin_spec(%{})
      cot_spec = ChainOfThought.plugin_spec(%{})
      aot_spec = AlgorithmOfThoughts.plugin_spec(%{})
      tot_spec = TreeOfThoughts.plugin_spec(%{})
      got_spec = GraphOfThoughts.plugin_spec(%{})
      trm_spec = TRM.plugin_spec(%{})
      adaptive_spec = Adaptive.plugin_spec(%{})

      assert chat_spec.name == "chat"
      assert chat_spec.state_key == :chat

      assert planning_spec.name == "planning"
      assert planning_spec.state_key == :planning

      assert cod_spec.state_key == :reasoning_cod
      assert cot_spec.state_key == :reasoning_cot
      assert aot_spec.state_key == :reasoning_aot
      assert tot_spec.state_key == :reasoning_tot
      assert got_spec.state_key == :reasoning_got
      assert trm_spec.state_key == :reasoning_trm
      assert adaptive_spec.state_key == :reasoning_adaptive
    end

    test "plugins maintain independent state" do
      {:ok, chat_state} = Chat.mount(%Jido.Agent{}, %{default_model: :capable})
      {:ok, planning_state} = Planning.mount(%Jido.Agent{}, %{default_model: :planning})
      {:ok, cot_state} = ChainOfThought.mount(%Jido.Agent{}, %{})

      assert chat_state.default_model == :capable
      assert planning_state.default_model == :planning
      assert cot_state.strategy == :cot
    end
  end

  describe "Chat Plugin Integration" do
    alias Jido.AI.Actions.LLM.{Complete, Embed, GenerateObject}
    alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}

    test "chat plugin includes conversational and tool actions" do
      actions = Chat.actions()

      assert CallWithTools in actions
      assert ExecuteTool in actions
      assert ListTools in actions
      assert ChatAction in actions
      assert Complete in actions
      assert Embed in actions
      assert GenerateObject in actions
      assert length(actions) == 7
    end

    test "Chat action schema is available" do
      schema = ChatAction.schema()
      assert schema.fields[:prompt].meta.required == true
      refute schema.fields[:model].meta.required
      assert schema.fields[:max_tokens].value == 1024
    end
  end

  describe "Planning Plugin Integration" do
    alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}

    test "planning plugin actions are accessible" do
      actions = Planning.actions()

      assert Plan in actions
      assert Decompose in actions
      assert Prioritize in actions
      assert length(actions) == 3
    end
  end

  describe "Strategy Plugin Integration" do
    test "all strategy plugins expose RunStrategy action" do
      plugins = [ChainOfDraft, ChainOfThought, AlgorithmOfThoughts, TreeOfThoughts, GraphOfThoughts, TRM, Adaptive]

      for plugin <- plugins do
        assert plugin.actions() == [RunStrategy]
      end
    end

    test "strategy plugin routes map to reasoning.*.run signals" do
      assert Map.new(ChainOfDraft.signal_routes(%{}))["reasoning.cod.run"] == RunStrategy
      assert Map.new(ChainOfThought.signal_routes(%{}))["reasoning.cot.run"] == RunStrategy
      assert Map.new(AlgorithmOfThoughts.signal_routes(%{}))["reasoning.aot.run"] == RunStrategy
      assert Map.new(TreeOfThoughts.signal_routes(%{}))["reasoning.tot.run"] == RunStrategy
      assert Map.new(GraphOfThoughts.signal_routes(%{}))["reasoning.got.run"] == RunStrategy
      assert Map.new(TRM.signal_routes(%{}))["reasoning.trm.run"] == RunStrategy
      assert Map.new(Adaptive.signal_routes(%{}))["reasoning.adaptive.run"] == RunStrategy
    end
  end

  describe "End-to-End Surface Checks" do
    test "all public plugins provide plugin_spec/1, mount/2, actions/0" do
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
        assert function_exported?(plugin, :plugin_spec, 1)
        assert function_exported?(plugin, :mount, 2)
        assert function_exported?(plugin, :actions, 0)
      end
    end

    test "total unique action count across public plugins" do
      unique_actions =
        Chat.actions()
        |> Kernel.++(Planning.actions())
        |> Kernel.++(ChainOfDraft.actions())
        |> Kernel.++(ChainOfThought.actions())
        |> Kernel.++(AlgorithmOfThoughts.actions())
        |> Kernel.++(TreeOfThoughts.actions())
        |> Kernel.++(GraphOfThoughts.actions())
        |> Kernel.++(TRM.actions())
        |> Kernel.++(Adaptive.actions())
        |> Enum.uniq()

      assert length(unique_actions) == 11
    end
  end
end
