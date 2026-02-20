defmodule Jido.AI.Plugins.ChatTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Chat
  alias Jido.Signal

  alias Jido.AI.Actions.LLM.Chat, as: ChatAction
  alias Jido.AI.Actions.LLM.{Complete, Embed, GenerateObject}

  alias Jido.AI.Actions.ToolCalling.{
    CallWithTools,
    ExecuteTool,
    ListTools
  }

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

    test "includes config in plugin spec" do
      config = %{default_model: :fast, auto_execute: false}
      spec = Chat.plugin_spec(config)

      assert spec.config == config
    end

    test "includes conversational and tool-calling actions" do
      spec = Chat.plugin_spec(%{})

      assert CallWithTools in spec.actions
      assert ExecuteTool in spec.actions
      assert ListTools in spec.actions
      assert ChatAction in spec.actions
      assert Complete in spec.actions
      assert Embed in spec.actions
      assert GenerateObject in spec.actions
      assert length(spec.actions) == 7
    end
  end

  describe "schema/0 and mount/2" do
    test "defines defaults for chat plugin state" do
      assert {:ok, parsed} = Zoi.parse(Chat.schema(), %{})

      assert parsed.default_model == :capable
      assert parsed.default_max_tokens == 4096
      assert parsed.default_temperature == 0.7
      assert parsed.auto_execute == true
      assert parsed.max_turns == 10
      assert parsed.tool_policy == :allow_all
      assert parsed.available_tools == []
    end

    test "initializes plugin with defaults" do
      assert {:ok, state} = Chat.mount(nil, %{})

      assert state.default_model == :capable
      assert state.default_max_tokens == 4096
      assert state.default_temperature == 0.7
      assert is_nil(state.default_system_prompt)
      assert state.auto_execute == true
      assert state.max_turns == 10
      assert state.tool_policy == :allow_all
      assert state.tools == %{}
      assert state.available_tools == []
    end

    test "normalizes configured tools into map and available_tools list" do
      assert {:ok, state} = Chat.mount(nil, %{tools: [ChatAction, Complete]})

      assert state.tools[ChatAction.name()] == ChatAction
      assert state.tools[Complete.name()] == Complete
      assert Enum.sort(state.available_tools) == Enum.sort([ChatAction.name(), Complete.name()])
      assert is_map(state.tools)
    end

    test "accepts custom configuration" do
      config = %{
        default_model: :fast,
        default_max_tokens: 1024,
        default_temperature: 0.1,
        default_system_prompt: "You are concise",
        auto_execute: false,
        max_turns: 3,
        tool_policy: :deny_all
      }

      assert {:ok, state} = Chat.mount(nil, config)

      assert state.default_model == :fast
      assert state.default_max_tokens == 1024
      assert state.default_temperature == 0.1
      assert state.default_system_prompt == "You are concise"
      assert state.auto_execute == false
      assert state.max_turns == 3
      assert state.tool_policy == :deny_all
    end
  end

  describe "signal_routes/1" do
    test "routes chat signals to expected tool-calling and llm actions" do
      route_map = Chat.signal_routes(%{}) |> Map.new()

      assert route_map["chat.message"] == CallWithTools
      assert route_map["chat.simple"] == ChatAction
      assert route_map["chat.complete"] == Complete
      assert route_map["chat.embed"] == Embed
      assert route_map["chat.generate_object"] == GenerateObject
      assert route_map["chat.execute_tool"] == ExecuteTool
      assert route_map["chat.list_tools"] == ListTools
      assert map_size(route_map) == 7
    end

    test "route targets are part of plugin action inventory" do
      route_targets =
        Chat.signal_routes(%{})
        |> Enum.map(fn {_signal, action} -> action end)
        |> Enum.uniq()
        |> MapSet.new()

      actions = Chat.actions() |> MapSet.new()

      assert MapSet.subset?(route_targets, actions)
      assert route_targets == actions
    end
  end

  describe "handle_signal/2 and transform_result/3" do
    test "handle_signal is pass-through" do
      signal = Signal.new!("chat.message", %{prompt: "hello"}, source: "/test")
      assert {:ok, :continue} = Chat.handle_signal(signal, %{})
    end

    test "transform_result is pass-through" do
      result = %{ok: true, response: "done"}
      assert Chat.transform_result(CallWithTools, result, %{state: %{}}) == result
    end
  end
end
