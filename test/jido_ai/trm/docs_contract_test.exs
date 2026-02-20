defmodule Jido.AI.Reasoning.TRM.DocsContractTest do
  use ExUnit.Case, async: true

  test "trm strategy docs include recursion loop and stopping controls" do
    strategy_doc = File.read!("lib/examples/strategies/trm.md")

    assert strategy_doc =~ "## TRM Recursive Loop"
    assert strategy_doc =~ "ai.trm.query"
    assert strategy_doc =~ "ai.llm.response"
    assert strategy_doc =~ "ai.llm.delta"
    assert strategy_doc =~ "ai.request.error"

    assert strategy_doc =~ "## Request Lifecycle Contract"
    assert strategy_doc =~ "reason/3"
    assert strategy_doc =~ "await/2"
    assert strategy_doc =~ "reason_sync/3"
    assert strategy_doc =~ "trm_request_error"

    assert strategy_doc =~ "## TRM Module Contracts"
    assert strategy_doc =~ "Jido.AI.Reasoning.TRM.Machine"
    assert strategy_doc =~ "Jido.AI.Reasoning.TRM.Reasoning"
    assert strategy_doc =~ "Jido.AI.Reasoning.TRM.Supervision"
    assert strategy_doc =~ "Jido.AI.Reasoning.TRM.ACT"

    assert strategy_doc =~ "## TRM Stopping Controls"
    assert strategy_doc =~ "max_supervision_steps"
    assert strategy_doc =~ "act_threshold"
    assert strategy_doc =~ ":max_steps"
    assert strategy_doc =~ ":act_threshold"
    assert strategy_doc =~ ":convergence_detected"
  end

  test "weather strategy matrix links TRM weather module and canonical command" do
    examples_readme = File.read!("lib/examples/README.md")

    assert examples_readme =~
             "| TRM | `Jido.AI.Examples.Weather.TRMAgent` (`lib/examples/weather/trm_agent.ex`) |"

    assert examples_readme =~ "| `lib/examples/strategies/trm.md` |"
    assert examples_readme =~ "mix jido_ai --agent Jido.AI.Examples.Weather.TRMAgent"
    assert examples_readme =~ "Stress test this storm-prep plan and improve it."
  end

  test "docs index uses normalized TRM strategy path" do
    docs_extras = Mix.Project.config()[:docs] |> Keyword.fetch!(:extras)
    root_readme = File.read!("README.md")

    assert "lib/examples/strategies/trm.md" in docs_extras
    assert root_readme =~ "lib/examples/strategies/trm.md"
    refute root_readme =~ "examples/strategies/trm_strategy.md"
    refute root_readme =~ "lib/examples/strategies/trm_strategy.md"
  end
end
