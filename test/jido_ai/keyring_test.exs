defmodule JidoTest.AI.KeyringTest do
  # Changed to false since we're mocking
  use ExUnit.Case, async: false
  alias Jido.AI.Keyring
  @moduletag :capture_log

  import Mimic

  setup :verify_on_exit!
  setup :set_mimic_global

  setup do
    # Reset application env
    Application.delete_env(:jido_ai, :keyring)

    # Mock Dotenvy.source! to return an empty map by default
    stub(Dotenvy, :source!, fn _sources -> %{} end)

    # Mock Dotenvy.env! to raise by default
    stub(Dotenvy, :env!, fn _key, _type -> raise "Not found" end)

    :ok
  end

  describe "initialization" do
    test "loads values from environment variables" do
      # Mock Dotenvy.source! to return our test environment variables
      expect(Dotenvy, :source!, fn _sources ->
        %{
          "ANTHROPIC_API_KEY" => "test_anthropic_key",
          "OPENAI_API_KEY" => "test_openai_key",
          "TEST_ENVIRONMENT_VARIABLE" => "test_value"
        }
      end)

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

      assert Keyring.get(name, :anthropic_api_key, nil) == "test_anthropic_key"
      assert Keyring.get(name, :openai_api_key, nil) == "test_openai_key"
      assert Keyring.get(name, :test_environment_variable, nil) == "test_value"
    end

    test "returns default value when environment variables are not set" do
      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

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

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

      assert Keyring.get(name, :test_environment_variable, nil) == "app_test_value"
    end

    test "environment variables take precedence over application environment" do
      # Set application environment
      Application.put_env(:jido_ai, :keyring, %{
        test_environment_variable: "app_test_value"
      })

      # Mock Dotenvy.source! to return our test environment variables
      expect(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

      # Environment variable should win
      assert Keyring.get(name, :test_environment_variable, nil) == "env_test_value"
    end
  end

  describe "session values" do
    test "can set and get session values" do
      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

      # Set session value
      Keyring.set_session_value(name, :test_key, "session_test_value")
      assert Keyring.get_session_value(name, :test_key) == "session_test_value"
    end

    test "session values take precedence over environment variables" do
      # Mock Dotenvy.source! to return our test environment variables
      expect(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

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

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

      # Set session value
      Keyring.set_session_value(name, :test_key, "session_test_value")

      # Session value should be returned
      assert Keyring.get(name, :test_key, nil) == "session_test_value"
    end

    test "session values are isolated to the calling process" do
      # Mock Dotenvy.source! to return our test environment variables
      expect(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

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
      expect(Dotenvy, :source!, fn _sources ->
        %{"TEST_ENVIRONMENT_VARIABLE" => "env_test_value"}
      end)

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

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
      expect(Dotenvy, :source!, fn _sources ->
        %{
          "TEST_ENVIRONMENT_VARIABLE" => "env_test_value",
          "TEST_ENVIRONMENT_VARIABLE2" => "env_test_value2"
        }
      end)

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

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
      expect(Dotenvy, :source!, fn _sources ->
        %{
          "SIMPLE_VAR" => "simple_value",
          "COMPLEX-VAR.NAME" => "complex_value",
          "MIXED_case_VAR" => "mixed_value"
        }
      end)

      # Start a fresh keyring instance with unique name and registry
      name = :"keyring_#{System.unique_integer()}"
      registry = :"registry_#{System.unique_integer()}"
      {:ok, _} = Keyring.start_link(name: name, registry: registry)

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
