defmodule Jido.AI.Reasoning.RequestLifecycleTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Reasoning.RequestLifecycle

  describe "put_active_request_id/4" do
    test "clears active request ids for string terminal statuses" do
      assert %{active_request_id: nil} =
               RequestLifecycle.put_active_request_id(
                 %{active_request_id: "req_1"},
                 %{status: "completed"},
                 nil,
                 [:running]
               )

      assert %{active_request_id: nil} =
               RequestLifecycle.put_active_request_id(
                 %{active_request_id: "req_2"},
                 %{status: "error"},
                 nil,
                 [:running]
               )
    end
  end

  describe "emit_terminal/4" do
    test "emits completion signal for string completed statuses" do
      previous_state = %{status: :running, active_request_id: "req_complete"}
      new_state = %{status: "completed", result: "done", config: %{observability: %{}}}

      assert :ok = RequestLifecycle.emit_terminal(:aot, previous_state, new_state)

      assert_receive {:"$gen_cast", {:signal, signal}}, 200
      assert signal.type == "ai.request.completed"
      assert signal.data.request_id == "req_complete"
      assert signal.data.result == "done"
    end

    test "emits failure signal for string error statuses" do
      previous_state = %{status: :running, active_request_id: "req_failed"}
      new_state = %{status: "error", result: :boom, config: %{observability: %{}}}

      assert :ok = RequestLifecycle.emit_terminal(:aot, previous_state, new_state)

      assert_receive {:"$gen_cast", {:signal, signal}}, 200
      assert signal.type == "ai.request.failed"
      assert signal.data.request_id == "req_failed"
      assert signal.data.error == :boom
    end
  end
end
