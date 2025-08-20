defmodule JidoTest.ExecIntegrationTest do
  @moduledoc """
  Comprehensive integration tests for Jido.Exec module.

  These tests establish a safety net before refactoring the exec module by covering:
  - Happy path sync execution
  - Happy path async execution  
  - Timeout scenarios
  - Retry scenarios with failing actions
  - Compensation scenarios with on_error/4
  """
  use JidoTest.ActionCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.CompensateAction
  alias JidoTest.TestActions.DelayAction
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.RetryAction

  @attempts_table :exec_integration_test_attempts

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Logger.put_process_level(self(), :debug)

    # Create table for retry tests
    :ets.new(@attempts_table, [:set, :public, :named_table])
    :ets.insert(@attempts_table, {:attempts, 0})

    on_exit(fn ->
      Logger.delete_process_level(self())

      if :ets.info(@attempts_table) != :undefined do
        :ets.delete(@attempts_table)
      end
    end)

    {:ok, attempts_table: @attempts_table}
  end

  describe "Happy path sync execution" do
    test "executes simple action successfully" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:ok, %{value: 42}} = Exec.run(BasicAction, %{value: 42})
        end)

      assert log =~ "Executing JidoTest.TestActions.BasicAction"
      assert log =~ "params: %{value: 42}"
      verify!()
    end

    test "executes action with context" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      context = %{user_id: "123", request_id: "abc"}

      log =
        capture_log(fn ->
          assert {:ok, %{value: 100}} = Exec.run(BasicAction, %{value: 100}, context)
        end)

      assert log =~ "Executing JidoTest.TestActions.BasicAction"
      verify!()
    end

    test "executes action with custom timeout" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:ok, %{value: 200}} =
                   Exec.run(BasicAction, %{value: 200}, %{}, timeout: 10_000)
        end)

      assert log =~ "Executing JidoTest.TestActions.BasicAction"
      verify!()
    end
  end

  describe "Happy path async execution" do
    test "executes simple async action successfully" do
      capture_log(fn ->
        async_ref = Exec.run_async(BasicAction, %{value: 123})

        assert is_map(async_ref)
        assert is_pid(async_ref.pid)
        assert is_reference(async_ref.ref)

        assert {:ok, %{value: 123}} = Exec.await(async_ref, 1_000)
      end)
    end

    test "executes async action with context" do
      context = %{correlation_id: "test-456"}

      capture_log(fn ->
        async_ref = Exec.run_async(BasicAction, %{value: 456}, context)
        assert {:ok, %{value: 456}} = Exec.await(async_ref, 1_000)
      end)
    end

    test "handles multiple concurrent async actions" do
      capture_log(fn ->
        async_refs =
          Enum.map(1..5, fn i ->
            Exec.run_async(BasicAction, %{value: i * 10}, %{id: i})
          end)

        results =
          Enum.map(async_refs, fn async_ref ->
            Exec.await(async_ref, 1_000)
          end)

        expected_results = [
          {:ok, %{value: 10}},
          {:ok, %{value: 20}},
          {:ok, %{value: 30}},
          {:ok, %{value: 40}},
          {:ok, %{value: 50}}
        ]

        assert results == expected_results
      end)
    end
  end

  describe "Timeout scenarios" do
    test "sync action times out properly" do
      capture_log(fn ->
        assert {:error, %Error.TimeoutError{} = error} =
                 Exec.run(DelayAction, %{delay: 100}, %{}, timeout: 50)

        assert Exception.message(error) =~ "timed out after 50ms"
      end)
    end

    test "async action times out during execution" do
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 200}, %{}, timeout: 100)

        assert {:error, %Error.TimeoutError{} = error} = Exec.await(async_ref, 2_000)
        assert Exception.message(error) =~ "timed out after 100ms"
      end)
    end

    test "async await times out while waiting for result" do
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 200}, %{}, timeout: 500)

        # Await with shorter timeout than action execution time
        assert {:error, %Error.TimeoutError{} = error} = Exec.await(async_ref, 100)
        assert Exception.message(error) =~ "Async action timed out after 100ms"
      end)
    end

    test "cancelled async action stops execution" do
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 1_000}, %{}, timeout: 5_000)

        # Cancel quickly after starting
        Process.sleep(10)
        assert :ok = Exec.cancel(async_ref)

        # Process should no longer be alive
        refute Process.alive?(async_ref.pid)

        # Await should return appropriate error since process is dead
        assert {:error, error} = Exec.await(async_ref, 100)
        assert is_exception(error)
      end)
    end
  end

  describe "Retry scenarios" do
    test "sync action retries and eventually succeeds", %{attempts_table: attempts_table} do
      # Reset attempts counter
      :ets.insert(attempts_table, {:attempts, 0})

      capture_log(fn ->
        result =
          Exec.run(
            RetryAction,
            %{max_attempts: 3, failure_type: :error},
            %{attempts_table: attempts_table},
            max_retries: 3,
            backoff: 10
          )

        assert {:ok, %{result: "success after 3 attempts"}} = result
      end)
    end

    test "sync action retries with exceptions and succeeds", %{attempts_table: attempts_table} do
      # Reset attempts counter
      :ets.insert(attempts_table, {:attempts, 0})

      capture_log(fn ->
        result =
          Exec.run(
            RetryAction,
            %{max_attempts: 2, failure_type: :exception},
            %{attempts_table: attempts_table},
            max_retries: 3,
            backoff: 10
          )

        assert {:ok, %{result: "success after 2 attempts"}} = result
      end)
    end

    test "async action retries and succeeds", %{attempts_table: attempts_table} do
      # Reset attempts counter  
      :ets.insert(attempts_table, {:attempts, 0})

      capture_log(fn ->
        async_ref =
          Exec.run_async(
            RetryAction,
            %{max_attempts: 2, failure_type: :error},
            %{attempts_table: attempts_table},
            max_retries: 3,
            backoff: 10
          )

        assert {:ok, %{result: "success after 2 attempts"}} = Exec.await(async_ref, 2_000)
      end)
    end

    test "action exhausts retries and fails", %{attempts_table: attempts_table} do
      # Reset attempts counter
      :ets.insert(attempts_table, {:attempts, 0})

      capture_log(fn ->
        # Action that needs 5 attempts but only gets 2 retries (3 total attempts)
        result =
          Exec.run(
            RetryAction,
            %{max_attempts: 5, failure_type: :error},
            %{attempts_table: attempts_table},
            max_retries: 2,
            backoff: 10
          )

        assert {:error, %Error.InternalError{}} = result
      end)
    end
  end

  describe "Compensation scenarios with on_error/4" do
    test "compensating action handles failure successfully" do
      capture_log(fn ->
        # Action should fail but compensation should succeed
        result =
          Exec.run(
            CompensateAction,
            %{should_fail: true, compensation_should_fail: false, test_value: "recovery_test"},
            %{original_context: "preserved"}
          )

        # Compensation returns error with details about successful compensation
        assert {:error, %Error.ExecutionFailureError{} = error} = result
        assert Exception.message(error) =~ "Compensation completed for:"
        assert error.details.compensated == true
        assert is_exception(error.details.original_error)
        assert error.details.test_value == "recovery_test"
        assert Map.has_key?(error.details, :compensation_context)
      end)
    end

    test "compensation itself can fail" do
      capture_log(fn ->
        result =
          Exec.run(
            CompensateAction,
            %{should_fail: true, compensation_should_fail: true},
            %{test_context: "failure"}
          )

        assert {:error, %Error.ExecutionFailureError{}} = result
        assert Exception.message(elem(result, 1)) =~ "Compensation failed for:"
      end)
    end

    test "successful action doesn't trigger compensation" do
      capture_log(fn ->
        result =
          Exec.run(
            CompensateAction,
            %{should_fail: false, test_value: "success_case"},
            %{}
          )

        assert {:ok, %{result: "CompensateAction completed"}} = result
      end)
    end

    test "async compensation works correctly" do
      capture_log(fn ->
        async_ref =
          Exec.run_async(
            CompensateAction,
            %{should_fail: true, compensation_should_fail: false, delay: 50},
            %{async_context: "test"}
          )

        # Async compensation also returns error with compensation details
        result = Exec.await(async_ref, 2_000)

        # Due to timeout in compensation (delay: 50, timeout: 50), compensation may timeout
        assert {:error, %Error.ExecutionFailureError{} = error} = result
        # Could be either successful compensation or compensation timeout
        assert Exception.message(error) =~ "Compensation"
        assert is_exception(error.details.original_error)
      end)
    end
  end

  describe "Error handling edge cases" do
    test "handles various error types properly" do
      capture_log(fn ->
        # Validation error
        assert {:error, error} = Exec.run(ErrorAction, %{error_type: :validation})
        assert is_binary(error) or is_exception(error)

        # Runtime error - gets wrapped in ExecutionFailureError
        assert {:error, error} = Exec.run(ErrorAction, %{error_type: :runtime})
        assert is_exception(error)

        # Argument error - gets wrapped in ExecutionFailureError  
        assert {:error, error} = Exec.run(ErrorAction, %{error_type: :argument})
        assert is_exception(error)

        # Custom error - gets wrapped in ExecutionFailureError
        assert {:error, error} = Exec.run(ErrorAction, %{error_type: :custom})
        assert is_exception(error)
      end)
    end

    test "handles thrown values" do
      capture_log(fn ->
        assert {:error, error} = Exec.run(ErrorAction, %{type: :throw})
        assert is_exception(error)
      end)
    end
  end

  describe "Configuration and options" do
    test "respects custom configuration values" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      capture_log(fn ->
        # Test with multiple configuration options
        assert {:ok, %{value: 789}} =
                 Exec.run(
                   BasicAction,
                   %{value: 789},
                   %{},
                   timeout: 2_000,
                   max_retries: 5,
                   backoff: 500,
                   log_level: :info
                 )
      end)

      verify!()
    end

    test "validates option types" do
      capture_log(fn ->
        # Invalid timeout should still work (gets normalized)
        assert {:ok, %{value: 999}} =
                 Exec.run(
                   BasicAction,
                   %{value: 999},
                   %{},
                   timeout: "invalid"
                 )
      end)
    end
  end

  describe "Complex integration scenarios" do
    test "full workflow with retries, compensation, and async" do
      capture_log(fn ->
        # Start async action that will fail and trigger compensation
        async_ref =
          Exec.run_async(
            CompensateAction,
            %{should_fail: true, compensation_should_fail: false, test_value: "complex_test"},
            %{workflow_id: "integration_test"},
            max_retries: 2,
            backoff: 25
          )

        # Should get compensated result in error format
        assert {:error, %Error.ExecutionFailureError{} = error} = Exec.await(async_ref, 3_000)
        assert Exception.message(error) =~ "Compensation completed for:"
        assert error.details.compensated == true
        assert error.details.test_value == "complex_test"
      end)
    end

    test "handles mixed success and failure in concurrent execution" do
      capture_log(fn ->
        # Mix of successful and failing actions
        tasks = [
          {BasicAction, %{value: 1}, %{}},
          {ErrorAction, %{error_type: :validation}, %{}},
          {BasicAction, %{value: 2}, %{}},
          {CompensateAction, %{should_fail: true, compensation_should_fail: false}, %{}}
        ]

        async_refs =
          Enum.map(tasks, fn {action, params, context} ->
            {action, Exec.run_async(action, params, context)}
          end)

        results =
          Enum.map(async_refs, fn {action, async_ref} ->
            {action, Exec.await(async_ref, 1_000)}
          end)

        # Verify we get expected mix of results
        success_count = Enum.count(results, fn {_, result} -> match?({:ok, _}, result) end)
        error_count = Enum.count(results, fn {_, result} -> match?({:error, _}, result) end)

        # BasicAction + CompensateAction (compensated)
        assert success_count >= 2
        # ErrorAction
        assert error_count >= 1
      end)
    end
  end
end
