defmodule Jido.AI.Plugins.ChatTest do
  use ExUnit.Case, async: true
  alias Jido.AI.Plugins.Chat

  defp definition(config) do
    Jido.Agent.new(%{
      name: "chat_config",
      schema: Zoi.object(%{result: Zoi.any() |> Zoi.default(nil)}),
      plugins: [{Chat, config}],
      routes: Chat.signal_routes(config)
    })
  end

  test "declared Chat defaults survive creation and an empty restored owned state" do
    assert {:ok, definition} =
             definition(
               default_max_tokens: 321,
               default_system_prompt: "Use labels",
               auto_execute: false,
               max_turns: 0
             )

    agent = Jido.Agent.instantiate!(definition)

    assert agent.state.chat.default_max_tokens == 321 and
             agent.state.chat.default_system_prompt == "Use labels"

    assert agent.state.chat.auto_execute == false and agent.state.chat.max_turns == 0
    {:chat, schema} = Chat.Agent.state_spec(default_max_tokens: 321, auto_execute: false)

    assert {:ok, %{default_max_tokens: 321, auto_execute: false, tools: %{}, available_tools: []}} =
             Zoi.parse(schema, %{})
  end

  test "invalid defaults and unsupported or duplicate configuration fail at the public Agent boundary" do
    for config <- [
          [default_max_tokens: 0],
          [default_temperature: 3.0],
          [default_system_prompt: 17],
          [auto_execute: :yes],
          [max_turns: -1],
          [into: "result"],
          [surprise: true],
          [max_turns: 1, max_turns: 2]
        ] do
      assert {:error, _} = definition(config)
    end
  end

  test "public catalogs retain all seven Actions and use explicit capability routes" do
    assert Chat.name() == "chat" and Chat.category() == "ai" and Chat.vsn() == "2.0.0"
    assert Chat.state_key() == :chat
    assert length(Chat.actions()) == 7
    assert length(Chat.signal_patterns()) == 7
    assert Enum.map(Chat.signal_routes([]), &elem(&1, 0)) == Chat.signal_patterns()
    assert Enum.all?(Chat.signal_routes([]), &(elem(&1, 1) == Jido.AI.Actions.Chat.RunCapability))

    for action <- Chat.actions() do
      assert action.category() == "ai" and action.vsn() == "1.0.0" and is_list(action.tags())
      assert is_map(action.schema())
    end
  end

  test "the route Action requires a declared capability binding" do
    assert {:error, :chat_capability_not_bound} =
             Jido.AI.Actions.Chat.RunCapability.run(%{prompt: "Label"}, %{})
  end
end
