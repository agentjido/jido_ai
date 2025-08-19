defmodule Kodo.InstanceTest do
  use ExUnit.Case, async: false
  alias Kodo.{Instance, InstanceManager}

  setup do
    # Clean up any test instances
    test_instances = [
      :test_instance_component_1,
      :test_instance_component_2,
      :test_instance_component_3
    ]

    for instance <- test_instances do
      if InstanceManager.exists?(instance) do
        InstanceManager.stop(instance)
      end
    end

    :ok
  end

  describe "start_link/1" do
    test "starts an instance supervisor successfully" do
      instance_name = :test_instance_component_1

      assert {:ok, _pid} = InstanceManager.start(instance_name)
      assert InstanceManager.exists?(instance_name)
    end
  end

  describe "child/2" do
    test "returns session supervisor PID when it exists" do
      instance_name = :test_instance_component_2

      assert {:ok, _instance_pid} = InstanceManager.start(instance_name)

      # Give the supervisor time to start children
      Process.sleep(10)

      assert {:ok, pid} = Instance.child(instance_name, :session_supervisor)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns command registry PID when it exists" do
      instance_name = :test_instance_component_3

      assert {:ok, _instance_pid} = InstanceManager.start(instance_name)

      # Give the supervisor time to start children
      Process.sleep(10)

      assert {:ok, pid} = Instance.child(instance_name, :command_registry)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns error for non-existent component" do
      instance_name = :test_instance_component_3

      assert {:ok, _instance_pid} = InstanceManager.start(instance_name)

      assert {:error, :not_found} = Instance.child(instance_name, :non_existent_component)
    end
  end

  describe "convenience functions" do
    setup do
      instance_name = :convenience_test_instance
      {:ok, _instance_pid} = InstanceManager.start(instance_name)

      # Give the supervisor time to start children
      Process.sleep(10)

      %{instance_name: instance_name}
    end

    test "sessions/1 returns session supervisor", %{instance_name: instance_name} do
      assert {:ok, pid} = Instance.sessions(instance_name)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "commands/1 returns command registry", %{instance_name: instance_name} do
      assert {:ok, pid} = Instance.commands(instance_name)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "jobs/1 returns job manager", %{instance_name: instance_name} do
      assert {:ok, pid} = Instance.jobs(instance_name)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end


  end

  describe "registry integration" do
    test "components are registered in the global registry" do
      instance_name = :registry_test_instance

      assert {:ok, _instance_pid} = InstanceManager.start(instance_name)

      # Give the supervisor time to start children
      Process.sleep(10)

      # Check that components are registered
      assert [{_pid, _}] =
               Registry.lookup(Kodo.InstanceRegistry, {:session_supervisor, instance_name})

      assert [{_pid, _}] =
               Registry.lookup(Kodo.InstanceRegistry, {:command_registry, instance_name})

      assert [{_pid, _}] = Registry.lookup(Kodo.InstanceRegistry, {:job_manager, instance_name})
    end

    test "instance itself is registered in the global registry" do
      instance_name = :registry_instance_test

      assert {:ok, instance_pid} = InstanceManager.start(instance_name)

      assert [{^instance_pid, _}] =
               Registry.lookup(Kodo.InstanceRegistry, {:instance, instance_name})
    end
  end

  describe "session registry" do
    test "creates a session registry for each instance" do
      instance_name = :session_registry_test

      assert {:ok, _instance_pid} = InstanceManager.start(instance_name)

      # Give the supervisor time to start children
      Process.sleep(10)

      session_registry_atom = String.to_atom("Kodo.SessionRegistry.#{instance_name}")

      # The registry should exist and be alive
      assert Process.whereis(session_registry_atom) != nil
      assert Process.alive?(Process.whereis(session_registry_atom))
    end
  end

  describe "fault tolerance" do
    test "instance supervisor restarts failed components" do
      instance_name = :fault_tolerance_test

      assert {:ok, _instance_pid} = InstanceManager.start(instance_name)

      # Give the supervisor time to start children
      Process.sleep(10)

      # Get the original command registry PID
      assert {:ok, original_pid} = Instance.commands(instance_name)

      # Kill the command registry
      Process.exit(original_pid, :kill)

      # Give the supervisor time to restart
      Process.sleep(50)

      # Should have a new PID (restarted)
      assert {:ok, new_pid} = Instance.commands(instance_name)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end
  end
end
