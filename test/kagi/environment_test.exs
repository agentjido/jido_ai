defmodule Kagi.EnvironmentTest do
  @moduledoc """
  Tests for environment variable loading and .env file processing.
  """

  use ExUnit.Case, async: false

  import Kagi.TestHelpers

  setup do
    stop_kagi_server()
    :ok
  end

  describe "system environment precedence" do
    test "system env vars are loaded" do
      with_env_vars(%{"TEST_KEY" => "system_value"}, fn ->
        start_kagi_server()
        assert Kagi.get(:test_key) == "system_value"
      end)
    end
  end

  describe "LiveBook variable handling" do
    test "processes LB_ prefixed variables correctly" do
      with_env_vars(%{"LB_API_KEY" => "lb_api_value"}, fn ->
        start_kagi_server()

        keys = Kagi.list()
        assert "lb_api_key" in keys

        assert Kagi.get(:api_key) == "lb_api_value"
        assert Kagi.get(:lb_api_key) == "lb_api_value"
      end)
    end
  end

  describe "reload behavior" do
    test "reload function exists" do
      start_kagi_server()
      assert Kagi.reload() == :ok
    end
  end
end
