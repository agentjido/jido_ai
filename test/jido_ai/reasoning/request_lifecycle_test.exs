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

    test "starts and retains an active request id" do
      assert %{active_request_id: "req_new"} =
               RequestLifecycle.put_active_request_id(
                 %{active_request_id: "req_old"},
                 %{status: :running},
                 "req_new",
                 [:running]
               )

      assert %{active_request_id: "req_old"} =
               RequestLifecycle.put_active_request_id(
                 %{active_request_id: "req_old"},
                 %{status: :idle},
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

      assert_receive {:"$gen_cast", {:signal, _admission, signal}}, 200
      assert signal.type == "ai.request.completed"
      assert signal.data.request_id == "req_complete"
      assert signal.data.result == "done"
    end

    test "emits failure signal for string error statuses" do
      previous_state = %{status: :running, active_request_id: "req_failed"}
      new_state = %{status: "error", result: :boom, config: %{observability: %{}}}

      assert :ok = RequestLifecycle.emit_terminal(:aot, previous_state, new_state)

      assert_receive {:"$gen_cast", {:signal, _admission, signal}}, 200
      assert signal.type == "ai.request.failed"
      assert signal.data.request_id == "req_failed"
      assert signal.data.error == :boom
    end

    test "emits a started signal and ignores non-terminal transitions" do
      assert :ok =
               RequestLifecycle.emit_started(
                 :aot,
                 %{config: %{observability: %{}}},
                 "req_start",
                 "question"
               )

      assert_receive {:"$gen_cast", {:signal, _admission, signal}}, 200
      assert signal.type == "ai.request.started"
      assert signal.data.query == "question"

      assert :ok =
               RequestLifecycle.emit_terminal(
                 :aot,
                 %{status: :running},
                 %{status: :running, result: nil}
               )

      refute_receive {:"$gen_cast", {:signal, _, _}}, 20
    end
  end

  describe "telemetry values" do
    test "extracts usage from direct and result fields" do
      assert RequestLifecycle.extract_usage(%{usage: %{input_tokens: 2}}) == %{input_tokens: 2}

      assert RequestLifecycle.extract_usage(%{usage: %{}, result: %{usage: %{output_tokens: 3}}}) ==
               %{output_tokens: 3}

      assert RequestLifecycle.extract_usage(%{}) == %{}
    end

    test "infers common error types" do
      assert RequestLifecycle.infer_error_type(%{termination: :timeout}) == :timeout
      assert RequestLifecycle.infer_error_type(%{reason: :busy}) == :busy
      assert RequestLifecycle.infer_error_type(%{type: :provider}) == :provider
      assert RequestLifecycle.infer_error_type(%{code: :invalid}) == :invalid
      assert RequestLifecycle.infer_error_type({:error, :closed, []}) == :closed
      assert RequestLifecycle.infer_error_type({:error, :failed}) == :failed
      assert RequestLifecycle.infer_error_type(:cancelled) == :cancelled
      assert RequestLifecycle.infer_error_type("unknown") == nil
    end

    test "emits telemetry with state and explicit option values" do
      state = %{
        config: %{observability: %{}, model: "openai:gpt-4o-mini"},
        result: {:error, :provider},
        current_call_id: "call_1",
        termination_reason: :provider_error
      }

      assert :ok =
               RequestLifecycle.emit_request_telemetry(:aot, state, :failed, "req_telemetry",
                 usage: %{input_tokens: 2, output_tokens: 3},
                 iteration: 2,
                 operation: :generate,
                 error_type: :provider
               )
    end
  end
end
