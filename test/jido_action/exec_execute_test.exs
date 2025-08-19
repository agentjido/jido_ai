defmodule JidoTest.ExecExecuteTest do
  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Exec
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.ContextAction
  alias JidoTest.TestActions.DelayAction
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.KilledAction
  alias JidoTest.TestActions.NoParamsAction
  alias JidoTest.TestActions.NormalExitAction
  alias JidoTest.TestActions.RawResultAction
  alias JidoTest.TestActions.SlowKilledAction

  @moduletag :capture_log

  setup do
    Logger.put_process_level(self(), :debug)
  end

  describe "execute_action/3" do
    test "successfully executes a Action" do
      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} =
                   Exec.execute_action(BasicAction, %{value: 5}, %{}, log_level: :debug)
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.BasicAction"
      assert log =~ "Finished execution of JidoTest.TestActions.BasicAction"
    end

    test "successfully executes a Action with context" do
      log =
        capture_log(fn ->
          assert {:ok, %{result: result}} =
                   Exec.execute_action(ContextAction, %{input: 5}, %{context: "test"},
                     log_level: :debug
                   )

          assert result =~ "5 processed with context"
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ContextAction"
      assert log =~ "Finished execution of JidoTest.TestActions.ContextAction"
    end

    test "successfully executes a Action with no params" do
      log =
        capture_log(fn ->
          assert {:ok, %{result: "No params"}} =
                   Exec.execute_action(NoParamsAction, %{}, %{}, log_level: :debug)
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.NoParamsAction"
      assert log =~ "Finished execution of JidoTest.TestActions.NoParamsAction"
    end

    test "successfully executes a Action with raw result" do
      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} =
                   Exec.execute_action(RawResultAction, %{value: 5}, %{}, log_level: :debug)
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.RawResultAction"
      assert log =~ "Finished execution of JidoTest.TestActions.RawResultAction"
    end

    test "handles Action execution error" do
      log =
        capture_log(fn ->
          assert {:error, error} =
                   Exec.execute_action(ErrorAction, %{error_type: :validation}, %{},
                     log_level: :debug
                   )

          assert is_exception(error)
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
    end

    test "handles runtime errors" do
      log =
        capture_log(fn ->
          assert {:error, error} =
                   Exec.execute_action(ErrorAction, %{error_type: :runtime}, %{},
                     log_level: :debug
                   )

          assert is_exception(error)
          assert Exception.message(error) =~ "Runtime error"
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
    end

    test "handles argument errors" do
      log =
        capture_log(fn ->
          assert {:error, error} =
                   Exec.execute_action(ErrorAction, %{error_type: :argument}, %{},
                     log_level: :debug
                   )

          assert is_exception(error)
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
    end

    test "handles unexpected errors" do
      log =
        capture_log(fn ->
          assert {:error, error} =
                   Exec.execute_action(ErrorAction, %{error_type: :custom}, %{},
                     log_level: :debug
                   )

          assert is_exception(error)

          assert Exception.message(error) =~
                   "Server error in JidoTest.TestActions.ErrorAction: Custom error"
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
    end
  end

  describe "execute_action_with_timeout/4" do
    test "successfully executes a Action with no params" do
      log =
        capture_log(fn ->
          assert {:ok, %{result: "No params"}} =
                   Exec.execute_action_with_timeout(NoParamsAction, %{}, %{}, 0,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.NoParamsAction"
      assert log =~ "Finished execution of JidoTest.TestActions.NoParamsAction"
    end

    test "executes quick action within timeout" do
      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} ==
                   Exec.execute_action_with_timeout(BasicAction, %{value: 5}, %{}, 1000,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.BasicAction"
      assert log =~ "Finished execution of JidoTest.TestActions.BasicAction"
    end

    test "executes without forking a Task when timeout is zero" do
      initial_process_count = length(Process.list())

      log =
        capture_log(fn ->
          result =
            Exec.execute_action_with_timeout(BasicAction, %{value: 5}, %{}, 0, log_level: :debug)

          # Verify the result is correct
          assert {:ok, %{value: 5}} = result
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.BasicAction"
      assert log =~ "Finished execution of JidoTest.TestActions.BasicAction"

      # Give any potential tasks time to start (though there shouldn't be any)
      Process.sleep(50)

      # Verify no new processes were created
      final_process_count = length(Process.list())
      assert_in_delta initial_process_count, final_process_count, 1
    end

    test "times out for slow action" do
      log =
        capture_log(fn ->
          assert {:error, %Jido.Action.Error.TimeoutError{}} =
                   Exec.execute_action_with_timeout(DelayAction, %{delay: 1000}, %{}, 100,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.DelayAction"
    end

    test "handles very short timeout" do
      log =
        capture_log(fn ->
          result =
            Exec.execute_action_with_timeout(DelayAction, %{delay: 100}, %{}, 1,
              log_level: :debug
            )

          assert {:error, %Jido.Action.Error.TimeoutError{}} = result
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.DelayAction"
    end

    test "handles action errors" do
      log =
        capture_log(fn ->
          assert {:error, error} =
                   Exec.execute_action_with_timeout(
                     ErrorAction,
                     %{error_type: :runtime},
                     %{},
                     1000,
                     log_level: :debug
                   )

          assert is_exception(error)
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
    end

    test "handles unexpected errors during execution" do
      log =
        capture_log(fn ->
          assert {:error, error} =
                   Exec.execute_action_with_timeout(
                     ErrorAction,
                     %{type: :unexpected},
                     %{},
                     1000,
                     log_level: :debug
                   )

          assert is_exception(error)
          assert Exception.message(error) =~ "Exec failed"
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
    end

    test "handles errors thrown during execution" do
      log =
        capture_log(fn ->
          assert {:error, error} =
                   Exec.execute_action_with_timeout(ErrorAction, %{type: :throw}, %{}, 1000,
                     log_level: :debug
                   )

          assert is_exception(error)
          assert Exception.message(error) =~ "Caught throw: \"Action threw an error\""
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
    end

    test "handles :DOWN message after killing the process" do
      test_pid = self()

      log =
        capture_log(fn ->
          spawn(fn ->
            result =
              Exec.execute_action_with_timeout(SlowKilledAction, %{}, %{}, 50, log_level: :debug)

            send(test_pid, {:result, result})
          end)

          assert_receive {:result, {:error, %Jido.Action.Error.TimeoutError{}}}, 1000
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.SlowKilledAction"
    end

    test "uses default timeout when not specified" do
      log =
        capture_log(fn ->
          assert {:ok, %{result: "Async action completed"}} ==
                   Exec.execute_action_with_timeout(DelayAction, %{delay: 80}, %{}, 0,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.DelayAction"
      assert log =~ "Finished execution of JidoTest.TestActions.DelayAction"
    end

    test "executes without timeout when timeout is zero" do
      log =
        capture_log(fn ->
          assert {:ok, %{result: "Async action completed"}} ==
                   Exec.execute_action_with_timeout(DelayAction, %{delay: 80}, %{}, 0,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.DelayAction"
      assert log =~ "Finished execution of JidoTest.TestActions.DelayAction"
    end

    test "uses default timeout for invalid timeout value" do
      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} ==
                   Exec.execute_action_with_timeout(BasicAction, %{value: 5}, %{}, -1,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.BasicAction"
      assert log =~ "Finished execution of JidoTest.TestActions.BasicAction"
    end

    test "handles normal exit" do
      log =
        capture_log(fn ->
          result =
            Exec.execute_action_with_timeout(NormalExitAction, %{}, %{}, 1000, log_level: :debug)

          assert {:error, error} = result
          assert is_exception(error)
          assert Exception.message(error) =~ "Task exited: :normal"
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.NormalExitAction"
    end

    test "handles killed tasks" do
      log =
        capture_log(fn ->
          result =
            Exec.execute_action_with_timeout(KilledAction, %{}, %{}, 1000, log_level: :debug)

          assert {:error, error} = result
          assert is_exception(error)
          assert Exception.message(error) =~ "Task was killed"
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.KilledAction"
    end

    test "handles concurrent action execution" do
      log =
        capture_log(fn ->
          tasks =
            for i <- 1..10 do
              Task.async(fn ->
                Exec.execute_action_with_timeout(BasicAction, %{value: i}, %{}, 1000,
                  log_level: :debug
                )
              end)
            end

          results = Task.await_many(tasks)
          assert Enum.all?(results, fn {:ok, %{value: v}} -> is_integer(v) end)
        end)

      # Each task should have logged its execution
      assert log =~ "Starting execution of JidoTest.TestActions.BasicAction"
      assert log =~ "Finished execution of JidoTest.TestActions.BasicAction"
    end
  end
end
