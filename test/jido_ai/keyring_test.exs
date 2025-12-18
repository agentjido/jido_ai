defmodule JidoTest.AI.KeyringTest do
  # Changed to false since we're mocking
  use ExUnit.Case, async: false
  alias Jido.AI.Keyring
  @moduletag :capture_log

  import Mimic

  setup :verify_on_exit!
  setup :set_mimic_global

  setup do
    # Copy modules for mocking
    Mimic.copy(Dotenvy)
    Mimic.copy(JidoKeys)

    # Reset application env
    Application.delete_env(:jido_ai, :keyring)

    # Create or clear ETS table to track test keyrings (shared across processes)
    # Use named table so it's accessible from helper functions
    case :ets.whereis(:test_keyrings) do
      :undefined -> :ets.new(:test_keyrings, [:set, :public, :named_table])
      _ref -> :ets.delete_all_objects(:test_keyrings)
    end

    # Mock Dotenvy.source! to return an empty map by default
    stub(Dotenvy, :source!, fn _sources -> %{} end)

    # Mock Dotenvy.env! to raise by default
    stub(Dotenvy, :env!, fn _key, _type -> raise "Not found" end)

    # Mock JidoKeys.get to read from Keyring's state instead of its own storage
    # This is necessary because Keyring.get() calls JidoKeys.get(), but the tests
    # mock Dotenvy which populates Keyring's ETS cache, not JidoKeys
    stub(JidoKeys, :get, fn key, default ->
      # Try to find a keyring that has this value in the ETS table
      case :ets.match(:test_keyrings, {:"$1", :"$2"}) do
        [] ->
          # No keyrings registered
          default

        keyrings ->
          # Try each registered keyring
          result =
            Enum.find_value(keyrings, fn [keyring_name, _pid] ->
              try do
                case GenServer.call(keyring_name, {:get_value, key, nil}) do
                  nil -> nil
                  value -> value
                end
              catch
                :exit, _ -> nil
              end
            end)

          result || default
      end
    end)

    on_exit(fn ->
      # Don't delete the table, just clear it - it might be reused by other tests
      try do
        :ets.delete_all_objects(:test_keyrings)
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  # Helper function to start a keyring with automatic cleanup
  defp start_test_keyring do
    name = :"keyring_#{System.unique_integer()}"
    registry = :"registry_#{System.unique_integer()}"
    {:ok, pid} = Keyring.start_link(name: name, registry: registry)

    # Register keyring in ETS table so JidoKeys.get stub can find it
    :ets.insert(:test_keyrings, {name, pid})

    on_exit(fn ->
      try do
        GenServer.stop(name, :normal, 1000)
      catch
        :exit, _ -> :ok
      end

      # Remove from tracking table (check if table still exists)
      try do
        if :ets.whereis(:test_keyrings) != :undefined do
          :ets.delete(:test_keyrings, name)
        end
      catch
        _, _ -> :ok
      end
    end)

    {name, registry, pid}
  end

  describe "initialization" do
    test "loads values from environment variables" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{
          "ANTHROPIC_API_KEY" => "test_anthropic_key",
          "OPENAI_API_KEY" => "test_openai_key",
          "TEST_ENVIRONMENT_VARIABLE" => "test_value"
        }
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      assert Keyring.get(name, :anthropic_api_key, nil) == "test_anthropic_key"
      assert Keyring.get(name, :openai_api_key, nil) == "test_openai_key"
      assert Keyring.get(name, :test_environment_variable, nil) == "test_value"
    end

    test "returns default value when environment variables are not set" do
      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Should return the default value
      assert Keyring.get(name, :test_environment_variable, "default_value") == "default_value"
    end
  end

  describe "application environment" do
    test "respects application environment settings" do
      # Set application environment
      Application.put_env(:jido_ai, :keyring, %{
        test_environment_variable: "app_test_value"
      })

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      assert Keyring.get(name, :test_environment_variable, nil) == "app_test_value"
    end

    test "environment variables take precedence over application environment" do
      # Set application environment
      Application.put_env(:jido_ai, :keyring, %{
        test_environment_variable: "app_test_value"
      })

      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Environment variable should win
      assert Keyring.get(name, :test_environment_variable, nil) == "env_test_value"
    end
  end

  describe "session values" do
    test "can set and get session values" do
      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Set session value
      Keyring.set_session_value(name, :test_key, "session_test_value")
      assert Keyring.get_session_value(name, :test_key) == "session_test_value"
    end

    test "session values take precedence over environment variables" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Set session value
      Keyring.set_session_value(name, :test_environment_variable, "session_test_value")

      # Session value should be returned
      assert Keyring.get(name, :test_environment_variable, nil) == "session_test_value"
    end

    test "session values take precedence over application environment" do
      # Set application environment
      Application.put_env(:jido_ai, :keyring, %{
        test_key: "app_test_value"
      })

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Set session value
      Keyring.set_session_value(name, :test_key, "session_test_value")

      # Session value should be returned
      assert Keyring.get(name, :test_key, nil) == "session_test_value"
    end

    test "session values are isolated to the calling process" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Set session value in this process
      Keyring.set_session_value(name, :test_environment_variable, "session_test_value")

      # Spawn another process to check values
      task =
        Task.async(fn ->
          # Should get env value, not session value from parent process
          Keyring.get(name, :test_environment_variable, nil)
        end)

      other_process_value = Task.await(task)

      # Other process should get env value
      assert other_process_value == "env_test_value"
      # This process should get session value
      assert Keyring.get(name, :test_environment_variable, nil) == "session_test_value"
    end

    test "clearing session value falls back to environment" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Set and verify session value
      Keyring.set_session_value(name, :test_environment_variable, "session_test_value")
      assert Keyring.get(name, :test_environment_variable, nil) == "session_test_value"

      # Clear session value
      Keyring.clear_session_value(name, :test_environment_variable)

      # Should fall back to env var
      assert Keyring.get(name, :test_environment_variable, nil) == "env_test_value"
    end

    test "clearing all session values falls back to environment" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{
          "TEST_ENVIRONMENT_VARIABLE" => "env_test_value",
          "TEST_ENVIRONMENT_VARIABLE2" => "env_test_value2"
        }
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Set session values
      Keyring.set_session_value(name, :test_environment_variable, "session_test_value")
      Keyring.set_session_value(name, :test_environment_variable2, "session_test_value2")

      # Verify session values
      assert Keyring.get(name, :test_environment_variable, nil) == "session_test_value"
      assert Keyring.get(name, :test_environment_variable2, nil) == "session_test_value2"

      # Clear all session values
      Keyring.clear_all_session_values(name)

      # Should fall back to env vars
      assert Keyring.get(name, :test_environment_variable, nil) == "env_test_value"
      assert Keyring.get(name, :test_environment_variable2, nil) == "env_test_value2"
    end
  end

  describe "session values with explicit PID" do
    test "can set and get session values for another process" do
      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Create another process
      {pid, ref} = spawn_monitor(fn -> Process.sleep(5000) end)

      # Set session value for the other process
      Keyring.set_session_value(name, :test_key, "other_process_value", pid)

      # Set different value for current process
      Keyring.set_session_value(name, :test_key, "current_process_value")

      # Check that the values are separate
      assert Keyring.get_session_value(name, :test_key, pid) == "other_process_value"
      assert Keyring.get_session_value(name, :test_key) == "current_process_value"

      # Check that get/4 works with explicit PID
      assert Keyring.get(name, :test_key, nil, pid) == "other_process_value"
      assert Keyring.get(name, :test_key) == "current_process_value"

      # Clean up the spawned process
      Process.demonitor(ref, [:flush])
      Process.exit(pid, :kill)
    end

    test "can clear session values for specific process" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Create another process
      {pid, ref} = spawn_monitor(fn -> Process.sleep(5000) end)

      # Set session values for both processes
      Keyring.set_session_value(name, :test_key, "other_process_value", pid)
      Keyring.set_session_value(name, :test_key, "current_process_value")

      # Clear just the other process's value
      Keyring.clear_session_value(name, :test_key, pid)

      # Check current process value is preserved
      assert Keyring.get_session_value(name, :test_key, pid) == nil
      assert Keyring.get_session_value(name, :test_key) == "current_process_value"

      # Clean up the spawned process
      Process.demonitor(ref, [:flush])
      Process.exit(pid, :kill)
    end

    test "can clear all session values for specific process" do
      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Create another process
      {pid, ref} = spawn_monitor(fn -> Process.sleep(5000) end)

      # Set multiple session values for both processes
      Keyring.set_session_value(name, :test_key1, "other_process_value1", pid)
      Keyring.set_session_value(name, :test_key2, "other_process_value2", pid)
      Keyring.set_session_value(name, :test_key1, "current_process_value1")
      Keyring.set_session_value(name, :test_key2, "current_process_value2")

      # Clear all values for the other process
      Keyring.clear_all_session_values(name, pid)

      # Check current process values are preserved
      assert Keyring.get_session_value(name, :test_key1, pid) == nil
      assert Keyring.get_session_value(name, :test_key2, pid) == nil
      assert Keyring.get_session_value(name, :test_key1) == "current_process_value1"
      assert Keyring.get_session_value(name, :test_key2) == "current_process_value2"

      # Clean up the spawned process
      Process.demonitor(ref, [:flush])
      Process.exit(pid, :kill)
    end

    test "get/4 falls back to environment variables when no session value for a process" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{"TEST_KEY" => "env_test_value"}
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Create another process
      {pid, ref} = spawn_monitor(fn -> Process.sleep(5000) end)

      # Only set value for current process
      Keyring.set_session_value(name, :test_key, "current_process_value")

      # For other process it should fall back to environment
      assert Keyring.get(name, :test_key, nil, pid) == "env_test_value"
      assert Keyring.get(name, :test_key) == "current_process_value"

      # Clean up the spawned process
      Process.demonitor(ref, [:flush])
      Process.exit(pid, :kill)
    end
  end

  describe "value validation" do
    test "has_value? correctly identifies valid values" do
      assert Keyring.has_value?("valid_value")
      refute Keyring.has_value?(nil)
      refute Keyring.has_value?("")
    end
  end

  describe "environment variable conversion" do
    test "converts environment variable names to atoms correctly" do
      # Mock Dotenvy.source! to return our test environment variables
      stub(Dotenvy, :source!, fn _sources ->
        %{
          "SIMPLE_VAR" => "simple_value",
          "COMPLEX-VAR.NAME" => "complex_value",
          "MIXED_case_VAR" => "mixed_value"
        }
      end)

      # Start a fresh keyring instance with automatic cleanup
      {name, _registry, _pid} = start_test_keyring()

      # Check that the environment variables were converted to atoms correctly
      assert Keyring.get(name, :simple_var, nil) == "simple_value"
      assert Keyring.get(name, :complex_var_name, nil) == "complex_value"
      assert Keyring.get(name, :mixed_case_var, nil) == "mixed_value"
    end
  end

  describe "get_env_var" do
    test "returns default when variable is not set" do
      # Mock Dotenvy.env! to raise an error
      expect(Dotenvy, :env!, fn _key, _type -> raise "Not found" end)

      assert Keyring.get_env_var("NONEXISTENT_VAR", "default") == "default"
    end

    test "returns value when variable is set" do
      # Mock Dotenvy.env! to return a value
      expect(Dotenvy, :env!, fn "EXISTENT_VAR", :string -> "value" end)

      assert Keyring.get_env_var("EXISTENT_VAR", "default") == "value"
    end
  end
end
