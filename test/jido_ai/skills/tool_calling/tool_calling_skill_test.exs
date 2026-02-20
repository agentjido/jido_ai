defmodule Jido.AI.Plugins.Reasoning.ChainOfThoughtTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Reasoning.ChainOfThought

  describe "plugin_spec/1" do
    test "returns valid plugin spec" do
      spec = ChainOfThought.plugin_spec(%{})

      assert spec.module == ChainOfThought
      assert spec.name == "reasoning_chain_of_thought"
      assert spec.state_key == :reasoning_cot
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert spec.actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end

    test "includes config in plugin spec" do
      config = %{default_model: :capable, timeout: 15_000}
      spec = ChainOfThought.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = ChainOfThought.mount(%Jido.Agent{}, %{})

      assert state.strategy == :cot
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end

    test "merges custom config into initial state" do
      {:ok, state} =
        ChainOfThought.mount(%Jido.Agent{}, %{default_model: :fast, timeout: 5000, options: %{llm_timeout_ms: 2000}})

      assert state.strategy == :cot
      assert state.default_model == :fast
      assert state.timeout == 5000
      assert state.options == %{llm_timeout_ms: 2000}
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} = ChainOfThought.mount(%Jido.Agent{}, %{})

      assert {:ok, _parsed_state} = Zoi.parse(ChainOfThought.schema(), state)
    end
  end

  describe "schema/0" do
    test "applies default values for cot plugin state" do
      assert {:ok, state} = Zoi.parse(ChainOfThought.schema(), %{})

      assert state.strategy == :cot
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end
  end

  describe "actions" do
    test "returns RunStrategy action" do
      actions = ChainOfThought.actions()

      assert actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end
  end

  describe "signal routing" do
    test "routes reasoning.cot.run to RunStrategy" do
      routes = ChainOfThought.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.cot.run"] == Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "handle_signal/2" do
    test "forces strategy :cot and overrides caller strategy input" do
      signal =
        Jido.Signal.new!(
          "reasoning.cot.run",
          %{prompt: "reason through this", strategy: :cod, timeout: 45_000, options: %{depth: 2}},
          source: "/test"
        )

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               ChainOfThought.handle_signal(signal, %{})

      assert params.strategy == :cot
      assert params.prompt == "reason through this"
      assert params.timeout == 45_000
      assert params.options == %{depth: 2}
    end

    test "normalizes non-map payload data and still injects strategy" do
      signal =
        Jido.Signal.new!("reasoning.cot.run", %{prompt: "placeholder"}, source: "/test")
        |> Map.put(:data, :not_a_map)

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               ChainOfThought.handle_signal(signal, %{})

      assert params == %{strategy: :cot}
    end
  end

  describe "documentation contracts" do
    test "developer guide explains CoT plugin handoff and defaults" do
      plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
      plugin_module_docs = File.read!("lib/jido_ai/plugins/reasoning/chain_of_thought.ex")

      assert plugin_guide =~ "### CoT Plugin Handoff (`reasoning.cot.run`)"
      assert plugin_guide =~ "{Jido.AI.Plugins.Reasoning.ChainOfThought,"
      assert plugin_guide =~ "Jido.AI.Actions.Reasoning.RunStrategy"
      assert plugin_guide =~ "strategy: :cot"
      assert plugin_guide =~ "## Reasoning CoT Plugin Defaults Contract"
      assert plugin_guide =~ "default_model: :reasoning"
      assert plugin_guide =~ "timeout: 30_000"
      assert plugin_guide =~ "options: %{}"

      assert plugin_module_docs =~ "## Signal Contracts"
      assert plugin_module_docs =~ "## Plugin-To-Action Handoff"
      assert plugin_module_docs =~ "## Mount State Defaults"
    end

    test "examples index includes CoT plugin execution path" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Plugin Capability Pattern"
      assert examples_readme =~ "| Reasoning CoT plugin | Mount `Jido.AI.Plugins.Reasoning.ChainOfThought`"
      assert examples_readme =~ "{Jido.AI.Plugins.Reasoning.ChainOfThought,"
      assert examples_readme =~ "reasoning.cot.run"
      assert examples_readme =~ "Jido.AI.Actions.Reasoning.RunStrategy"
    end
  end
end
