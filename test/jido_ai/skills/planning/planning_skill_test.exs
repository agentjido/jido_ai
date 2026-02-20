defmodule Jido.AI.Plugins.PlanningTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}
  alias Jido.AI.Plugins.Planning

  describe "plugin_spec/1" do
    test "returns valid skill spec with empty config" do
      spec = Planning.plugin_spec(%{})

      assert spec.module == Planning
      assert spec.name == "planning"
      assert spec.state_key == :planning
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert length(spec.actions) == 3
    end

    test "includes config in skill spec" do
      config = %{default_model: :capable, default_max_tokens: 8192}
      spec = Planning.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = Planning.mount(%Jido.Agent{}, %{})

      assert state.default_model == :planning
      assert state.default_max_tokens == 4096
      assert state.default_temperature == 0.7
    end

    test "merges custom config into initial state" do
      {:ok, state} =
        Planning.mount(%Jido.Agent{}, %{default_model: :fast, default_max_tokens: 1024})

      assert state.default_model == :fast
      assert state.default_max_tokens == 1024
      assert state.default_temperature == 0.7
    end
  end

  describe "actions" do
    test "returns all three actions" do
      actions = Planning.actions()

      assert length(actions) == 3
      assert Plan in actions
      assert Decompose in actions
      assert Prioritize in actions
    end
  end

  describe "signal_routes/1" do
    test "routes planning signals to planning actions" do
      route_map = Planning.signal_routes(%{}) |> Map.new()

      assert route_map["planning.plan"] == Plan
      assert route_map["planning.decompose"] == Decompose
      assert route_map["planning.prioritize"] == Prioritize
      assert map_size(route_map) == 3
    end

    test "route targets are part of plugin action inventory" do
      route_targets =
        Planning.signal_routes(%{})
        |> Enum.map(fn {_signal, action} -> action end)
        |> Enum.uniq()
        |> MapSet.new()

      actions = Planning.actions() |> MapSet.new()

      assert MapSet.subset?(route_targets, actions)
      assert route_targets == actions
    end
  end
end
