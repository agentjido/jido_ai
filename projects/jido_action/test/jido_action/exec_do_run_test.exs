defmodule JidoTest.ExecDoRunTest do
  use JidoTest.ActionCase, async: false
  use Mimic

  import ExUnit.CaptureLog

  alias Jido.Exec
  alias JidoTest.TestActions.BasicAction
  alias JidoTest.TestActions.ErrorAction
  alias JidoTest.TestActions.RetryAction

  @attempts_table :action_do_run_test_attempts

  @attempts_table :action_do_run_test_attempts

  setup :set_mimic_global

  setup do
    Logger.put_process_level(self(), :debug)

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

  describe "do_run/3" do
    test "executes action with full telemetry" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} =
                   Exec.do_run(BasicAction, %{value: 5}, %{},
                     telemetry: :full,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.BasicAction"
      assert log =~ "Finished execution of JidoTest.TestActions.BasicAction"
      verify!()
    end

    test "executes action with minimal telemetry" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} =
                   Exec.do_run(BasicAction, %{value: 5}, %{},
                     telemetry: :minimal,
                     log_level: :debug
                   )
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.BasicAction"
      assert log =~ "Finished execution of JidoTest.TestActions.BasicAction"
      verify!()
    end

    test "executes action in silent mode" do
      Mimic.reject(&System.monotonic_time/1)

      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} =
                   Exec.do_run(BasicAction, %{value: 5}, %{},
                     telemetry: :silent,
                     timeout: 0
                   )
        end)

      assert log == ""
      verify!()
    end

    test "handles action error" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      log =
        capture_log(fn ->
          assert {:error, _} =
                   Exec.do_run(ErrorAction, %{}, %{}, telemetry: :full, log_level: :debug)
        end)

      assert log =~ "Starting execution of JidoTest.TestActions.ErrorAction"
      assert log =~ "Action JidoTest.TestActions.ErrorAction failed"
      verify!()
    end
  end

  describe "do_run_with_retry/4" do
    test "succeeds on first try" do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      capture_log(fn ->
        assert {:ok, %{value: 5}} =
                 Exec.do_run_with_retry(BasicAction, %{value: 5}, %{}, [])
      end)

      verify!()
    end

    test "retries on error and then succeeds", %{attempts_table: attempts_table} do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      capture_log(fn ->
        result =
          Exec.do_run_with_retry(
            RetryAction,
            %{max_attempts: 3, failure_type: :error},
            %{attempts_table: attempts_table},
            max_retries: 2,
            backoff: 10
          )

        assert {:ok, %{result: "success after 3 attempts"}} = result
        assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
      end)

      verify!()
    end

    test "retries on exception and then succeeds", %{attempts_table: attempts_table} do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      capture_log(fn ->
        result =
          Exec.do_run_with_retry(
            RetryAction,
            %{max_attempts: 3, failure_type: :exception},
            %{attempts_table: attempts_table},
            max_retries: 2,
            backoff: 10
          )

        assert {:ok, %{result: "success after 3 attempts"}} = result
        assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
      end)

      verify!()
    end

    test "fails after max retries", %{attempts_table: attempts_table} do
      stub(:telemetry, :execute, fn _, _, _ -> :ok end)

      capture_log(fn ->
        result =
          Exec.do_run_with_retry(
            RetryAction,
            %{max_attempts: 5, failure_type: :error},
            %{attempts_table: attempts_table},
            max_retries: 2,
            backoff: 10
          )

        assert {:error, _} = result
        assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
      end)

      verify!()
    end
  end
end
