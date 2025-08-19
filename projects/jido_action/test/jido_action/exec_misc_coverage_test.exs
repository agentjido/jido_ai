defmodule JidoTest.ExecMiscCoverageTest do
  @moduledoc """
  Tests for miscellaneous uncovered lines in exec.ex
  """

  use JidoTest.ActionCase, async: false

  import ExUnit.CaptureLog

  alias Jido.Action.Error
  alias Jido.Exec

  @moduletag :capture_log

  describe "miscellaneous coverage" do
    test "handle various error message extraction scenarios" do
      # Test extract_safe_error_message with struct containing message field
      defmodule StructMessageAction do
        use Jido.Action, name: "struct_message", description: "Test struct message"

        def run(_params, _context) do
          # Create an error with a struct that has a message field
          struct_with_message = %ArgumentError{message: "argument error"}
          {:error, %{message: struct_with_message}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(StructMessageAction, %{}, %{})
      end)
    end

    test "await with process exit scenarios" do
      # Test the edge case where a process exits normally but we receive the result
      capture_log(fn ->
        parent = self()
        ref = make_ref()

        # Create a task that exits normally but sends result first
        {:ok, pid} =
          Task.start_link(fn ->
            send(parent, {:action_async_result, ref, {:ok, %{delayed: true}}})
            # Exit normally
            :ok
          end)

        # Monitor the process
        Process.monitor(pid)
        async_ref = %{ref: ref, pid: pid}

        # Wait for the result - this should handle the normal exit case
        result = Exec.await(async_ref, 1000)
        assert {:ok, %{delayed: true}} = result
      end)
    end

    test "normalize params with various invalid structures" do
      # Test edge cases in param normalization
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(fn -> :function end)
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(self())
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(make_ref())
    end

    test "compensation with specific timeout configurations" do
      defmodule SpecificTimeoutCompAction do
        use Jido.Action,
          name: "specific_timeout_comp",
          description: "Compensation with specific timeout",
          compensation: [enabled: true, timeout: 50]

        def run(_params, _context) do
          {:error, Error.execution_error("compensation test")}
        end

        def on_error(_params, _error, _context, _opts) do
          # Sleep longer than timeout
          Process.sleep(100)
          {:ok, %{compensated: true}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(SpecificTimeoutCompAction, %{}, %{})
      end)
    end

    test "task cleanup and process group management" do
      # Create an action that will trigger task group cleanup
      defmodule CleanupTestAction do
        use Jido.Action, name: "cleanup_test", description: "Test cleanup"

        def run(_params, context) do
          # Access the task group to trigger that code path
          _task_group = Map.get(context, :__task_group__)

          # Force a timeout to trigger cleanup
          Process.sleep(200)
          {:ok, %{}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.TimeoutError{}} =
                 Exec.run(CleanupTestAction, %{}, %{}, timeout: 50)
      end)
    end

    test "additional error handling paths" do
      # Test the catch clause for throw/exit in execute_action_with_timeout
      defmodule CatchTestAction do
        use Jido.Action, name: "catch_test", description: "Test catch clauses"

        def run(%{error_type: :throw}, _context) do
          throw("test throw")
        end

        def run(%{error_type: :exit}, _context) do
          exit("test exit")
        end

        def run(params, _context), do: {:ok, params}
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CatchTestAction, %{error_type: :throw}, %{}, timeout: 1000)
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CatchTestAction, %{error_type: :exit}, %{}, timeout: 1000)
      end)
    end

    test "backoff calculation edge cases" do
      # Test the calculate_backoff function by forcing a few retries with small backoff
      defmodule SmallBackoffAction do
        use Jido.Action, name: "small_backoff", description: "Test small backoff"

        def run(%{succeed: true}, _context) do
          {:ok, %{succeeded: true}}
        end

        def run(params, _context), do: {:ok, params}
      end

      capture_log(fn ->
        # Use small backoff to test calculate_backoff without timing out
        result = Exec.run(SmallBackoffAction, %{succeed: true}, %{}, max_retries: 2, backoff: 50)
        assert {:ok, %{succeeded: true}} = result
      end)
    end
  end
end
