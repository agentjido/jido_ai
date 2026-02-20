defmodule Jido.AI.Actions.Retrieval.DocsContractTest do
  use ExUnit.Case, async: true

  test "actions catalog maps retrieval actions to parameter and output contracts" do
    catalog = File.read!("guides/developer/actions_catalog.md")

    assert catalog =~ "## Retrieval Actions"

    assert catalog =~ "`Jido.AI.Actions.Retrieval.UpsertMemory`"
    assert catalog =~ "Required params: `text`."
    assert catalog =~ "Output contract: `%{retrieval: %{namespace, last_upsert}}`"
    assert catalog =~ "retrieval_actions.md#upsertmemory-action"

    assert catalog =~ "`Jido.AI.Actions.Retrieval.RecallMemory`"
    assert catalog =~ "Required params: `query`."
    assert catalog =~ "Output contract: `%{retrieval: %{namespace, query, memories, count}}`"
    assert catalog =~ "retrieval_actions.md#recallmemory-action"

    assert catalog =~ "`Jido.AI.Actions.Retrieval.ClearMemory`"
    assert catalog =~ "Output contract: `%{retrieval: %{namespace, cleared}}`"
    assert catalog =~ "retrieval_actions.md#clearmemory-action"
  end

  test "retrieval runtime docs describe action route contracts and namespace behavior" do
    plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")

    assert plugin_guide =~ "### Retrieval Runtime Contract"
    assert plugin_guide =~ "Retrieval action route contracts:"
    assert plugin_guide =~ "`retrieval.upsert` -> `Jido.AI.Actions.Retrieval.UpsertMemory`"
    assert plugin_guide =~ "`retrieval.recall` -> `Jido.AI.Actions.Retrieval.RecallMemory`"
    assert plugin_guide =~ "`retrieval.clear` -> `Jido.AI.Actions.Retrieval.ClearMemory`"
    assert plugin_guide =~ "If omitted, namespace falls back to agent id"
  end

  test "examples include retrieval action snippets and index entry" do
    snippets = File.read!("lib/examples/actions/retrieval_actions.md")
    examples_index = File.read!("lib/examples/README.md")

    assert snippets =~ "## UpsertMemory Action"
    assert snippets =~ "## RecallMemory Action"
    assert snippets =~ "## ClearMemory Action"
    assert snippets =~ "Jido.AI.Actions.Retrieval.UpsertMemory"
    assert snippets =~ "mix run -e"

    assert examples_index =~ "| Standalone retrieval actions | `lib/examples/actions/retrieval_actions.md` |"
  end
end
