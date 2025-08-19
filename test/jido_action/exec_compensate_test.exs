defmodule JidoTest.ExecCompensateTest do
  use JidoTest.ActionCase, async: true
  use Mimic

  alias Jido.Exec
  alias JidoTest.TestActions.CompensateAction

  @moduletag :capture_log

  setup :set_mimic_global

  describe "do_run with compensation" do
    test "triggers compensation on action failure" do
      params = %{
        test_value: "test",
        should_fail: true,
        compensation_should_fail: false,
        delay: 10
      }

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, %{}, timeout: 50, backoff: 25)

      assert Exception.message(error) =~ "Compensation completed for:"
      assert error.details.compensated == true
      assert Exception.message(error.details.original_error) =~ "Intentional failure"
      assert is_map(error.details)
    end

    test "handles failed compensation" do
      params = %{should_fail: true, compensation_should_fail: true}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert Exception.message(error) =~ "Compensation failed for:"
      assert error.details.compensated == false
      assert Exception.message(error.details.original_error) =~ "Intentional failure"
      assert Exception.message(error.details.compensation_error) =~ "Compensation failed"
    end

    test "preserves context in compensation" do
      params = %{should_fail: true}
      context = %{test_id: "123"}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, context, timeout: 100, backoff: 25)

      assert error.details.compensation_context.test_id == "123"
    end

    test "preserves original params in compensation" do
      params = %{should_fail: true, test_value: "preserved"}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert error.details.test_value == "preserved"
    end

    test "compensation respects delay" do
      params = %{should_fail: true, delay: 25}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert error.details.compensated == true
    end
  end

  describe "timeout behavior with compensation" do
    test "times out during long compensation using action metadata timeout" do
      # Use a delay longer than the 50ms timeout defined in the CompensateAction
      params = %{should_fail: true, compensation_should_fail: false, delay: 100}

      assert {:error, %_{} = error} =
               Exec.run(CompensateAction, params, %{}, timeout: 50, backoff: 25)

      assert is_exception(error)
      # This should be a timeout or compensation error
      message = Exception.message(error)
      assert message =~ "timed out" or message =~ "Compensation failed"
    end

    test "completes compensation within timeout" do
      params = %{should_fail: true, delay: 10}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, %{}, timeout: 100, backoff: 25)

      assert error.details.compensated == true
    end
  end

  describe "telemetry with compensation" do
    test "emits telemetry events for compensation flow" do
      params = %{should_fail: true}
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, %{},
                 telemetry: :full,
                 timeout: 100,
                 backoff: 25
               )

      assert error.details.compensated == true

      verify!()
    end
  end

  describe "retry behavior with compensation" do
    test "attempts compensation after all retries are exhausted" do
      params = %{should_fail: true}

      assert {:error, %Jido.Action.Error.ExecutionFailureError{} = error} =
               Exec.run(CompensateAction, params, %{},
                 max_retries: 2,
                 backoff: 10,
                 timeout: 100
               )

      assert error.details.compensated == true
      assert Exception.message(error.details.original_error) =~ "Intentional failure"
    end

    test "doesn't attempt compensation if retry succeeds" do
      params = %{should_fail: false}

      assert {:ok, %{result: "CompensateAction completed"}} =
               Exec.run(CompensateAction, params, %{}, max_retries: 2, backoff: 10, timeout: 100)
    end
  end
end
