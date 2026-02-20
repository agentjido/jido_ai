defmodule Jido.AI.Plugins.Reasoning.AdaptiveTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Reasoning.Adaptive

  describe "plugin_spec/1" do
    test "returns valid plugin spec" do
      spec = Adaptive.plugin_spec(%{})

      assert spec.module == Adaptive
      assert spec.name == "reasoning_adaptive"
      assert spec.state_key == :reasoning_adaptive
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert spec.actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end

    test "includes config in plugin spec" do
      config = %{default_model: :capable, timeout: 15_000}
      spec = Adaptive.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = Adaptive.mount(%Jido.Agent{}, %{})

      assert state.strategy == :adaptive
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end

    test "merges custom config into initial state, including Adaptive options" do
      {:ok, state} =
        Adaptive.mount(%Jido.Agent{}, %{
          default_model: :fast,
          timeout: 5_000,
          options: %{
            default_strategy: :react,
            available_strategies: [:cod, :cot, :react, :tot, :got, :trm, :aot],
            complexity_thresholds: %{simple: 0.25, complex: 0.8}
          }
        })

      assert state.strategy == :adaptive
      assert state.default_model == :fast
      assert state.timeout == 5_000

      assert state.options == %{
               default_strategy: :react,
               available_strategies: [:cod, :cot, :react, :tot, :got, :trm, :aot],
               complexity_thresholds: %{simple: 0.25, complex: 0.8}
             }
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} = Adaptive.mount(%Jido.Agent{}, %{})

      assert {:ok, _parsed_state} = Zoi.parse(Adaptive.schema(), state)
    end
  end

  describe "schema/0" do
    test "applies default values for Adaptive plugin state" do
      assert {:ok, state} = Zoi.parse(Adaptive.schema(), %{})

      assert state.strategy == :adaptive
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end
  end

  describe "actions" do
    test "returns RunStrategy action" do
      actions = Adaptive.actions()

      assert actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end
  end

  describe "signal routing" do
    test "routes reasoning.adaptive.run to RunStrategy" do
      routes = Adaptive.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.adaptive.run"] == Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "handle_signal/2" do
    test "forces strategy :adaptive and preserves Adaptive options" do
      signal =
        Jido.Signal.new!(
          "reasoning.adaptive.run",
          %{
            prompt: "Pick the best approach and provide a weather-safe plan.",
            strategy: :cot,
            timeout: 45_000,
            options: %{
              default_strategy: :react,
              available_strategies: [:cod, :cot, :react, :tot, :got, :trm, :aot],
              complexity_thresholds: %{simple: 0.25, complex: 0.8}
            }
          },
          source: "/test"
        )

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               Adaptive.handle_signal(signal, %{})

      assert params.strategy == :adaptive
      assert params.prompt == "Pick the best approach and provide a weather-safe plan."
      assert params.timeout == 45_000

      assert params.options == %{
               default_strategy: :react,
               available_strategies: [:cod, :cot, :react, :tot, :got, :trm, :aot],
               complexity_thresholds: %{simple: 0.25, complex: 0.8}
             }
    end

    test "normalizes non-map payload data and still injects strategy" do
      signal =
        Jido.Signal.new!("reasoning.adaptive.run", %{prompt: "placeholder"}, source: "/test")
        |> Map.put(:data, :not_a_map)

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               Adaptive.handle_signal(signal, %{})

      assert params == %{strategy: :adaptive}
    end
  end

  describe "documentation contracts" do
    test "developer guide explains Adaptive plugin handoff, options, and defaults" do
      plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
      plugin_module_docs = File.read!("lib/jido_ai/plugins/reasoning/adaptive.ex")

      assert plugin_guide =~ "### Adaptive Plugin Handoff (`reasoning.adaptive.run`)"
      assert plugin_guide =~ "{Jido.AI.Plugins.Reasoning.Adaptive,"
      assert plugin_guide =~ "Jido.AI.Actions.Reasoning.RunStrategy"
      assert plugin_guide =~ "strategy: :adaptive"
      assert plugin_guide =~ "default_strategy"
      assert plugin_guide =~ "available_strategies"
      assert plugin_guide =~ "complexity_thresholds"
      assert plugin_guide =~ "## Reasoning Adaptive Plugin Defaults Contract"
      assert plugin_guide =~ "default_model: :reasoning"
      assert plugin_guide =~ "timeout: 30_000"
      assert plugin_guide =~ "options: %{}"

      assert plugin_module_docs =~ "## Signal Contracts"
      assert plugin_module_docs =~ "## Plugin-To-Action Handoff"
      assert plugin_module_docs =~ "## Usage"
      assert plugin_module_docs =~ "## Adaptive Options"
      assert plugin_module_docs =~ "## Mount State Defaults"
    end

    test "examples index includes Adaptive plugin execution path" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Plugin Capability Pattern"
      assert examples_readme =~ "| Reasoning Adaptive plugin | Mount `Jido.AI.Plugins.Reasoning.Adaptive`"
      assert examples_readme =~ "{Jido.AI.Plugins.Reasoning.Adaptive,"
      assert examples_readme =~ "reasoning.adaptive.run"
      assert examples_readme =~ "default_strategy"
      assert examples_readme =~ "Jido.AI.Actions.Reasoning.RunStrategy"
    end
  end
end
