defmodule JidoTest.AI.ZoiDefaultsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request

  defmodule GeneratedAgent do
    use Jido.AI.Agent,
      name: "zoi_defaults_regression_agent",
      tools: []
  end

  test "a generated ReAct agent stores its first request without a provider call" do
    agent = GeneratedAgent.new()

    assert agent.state.requests == %{}
    updated = Request.start_request(agent, "first-request", "hello")

    assert updated.state.requests["first-request"].status == :pending
    assert updated.state.requests["first-request"].query == "hello"
    assert updated.state.last_request_id == "first-request"
    assert agent.state.requests == %{}
  end
end
