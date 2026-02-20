defmodule Jido.AI.Reasoning.Adaptive.DocsContractTest do
  use ExUnit.Case, async: true

  test "adaptive strategy docs include selection constraints, defaults, and lifecycle contracts" do
    strategy_doc = File.read!("lib/examples/strategies/adaptive.md")

    assert strategy_doc =~ "## Adaptive Selection Flow"
    assert strategy_doc =~ "ai.adaptive.query"
    assert strategy_doc =~ "ai.llm.response"
    assert strategy_doc =~ "ai.llm.delta"
    assert strategy_doc =~ "ai.request.error"

    assert strategy_doc =~ "## Strategy-Selection Constraints"
    assert strategy_doc =~ "available_strategies"
    assert strategy_doc =~ "default_strategy"
    assert strategy_doc =~ "complexity_thresholds"
    assert strategy_doc =~ ":react"
    assert strategy_doc =~ ":trm"

    assert strategy_doc =~ "## Request Lifecycle Contract"
    assert strategy_doc =~ "ask/3"
    assert strategy_doc =~ "await/2"
    assert strategy_doc =~ "ask_sync/3"
    assert strategy_doc =~ "adaptive_request_error"
  end

  test "weather strategy matrix links adaptive weather module and canonical command" do
    examples_readme = File.read!("lib/examples/README.md")

    assert examples_readme =~
             "| Adaptive | `Jido.AI.Examples.Weather.AdaptiveAgent` (`lib/examples/weather/adaptive_agent.ex`) |"

    assert examples_readme =~ "| `lib/examples/strategies/adaptive.md` |"
    assert examples_readme =~ "mix jido_ai --agent Jido.AI.Examples.Weather.AdaptiveAgent"
    assert examples_readme =~ "I need a weather-aware commute and backup plan for tomorrow."
  end

  test "docs index uses normalized adaptive strategy path" do
    docs_extras = Mix.Project.config()[:docs] |> Keyword.fetch!(:extras)
    root_readme = File.read!("README.md")

    assert "lib/examples/strategies/adaptive.md" in docs_extras
    assert root_readme =~ "lib/examples/strategies/adaptive.md"
    refute root_readme =~ "examples/strategies/adaptive_strategy.md"
    refute root_readme =~ "lib/examples/strategies/adaptive_strategy.md"
  end
end
