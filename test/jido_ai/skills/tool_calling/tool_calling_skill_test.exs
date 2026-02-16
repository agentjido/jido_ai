defmodule Jido.AI.Plugins.ToolCallingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.ToolCalling

  describe "plugin_spec/1" do
    test "returns valid skill spec with empty config" do
      spec = ToolCalling.plugin_spec(%{})

      assert spec.module == ToolCalling
      assert spec.name == "tool_calling"
      assert spec.state_key == :tool_calling
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert length(spec.actions) == 3
    end

    test "includes config in skill spec" do
      config = %{auto_execute: true, max_turns: 5}
      spec = ToolCalling.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = ToolCalling.mount(%Jido.Agent{}, %{})

      assert state.default_model == :capable
      assert state.default_max_tokens == 4096
      assert state.default_temperature == 0.7
      assert state.auto_execute == false
      assert state.max_turns == 10
      assert is_list(state.available_tools)
    end

    test "merges custom config into initial state" do
      {:ok, state} =
        ToolCalling.mount(%Jido.Agent{}, %{auto_execute: true, max_turns: 5})

      assert state.auto_execute == true
      assert state.max_turns == 5
      assert state.default_model == :capable
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} =
        ToolCalling.mount(%Jido.Agent{}, %{tools: [Jido.AI.Actions.ToolCalling.ExecuteTool]})

      assert {:ok, _parsed_state} = Zoi.parse(ToolCalling.schema(), state)
    end
  end

  describe "actions" do
    test "returns all three actions" do
      actions = ToolCalling.actions()

      assert length(actions) == 3
      assert Jido.AI.Actions.ToolCalling.CallWithTools in actions
      assert Jido.AI.Actions.ToolCalling.ExecuteTool in actions
      assert Jido.AI.Actions.ToolCalling.ListTools in actions
    end
  end
end
