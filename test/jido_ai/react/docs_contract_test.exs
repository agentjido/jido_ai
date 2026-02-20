defmodule Jido.AI.Reasoning.ReAct.DocsContractTest do
  use ExUnit.Case, async: true

  test "react strategy docs include delegated loop and request lifecycle contracts" do
    strategy_doc = File.read!("lib/examples/strategies/react.md")

    assert strategy_doc =~ "## ReAct Tool Loop Flow"
    assert strategy_doc =~ "ai.react.query"
    assert strategy_doc =~ "ai.react.worker.start"
    assert strategy_doc =~ "ai.react.worker.event"
    assert strategy_doc =~ "request_started"
    assert strategy_doc =~ "request_completed"
    assert strategy_doc =~ "request_failed"

    assert strategy_doc =~ "## Request Lifecycle Contract"
    assert strategy_doc =~ "ask/3"
    assert strategy_doc =~ "await/2"
    assert strategy_doc =~ "ask_sync/3"
    assert strategy_doc =~ "ai.react.cancel"
    assert strategy_doc =~ "request_policy: :reject"
  end

  test "docs index links react production defaults to weather parity module" do
    readme = File.read!("README.md")
    examples_readme = File.read!("lib/examples/README.md")

    assert readme =~ "lib/examples/weather/react_agent.ex"
    assert readme =~ "lib/examples/weather/overview.ex"
    assert readme =~ "lib/examples/strategies/react.md"
    refute readme =~ "lib/examples/agents/weather_agent.ex"

    assert examples_readme =~ "Jido.AI.Examples.Weather.ReActAgent"
    assert examples_readme =~ "lib/examples/weather/react_agent.ex"
    assert examples_readme =~ "lib/examples/strategies/react.md"
  end
end
