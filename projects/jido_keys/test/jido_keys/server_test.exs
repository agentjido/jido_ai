defmodule JidoKeys.ServerTest do
  @moduledoc """
  Tests for the JidoKeys.Server GenServer.
  """

  use ExUnit.Case, async: false

  import JidoKeys.TestHelpers

  setup do
    stop_jido_keys_server()
    :ok
  end

  describe "GenServer lifecycle" do
    test "starts and stops correctly" do
      assert {:ok, pid} = start_jido_keys_server([])
      assert Process.alive?(pid)
      # Let the cleanup handle stopping the server
    end

    test "initializes ETS table" do
      start_jido_keys_server()
      assert :ets.whereis(:jido_keys_env_cache) != :undefined
    end
  end

  describe "environment loading" do
    test "loads environment variables" do
      with_env_vars(%{"TEST_SERVER_KEY" => "server_value"}, fn ->
        start_jido_keys_server()
        result = GenServer.call(JidoKeys.Server, {:get, :test_server_key, nil})
        assert result == "server_value"
      end)
    end
  end

  describe "hierarchical value resolution" do
    test "resolves values in correct priority order" do
      config = %{test_priority_key: "app_value"}

      with_app_config(config, fn ->
        with_env_vars(%{"TEST_PRIORITY_KEY" => "env_value"}, fn ->
          start_jido_keys_server()
          result = GenServer.call(JidoKeys.Server, {:get, :test_priority_key, nil})
          assert result == "env_value"
        end)
      end)
    end
  end

  describe "key normalization" do
    test "normalizes keys consistently" do
      with_env_vars(%{"Test-Key_123" => "normalized_value"}, fn ->
        start_jido_keys_server()

        result1 = GenServer.call(JidoKeys.Server, {:get, :test_key_123, nil})
        result2 = GenServer.call(JidoKeys.Server, {:get, "test_key_123", nil})

        assert result1 == "normalized_value"
        assert result2 == "normalized_value"
      end)
    end
  end

  describe "GenServer call handling" do
    test "handles get calls correctly" do
      with_env_vars(%{"EXISTING_KEY" => "existing_value"}, fn ->
        start_jido_keys_server()

        result = GenServer.call(JidoKeys.Server, {:get, :existing_key, nil})
        assert result == "existing_value"

        result = GenServer.call(JidoKeys.Server, {:get, :missing_key, "default"})
        assert result == "default"
      end)
    end

    test "handles list calls" do
      with_env_vars(%{"KEY1" => "value1", "KEY2" => "value2"}, fn ->
        start_jido_keys_server()

        keys = GenServer.call(JidoKeys.Server, :list)
        assert is_list(keys)
        assert "key1" in keys
        assert "key2" in keys
      end)
    end
  end

  describe "reload functionality" do
    test "reloads configuration" do
      start_jido_keys_server()

      with_env_vars(%{"RELOAD_TEST_KEY" => "new_value"}, fn ->
        GenServer.cast(JidoKeys.Server, {:reload, []})
        :timer.sleep(50)

        result = GenServer.call(JidoKeys.Server, {:get, :reload_test_key, nil})
        assert result == "new_value"
      end)
    end
  end
end
