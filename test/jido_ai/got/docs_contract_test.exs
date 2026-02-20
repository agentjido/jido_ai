defmodule Jido.AI.Reasoning.GraphOfThoughts.DocsContractTest do
  use ExUnit.Case, async: true

  test "got strategy docs include flow, lifecycle, and macro contracts" do
    strategy_doc = File.read!("lib/examples/strategies/got.md")

    assert strategy_doc =~ "## GoT Execution Flow"
    assert strategy_doc =~ "ai.got.query"
    assert strategy_doc =~ "ai.llm.response"
    assert strategy_doc =~ "ai.llm.delta"
    assert strategy_doc =~ "ai.request.error"

    assert strategy_doc =~ "## Request Lifecycle Contract"
    assert strategy_doc =~ "explore/3"
    assert strategy_doc =~ "await/2"
    assert strategy_doc =~ "explore_sync/3"
    assert strategy_doc =~ "got_request_error"

    assert strategy_doc =~ "## GoT Agent Macro Contract"
    assert strategy_doc =~ "use Jido.AI.GoTAgent"
    assert strategy_doc =~ "model: \"anthropic:claude-haiku-4-5\""
    assert strategy_doc =~ "max_nodes: 20"
    assert strategy_doc =~ "max_depth: 5"
    assert strategy_doc =~ "aggregation_strategy: :synthesis"
  end

  test "weather strategy matrix links GoT weather module and canonical command" do
    examples_readme = File.read!("lib/examples/README.md")

    assert examples_readme =~
             "| GoT | `Jido.AI.Examples.Weather.GoTAgent` (`lib/examples/weather/got_agent.ex`) |"

    assert examples_readme =~ "| `lib/examples/strategies/got.md` |"
    assert examples_readme =~ "mix jido_ai --agent Jido.AI.Examples.Weather.GoTAgent"
    assert examples_readme =~ "Compare weather risks across NYC, Chicago, and Denver for a trip."
  end

  test "docs index uses normalized GoT strategy path" do
    docs_extras = Mix.Project.config()[:docs] |> Keyword.fetch!(:extras)
    root_readme = File.read!("README.md")

    assert "lib/examples/strategies/got.md" in docs_extras
    assert root_readme =~ "lib/examples/strategies/got.md"
    refute root_readme =~ "examples/strategies/graph_of_thoughts.md"
  end
end
