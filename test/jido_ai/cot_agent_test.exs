defmodule Jido.AI.CoTAgentTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Request

  defmodule TestCoTAgent do
    use Jido.AI.CoTAgent,
      name: "test_cot_agent",
      model: "test:model"
  end

  describe "request lifecycle hooks" do
    test "on_before_cmd marks request as failed on cot_request_error" do
      agent = TestCoTAgent.new()
      agent = Request.start_request(agent, "req_1", "query")

      {:ok, agent, _action} =
        TestCoTAgent.on_before_cmd(
          agent,
          {:cot_request_error, %{request_id: "req_1", reason: :busy, message: "busy"}}
        )

      assert get_in(agent.state, [:requests, "req_1", :status]) == :failed
      assert get_in(agent.state, [:requests, "req_1", :error]) == {:rejected, :busy, "busy"}
    end
  end
end
