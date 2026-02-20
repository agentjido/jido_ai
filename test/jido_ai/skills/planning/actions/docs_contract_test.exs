defmodule Jido.AI.Actions.Planning.DocsContractTest do
  use ExUnit.Case, async: true

  test "actions catalog maps each planning action to selection guidance and snippets" do
    catalog = File.read!("guides/developer/actions_catalog.md")

    assert catalog =~ "## Planning Actions"

    assert catalog =~ "`Jido.AI.Actions.Planning.Plan`"
    assert catalog =~ "Use when you need a sequential execution plan from one goal."
    assert catalog =~ "planning_actions.md#plan-action"

    assert catalog =~ "`Jido.AI.Actions.Planning.Decompose`"
    assert catalog =~ "Use when the goal is too large and should be split into hierarchical sub-goals."
    assert catalog =~ "planning_actions.md#decompose-action"

    assert catalog =~ "`Jido.AI.Actions.Planning.Prioritize`"
    assert catalog =~ "Use when you already have a task list and need ranked execution order."
    assert catalog =~ "planning_actions.md#prioritize-action"
  end

  test "planning plugin docs remain aligned with planning action ownership and defaults" do
    plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
    plugin_module_docs = File.read!("lib/jido_ai/plugins/planning.ex")

    assert plugin_guide =~ "## Planning Plugin Defaults Contract"
    assert plugin_guide =~ "default_model: :planning"
    assert plugin_guide =~ "default_max_tokens: 4096"
    assert plugin_guide =~ "default_temperature: 0.7"
    assert plugin_guide =~ "`Plan`: `goal`, optional `constraints`/`resources`, optional `max_steps`"
    assert plugin_guide =~ "`Decompose`: `goal`, optional `max_depth`, optional `context`"
    assert plugin_guide =~ "`Prioritize`: `tasks`, optional `criteria`, optional `context`"

    assert plugin_module_docs =~ "## Signal Contracts"
    assert plugin_module_docs =~ "## Mount State Defaults"
    assert plugin_module_docs =~ "Action-specific inputs remain action-owned"
  end

  test "planning examples include an end-to-end decomposition workflow snippet" do
    snippets = File.read!("lib/examples/actions/planning_actions.md")
    examples_index = File.read!("lib/examples/README.md")

    assert snippets =~ "## Planning Workflow With Task Decomposition"
    assert snippets =~ "Jido.AI.Actions.Planning.Plan"
    assert snippets =~ "Jido.AI.Actions.Planning.Decompose"
    assert snippets =~ "Jido.AI.Actions.Planning.Prioritize"

    assert examples_index =~ "| Standalone planning actions | `lib/examples/actions/planning_actions.md` |"
  end
end
