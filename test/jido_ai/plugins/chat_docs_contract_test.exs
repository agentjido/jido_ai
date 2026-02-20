defmodule Jido.AI.Plugins.ChatDocsContractTest do
  use ExUnit.Case, async: true

  test "chat plugin docs define signal contracts and defaults" do
    plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
    plugin_module_docs = File.read!("lib/jido_ai/plugins/chat.ex")

    assert plugin_guide =~ "## Plugin Signal Contracts"
    assert plugin_guide =~ "Jido.AI.Plugins.Chat"
    assert plugin_guide =~ "chat.message"
    assert plugin_guide =~ "chat.simple"
    assert plugin_guide =~ "chat.complete"
    assert plugin_guide =~ "chat.embed"
    assert plugin_guide =~ "chat.generate_object"
    assert plugin_guide =~ "chat.execute_tool"
    assert plugin_guide =~ "chat.list_tools"

    assert plugin_guide =~ "## Chat Plugin Defaults Contract"
    assert plugin_guide =~ "default_model: :capable"
    assert plugin_guide =~ "default_max_tokens: 4096"
    assert plugin_guide =~ "default_temperature: 0.7"
    assert plugin_guide =~ "default_system_prompt: nil"
    assert plugin_guide =~ "auto_execute: true"
    assert plugin_guide =~ "max_turns: 10"
    assert plugin_guide =~ "tool_policy: :allow_all"

    assert plugin_module_docs =~ "## Signal Contracts"
    assert plugin_module_docs =~ "## Mount State Defaults"
  end

  test "examples index includes plugin-based chat usage mapping" do
    examples_readme = File.read!("lib/examples/README.md")

    assert examples_readme =~ "## Plugin Capability Pattern"
    assert examples_readme =~ "| Chat plugin | Mount `Jido.AI.Plugins.Chat`"
    assert examples_readme =~ "plugins: ["
    assert examples_readme =~ "{Jido.AI.Plugins.Chat,"
    assert examples_readme =~ "chat.message"
    assert examples_readme =~ "CallWithTools"
  end
end
