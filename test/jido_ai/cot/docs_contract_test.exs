defmodule Jido.AI.Reasoning.ChainOfThought.DocsContractTest do
  use ExUnit.Case, async: true

  test "cot strategy docs include delegated flow and request lifecycle contracts" do
    strategy_doc = File.read!("lib/examples/strategies/cot.md")

    assert strategy_doc =~ "## CoT Delegation Flow"
    assert strategy_doc =~ "ai.cot.query"
    assert strategy_doc =~ "ai.cot.worker.start"
    assert strategy_doc =~ "ai.cot.worker.event"
    assert strategy_doc =~ "request_started"
    assert strategy_doc =~ "request_completed"
    assert strategy_doc =~ "request_failed"
    assert strategy_doc =~ "request_cancelled"

    assert strategy_doc =~ "## Request Lifecycle Contract"
    assert strategy_doc =~ "think/3"
    assert strategy_doc =~ "await/2"
    assert strategy_doc =~ "think_sync/3"
    assert strategy_doc =~ "ai.request.error"
    assert strategy_doc =~ "request_policy: :reject"
  end

  test "weather strategy matrix links CoT weather module and canonical command" do
    examples_readme = File.read!("lib/examples/README.md")

    assert examples_readme =~ "| CoT | `Jido.AI.Examples.Weather.CoTAgent` (`lib/examples/weather/cot_agent.ex`) |"
    assert examples_readme =~ "| `lib/examples/strategies/cot.md` |"
    assert examples_readme =~ "mix jido_ai --agent Jido.AI.Examples.Weather.CoTAgent"
    assert examples_readme =~ "How should I decide between biking and transit in rainy weather?"
  end
end
