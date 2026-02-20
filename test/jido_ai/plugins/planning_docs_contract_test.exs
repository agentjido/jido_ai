defmodule Jido.AI.Plugins.PlanningDocsContractTest do
  use ExUnit.Case, async: true

  test "planning plugin docs define signal contracts and defaults" do
    plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
    plugin_module_docs = File.read!("lib/jido_ai/plugins/planning.ex")

    assert plugin_guide =~ "## Plugin Signal Contracts"
    assert plugin_guide =~ "Jido.AI.Plugins.Planning"
    assert plugin_guide =~ "planning.plan"
    assert plugin_guide =~ "planning.decompose"
    assert plugin_guide =~ "planning.prioritize"

    assert plugin_guide =~ "## Planning Plugin Defaults Contract"
    assert plugin_guide =~ "default_model: :planning"
    assert plugin_guide =~ "default_max_tokens: 4096"
    assert plugin_guide =~ "default_temperature: 0.7"

    assert plugin_module_docs =~ "## Signal Contracts"
    assert plugin_module_docs =~ "## Mount State Defaults"
  end

  test "examples index includes plugin-based planning usage mapping" do
    examples_readme = File.read!("lib/examples/README.md")

    assert examples_readme =~ "## Plugin Capability Pattern"
    assert examples_readme =~ "| Planning plugin | Mount `Jido.AI.Plugins.Planning`"
    assert examples_readme =~ "{Jido.AI.Plugins.Planning,"
    assert examples_readme =~ "planning.plan"
    assert examples_readme =~ "Jido.AI.Actions.Planning.Plan"
  end
end
