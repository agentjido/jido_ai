defmodule JidoKeys.ApplicationTest do
  @moduledoc """
  Tests for the JidoKeys.Application supervision tree and lifecycle.
  """

  use ExUnit.Case, async: false

  describe "application startup" do
    test "application starts and supervises JidoKeys.Server" do
      Application.stop(:jido_keys)
      assert :ok = Application.start(:jido_keys)
      assert Process.whereis(JidoKeys.Server) != nil
      assert is_list(JidoKeys.list())
    end

    test "supervised restart on server crash" do
      Application.start(:jido_keys)
      original_pid = Process.whereis(JidoKeys.Server)

      Process.exit(original_pid, :kill)
      :timer.sleep(100)

      new_pid = Process.whereis(JidoKeys.Server)
      assert new_pid != nil
      assert new_pid != original_pid
    end
  end

  describe "application environment" do
    test "loads application configuration" do
      original_config = Application.get_env(:jido_keys, :keys)

      try do
        app_config = %{test_config_key: "config_value"}
        Application.put_env(:jido_keys, :keys, app_config)

        Application.stop(:jido_keys)
        Application.start(:jido_keys)

        assert JidoKeys.get(:test_config_key) == "config_value"
      after
        if original_config do
          Application.put_env(:jido_keys, :keys, original_config)
        else
          Application.delete_env(:jido_keys, :keys)
        end

        Application.stop(:jido_keys)
        Application.start(:jido_keys)
      end
    end
  end

  describe "application lifecycle" do
    test "ETS tables are cleaned up on application stop" do
      Application.start(:jido_keys)
      assert :ets.whereis(:jido_keys_env_cache) != :undefined

      Application.stop(:jido_keys)
      :timer.sleep(100)

      assert :ets.whereis(:jido_keys_env_cache) == :undefined
    end
  end
end
