defmodule Kodo.InstanceManagerTest do
  use ExUnit.Case, async: false

  alias Kodo.InstanceManager

  setup do
    # Ensure InstanceManager is running
    case GenServer.whereis(InstanceManager) do
      nil ->
        {:ok, _pid} = InstanceManager.start_link([])
        :ok

      _pid ->
        :ok
    end

    # Clean up any test instances
    on_exit(fn ->
      for instance <- InstanceManager.list() do
        if instance != :default do
          InstanceManager.stop(instance)
        end
      end
    end)

    :ok
  end

  describe "start/1" do
    test "starts a new instance" do
      instance = Kodo.Case.unique_atom("test_instance")
      assert {:ok, pid} = InstanceManager.start(instance)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns existing instance if already started" do
      instance = Kodo.Case.unique_atom("test_instance")
      assert {:ok, pid1} = InstanceManager.start(instance)
      assert {:ok, pid2} = InstanceManager.start(instance)
      assert pid1 == pid2
    end

    test "fails with invalid name" do
      assert_raise FunctionClauseError, fn ->
        InstanceManager.start("invalid_name")
      end
    end
  end

  describe "stop/1" do
    test "stops an existing instance" do
      instance = Kodo.Case.unique_atom("test_instance")
      {:ok, _pid} = InstanceManager.start(instance)
      assert :ok = InstanceManager.stop(instance)
      refute InstanceManager.exists?(instance)
    end

    test "returns error for non-existent instance" do
      assert {:error, :not_found} = InstanceManager.stop(:non_existent)
    end
  end

  describe "get/1" do
    test "returns pid for existing instance" do
      instance = Kodo.Case.unique_atom("test_instance")
      {:ok, expected_pid} = InstanceManager.start(instance)
      assert {:ok, pid} = InstanceManager.get(instance)
      assert pid == expected_pid
    end

    test "returns error for non-existent instance" do
      assert {:error, :not_found} = InstanceManager.get(:non_existent)
    end
  end

  describe "list/0" do
    test "returns list of all instances" do
      instances = InstanceManager.list()
      assert is_list(instances)
      assert :default in instances
    end

    test "includes newly created instances" do
      instance1 = Kodo.Case.unique_atom("test_instance1")
      instance2 = Kodo.Case.unique_atom("test_instance2")
      InstanceManager.start(instance1)
      InstanceManager.start(instance2)

      instances = InstanceManager.list()
      assert instance1 in instances
      assert instance2 in instances
    end
  end

  describe "exists?/1" do
    test "returns true for existing instance" do
      instance = Kodo.Case.unique_atom("test_instance")
      InstanceManager.start(instance)
      assert InstanceManager.exists?(instance)
    end

    test "returns false for non-existent instance" do
      refute InstanceManager.exists?(:non_existent)
    end
  end

  describe "process monitoring" do
    test "removes instance from list when process dies" do
      instance = Kodo.Case.unique_atom("test_instance")
      {:ok, pid} = InstanceManager.start(instance)
      assert InstanceManager.exists?(instance)

      # Kill the instance process
      Process.exit(pid, :kill)

      # Wait for monitor to process the DOWN message
      Process.sleep(10)

      refute InstanceManager.exists?(instance)
    end
  end
end
