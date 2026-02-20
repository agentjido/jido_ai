defmodule Jido.AI.Actions.Reasoning.DocsContractTest do
  use ExUnit.Case, async: true

  test "actions catalog maps reasoning actions to output contracts and strategy parameter requirements" do
    catalog = File.read!("guides/developer/actions_catalog.md")

    assert catalog =~ "## Reasoning Actions"

    assert catalog =~ "`Jido.AI.Actions.Reasoning.Analyze`"
    assert catalog =~ "Use when you need structured analysis"
    assert catalog =~ "Output contract: `%{result, analysis_type, model, usage}`"
    assert catalog =~ "reasoning_actions.md#analyze-action"

    assert catalog =~ "`Jido.AI.Actions.Reasoning.Infer`"
    assert catalog =~ "Output contract: `%{result, reasoning, model, usage}`"
    assert catalog =~ "reasoning_actions.md#infer-action"

    assert catalog =~ "`Jido.AI.Actions.Reasoning.Explain`"
    assert catalog =~ "Output contract: `%{result, detail_level, model, usage}`"
    assert catalog =~ "reasoning_actions.md#explain-action"

    assert catalog =~ "`Jido.AI.Actions.Reasoning.RunStrategy`"
    assert catalog =~ "Required parameters: `strategy`"
    assert catalog =~ "Strategy tuning parameters can be passed at top-level or inside `options`"
    assert catalog =~ "Output contract: `%{strategy, status, output, usage, diagnostics}`"
    assert catalog =~ "reasoning_actions.md#runstrategy-action"
  end

  test "run strategy docs include explicit fast-smoke vs full-checkpoint coverage split guidance" do
    catalog = File.read!("guides/developer/actions_catalog.md")

    assert catalog =~ "Coverage split guidance"
    assert catalog =~ "run_strategy_action_fast_test.exs"
    assert catalog =~ "run_strategy_action_test.exs"
  end

  test "reasoning examples include action invocation and strategy-run snippets" do
    snippets = File.read!("lib/examples/actions/reasoning_actions.md")
    examples_index = File.read!("lib/examples/README.md")

    assert snippets =~ "## Analyze Action"
    assert snippets =~ "Jido.AI.Actions.Reasoning.Analyze"
    assert snippets =~ "## Infer Action"
    assert snippets =~ "Jido.AI.Actions.Reasoning.Infer"
    assert snippets =~ "## Explain Action"
    assert snippets =~ "Jido.AI.Actions.Reasoning.Explain"
    assert snippets =~ "## RunStrategy Action"
    assert snippets =~ "Jido.AI.Actions.Reasoning.RunStrategy"
    assert snippets =~ "mix run -e"

    assert examples_index =~ "| Standalone reasoning actions | `lib/examples/actions/reasoning_actions.md` |"
  end
end
