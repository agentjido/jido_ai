defmodule KagiTest do
  use ExUnit.Case

  setup do
    # Clear any existing state
    Kagi.clear_all_session_values()
    :ok
  end

  test "can set and get session values" do
    Kagi.set_session_value(:test_key, "test_value")
    assert Kagi.get(:test_key) == "test_value"
  end

  test "returns default when key not found" do
    assert Kagi.get(:nonexistent_key, "default") == "default"
  end

  test "can clear session values" do
    Kagi.set_session_value(:test_key, "test_value")
    Kagi.clear_session_value(:test_key)
    assert Kagi.get(:test_key, "default") == "default"
  end

  test "can clear all session values" do
    Kagi.set_session_value(:key1, "value1")
    Kagi.set_session_value(:key2, "value2")
    Kagi.clear_all_session_values()
    assert Kagi.get(:key1, "default") == "default"
    assert Kagi.get(:key2, "default") == "default"
  end

  test "can list keys" do
    # The list will contain environment variables, so we just check it returns a list
    keys = Kagi.list()
    assert is_list(keys)
  end

  test "has_value? works correctly" do
    # With no session value, should check environment
    # Since we can't predict what's in the environment, we'll test with session values
    Kagi.set_session_value(:test_key, "test_value")
    assert Kagi.has_value?(:test_key) == true

    Kagi.clear_session_value(:test_key)
    # For a key that definitely doesn't exist
    refute Kagi.has_value?(:definitely_nonexistent_key_12345)
  end
end
