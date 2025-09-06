defmodule KagiTest do
  @moduledoc """
  Tests for the main Kagi facade module.
  """

  use ExUnit.Case, async: false

  import Kagi.TestHelpers

  setup do
    stop_kagi_server()
    :ok
  end

  describe "get/2" do
    test "returns value when key exists, default when missing" do
      with_env_vars(%{"TEST_KEY" => "test_value"}, fn ->
        start_kagi_server()
        assert Kagi.get(:test_key) == "test_value"
        assert Kagi.get("test_key") == "test_value"
        assert Kagi.get(:missing_key, "default") == "default"
        assert Kagi.get(:missing_key) == nil
      end)
    end

    test "normalizes keys correctly" do
      with_env_vars(%{"Test_Key-123" => "normalized_value"}, fn ->
        start_kagi_server()
        assert Kagi.get(:test_key_123) == "normalized_value"
        assert Kagi.get("test_key_123") == "normalized_value"
      end)
    end
  end

  describe "get!/1" do
    test "returns value when key exists, raises when missing" do
      with_env_vars(%{"TEST_KEY" => "test_value"}, fn ->
        start_kagi_server()
        assert Kagi.get!(:test_key) == "test_value"

        assert_raise ArgumentError, ~r/Configuration key :missing_key not found/, fn ->
          Kagi.get!(:missing_key)
        end
      end)
    end
  end

  describe "has?/1 and has_value?/1" do
    test "checks key existence and value presence" do
      with_env_vars(%{"TEST_KEY" => "test_value", "EMPTY_KEY" => ""}, fn ->
        start_kagi_server()

        # has? returns true for any non-nil value
        assert Kagi.has?(:test_key) == true
        assert Kagi.has?(:missing_key) == false

        # has_value? returns true only for non-empty values
        assert Kagi.has_value?(:test_key) == true
        assert Kagi.has_value?(:empty_key) == false
        assert Kagi.has_value?(:missing_key) == false
      end)
    end
  end

  describe "list/0" do
    test "returns list of loaded keys" do
      with_env_vars(%{"KEY_ONE" => "value1", "KEY_TWO" => "value2"}, fn ->
        start_kagi_server()
        keys = Kagi.list()
        assert is_list(keys)
        assert "key_one" in keys
        assert "key_two" in keys
      end)
    end
  end

  describe "hierarchical configuration priority" do
    test "environment variables take precedence over app config" do
      config = %{test_key: "app_value"}

      with_app_config(config, fn ->
        with_env_vars(%{"TEST_KEY" => "env_value"}, fn ->
          start_kagi_server()
          assert Kagi.get(:test_key) == "env_value"
        end)
      end)
    end

    test "app config used when no environment variable" do
      config = %{test_key: "app_value"}

      with_app_config(config, fn ->
        start_kagi_server()
        assert Kagi.get(:test_key) == "app_value"
      end)
    end

    test "default used when no config or environment variable" do
      start_kagi_server()
      assert Kagi.get(:test_key, "default_value") == "default_value"
    end
  end

  describe "LiveBook integration" do
    test "LB_ prefixed keys work with precedence" do
      with_env_vars(%{"LB_TEST_KEY" => "lb_value", "TEST_KEY" => "regular_value"}, fn ->
        start_kagi_server()

        # Non-prefixed should take precedence
        assert Kagi.get(:test_key) == "regular_value"
        # Original LB_ key should still be accessible
        assert Kagi.get("lb_test_key") == "lb_value"
      end)
    end
  end

  describe "key normalization" do
    test "handles various key formats" do
      with_env_vars(%{"Key-With-Dashes" => "dashes", "MiXeD_CaSe-Key" => "mixed"}, fn ->
        start_kagi_server()
        assert Kagi.get(:key_with_dashes) == "dashes"
        assert Kagi.get(:mixed_case_key) == "mixed"
      end)
    end
  end

  describe "put/2" do
    test "sets values in session store" do
      start_kagi_server()
      
      assert Kagi.put(:test_session_key, "session_value") == :ok
      assert Kagi.get(:test_session_key) == "session_value"
      
      assert Kagi.put("string_key", "string_value") == :ok
      assert Kagi.get("string_key") == "string_value"
    end

    test "overwrites existing values" do
      start_kagi_server()
      
      assert Kagi.put(:overwrite_key, "original") == :ok
      assert Kagi.get(:overwrite_key) == "original"
      
      assert Kagi.put(:overwrite_key, "updated") == :ok
      assert Kagi.get(:overwrite_key) == "updated"
    end

    test "normalizes keys consistently with get" do
      start_kagi_server()
      
      assert Kagi.put("Test-Key_123", "normalized") == :ok
      assert Kagi.get(:test_key_123) == "normalized"
      assert Kagi.get("test_key_123") == "normalized"
    end
  end
end
