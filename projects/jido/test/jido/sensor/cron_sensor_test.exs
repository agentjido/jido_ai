defmodule JidoTest.CronTest do
  @moduledoc false
  use JidoTest.Case, async: true
  import ExUnit.CaptureLog

  import Crontab.CronExpression, only: [sigil_e: 2]

  alias Jido.Sensors.Cron
  alias Jido.Signal

  @moduletag :capture_log

  setup do
    {:ok, test_pid: self()}
  end

  describe "Cron integration with Quantum" do
    test "adds and executes a scheduled job", %{test_pid: test_pid} do
      capture_log(fn ->
        {:ok, sensor_pid} =
          Cron.start_link(
            id: "test_cron_sensor",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler
          )

        schedule = ~e"* * * * * *"e
        :ok = Cron.add_job(sensor_pid, :test_job, schedule, :dummy_task)

        assert_eventually(
          fn ->
            receive do
              {:signal, {:ok, %Signal{} = signal}} ->
                signal.type == "cron_trigger" and signal.data.name == :test_job
            after
              0 -> false
            end
          end,
          timeout: 1000
        )

        # Cleanup
        :ok = Cron.remove_job(sensor_pid, :test_job)
      end)
    end

    test "can specify multiple jobs at startup", %{test_pid: test_pid} do
      capture_log(fn ->
        {:ok, sensor_pid} =
          Cron.start_link(
            id: "multi_cron_sensor",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler,
            jobs: [
              # auto-named
              {~e"* * * * * *"e, :auto_task},
              # manual named
              {:named_job, ~e"* * * * * *"e, :named_task}
            ]
          )

        # Create a reference point for collecting signals
        signals_ref = :ets.new(:signals, [:set, :public])

        assert_eventually(
          fn ->
            receive do
              {:signal, {:ok, %Signal{} = signal}} ->
                :ets.insert(signals_ref, {System.system_time(), signal})
            after
              0 -> :ok
            end

            signals = :ets.tab2list(signals_ref) |> Enum.map(fn {_ts, signal} -> signal end)

            length(signals) >= 2 and
              Enum.all?(signals, &(&1.type == "cron_trigger")) and
              Enum.any?(signals, &(&1.data.name == :named_job))
          end,
          timeout: 2000
        )

        # Cleanup
        :ets.delete(signals_ref)
        :ok = Cron.remove_job(sensor_pid, :named_job)
      end)
    end

    test "runs job immediately on demand", %{test_pid: test_pid} do
      capture_log(fn ->
        {:ok, sensor_pid} =
          Cron.start_link(
            id: "test_cron_sensor_immediate",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler
          )

        # something that won't trigger soon
        schedule = ~e"0 0 * * *"e
        :ok = Cron.add_job(sensor_pid, :immediate_job, schedule, :dummy_task)

        :ok = Cron.run_job(sensor_pid, :immediate_job)

        assert_eventually(
          fn ->
            receive do
              {:signal, {:ok, %Signal{} = signal}} ->
                signal.type == "cron_trigger" and signal.data.name == :immediate_job
            after
              0 -> false
            end
          end,
          timeout: 500
        )

        # Cleanup
        :ok = Cron.remove_job(sensor_pid, :immediate_job)
      end)
    end

    test "activate/deactivate a job", %{test_pid: test_pid} do
      capture_log(fn ->
        {:ok, sensor_pid} =
          Cron.start_link(
            id: "test_cron_sensor_toggle",
            target: {:pid, target: test_pid},
            scheduler: Jido.Scheduler
          )

        schedule = ~e"* * * * * *"e
        :ok = Cron.add_job(sensor_pid, :toggle_job, schedule, :dummy_task)
        # Deactivate it
        :ok = Cron.deactivate_job(sensor_pid, :toggle_job)

        # Verify no signals received for 750ms
        Process.sleep(750)
        refute_received {:signal, {:ok, _}}

        # Activate it
        :ok = Cron.activate_job(sensor_pid, :toggle_job)

        assert_eventually(
          fn ->
            receive do
              {:signal, {:ok, %Signal{}}} -> true
            after
              0 -> false
            end
          end,
          timeout: 750
        )

        # Cleanup
        :ok = Cron.remove_job(sensor_pid, :toggle_job)
      end)
    end
  end
end
