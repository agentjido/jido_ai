defmodule Jido.AI.Integration.RawErrorPropagationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.ReAct.Strategy, as: ReAct
  alias Jido.AI.Request

  defmodule TestAgent do
    use Jido.AI.Agent,
      name: "raw_error_test_agent",
      tools: []
  end

  test "on_after_cmd propagates raw_error through failure_reason to request error" do
    agent = TestAgent.new()

    # Start a request so request_pending? returns true
    agent = Request.start_request(agent, "req_fail", "query")

    # Drive the strategy into a failed state with raw_error by
    # sending a start + request_failed event sequence
    {agent, _directives} =
      ReAct.cmd(
        agent,
        [%Jido.Instruction{action: ReAct.start_action(), params: %{query: "Q", request_id: "req_fail"}}],
        %{}
      )

    raw_error = %{type: :stream_error, status: 503, message: "Too many connections"}

    failed_event = %{
      id: "evt_2",
      seq: 2,
      at_ms: 1_700_000_000_002,
      run_id: "req_fail",
      request_id: "req_fail",
      iteration: 1,
      kind: :request_failed,
      llm_call_id: "call_1",
      tool_call_id: nil,
      tool_name: nil,
      data: %{error: raw_error}
    }

    {agent, _directives} =
      ReAct.cmd(
        agent,
        [%Jido.Instruction{action: :ai_react_worker_event, params: %{request_id: "req_fail", event: failed_event}}],
        %{}
      )

    # Now call on_after_cmd as the AgentServer would
    {:ok, agent, _directives} =
      TestAgent.on_after_cmd(agent, {:ai_react_start, %{request_id: "req_fail"}}, [])

    # The request error should contain the raw error term, not an inspected string
    assert {:error, {:failed, :error, ^raw_error}} = Request.get_result(agent, "req_fail")
  end
end
