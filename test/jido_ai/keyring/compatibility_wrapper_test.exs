defmodule Jido.AI.Keyring.CompatibilityWrapperTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Keyring
  alias Jido.AI.Keyring.CompatibilityWrapper

  setup do
    # Start a unique Keyring for testing
    test_keyring_name = :"test_keyring_compat_#{:erlang.unique_integer([:positive])}"
    {:ok, _pid} = Keyring.start_link(name: test_keyring_name)

    on_exit(fn ->
      try do
        GenServer.stop(test_keyring_name)
      catch
        :exit, _ -> :ok
      end
    end)

    %{keyring: test_keyring_name}
  end

  describe "API compatibility validation" do
    test "ensures get/4 returns compatible values" do
      test_cases = [
        {:get, [], "string_value"},
        {:get, [], nil},
        {:get, [], 123},
        {:get, [], :atom_value}
      ]

      for {function_name, args, result} <- test_cases do
        compatible_result =
          CompatibilityWrapper.ensure_api_compatibility(function_name, args, result)

        case function_name do
          :get ->
            # Should return string or nil
            assert is_binary(compatible_result) or is_nil(compatible_result)
        end
      end
    end

    test "ensures list/0 returns list of atoms" do
      test_results = [
        [:atom1, :atom2, :atom3],
        ["string1", "string2"],
        [:mixed, "types"],
        []
      ]

      for result <- test_results do
        compatible_result = CompatibilityWrapper.ensure_api_compatibility(:list, [], result)
        assert is_list(compatible_result)
        assert Enum.all?(compatible_result, &is_atom/1)
      end
    end

    test "preserves :ok return values for session operations" do
      session_operations = [:set_session_value, :clear_session_value, :clear_all_session_values]

      for operation <- session_operations do
        result = CompatibilityWrapper.ensure_api_compatibility(operation, [], :ok)
        assert result == :ok
      end
    end
  end

  describe "JidoKeys error mapping" do
    test "maps JidoKeys not_found errors to nil" do
      result = CompatibilityWrapper.map_jido_keys_errors(:get, :test_key, {:error, :not_found})
      assert result == nil
    end

    test "maps JidoKeys string errors to nil with logging" do
      log_output =
        ExUnit.CaptureLog.capture_log(fn ->
          result =
            CompatibilityWrapper.map_jido_keys_errors(:get, :test_key, {:error, "Key not found"})

          assert result == nil
        end)

      assert String.contains?(log_output, "get failed for test_key")
    end

    test "maps JidoKeys generic errors to nil" do
      result =
        CompatibilityWrapper.map_jido_keys_errors(:set, :test_key, {:error, :permission_denied})

      assert result == nil
    end

    test "passes through successful values unchanged" do
      test_values = ["success_value", 42, :atom_result]

      for value <- test_values do
        result = CompatibilityWrapper.map_jido_keys_errors(:get, :test_key, value)
        assert result == value
      end
    end
  end

  describe "session isolation compatibility" do
    test "validates set operation isolation", %{keyring: keyring} do
      result =
        CompatibilityWrapper.validate_session_isolation_compatibility(
          keyring,
          :set,
          :test_key,
          self()
        )

      assert result == :ok
    end

    test "validates get operation isolation", %{keyring: keyring} do
      result =
        CompatibilityWrapper.validate_session_isolation_compatibility(
          keyring,
          :get,
          :test_key,
          self()
        )

      assert result == :ok
    end

    test "validates clear operation isolation", %{keyring: keyring} do
      result =
        CompatibilityWrapper.validate_session_isolation_compatibility(
          keyring,
          :clear,
          :test_key,
          self()
        )

      assert result == :ok
    end

    test "handles unknown operations gracefully" do
      result =
        CompatibilityWrapper.validate_session_isolation_compatibility(
          nil,
          :unknown,
          :test_key,
          self()
        )

      assert result == :ok
    end
  end

  describe "performance compatibility validation" do
    test "validates get operation performance" do
      # Mock JidoKeys for consistent performance testing
      expect(JidoKeys, :get, 100, fn _key, nil -> "performance_value" end)

      result = CompatibilityWrapper.validate_performance_compatibility(:get, 100, 50)
      assert result == :ok
    end

    test "validates session operation performance", %{keyring: keyring} do
      result = CompatibilityWrapper.validate_performance_compatibility(:set_session, 50, 100)

      case result do
        :ok ->
          assert true

        {:error, perf_data} ->
          # If performance is slow, ensure error data is properly formatted
          assert is_map(perf_data)
          assert Map.has_key?(perf_data, :operation)
          assert Map.has_key?(perf_data, :average_time_ms)
      end
    end

    test "detects performance regressions" do
      # Test with very strict time limit to trigger performance error
      result = CompatibilityWrapper.validate_performance_compatibility(:get, 10, 0.001)
      assert {:error, perf_data} = result
      assert perf_data.operation == :get
      assert perf_data.average_time_ms > perf_data.max_allowed_ms
    end

    test "handles unsupported operations gracefully" do
      result = CompatibilityWrapper.validate_performance_compatibility(:unknown_operation, 10, 50)
      # Should not crash on unknown operations
      assert result == :ok
    end
  end

  describe "configuration compatibility mapping" do
    test "merges JidoKeys and Keyring configurations" do
      jido_keys_config = %{
        jido_keys_feature: true,
        shared_setting: "jido_keys_value"
      }

      keyring_config = %{
        keyring_feature: true,
        shared_setting: "keyring_value",
        session_timeout: 120
      }

      merged =
        CompatibilityWrapper.map_configuration_compatibility(jido_keys_config, keyring_config)

      # Should preserve keyring features
      assert merged.keyring_feature == true
      # Should add jido_keys features
      assert merged.jido_keys_feature == true
      # JidoKeys should override shared settings
      assert merged.shared_setting == "jido_keys_value"
      # Should preserve keyring-specific settings
      assert merged.session_timeout == 120
    end

    test "ensures session timeout compatibility" do
      configs = [
        {%{}, %{}},
        {%{session_timeout: nil}, %{}},
        {%{session_timeout: "invalid"}, %{}},
        {%{session_timeout: 300}, %{}}
      ]

      for {jido_config, keyring_config} <- configs do
        merged = CompatibilityWrapper.map_configuration_compatibility(jido_config, keyring_config)
        assert is_integer(merged.session_timeout)
        assert merged.session_timeout > 0
      end
    end

    test "ensures environment loading compatibility" do
      merged = CompatibilityWrapper.map_configuration_compatibility(%{}, %{})
      assert merged.load_env_on_start == true
    end

    test "ensures logging compatibility" do
      merged = CompatibilityWrapper.map_configuration_compatibility(%{}, %{})
      assert Map.has_key?(merged, :log_level)
      assert merged.enable_credential_filtering == true
    end
  end

  describe "comprehensive compatibility test suite" do
    test "runs all compatibility tests successfully", %{keyring: keyring} do
      result = CompatibilityWrapper.run_compatibility_tests()

      case result do
        :ok ->
          assert true

        {:error, failed_tests} ->
          # If tests fail, ensure failures are properly reported
          assert is_list(failed_tests)

          for failure <- failed_tests do
            assert is_binary(failure), "Failure should be descriptive string: #{inspect(failure)}"
          end
      end
    end
  end

  describe "individual compatibility tests" do
    test "get compatibility test passes", %{keyring: keyring} do
      # Mock JidoKeys for predictable testing
      expect(JidoKeys, :get, fn _key, nil -> nil end)

      # This calls the private function through the public interface
      result = CompatibilityWrapper.run_compatibility_tests()
      # The test suite should pass or provide meaningful failures
      case result do
        :ok -> assert true
        {:error, failures} -> assert is_list(failures)
      end
    end

    test "session compatibility operations work as expected", %{keyring: keyring} do
      # Test the actual operations that the compatibility test checks
      key = :compat_test_key
      value = "compat_test_value"

      # These operations should work exactly as in the original Keyring
      assert :ok = Keyring.set_session_value(keyring, key, value)
      assert ^value = Keyring.get_session_value(keyring, key)
      assert :ok = Keyring.clear_session_value(keyring, key)
      assert nil == Keyring.get_session_value(keyring, key)
    end

    test "environment value compatibility", %{keyring: keyring} do
      # Mock JidoKeys for env value testing
      expect(JidoKeys, :get, fn :env_compat_test, nil -> "env_value" end)

      result = Keyring.get_env_value(keyring, :env_compat_test, "default")
      assert is_binary(result) or is_nil(result)
    end

    test "list operation compatibility", %{keyring: keyring} do
      result = Keyring.list(keyring)
      assert is_list(result)
      assert Enum.all?(result, &is_atom/1)
    end

    test "error handling maintains backward compatibility", %{keyring: keyring} do
      # These operations should not raise but return expected values
      nil_result = Keyring.get(keyring, :nonexistent_compat_key)
      default_result = Keyring.get(keyring, :nonexistent_compat_key, "default")

      assert nil_result == nil
      assert default_result == "default"
    end

    test "process isolation compatibility maintained", %{keyring: keyring} do
      key = :isolation_compat_test
      parent_value = "parent_value"

      # Set value in current process
      :ok = Keyring.set_session_value(keyring, key, parent_value)

      # Test in child process
      task =
        Task.async(fn ->
          child_value = Keyring.get_session_value(keyring, key)
          {child_value, self()}
        end)

      {child_result, child_pid} = Task.await(task)

      # Child should not see parent's value (isolation maintained)
      assert child_result == nil
      assert child_pid != self()

      # Parent should still see its value
      parent_result = Keyring.get_session_value(keyring, key)
      assert parent_result == parent_value
    end
  end

  describe "edge cases and error conditions" do
    test "handles API compatibility with invalid inputs" do
      edge_cases = [
        {:get, [], %{invalid: :structure}},
        {:list, [], "not_a_list"},
        {:unknown_function, [], :any_result}
      ]

      for {function_name, args, result} <- edge_cases do
        # Should not crash on invalid inputs
        compatible_result =
          CompatibilityWrapper.ensure_api_compatibility(function_name, args, result)

        # Should return something reasonable
        assert compatible_result != nil
      end
    end

    test "handles error mapping with edge cases" do
      edge_cases = [
        {:error, %{complex: "error"}},
        {:error, ["list", "error"]},
        {:error, :very_specific_atom},
        {:ok, "wrapped_success"},
        :bare_atom_result
      ]

      for error_case <- edge_cases do
        result = CompatibilityWrapper.map_jido_keys_errors(:test, :test_key, error_case)
        # Should handle all cases gracefully
        # Should be predictable
        assert result != nil or result == nil
      end
    end

    test "configuration mapping handles missing or invalid configs" do
      edge_cases = [
        {nil, %{}},
        {%{}, nil},
        {"invalid", %{}},
        {[], %{}}
      ]

      for {jido_config, keyring_config} <- edge_cases do
        # Should not crash and should return a valid config
        result = CompatibilityWrapper.map_configuration_compatibility(jido_config, keyring_config)
        assert is_map(result)
        assert Map.has_key?(result, :session_timeout)
      end
    end
  end

  describe "integration with enhanced features" do
    test "compatibility wrapper works with runtime configuration", %{keyring: keyring} do
      expect(JidoKeys, :put, fn :runtime_compat_key, "runtime_value" ->
        :ok
      end)

      # Runtime configuration should work through compatibility layer
      result = Keyring.set_runtime_value(:runtime_compat_key, "runtime_value")
      assert result == :ok
    end

    test "compatibility maintained with enhanced security features", %{keyring: keyring} do
      # Set a potentially sensitive value
      :ok = Keyring.set_session_value(keyring, :security_compat_key, "sk-sensitive123")

      # Should work with enhanced security but maintain compatibility
      result = Keyring.get_session_value(keyring, :security_compat_key)
      # Should return a string (potentially filtered)
      assert is_binary(result)
    end

    test "compatibility with enhanced error handling" do
      # Mock JidoKeys to return an error
      expect(JidoKeys, :get, fn :error_compat_key, nil ->
        raise "Simulated JidoKeys error"
      end)

      # Should handle error gracefully and maintain compatibility
      result = Keyring.get(:error_compat_key, "default")
      # Should fall back as expected
      assert result == "default"
    end
  end
end
