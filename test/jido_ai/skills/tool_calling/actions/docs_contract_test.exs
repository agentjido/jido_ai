defmodule Jido.AI.Actions.ToolCalling.DocsContractTest do
  use ExUnit.Case, async: true

  test "actions catalog maps each tool-calling action to when-to-use guidance and snippets" do
    catalog = File.read!("guides/developer/actions_catalog.md")

    assert catalog =~ "## Tool Calling Actions"

    assert catalog =~ "`Jido.AI.Actions.ToolCalling.CallWithTools`"
    assert catalog =~ "Use when the model should decide whether to call tools"
    assert catalog =~ "tool_calling_actions.md#callwithtools-one-shot"
    assert catalog =~ "tool_calling_actions.md#callwithtools-auto-execute"

    assert catalog =~ "`Jido.AI.Actions.ToolCalling.ExecuteTool`"
    assert catalog =~ "Use when your app already selected the tool and arguments"
    assert catalog =~ "tool_calling_actions.md#executetool-direct"

    assert catalog =~ "`Jido.AI.Actions.ToolCalling.ListTools`"
    assert catalog =~ "Use when you need tool discovery, optional schema projection, and sensitive-name filtering"
    assert catalog =~ "tool_calling_actions.md#listtools-discovery-and-security-filtering"
  end

  test "tool-calling guides define tool-registry precedence and security filtering contracts" do
    user_guide = File.read!("guides/user/tool_calling_with_actions.md")
    developer_guide = File.read!("guides/developer/plugins_and_actions_composition.md")

    assert user_guide =~ "## Tool Registry Precedence (Tool Map / Context / Plugin State)"
    assert user_guide =~ "1. `context[:tools]`"
    assert user_guide =~ "9. `context[:plugin_state][:chat][:tools]`"
    assert user_guide =~ "Security filtering behavior:"
    assert user_guide =~ "include_sensitive: true"
    assert user_guide =~ "allowed_tools: [...]"

    assert developer_guide =~ "## Tool Registry Precedence Contract"
    assert developer_guide =~ "context[:tool_calling][:tools]"
    assert developer_guide =~ "context[:plugin_state][:chat][:tools]"
    assert developer_guide =~ "`ListTools` security filtering defaults:"
  end

  test "tool-calling examples include one-shot and auto-execute workflows" do
    snippets = File.read!("lib/examples/actions/tool_calling_actions.md")
    examples_index = File.read!("lib/examples/README.md")

    assert snippets =~ "## CallWithTools One-Shot"
    assert snippets =~ "Jido.AI.Actions.ToolCalling.CallWithTools"

    assert snippets =~ "## CallWithTools Auto-Execute"
    assert snippets =~ "auto_execute: true"
    assert snippets =~ "turns"
    assert snippets =~ "messages"

    assert snippets =~ "## ExecuteTool Direct"
    assert snippets =~ "Jido.AI.Actions.ToolCalling.ExecuteTool"

    assert snippets =~ "## ListTools Discovery And Security Filtering"
    assert snippets =~ "Jido.AI.Actions.ToolCalling.ListTools"

    assert examples_index =~ "| Standalone tool-calling actions | `lib/examples/actions/tool_calling_actions.md` |"
  end
end
