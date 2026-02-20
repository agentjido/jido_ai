defmodule Jido.AI.Plugins.Reasoning.TreeOfThoughtsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Reasoning.TreeOfThoughts

  describe "plugin_spec/1" do
    test "returns valid plugin spec" do
      spec = TreeOfThoughts.plugin_spec(%{})

      assert spec.module == TreeOfThoughts
      assert spec.name == "reasoning_tree_of_thoughts"
      assert spec.state_key == :reasoning_tot
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert spec.actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end

    test "includes config in plugin spec" do
      config = %{default_model: :capable, timeout: 15_000}
      spec = TreeOfThoughts.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = TreeOfThoughts.mount(%Jido.Agent{}, %{})

      assert state.strategy == :tot
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end

    test "merges custom config into initial state, including ToT options" do
      {:ok, state} =
        TreeOfThoughts.mount(%Jido.Agent{}, %{
          default_model: :fast,
          timeout: 5_000,
          options: %{branching_factor: 4, max_depth: 5, traversal_strategy: :best_first}
        })

      assert state.strategy == :tot
      assert state.default_model == :fast
      assert state.timeout == 5_000
      assert state.options == %{branching_factor: 4, max_depth: 5, traversal_strategy: :best_first}
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} = TreeOfThoughts.mount(%Jido.Agent{}, %{})

      assert {:ok, _parsed_state} = Zoi.parse(TreeOfThoughts.schema(), state)
    end
  end

  describe "schema/0" do
    test "applies default values for ToT plugin state" do
      assert {:ok, state} = Zoi.parse(TreeOfThoughts.schema(), %{})

      assert state.strategy == :tot
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end
  end

  describe "actions" do
    test "returns RunStrategy action" do
      actions = TreeOfThoughts.actions()

      assert actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end
  end

  describe "signal routing" do
    test "routes reasoning.tot.run to RunStrategy" do
      routes = TreeOfThoughts.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.tot.run"] == Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "handle_signal/2" do
    test "forces strategy :tot and preserves ToT options" do
      signal =
        Jido.Signal.new!(
          "reasoning.tot.run",
          %{
            prompt: "explore weather-safe plans",
            strategy: :cot,
            timeout: 45_000,
            options: %{branching_factor: 4, max_depth: 5, traversal_strategy: :dfs}
          },
          source: "/test"
        )

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               TreeOfThoughts.handle_signal(signal, %{})

      assert params.strategy == :tot
      assert params.prompt == "explore weather-safe plans"
      assert params.timeout == 45_000
      assert params.options == %{branching_factor: 4, max_depth: 5, traversal_strategy: :dfs}
    end

    test "normalizes non-map payload data and still injects strategy" do
      signal =
        Jido.Signal.new!("reasoning.tot.run", %{prompt: "placeholder"}, source: "/test")
        |> Map.put(:data, :not_a_map)

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               TreeOfThoughts.handle_signal(signal, %{})

      assert params == %{strategy: :tot}
    end
  end

  describe "documentation contracts" do
    test "developer guide explains ToT plugin handoff, options, and defaults" do
      plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
      plugin_module_docs = File.read!("lib/jido_ai/plugins/reasoning/tree_of_thoughts.ex")

      assert plugin_guide =~ "### ToT Plugin Handoff (`reasoning.tot.run`)"
      assert plugin_guide =~ "{Jido.AI.Plugins.Reasoning.TreeOfThoughts,"
      assert plugin_guide =~ "Jido.AI.Actions.Reasoning.RunStrategy"
      assert plugin_guide =~ "strategy: :tot"
      assert plugin_guide =~ "branching_factor"
      assert plugin_guide =~ "max_depth"
      assert plugin_guide =~ "traversal_strategy"
      assert plugin_guide =~ "## Reasoning ToT Plugin Defaults Contract"
      assert plugin_guide =~ "default_model: :reasoning"
      assert plugin_guide =~ "timeout: 30_000"
      assert plugin_guide =~ "options: %{}"

      assert plugin_module_docs =~ "## Signal Contracts"
      assert plugin_module_docs =~ "## Plugin-To-Action Handoff"
      assert plugin_module_docs =~ "## Usage"
      assert plugin_module_docs =~ "## ToT Options"
      assert plugin_module_docs =~ "## Mount State Defaults"
    end

    test "examples index includes ToT plugin execution path" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Plugin Capability Pattern"
      assert examples_readme =~ "| Reasoning ToT plugin | Mount `Jido.AI.Plugins.Reasoning.TreeOfThoughts`"
      assert examples_readme =~ "{Jido.AI.Plugins.Reasoning.TreeOfThoughts,"
      assert examples_readme =~ "reasoning.tot.run"
      assert examples_readme =~ "branching_factor"
      assert examples_readme =~ "Jido.AI.Actions.Reasoning.RunStrategy"
    end
  end
end
