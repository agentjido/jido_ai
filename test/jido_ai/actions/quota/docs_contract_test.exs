defmodule Jido.AI.Actions.Quota.DocsContractTest do
  use ExUnit.Case, async: true

  test "actions catalog maps quota actions to contracts and snippets" do
    catalog = File.read!("guides/developer/actions_catalog.md")

    assert catalog =~ "## Quota Actions"

    assert catalog =~ "`Jido.AI.Actions.Quota.GetStatus`"
    assert catalog =~ "Use when you need the current rolling quota snapshot for one scope."
    assert catalog =~ "Required params: none. Optional params: `scope`."
    assert catalog =~ "Output contract: `%{quota: %{scope, window_ms, usage, limits, remaining, over_budget?}}`"
    assert catalog =~ "quota_actions.md#getstatus-action"

    assert catalog =~ "`Jido.AI.Actions.Quota.Reset`"
    assert catalog =~ "Use when you need to clear rolling quota counters for one scope."
    assert catalog =~ "Output contract: `%{quota: %{scope, reset}}`"
    assert catalog =~ "quota_actions.md#reset-action"
  end

  test "quota plugin guide defines action route contracts and context precedence" do
    plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")

    assert plugin_guide =~ "### Quota Runtime Contract"
    assert plugin_guide =~ "Quota action route contracts:"
    assert plugin_guide =~ "`quota.status` -> `Jido.AI.Actions.Quota.GetStatus`"
    assert plugin_guide =~ "`quota.reset` -> `Jido.AI.Actions.Quota.Reset`"
    assert plugin_guide =~ "Scope resolution precedence for quota actions:"
    assert plugin_guide =~ "context[:plugin_state][:quota][:scope]"
    assert plugin_guide =~ "context[:state][:quota][:scope]"
    assert plugin_guide =~ "context[:agent][:id]"
    assert plugin_guide =~ "`GetStatus` context defaults for limits/window:"
  end

  test "examples include quota action snippets and index entry" do
    snippets = File.read!("lib/examples/actions/quota_actions.md")
    examples_index = File.read!("lib/examples/README.md")

    assert snippets =~ "## GetStatus Action"
    assert snippets =~ "Jido.AI.Actions.Quota.GetStatus"
    assert snippets =~ "## Reset Action"
    assert snippets =~ "Jido.AI.Actions.Quota.Reset"
    assert snippets =~ "mix run -e"

    assert examples_index =~ "| Standalone quota actions | `lib/examples/actions/quota_actions.md` |"
  end
end
