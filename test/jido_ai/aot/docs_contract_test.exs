defmodule Jido.AI.Reasoning.AlgorithmOfThoughts.DocsContractTest do
  use ExUnit.Case, async: true

  test "aot strategy docs include flow, lifecycle, and macro contracts" do
    strategy_doc = File.read!("lib/examples/strategies/aot.md")

    assert strategy_doc =~ "## AoT Execution Flow"
    assert strategy_doc =~ "ai.aot.query"
    assert strategy_doc =~ "ai.llm.response"
    assert strategy_doc =~ "ai.llm.delta"
    assert strategy_doc =~ "ai.request.error"

    assert strategy_doc =~ "## Request Lifecycle Contract"
    assert strategy_doc =~ "explore/3"
    assert strategy_doc =~ "await/2"
    assert strategy_doc =~ "explore_sync/3"
    assert strategy_doc =~ "aot_request_error"

    assert strategy_doc =~ "## AoT Agent Macro Contract"
    assert strategy_doc =~ "use Jido.AI.AoTAgent"
    assert strategy_doc =~ "model: \"anthropic:claude-haiku-4-5\""
    assert strategy_doc =~ "profile: :standard"
    assert strategy_doc =~ "search_style: :dfs"
    assert strategy_doc =~ "require_explicit_answer: true"
  end

  test "weather strategy matrix links AoT weather module and canonical command" do
    examples_readme = File.read!("lib/examples/README.md")

    assert examples_readme =~
             "| AoT | `Jido.AI.Examples.Weather.AoTAgent` (`lib/examples/weather/aot_agent.ex`) |"

    assert examples_readme =~ "| `lib/examples/strategies/aot.md` |"
    assert examples_readme =~ "mix jido_ai --agent Jido.AI.Examples.Weather.AoTAgent"
    assert examples_readme =~ "Find the best weather-safe weekend option with one backup."
  end

  test "docs index uses normalized AoT strategy path" do
    docs_extras = Mix.Project.config()[:docs] |> Keyword.fetch!(:extras)
    root_readme = File.read!("README.md")

    assert "lib/examples/strategies/aot.md" in docs_extras
    assert root_readme =~ "lib/examples/strategies/aot.md"
    refute root_readme =~ "examples/strategies/algorithm_of_thoughts.md"
  end
end
