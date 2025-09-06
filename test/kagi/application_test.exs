defmodule Kagi.ApplicationTest do
  @moduledoc """
  Tests for the Kagi.Application supervision tree and lifecycle.
  """

  use ExUnit.Case, async: false

  describe "application startup" do
    test "application starts and supervises Kagi.Server" do
      Application.stop(:kagi)
      assert :ok = Application.start(:kagi)
      assert Process.whereis(Kagi.Server) != nil
      assert is_list(Kagi.list())
    end

    test "supervised restart on server crash" do
      Application.start(:kagi)
      original_pid = Process.whereis(Kagi.Server)

      Process.exit(original_pid, :kill)
      :timer.sleep(100)

      new_pid = Process.whereis(Kagi.Server)
      assert new_pid != nil
      assert new_pid != original_pid
    end
  end

  describe "application environment" do
    test "loads keyring configuration" do
      original_keyring = Application.get_env(:kagi, :keyring)

      try do
        keyring_config = %{test_keyring_key: "keyring_value"}
        Application.put_env(:kagi, :keyring, keyring_config)

        Application.stop(:kagi)
        Application.start(:kagi)

        assert Kagi.get(:test_keyring_key) == "keyring_value"
      after
        if original_keyring do
          Application.put_env(:kagi, :keyring, original_keyring)
        else
          Application.delete_env(:kagi, :keyring)
        end

        Application.stop(:kagi)
        Application.start(:kagi)
      end
    end
  end

  describe "application lifecycle" do
    test "ETS tables are cleaned up on application stop" do
      Application.start(:kagi)
      assert :ets.whereis(:kagi_env_cache) != :undefined

      Application.stop(:kagi)
      :timer.sleep(100)

      assert :ets.whereis(:kagi_env_cache) == :undefined
    end
  end
end
