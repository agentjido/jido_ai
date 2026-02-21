defmodule Jido.AI.TRMAgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request

  defmodule TestTRMAgent do
    use Jido.AI.TRMAgent,
      name: "test_trm_agent",
      model: "test:model"
  end

  describe "request lifecycle hooks" do
    test "on_before_cmd marks request as failed on trm_request_error" do
      agent = TestTRMAgent.new()
      agent = Request.start_request(agent, "req_1", "query")

      {:ok, agent, _action} =
        TestTRMAgent.on_before_cmd(
          agent,
          {:trm_request_error, %{request_id: "req_1", reason: :busy, message: "busy"}}
        )

      assert get_in(agent.state, [:requests, "req_1", :status]) == :failed
      assert get_in(agent.state, [:requests, "req_1", :error]) == {:rejected, :busy, "busy"}
    end

    test "on_after_cmd finalizes pending request on delegated worker completion" do
      agent =
        TestTRMAgent.new()
        |> Request.start_request("req_done", "query")
        |> with_completed_strategy("improved answer")

      {:ok, updated_agent, directives} =
        TestTRMAgent.on_after_cmd(
          agent,
          {:trm_worker_event, %{request_id: "req_done", event: %{request_id: "req_done"}}},
          [:noop]
        )

      assert directives == [:noop]
      assert get_in(updated_agent.state, [:requests, "req_done", :status]) == :completed
      assert get_in(updated_agent.state, [:requests, "req_done", :result]) == "improved answer"
      assert updated_agent.state.last_result == "improved answer"
      assert updated_agent.state.completed == true
    end
  end

  defp with_completed_strategy(agent, result) do
    strategy_state = %{status: :completed, result: result}
    put_in(agent.state[:__strategy__], strategy_state)
  end
end
