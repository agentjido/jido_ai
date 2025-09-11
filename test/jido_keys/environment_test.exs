defmodule JidoKeys.EnvironmentTest do
  @moduledoc """
  Tests for environment variable loading and .env file processing.
  """

  use ExUnit.Case, async: false

  import JidoKeys.TestHelpers

  setup do
    stop_jido_keys_server()
    :ok
  end

  describe "system environment precedence" do
    test "system env vars are loaded" do
      with_env_vars(%{"TEST_KEY" => "system_value"}, fn ->
        start_jido_keys_server()
        assert JidoKeys.get(:test_key) == "system_value"
      end)
    end
  end

  describe "LiveBook variable handling" do
    test "processes LB_ prefixed variables correctly" do
      with_env_vars(%{"LB_API_KEY" => "lb_api_value"}, fn ->
        start_jido_keys_server()

        keys = JidoKeys.list()
        assert "lb_api_key" in keys

        assert JidoKeys.get(:api_key) == "lb_api_value"
        assert JidoKeys.get(:lb_api_key) == "lb_api_value"
      end)
    end
  end

  describe "reload behavior" do
    test "reload function exists" do
      start_jido_keys_server()
      assert JidoKeys.reload() == :ok
    end
  end
end
