defmodule Jido.DiscoveryTest do
  use ExUnit.Case
  alias Jido.Discovery

  @moduletag :capture_log

  setup do
    # Reset cache before each test
    :ok = Discovery.init()
    :ok
  end

  describe "init/0" do
    test "initializes cache successfully" do
      assert :ok = Discovery.init()
      assert {:ok, _cache} = Discovery.__get_cache__()
    end
  end

  describe "refresh/0" do
    test "refreshes cache successfully" do
      assert :ok = Discovery.refresh()
      assert {:ok, _cache} = Discovery.__get_cache__()
    end
  end

  describe "last_updated/0" do
    test "returns last update time when cache exists" do
      :ok = Discovery.init()
      assert {:ok, %DateTime{}} = Discovery.last_updated()
    end

    test "returns error when cache not initialized" do
      :persistent_term.erase(:__jido_discovery_cache__)
      assert {:error, :not_initialized} = Discovery.last_updated()
    end
  end

  describe "get_by_slug functions" do
    test "returns nil when cache not initialized" do
      :persistent_term.erase(:__jido_discovery_cache__)
      assert nil == Discovery.get_action_by_slug("any")
      assert nil == Discovery.get_sensor_by_slug("any")
      # assert nil == Discovery.get_command_by_slug("any")
      assert nil == Discovery.get_agent_by_slug("any")
    end

    test "returns nil for non-existent slugs" do
      :ok = Discovery.init()
      assert nil == Discovery.get_action_by_slug("nonexistent")
      assert nil == Discovery.get_sensor_by_slug("nonexistent")
      # assert nil == Discovery.get_command_by_slug("nonexistent")
      assert nil == Discovery.get_agent_by_slug("nonexistent")
    end
  end

  describe "list functions" do
    test "returns empty list when cache not initialized" do
      :persistent_term.erase(:__jido_discovery_cache__)
      assert [] == Discovery.list_actions()
      assert [] == Discovery.list_sensors()
      # assert [] == Discovery.list_commands()
      assert [] == Discovery.list_agents()
    end

    test "applies pagination options" do
      :ok = Discovery.init()

      # Test limit
      assert length(Discovery.list_actions(limit: 1)) <= 1
      assert length(Discovery.list_sensors(limit: 1)) <= 1
      # assert length(Discovery.list_commands(limit: 1)) <= 1
      assert length(Discovery.list_agents(limit: 1)) <= 1

      # Test offset
      all_actions = Discovery.list_actions()
      offset_actions = Discovery.list_actions(offset: 1)
      assert length(offset_actions) <= max(length(all_actions) - 1, 0)
    end

    test "applies filtering options" do
      :ok = Discovery.init()

      # Test name filter
      actions_filtered = Discovery.list_actions(name: "nonexistent")
      assert Enum.empty?(actions_filtered)

      # Test category filter
      sensors_filtered = Discovery.list_sensors(category: :nonexistent)
      assert Enum.empty?(sensors_filtered)

      # Test tag filter
      agents_filtered = Discovery.list_agents(tag: :nonexistent)
      assert Enum.empty?(agents_filtered)
    end
  end
end
