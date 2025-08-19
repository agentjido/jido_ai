defmodule Kodo.InstanceManagerTest do
  use ExUnit.Case, async: false
  alias Kodo.InstanceManager

  # Helper function to wait for a condition to become true
  defp eventually(fun, timeout \\ 1000, sleep_time \\ 50) do
    eventually_loop(fun, timeout, sleep_time, System.monotonic_time(:millisecond))
  end

  defp eventually_loop(fun, timeout, sleep_time, start_time) do
    if fun.() do
      :ok
    else
      current_time = System.monotonic_time(:millisecond)
      if current_time - start_time >= timeout do
        flunk("Condition not met within #{timeout}ms")
      else
        Process.sleep(sleep_time)
        eventually_loop(fun, timeout, sleep_time, start_time)
      end
    end
  end

  setup do
    # Stop any existing instances from previous tests
    existing_instances = InstanceManager.list()

    for instance <- existing_instances do
      if instance != :default do
        case InstanceManager.stop(instance) do
          {:ok, :stopping} ->
            # Wait for stop completion
            ref = InstanceManager.monitor_operation(instance, :stop)
            receive do
              {:instance_operation, ^ref, ^instance, _result} -> :ok
            after
              1000 -> :timeout
            end
          {:error, :not_found} -> :ok
        end
      end
    end

    :ok
  end

  describe "start/1" do
    test "starts a new instance successfully" do
      instance_name = :test_instance_1

      assert {:ok, :starting} = InstanceManager.start(instance_name)
      
      # Wait for the instance to actually start by polling get/1
      eventually(fn ->
        case InstanceManager.get(instance_name) do
          {:ok, pid} when is_pid(pid) -> 
            assert Process.alive?(pid)
            true
          {:ok, :starting} -> false
          {:error, _} -> false
        end
      end, 1000, 50)
    end

    test "returns existing PID when instance already exists" do
      instance_name = :test_instance_2

      # First start
      assert {:ok, :starting} = InstanceManager.start(instance_name)
      
      # Wait for first start to complete
      eventually(fn ->
        case InstanceManager.get(instance_name) do
          {:ok, pid} when is_pid(pid) -> true
          _ -> false
        end
      end)
      
      {:ok, pid1} = InstanceManager.get(instance_name)
      
      # Second start should return existing PID
      assert {:ok, pid2} = InstanceManager.start(instance_name)
      assert pid1 == pid2
    end

    test "can start multiple instances with different names" do
      assert {:ok, :starting} = InstanceManager.start(:instance_a)
      assert {:ok, :starting} = InstanceManager.start(:instance_b)
      
      ref_a = InstanceManager.monitor_operation(:instance_a, :start)
      ref_b = InstanceManager.monitor_operation(:instance_b, :start)

      # Wait for both to complete
      pid_a = receive do
        {:instance_operation, ^ref_a, :instance_a, {:ok, pid}} -> pid
      after
        1000 -> flunk("Instance A start timed out")
      end

      pid_b = receive do
        {:instance_operation, ^ref_b, :instance_b, {:ok, pid}} -> pid
      after
        1000 -> flunk("Instance B start timed out")
      end

      assert pid_a != pid_b
      assert Process.alive?(pid_a)
      assert Process.alive?(pid_b)
    end
  end

  describe "stop/1" do
    test "stops an existing instance" do
      instance_name = :test_instance_3

      # Start instance first
      assert {:ok, :starting} = InstanceManager.start(instance_name)
      start_ref = InstanceManager.monitor_operation(instance_name, :start)
      
      pid = receive do
        {:instance_operation, ^start_ref, ^instance_name, {:ok, pid}} -> pid
      after
        1000 -> flunk("Start operation timed out")
      end

      assert Process.alive?(pid)

      # Stop the instance
      assert {:ok, :stopping} = InstanceManager.stop(instance_name)
      stop_ref = InstanceManager.monitor_operation(instance_name, :stop)

      receive do
        {:instance_operation, ^stop_ref, ^instance_name, :stopped} ->
          refute Process.alive?(pid)
      after
        1000 -> flunk("Stop operation timed out")
      end
    end

    test "returns error when trying to stop non-existent instance" do
      assert {:error, :not_found} = InstanceManager.stop(:non_existent_instance)
    end
  end

  describe "get/1" do
    test "returns PID for existing instance" do
      instance_name = :test_instance_4

      assert {:ok, :starting} = InstanceManager.start(instance_name)
      
      # Should return :starting while instance is starting
      assert {:ok, :starting} = InstanceManager.get(instance_name)
      
      # Wait for start to complete
      ref = InstanceManager.monitor_operation(instance_name, :start)
      
      receive do
        {:instance_operation, ^ref, ^instance_name, {:ok, pid}} ->
          assert {:ok, ^pid} = InstanceManager.get(instance_name)
      after
        1000 -> flunk("Start operation timed out")
      end
    end

    test "returns error for non-existent instance" do
      assert {:error, :not_found} = InstanceManager.get(:non_existent_instance)
    end

    test "returns stopping state during stop operation" do
      instance_name = :test_instance_get_stopping

      # Start instance
      assert {:ok, :starting} = InstanceManager.start(instance_name)
      start_ref = InstanceManager.monitor_operation(instance_name, :start)
      
      receive do
        {:instance_operation, ^start_ref, ^instance_name, {:ok, _pid}} -> :ok
      after
        1000 -> flunk("Start operation timed out")
      end

      # Stop instance
      assert {:ok, :stopping} = InstanceManager.stop(instance_name)
      assert {:ok, :stopping} = InstanceManager.get(instance_name)

      # Wait for stop to complete
      stop_ref = InstanceManager.monitor_operation(instance_name, :stop)
      
      receive do
        {:instance_operation, ^stop_ref, ^instance_name, :stopped} ->
          assert {:error, :not_found} = InstanceManager.get(instance_name)
      after
        1000 -> flunk("Stop operation timed out")
      end
    end
  end

  describe "list/0" do
    test "includes default instance on startup" do
      instances = InstanceManager.list()
      assert :default in instances
    end

    test "lists all active instances" do
      # Start some test instances
      assert {:ok, :starting} = InstanceManager.start(:list_test_1)
      assert {:ok, :starting} = InstanceManager.start(:list_test_2)

      # Wait for both to complete
      ref1 = InstanceManager.monitor_operation(:list_test_1, :start)
      ref2 = InstanceManager.monitor_operation(:list_test_2, :start)

      receive do
        {:instance_operation, ^ref1, :list_test_1, {:ok, _}} -> :ok
      after
        1000 -> flunk("list_test_1 start timed out")
      end

      receive do
        {:instance_operation, ^ref2, :list_test_2, {:ok, _}} -> :ok
      after
        1000 -> flunk("list_test_2 start timed out")
      end

      instances = InstanceManager.list()

      assert :default in instances
      assert :list_test_1 in instances
      assert :list_test_2 in instances
    end

    test "removes instances from list when stopped" do
      instance_name = :list_test_3

      assert {:ok, :starting} = InstanceManager.start(instance_name)
      start_ref = InstanceManager.monitor_operation(instance_name, :start)

      receive do
        {:instance_operation, ^start_ref, ^instance_name, {:ok, _}} ->
          assert instance_name in InstanceManager.list()
      after
        1000 -> flunk("Start operation timed out")
      end

      assert {:ok, :stopping} = InstanceManager.stop(instance_name)
      stop_ref = InstanceManager.monitor_operation(instance_name, :stop)

      receive do
        {:instance_operation, ^stop_ref, ^instance_name, :stopped} ->
          refute instance_name in InstanceManager.list()
      after
        1000 -> flunk("Stop operation timed out")
      end
    end
  end

  describe "exists?/1" do
    test "returns true for existing instance" do
      instance_name = :test_instance_5

      assert {:ok, :starting} = InstanceManager.start(instance_name)
      # Should return true even during startup
      assert InstanceManager.exists?(instance_name)

      ref = InstanceManager.monitor_operation(instance_name, :start)
      receive do
        {:instance_operation, ^ref, ^instance_name, {:ok, _}} ->
          assert InstanceManager.exists?(instance_name)
      after
        1000 -> flunk("Start operation timed out")
      end
    end

    test "returns false for non-existent instance" do
      refute InstanceManager.exists?(:non_existent_instance)
    end

    test "returns false after instance is stopped" do
      instance_name = :test_instance_6

      assert {:ok, :starting} = InstanceManager.start(instance_name)
      assert InstanceManager.exists?(instance_name)

      start_ref = InstanceManager.monitor_operation(instance_name, :start)
      receive do
        {:instance_operation, ^start_ref, ^instance_name, {:ok, _}} -> :ok
      after
        1000 -> flunk("Start operation timed out")
      end

      assert {:ok, :stopping} = InstanceManager.stop(instance_name)
      # Should still return true during stopping
      assert InstanceManager.exists?(instance_name)

      stop_ref = InstanceManager.monitor_operation(instance_name, :stop)
      receive do
        {:instance_operation, ^stop_ref, ^instance_name, :stopped} ->
          refute InstanceManager.exists?(instance_name)
      after
        1000 -> flunk("Stop operation timed out")
      end
    end
  end

  describe "process monitoring" do
    test "cleans up state when instance process crashes" do
      instance_name = :crash_test_instance

      assert {:ok, :starting} = InstanceManager.start(instance_name)
      ref = InstanceManager.monitor_operation(instance_name, :start)

      pid = receive do
        {:instance_operation, ^ref, ^instance_name, {:ok, pid}} -> pid
      after
        1000 -> flunk("Start operation timed out")
      end

      assert InstanceManager.exists?(instance_name)

      # Kill the instance process
      Process.exit(pid, :kill)

      # Wait for the DOWN message to be processed
      Process.sleep(50)

      refute InstanceManager.exists?(instance_name)
      refute instance_name in InstanceManager.list()
    end
  end

  describe "default instance" do
    test "default instance is started automatically" do
      assert InstanceManager.exists?(:default)
      assert {:ok, _pid} = InstanceManager.get(:default)
    end
  end
end
