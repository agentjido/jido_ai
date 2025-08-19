defmodule JidoTest.ExecEdgeCasesTest do
  @moduledoc """
  Additional edge case tests to achieve >90% coverage for lib/jido_action/exec.ex
  """

  use JidoTest.ActionCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Jido.Action.Error
  alias Jido.Exec
  alias JidoTest.TestActions.DelayAction

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Logger.put_process_level(self(), :debug)

    on_exit(fn ->
      Logger.delete_process_level(self())
    end)

    :ok
  end

  describe "compensation edge cases" do
    test "handles compensation with timeout configuration from metadata" do
      defmodule CompensationTimeoutAction do
        use Jido.Action,
          name: "compensation_timeout_action",
          description: "Action with compensation timeout config",
          compensation: [enabled: true, timeout: 2000]

        def run(_params, _context) do
          {:error, Error.execution_error("test error")}
        end

        def on_error(_params, _error, _context, _opts) do
          Process.sleep(100)
          {:ok, %{compensated: true}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CompensationTimeoutAction, %{}, %{}, [])
      end)
    end

    test "handles compensation with error result" do
      defmodule FailingCompensationAction do
        use Jido.Action,
          name: "failing_compensation",
          description: "Action with failing compensation",
          compensation: [enabled: true]

        def run(_params, _context) do
          {:error, Error.execution_error("original error")}
        end

        def on_error(_params, _error, _context, _opts) do
          {:error, "compensation failed"}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(FailingCompensationAction, %{}, %{}, [])
      end)
    end

    test "handles compensation with invalid result" do
      defmodule InvalidCompensationResultAction do
        use Jido.Action,
          name: "invalid_compensation_result",
          description: "Action with invalid compensation result",
          compensation: [enabled: true]

        def run(_params, _context) do
          {:error, Error.execution_error("original error")}
        end

        def on_error(_params, _error, _context, _opts) do
          :invalid_result
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(InvalidCompensationResultAction, %{}, %{}, [])
      end)
    end

    test "compensation with special result fields" do
      defmodule SpecialFieldsCompensationAction do
        use Jido.Action,
          name: "special_fields_compensation",
          description: "Action with special compensation fields",
          compensation: [enabled: true]

        def run(_params, _context) do
          {:error, Error.execution_error("original error")}
        end

        def on_error(_params, _error, _context, _opts) do
          {:ok,
           %{
             test_value: "special",
             compensation_context: %{data: "context"},
             other_field: "normal"
           }}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{details: details}} =
                 Exec.run(SpecialFieldsCompensationAction, %{}, %{}, [])

        # Check that special fields are extracted to top level
        assert details.test_value == "special"
        assert details.compensation_context == %{data: "context"}
        assert details.compensation_result == %{other_field: "normal"}
      end)
    end
  end

  describe "error handling edge cases with directives" do
    test "handles errors with directive tuples" do
      defmodule DirectiveErrorAction do
        use Jido.Action,
          name: "directive_error",
          description: "Action that returns error with directive"

        def run(_params, _context) do
          directive = %{type: "test_directive", data: "test"}
          {:error, Error.execution_error("error with directive"), directive}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}, directive} =
                 Exec.run(DirectiveErrorAction, %{}, %{}, [])

        assert directive.type == "test_directive"
      end)
    end

    test "handles compensation timeout with directive" do
      defmodule CompensationTimeoutDirectiveAction do
        use Jido.Action,
          name: "compensation_timeout_directive",
          description: "Action with compensation timeout and directive",
          compensation: [enabled: true, timeout: 50]

        def run(_params, _context) do
          directive = %{type: "timeout_directive"}
          {:error, Error.execution_error("error"), directive}
        end

        def on_error(_params, _error, _context, _opts) do
          # Sleep longer than timeout
          Process.sleep(100)
          {:ok, %{compensated: true}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}, directive} =
                 Exec.run(CompensationTimeoutDirectiveAction, %{}, %{}, [])

        assert directive.type == "timeout_directive"
      end)
    end
  end

  describe "task execution edge cases" do
    test "handles killed task in timeout execution" do
      defmodule KillableAction do
        use Jido.Action,
          name: "killable",
          description: "Action that can be killed"

        def run(_params, _context) do
          # Simulate getting killed
          Process.exit(self(), :kill)
          {:ok, %{}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(KillableAction, %{}, %{}, timeout: 1000)
      end)
    end

    test "handles task exit with reason" do
      defmodule ExitingTaskAction do
        use Jido.Action,
          name: "exiting_task",
          description: "Action that exits with reason"

        def run(_params, _context) do
          Process.exit(self(), {:shutdown, :custom_reason})
          {:ok, %{}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ExitingTaskAction, %{}, %{}, timeout: 1000)
      end)
    end

    test "handles task group cleanup edge cases" do
      # This test exercises the cleanup_task_group function with orphaned processes
      capture_log(fn ->
        # Start a long-running action that will timeout and trigger cleanup
        assert {:error, %Error.TimeoutError{}} =
                 Exec.run(DelayAction, %{delay: 5000}, %{}, timeout: 100)
      end)
    end
  end

  describe "action result edge cases" do
    test "handles action returning 3-tuple success with directive" do
      defmodule ThreeTupleSuccessAction do
        use Jido.Action,
          name: "three_tuple_success",
          description: "Action returning 3-tuple success"

        def run(params, _context) do
          directive = %{type: "success_directive", data: "test"}
          {:ok, params, directive}
        end
      end

      capture_log(fn ->
        assert {:ok, %{value: 42}, directive} =
                 Exec.run(ThreeTupleSuccessAction, %{value: 42}, %{}, [])

        assert directive.type == "success_directive"
      end)
    end

    test "handles action output validation with 3-tuple" do
      defmodule ThreeTupleValidationAction do
        use Jido.Action,
          name: "three_tuple_validation",
          description: "Action with 3-tuple and validation"

        def run(params, _context) do
          directive = %{type: "validation_directive"}
          {:ok, params, directive}
        end
      end

      capture_log(fn ->
        assert {:ok, %{value: 1}, directive} =
                 Exec.run(ThreeTupleValidationAction, %{value: 1}, %{}, [])

        assert directive.type == "validation_directive"
      end)
    end

    test "handles action 3-tuple success results" do
      # Test that 3-tuple success results work correctly
      defmodule Simple3TupleAction do
        use Jido.Action,
          name: "simple_three_tuple",
          description: "Action with simple 3-tuple result"

        def run(params, _context) do
          directive = %{type: "simple_directive"}
          {:ok, params, directive}
        end
      end

      capture_log(fn ->
        assert {:ok, %{value: 1}, directive} =
                 Exec.run(Simple3TupleAction, %{value: 1}, %{}, [])

        assert directive.type == "simple_directive"
      end)
    end
  end

  describe "exception handling in execute_action" do
    test "handles RuntimeError in action execution" do
      defmodule RuntimeErrorAction do
        use Jido.Action,
          name: "runtime_error",
          description: "Action that raises RuntimeError"

        def run(_params, _context) do
          raise "runtime error occurred"
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(RuntimeErrorAction, %{}, %{}, [])
      end)
    end

    test "handles ArgumentError in action execution" do
      defmodule ArgumentErrorAction do
        use Jido.Action,
          name: "argument_error",
          description: "Action that raises ArgumentError"

        def run(_params, _context) do
          raise ArgumentError, "invalid argument"
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ArgumentErrorAction, %{}, %{}, [])
      end)
    end

    test "handles other exceptions in action execution" do
      defmodule OtherExceptionAction do
        use Jido.Action,
          name: "other_exception",
          description: "Action that raises other exception"

        def run(_params, _context) do
          raise KeyError, "key not found"
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(OtherExceptionAction, %{}, %{}, [])
      end)
    end
  end

  describe "additional normalization edge cases" do
    test "normalize_params with nested {:ok, {:ok, params}}" do
      # Test nested ok tuples
      nested_ok = {:ok, {:ok, %{key: "value"}}}
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(nested_ok)
    end

    test "normalize_params with complex nested error" do
      nested_error = {:error, {:nested, "error"}}
      assert {:error, %Error.InvalidInputError{}} = Exec.normalize_params(nested_error)
    end
  end
end
