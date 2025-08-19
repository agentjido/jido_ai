defmodule JidoTest.ExecFinalCoverageTest do
  @moduledoc """
  Final tests to push exec.ex coverage above 90%
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

  describe "private function coverage" do
    test "test private helper functions through public interface" do
      # Test extract_safe_error_message with various error types
      defmodule ErrorMessageTestAction do
        use Jido.Action,
          name: "error_message_test",
          description: "Test error message extraction"

        def run(%{error_type: :nil_message}, _context) do
          {:error, %{message: nil}}
        end

        def run(%{error_type: :string_message}, _context) do
          {:error, %{message: "string error"}}
        end

        def run(%{error_type: :struct_message}, _context) do
          {:error, %{message: %ArgumentError{message: "struct error"}}}
        end

        def run(%{error_type: :nested_message}, _context) do
          {:error, %{message: %{message: "nested error"}}}
        end

        def run(%{error_type: :no_message}, _context) do
          {:error, %{other: "field"}}
        end

        def run(params, _context), do: {:ok, params}
      end

      # Test different error message types
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ErrorMessageTestAction, %{error_type: :nil_message}, %{}, [])
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ErrorMessageTestAction, %{error_type: :string_message}, %{}, [])
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ErrorMessageTestAction, %{error_type: :struct_message}, %{}, [])
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ErrorMessageTestAction, %{error_type: :nested_message}, %{}, [])
      end)

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(ErrorMessageTestAction, %{error_type: :no_message}, %{}, [])
      end)
    end

    test "timeout handling with edge cases" do
      # Test timeout with exactly 0
      capture_log(fn ->
        assert {:ok, %{value: 1}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, timeout: 0)
      end)

      # Test timeout with negative value (should use default)
      capture_log(fn ->
        assert {:ok, %{value: 2}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, timeout: -1)
      end)

      # Test timeout with non-integer (should use default)
      capture_log(fn ->
        assert {:ok, %{value: 3}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 3}, %{}, timeout: nil)
      end)
    end

    test "retry logic with different failure patterns" do
      defmodule RetryPatternAction do
        use Jido.Action,
          name: "retry_pattern",
          description: "Action with specific retry patterns"

        def run(%{pattern: :immediate_success}, _context) do
          {:ok, %{result: "immediate"}}
        end

        def run(%{pattern: :fail_once, attempt: _attempt}, context) do
          current_attempt = Map.get(context, :current_attempt, 0) + 1
          _new_context = Map.put(context, :current_attempt, current_attempt)

          if current_attempt == 1 do
            {:error, Error.execution_error("first attempt fails")}
          else
            {:ok, %{result: "success on attempt #{current_attempt}"}}
          end
        end

        def run(params, _context), do: {:ok, params}
      end

      # Test immediate success (no retries needed)
      capture_log(fn ->
        assert {:ok, %{result: "immediate"}} =
                 Exec.run(RetryPatternAction, %{pattern: :immediate_success}, %{}, max_retries: 2)
      end)
    end

    test "task group and process management edge cases" do
      # Test action that spawns subtasks
      defmodule TaskSpawningAction do
        use Jido.Action,
          name: "task_spawning",
          description: "Action that spawns tasks"

        def run(_params, context) do
          if _task_group = Map.get(context, :__task_group__) do
            # Spawn a task under the task group (if available)
            {:ok, _pid} =
              Task.start(fn ->
                Process.sleep(10)
              end)
          end

          {:ok, %{spawned: true}}
        end
      end

      capture_log(fn ->
        assert {:ok, %{spawned: true}} =
                 Exec.run(TaskSpawningAction, %{}, %{}, timeout: 1000)
      end)
    end

    test "action result normalization edge cases" do
      defmodule ResultNormalizationAction do
        use Jido.Action,
          name: "result_normalization",
          description: "Action with various result types"

        def run(%{result_type: :standard_ok}, _context) do
          {:ok, %{standard: true}}
        end

        def run(%{result_type: :three_tuple_ok}, _context) do
          {:ok, %{three_tuple: true}, %{directive: "test"}}
        end

        def run(%{result_type: :three_tuple_error}, _context) do
          {:error, Error.execution_error("three tuple error"), %{directive: "error"}}
        end

        def run(%{result_type: :raw_value}, _context) do
          # Return raw value (not ok/error tuple)
          %{raw: true}
        end

        def run(params, _context), do: {:ok, params}
      end

      # Test standard success
      capture_log(fn ->
        assert {:ok, %{standard: true}} =
                 Exec.run(ResultNormalizationAction, %{result_type: :standard_ok}, %{}, [])
      end)

      # Test three-tuple success
      capture_log(fn ->
        assert {:ok, %{three_tuple: true}, %{directive: "test"}} =
                 Exec.run(ResultNormalizationAction, %{result_type: :three_tuple_ok}, %{}, [])
      end)

      # Test three-tuple error
      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}, %{directive: "error"}} =
                 Exec.run(ResultNormalizationAction, %{result_type: :three_tuple_error}, %{}, [])
      end)

      # Test raw value (gets validated as output)
      capture_log(fn ->
        assert {:ok, %{raw: true}} =
                 Exec.run(ResultNormalizationAction, %{result_type: :raw_value}, %{}, [])
      end)
    end

    test "async execution edge case coverage" do
      # Test await with normal process exit and delayed result
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 50}, %{}, timeout: 200)

        # Test successful await
        assert {:ok, %{}} = Exec.await(async_ref, 300)
      end)

      # Test cancellation edge cases
      capture_log(fn ->
        async_ref = Exec.run_async(DelayAction, %{delay: 1000}, %{}, timeout: 2000)

        # Cancel immediately
        assert :ok = Exec.cancel(async_ref)
      end)
    end

    test "validation edge cases" do
      # Test action without validate_output/1 function (should skip validation)
      defmodule NoValidateOutputAction do
        use Jido.Action,
          name: "no_validate_output",
          description: "Action without validate_output"

        def run(params, _context), do: {:ok, params}

        # Don't override validate_output - should use default
      end

      capture_log(fn ->
        assert {:ok, %{value: 42}} =
                 Exec.run(NoValidateOutputAction, %{value: 42}, %{}, [])
      end)
    end

    test "compensation edge cases with timeout from opts" do
      # Test compensation timeout coming from execution options
      defmodule CompensationOptsAction do
        use Jido.Action,
          name: "compensation_opts",
          description: "Action testing compensation with opts",
          compensation: [enabled: true]

        def run(_params, _context) do
          {:error, Error.execution_error("test error")}
        end

        def on_error(_params, _error, _context, _opts) do
          Process.sleep(200)
          {:ok, %{compensated: true}}
        end
      end

      capture_log(fn ->
        assert {:error, %Error.ExecutionFailureError{}} =
                 Exec.run(CompensationOptsAction, %{}, %{}, timeout: 100)
      end)
    end
  end

  describe "telemetry and monitoring coverage" do
    test "telemetry span execution" do
      # Test normal telemetry execution (not silent)
      capture_log(fn ->
        assert {:ok, %{value: 1}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, telemetry: :full)
      end)

      # Test silent telemetry
      capture_log(fn ->
        assert {:ok, %{value: 2}} =
                 Exec.run(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, telemetry: :silent)
      end)
    end
  end

  describe "configuration function coverage" do
    test "configuration functions with different app env states" do
      # These are already tested in other files, but let's ensure they're hit
      original_env = Application.get_all_env(:jido_action)

      try do
        # Clear all environment
        for {key, _value} <- original_env do
          Application.delete_env(:jido_action, key)
        end

        # Test with missing config (should use defaults)
        capture_log(fn ->
          assert {:ok, %{value: 1}} =
                   Exec.run(JidoTest.TestActions.BasicAction, %{value: 1}, %{}, [])
        end)

        # Test async with default timeout
        capture_log(fn ->
          async_ref = Exec.run_async(JidoTest.TestActions.BasicAction, %{value: 2}, %{}, [])
          assert {:ok, %{value: 2}} = Exec.await(async_ref)
        end)
      after
        # Restore original environment
        for {key, value} <- original_env do
          Application.put_env(:jido_action, key, value)
        end
      end
    end
  end
end
