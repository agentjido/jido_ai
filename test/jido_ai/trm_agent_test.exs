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
  end
end
