defmodule Jido.AI.Plugins.Reasoning.TRMTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Reasoning.TRM

  describe "plugin_spec/1" do
    test "returns valid plugin spec" do
      spec = TRM.plugin_spec(%{})

      assert spec.module == TRM
      assert spec.name == "reasoning_trm"
      assert spec.state_key == :reasoning_trm
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert spec.actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end

    test "includes config in plugin spec" do
      config = %{default_model: :capable, timeout: 15_000}
      spec = TRM.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = TRM.mount(%Jido.Agent{}, %{})

      assert state.strategy == :trm
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end

    test "merges custom config into initial state, including TRM options" do
      {:ok, state} =
        TRM.mount(%Jido.Agent{}, %{
          default_model: :fast,
          timeout: 5_000,
          options: %{max_supervision_steps: 6, act_threshold: 0.92}
        })

      assert state.strategy == :trm
      assert state.default_model == :fast
      assert state.timeout == 5_000
      assert state.options == %{max_supervision_steps: 6, act_threshold: 0.92}
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} = TRM.mount(%Jido.Agent{}, %{})

      assert {:ok, _parsed_state} = Zoi.parse(TRM.schema(), state)
    end
  end

  describe "schema/0" do
    test "applies default values for TRM plugin state" do
      assert {:ok, state} = Zoi.parse(TRM.schema(), %{})

      assert state.strategy == :trm
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end
  end

  describe "actions" do
    test "returns RunStrategy action" do
      actions = TRM.actions()

      assert actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end
  end

  describe "signal routing" do
    test "routes reasoning.trm.run to RunStrategy" do
      routes = TRM.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.trm.run"] == Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "handle_signal/2" do
    test "forces strategy :trm and preserves TRM options" do
      signal =
        Jido.Signal.new!(
          "reasoning.trm.run",
          %{
            prompt: "Iteratively improve this answer and score confidence.",
            strategy: :cot,
            timeout: 45_000,
            options: %{max_supervision_steps: 7, act_threshold: 0.95}
          },
          source: "/test"
        )

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               TRM.handle_signal(signal, %{})

      assert params.strategy == :trm
      assert params.prompt == "Iteratively improve this answer and score confidence."
      assert params.timeout == 45_000
      assert params.options == %{max_supervision_steps: 7, act_threshold: 0.95}
    end

    test "normalizes non-map payload data and still injects strategy" do
      signal =
        Jido.Signal.new!("reasoning.trm.run", %{prompt: "placeholder"}, source: "/test")
        |> Map.put(:data, :not_a_map)

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               TRM.handle_signal(signal, %{})

      assert params == %{strategy: :trm}
    end
  end

  describe "documentation contracts" do
    test "developer guide explains TRM plugin handoff, options, and defaults" do
      plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
      plugin_module_docs = File.read!("lib/jido_ai/plugins/reasoning/trm.ex")

      assert plugin_guide =~ "### TRM Plugin Handoff (`reasoning.trm.run`)"
      assert plugin_guide =~ "{Jido.AI.Plugins.Reasoning.TRM,"
      assert plugin_guide =~ "Jido.AI.Actions.Reasoning.RunStrategy"
      assert plugin_guide =~ "strategy: :trm"
      assert plugin_guide =~ "max_supervision_steps"
      assert plugin_guide =~ "act_threshold"
      assert plugin_guide =~ "## Reasoning TRM Plugin Defaults Contract"
      assert plugin_guide =~ "default_model: :reasoning"
      assert plugin_guide =~ "timeout: 30_000"
      assert plugin_guide =~ "options: %{}"

      assert plugin_module_docs =~ "## Signal Contracts"
      assert plugin_module_docs =~ "## Plugin-To-Action Handoff"
      assert plugin_module_docs =~ "## Usage"
      assert plugin_module_docs =~ "## TRM Options"
      assert plugin_module_docs =~ "## Mount State Defaults"
    end

    test "examples index includes TRM plugin execution path" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Plugin Capability Pattern"
      assert examples_readme =~ "| Reasoning TRM plugin | Mount `Jido.AI.Plugins.Reasoning.TRM`"
      assert examples_readme =~ "{Jido.AI.Plugins.Reasoning.TRM,"
      assert examples_readme =~ "reasoning.trm.run"
      assert examples_readme =~ "max_supervision_steps"
      assert examples_readme =~ "Jido.AI.Actions.Reasoning.RunStrategy"
    end
  end
end
