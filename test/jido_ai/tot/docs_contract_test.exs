defmodule Jido.AI.Reasoning.TreeOfThoughts.DocsContractTest do
  use ExUnit.Case, async: true

  test "tot strategy docs include structured result contract and control knobs" do
    strategy_doc = File.read!("lib/examples/strategies/tot.md")

    assert strategy_doc =~ "## ToT Search Flow"
    assert strategy_doc =~ "ai.tot.query"
    assert strategy_doc =~ "ai.llm.response"
    assert strategy_doc =~ "ai.llm.delta"
    assert strategy_doc =~ "Jido.AI.Directive.ToolExec"

    assert strategy_doc =~ "## Structured Result Contract"
    assert strategy_doc =~ "- `best`"
    assert strategy_doc =~ "- `candidates`"
    assert strategy_doc =~ "- `termination`"
    assert strategy_doc =~ "- `tree`"
    assert strategy_doc =~ "- `usage`"
    assert strategy_doc =~ "- `diagnostics`"
    assert strategy_doc =~ "best_answer/1"
    assert strategy_doc =~ "top_candidates/2"
    assert strategy_doc =~ "result_summary/1"

    assert strategy_doc =~ "## ToT Control Knobs"
    assert strategy_doc =~ "top_k"
    assert strategy_doc =~ "min_depth"
    assert strategy_doc =~ "max_nodes"
    assert strategy_doc =~ "max_duration_ms"
    assert strategy_doc =~ "beam_width"
    assert strategy_doc =~ "max_parse_retries"
    assert strategy_doc =~ "max_tool_round_trips"
  end

  test "weather strategy matrix links tot weather module and canonical command" do
    examples_readme = File.read!("lib/examples/README.md")
    root_readme = File.read!("README.md")

    assert examples_readme =~
             "| ToT | `Jido.AI.Examples.Weather.ToTAgent` (`lib/examples/weather/tot_agent.ex`) |"

    assert examples_readme =~ "| `lib/examples/strategies/tot.md` |"
    assert examples_readme =~ "mix jido_ai --agent Jido.AI.Examples.Weather.ToTAgent"
    assert examples_readme =~ "Plan three weekend options for Boston if weather is uncertain."

    assert root_readme =~ "lib/examples/strategies/tot.md"
  end
end
