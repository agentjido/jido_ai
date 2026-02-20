defmodule Jido.AI.Actions.LLM.DocsContractTest do
  use ExUnit.Case, async: true

  test "actions catalog maps each llm action to when-to-use guidance and snippets" do
    catalog = File.read!("guides/developer/actions_catalog.md")

    assert catalog =~ "## LLM Actions"

    assert catalog =~ "`Jido.AI.Actions.LLM.Chat`"
    assert catalog =~ "Use when you need single-turn conversational output"
    assert catalog =~ "llm_actions.md#chat-action"

    assert catalog =~ "`Jido.AI.Actions.LLM.Complete`"
    assert catalog =~ "Use when you want compatibility-style prompt completion"
    assert catalog =~ "llm_actions.md#complete-action"

    assert catalog =~ "`Jido.AI.Actions.LLM.Embed`"
    assert catalog =~ "Use when you need vector embeddings"
    assert catalog =~ "llm_actions.md#embed-action"

    assert catalog =~ "`Jido.AI.Actions.LLM.GenerateObject`"
    assert catalog =~ "Use when downstream code expects schema-constrained structured output"
    assert catalog =~ "llm_actions.md#generateobject-action"
  end

  test "llm action examples include runnable patterns for each action class" do
    snippets = File.read!("lib/examples/actions/llm_actions.md")
    examples_index = File.read!("lib/examples/README.md")

    assert snippets =~ "## Chat Action"
    assert snippets =~ "Jido.AI.Actions.LLM.Chat"

    assert snippets =~ "## Complete Action"
    assert snippets =~ "Jido.AI.Actions.LLM.Complete"

    assert snippets =~ "## Embed Action"
    assert snippets =~ "Jido.AI.Actions.LLM.Embed"

    assert snippets =~ "## GenerateObject Action"
    assert snippets =~ "Jido.AI.Actions.LLM.GenerateObject"

    assert snippets =~ "mix run -e"

    assert examples_index =~ "| Standalone LLM actions | `lib/examples/actions/llm_actions.md` |"
  end
end
