defmodule Jido.AI.Plugins.ChatTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Chat

  describe "plugin_spec/1" do
    test "returns valid plugin specification" do
      spec = Chat.plugin_spec(%{})

      assert spec.module == Jido.AI.Plugins.Chat
      assert spec.name == "chat"
      assert spec.state_key == :chat
      assert spec.description == "Provides conversational AI with built-in tool calling"
      assert spec.category == "ai"
      assert spec.vsn == "2.0.0"
      assert spec.tags == ["chat", "conversation", "tool-calling", "llm"]
    end

    test "includes conversational and tool-calling actions" do
      spec = Chat.plugin_spec(%{})

      assert Jido.AI.Actions.ToolCalling.CallWithTools in spec.actions
      assert Jido.AI.Actions.ToolCalling.ExecuteTool in spec.actions
      assert Jido.AI.Actions.ToolCalling.ListTools in spec.actions
      assert Jido.AI.Actions.LLM.Chat in spec.actions
      assert Jido.AI.Actions.LLM.Complete in spec.actions
      assert Jido.AI.Actions.LLM.Embed in spec.actions
      assert Jido.AI.Actions.LLM.GenerateObject in spec.actions
    end
  end

  describe "mount/2" do
    test "initializes plugin with defaults" do
      assert {:ok, state} = Chat.mount(nil, %{})
      assert state.default_model == :capable
      assert state.default_max_tokens == 4096
      assert state.default_temperature == 0.7
      assert state.auto_execute == true
      assert state.max_turns == 10
      assert is_map(state.tools)
    end

    test "accepts custom configuration" do
      assert {:ok, state} = Chat.mount(nil, %{default_model: :fast, auto_execute: false, max_turns: 3})
      assert state.default_model == :fast
      assert state.auto_execute == false
      assert state.max_turns == 3
    end
  end
end
