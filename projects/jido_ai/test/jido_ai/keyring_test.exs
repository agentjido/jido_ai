defmodule Jido.AI.KeyringTest do
  use Jido.AI.TestSupport.KeyringCase, async: false
  use Jido.AI.TestMacros
  use ExUnitProperties
  
  # Skip this entire test module since Keyring has been extracted to Kagi project
  @moduletag :skip

  @session_registry :jido_ai_keyring_sessions
  @default_name Kagi

  describe "get/4" do
    test "returns default when no value found" do
      assert Kagi.get(:test_key, "default") == "default"
    end

    test "returns session value when set" do
      session(test_key: "session_value") do
        assert_value(:test_key, "session_value")
      end
    end

    test "returns env value when no session override" do
      env(test_key: "env_value") do
        assert_value(:test_key, "env_value")
      end
    end

    test "session value takes precedence over env value" do
      env(test_key: "env_value") do
        session(test_key: "session_value") do
          assert_value(:test_key, "session_value")
        end
      end
    end

    test "supports LiveBook fallback with lb_ prefix" do
      env(lb_test_key: "lb_value") do
        assert_value(:test_key, "lb_value")
      end
    end

    test "prioritizes regular env over LiveBook env" do
      env(test_key: "regular_value", lb_test_key: "lb_value") do
        assert_value(:test_key, "regular_value")
      end
    end

    test "uses custom keyring name" do
      custom_keyring = start_supervised!({Keyring, name: :custom_keyring})
      GenServer.call(custom_keyring, {:set_test_env_vars, %{"TEST_KEY" => "custom_value"}})

      assert Kagi.get(:custom_keyring, :test_key, "default") == "custom_value"
    end

    table_test(
      "handles different data types",
      [
        string_key: "string",
        integer_key: 42,
        atom_key: :atom_value,
        list_key: [1, 2, 3]
      ],
      fn {key, value} ->
        session([{key, value}]) do
          assert_value(key, value)
        end
      end
    )
  end

  describe "set_session_value/4" do
    test "sets value for default keyring" do
      Kagi.set_session_value(:test_key, "value")
      assert_value(:test_key, "value")
    end

    test "sets value for custom keyring" do
      _custom_keyring = start_supervised!({Keyring, name: :custom_keyring})

      Kagi.set_session_value(:custom_keyring, :test_key, "custom_value")
      assert Kagi.get(:custom_keyring, :test_key, "default") == "custom_value"
    end

    test "overwrites existing session value" do
      session(test_key: "old_value") do
        Kagi.set_session_value(:test_key, "new_value")
        assert_value(:test_key, "new_value")
      end
    end
  end

  describe "clear_session_value/3" do
    test "clears specific session value" do
      session(test_key: "value") do
        Kagi.clear_session_value(:test_key)
        refute_value(:test_key, "default")
      end
    end

    test "clearing non-existent key is safe" do
      assert :ok = Kagi.clear_session_value(:non_existent)
    end

    test "clearing preserves other session values" do
      session(key1: "value1", key2: "value2") do
        Kagi.clear_session_value(:key1)
        refute_value(:key1, "default")
        assert_value(:key2, "value2")
      end
    end
  end

  describe "clear_all_session_values/1" do
    test "clears all session values" do
      session(key1: "value1", key2: "value2") do
        Kagi.clear_all_session_values()
        refute_value(:key1, "default")
        refute_value(:key2, "default")
      end
    end

    test "preserves env values after clearing session values" do
      env(env_key: "env_value") do
        session(env_key: "session_override") do
          assert_value(:env_key, "session_override")

          Kagi.clear_all_session_values()
          assert_value(:env_key, "env_value")
        end
      end
    end
  end

  describe "list/2" do
    test "returns empty list when no env vars" do
      assert Kagi.list() == []
    end

    test "returns env-level keys only" do
      env(api_key: "secret", model: "gpt-4") do
        keys = Kagi.list()
        assert "api_key" in keys
        assert "model" in keys
        assert length(keys) == 2
      end
    end

    test "does not include session overrides in list" do
      env(api_key: "env_value") do
        session(api_key: "session_value", session_only: "session_only_value") do
          keys = Kagi.list()
          assert keys == ["api_key"]
        end
      end
    end

    test "includes LiveBook keys in list" do
      env(api_key: "regular", lb_lb_key: "livebook") do
        keys = Kagi.list()
        assert "api_key" in keys
        assert "lb_lb_key" in keys
      end
    end

    test "returns string keys consistently" do
      env(string_key: "value1", another_key: "value2") do
        keys = Kagi.list()

        # Verify all keys are strings
        assert Enum.all?(keys, &is_binary/1)
        assert "string_key" in keys
        assert "another_key" in keys
      end
    end
  end

  describe "has_value?/2" do
    test "returns false when no value exists" do
      refute Kagi.has_value?(:non_existent)
    end

    test "returns true for session values" do
      session(test_key: "value") do
        assert Kagi.has_value?(:test_key)
      end
    end

    test "returns true for env values" do
      env(test_key: "env_value") do
        assert Kagi.has_value?(:test_key)
      end
    end

    test "returns false for nil values" do
      session(nil_key: nil) do
        refute Kagi.has_value?(:nil_key)
      end
    end

    test "returns true for LiveBook values" do
      env(lb_test_key: "lb_value") do
        assert Kagi.has_value?(:test_key)
      end
    end
  end

  describe "process isolation" do
    test "session values are process-specific" do
      parent = self()

      spawn(fn ->
        Kagi.set_session_value(:isolation_test, "child_value")
        send(parent, Kagi.get(:isolation_test, "default"))
      end)

      Kagi.set_session_value(:isolation_test, "parent_value")

      assert_receive "child_value"
      assert Kagi.get(:isolation_test, "default") == "parent_value"
    end
  end

  describe "state recovery" do
    test "keyring restarts cleanly" do
      custom_keyring = start_supervised!({Keyring, name: :test_recovery})

      Kagi.set_session_value(:test_recovery, :test_key, "value")
      assert Kagi.get(:test_recovery, :test_key, "default") == "value"

      GenServer.stop(custom_keyring, :normal)
      _new_keyring = start_supervised!({Keyring, name: :test_recovery_new})

      # Use different key since session values are process-specific
      assert Kagi.get(:test_recovery_new, :different_key, "default") == "default"
    end
  end

  describe "configuration precedence" do
    test "session > env > app config > default" do
      # Set env value
      env(precedence_test: "env_value") do
        assert_value(:precedence_test, "env_value")

        # Session overrides env
        session(precedence_test: "session_value") do
          assert_value(:precedence_test, "session_value")
        end

        # After clearing session, falls back to env
        assert_value(:precedence_test, "env_value")
      end
    end

    test "complex precedence with LiveBook" do
      env(complex_test: "regular_env", lb_complex_test: "livebook_env") do
        # Regular env takes precedence over LiveBook
        assert_value(:complex_test, "regular_env")

        # Session overrides both
        session(complex_test: "session_value") do
          assert_value(:complex_test, "session_value")
        end

        # After clearing session, falls back to regular env (not LiveBook)
        assert_value(:complex_test, "regular_env")
      end
    end
  end

  describe "LiveBook integration" do
    test "lb_ prefix fallback works" do
      env(lb_livebook_test: "lb_value") do
        assert_value(:livebook_test, "lb_value")
      end
    end

    test "regular env takes precedence over lb_ prefix" do
      env(livebook_test: "regular_value", lb_livebook_test: "lb_value") do
        assert_value(:livebook_test, "regular_value")
      end
    end

    test "lb_ keys appear in list" do
      env(regular_key: "regular", lb_lb_key: "livebook") do
        keys = Kagi.list()
        assert "regular_key" in keys
        assert "lb_lb_key" in keys
      end
    end
  end

  describe "ETS table management" do
    test "ETS cleanup on termination" do
      test_keyring = start_supervised!({Keyring, name: :test_cleanup})

      env_table = GenServer.call(test_keyring, :get_env_table)
      assert :ets.whereis(env_table) != :undefined

      GenServer.stop(test_keyring, :normal)
      assert :ets.whereis(env_table) == :undefined
    end
  end

  describe "concurrent access" do
    test "concurrent session operations are safe" do
      tasks =
        1..5
        |> Enum.map(fn i ->
          Task.async(fn ->
            key = :"concurrent_key_#{i}"
            value = "value_#{i}"

            Kagi.set_session_value(key, value)
            retrieved = Kagi.get(key, "default")
            Kagi.clear_session_value(key)

            {retrieved, Kagi.get(key, "default")}
          end)
        end)

      results = Task.await_many(tasks)

      for {retrieved, cleared} <- results do
        assert String.starts_with?(retrieved, "value_")
        assert cleared == "default"
      end
    end

    test "concurrent reads are consistent" do
      env(shared_key: "shared_value") do
        results =
          1..5
          |> Enum.map(fn _ ->
            Task.async(fn -> Kagi.get(:shared_key, "default") end)
          end)
          |> Task.await_many()

        assert Enum.all?(results, &(&1 == "shared_value"))
      end
    end
  end

  describe "key normalization" do
    test "atom and string access work consistently" do
      env(openai_api_key: "test-key") do
        assert_value(:openai_api_key, "test-key")
        assert Kagi.get("openai_api_key", "default") == "test-key"
        assert Kagi.has_value?(:openai_api_key)
      end
    end

    test "keys normalize to strings in list" do
      env(test_key: "value") do
        keys = Kagi.list()
        assert "test_key" in keys
        assert Enum.all?(keys, &is_binary/1)
      end
    end

    test "case normalization works" do
      Kagi.set_test_env_vars(%{"TEST_NORMALIZATION" => "value1", "test_normalization" => "value2"})

      assert Kagi.get(:test_normalization, "default") == "value2"
      assert Kagi.get("test_normalization", "default") == "value2"

      keys = Kagi.list()
      assert "test_normalization" in keys
      assert length(Enum.filter(keys, &(&1 == "test_normalization"))) == 1
    end
  end

  describe "edge cases" do
    test "handles long values and special characters" do
      long_value = String.duplicate("b", 100)

      session(long_key: long_value, empty_key: "", special_key_123: "special") do
        assert_value(:long_key, long_value)
        assert_value(:empty_key, "")
        assert_value(:special_key_123, "special")
        assert Kagi.has_value?(:empty_key)
      end
    end

    test "ignores malformed env vars" do
      Kagi.set_test_env_vars(%{"NOT_JIDO_AI_KEY" => "ignored", "" => "empty"})

      refute Kagi.has_value?(:key)
      refute Kagi.has_value?("")
    end
  end

  describe "memory management" do
    test "session cleanup prevents memory leaks" do
      keys = Enum.map(1..10, &:"memory_test_#{&1}")

      Enum.each(keys, &Kagi.set_session_value(&1, "value"))
      Enum.each(keys, &assert(Kagi.get(&1, "default") == "value"))

      Kagi.clear_all_session_values()

      Enum.each(keys, &assert(Kagi.get(&1, "default") == "default"))
    end
  end

  describe "internal functions" do
    test "get_env_value returns defaults for missing keys" do
      assert Kagi.get_env_value(@default_name, :missing_key, "default") == "default"
    end

    test "get_session_value handles process isolation" do
      {:ok, _pid} = Kagi.start_link(name: :test_session)

      task =
        Task.async(fn ->
          Kagi.set_session_value(:test_session, :test_key, "task_value")
          self()
        end)

      task_pid = Task.await(task)

      assert Kagi.get_session_value(:test_session, :test_key, task_pid) == "task_value"
      assert Kagi.get_session_value(:test_session, :test_key) == nil
    end
  end

  describe "supervisor integration" do
    test "child_spec and start_link work" do
      spec = Kagi.child_spec(name: :test_child_spec)
      assert spec.id == :test_child_spec
      assert spec.type == :worker

      {:ok, pid} = Kagi.start_link(name: :test_start)
      assert is_pid(pid)
      assert Process.whereis(:test_start) == pid
    end
  end

  describe "additional coverage" do
    test "handles get arity variations" do
      assert Kagi.get(:missing_key) == nil
      assert Kagi.get(:missing_key, "default") == "default"
    end

    test "exercises GenServer calls" do
      {:ok, pid} = Kagi.start_link(name: :test_calls)

      assert is_list(GenServer.call(pid, :list_keys))
      assert GenServer.call(pid, :get_registry) == @session_registry
      assert GenServer.call(pid, {:get_value, :test_key, "default"}) == "default"
    end

    test "custom keyring lifecycle" do
      {:ok, pid} = Kagi.start_link(name: :test_lifecycle)

      Kagi.set_session_value(:test_lifecycle, :test_key, "value")
      assert Kagi.has_value?(:test_key, :test_lifecycle)

      GenServer.stop(pid, :normal)
      assert Process.whereis(:test_lifecycle) == nil
    end
  end

  describe "property-based tests" do
    property "session values are process-isolated" do
      check all(
              value1 <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
              value2 <- StreamData.string(:alphanumeric, min_length: 1, max_length: 10),
              value1 != value2
            ) do
        parent = self()

        # Two processes set different values for same key
        spawn(fn ->
          Kagi.set_session_value(:test_key, value1)
          send(parent, {:result, 1, Kagi.get(:test_key, "default")})
        end)

        spawn(fn ->
          Kagi.set_session_value(:test_key, value2)
          send(parent, {:result, 2, Kagi.get(:test_key, "default")})
        end)

        # Each gets its own value
        result1 =
          receive do
            {:result, 1, r} -> r
          after
            1000 -> "timeout"
          end

        result2 =
          receive do
            {:result, 2, r} -> r
          after
            1000 -> "timeout"
          end

        assert result1 == value1
        assert result2 == value2
        assert Kagi.get(:test_key, "default") == "default"
      end
    end
  end
end
