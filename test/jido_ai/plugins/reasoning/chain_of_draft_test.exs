defmodule Jido.AI.Plugins.Reasoning.ChainOfDraftTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Reasoning.ChainOfDraft

  describe "plugin_spec/1" do
    test "returns valid plugin spec" do
      spec = ChainOfDraft.plugin_spec(%{})

      assert spec.module == ChainOfDraft
      assert spec.name == "reasoning_chain_of_draft"
      assert spec.state_key == :reasoning_cod
      assert spec.category == "ai"
      assert spec.actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = ChainOfDraft.mount(%Jido.Agent{}, %{})

      assert state.strategy == :cod
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} = ChainOfDraft.mount(%Jido.Agent{}, %{})
      assert {:ok, _parsed_state} = Zoi.parse(ChainOfDraft.schema(), state)
    end
  end

  describe "signal routing" do
    test "routes reasoning.cod.run to RunStrategy" do
      routes = ChainOfDraft.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.cod.run"] == Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "handle_signal/2" do
    test "forces strategy :cod and overrides caller strategy input" do
      signal =
        Jido.Signal.new!(
          "reasoning.cod.run",
          %{prompt: "solve this quickly", strategy: :cot, timeout: 45_000, options: %{depth: 2}},
          source: "/test"
        )

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               ChainOfDraft.handle_signal(signal, %{})

      assert params.strategy == :cod
      assert params.prompt == "solve this quickly"
      assert params.timeout == 45_000
      assert params.options == %{depth: 2}
    end

    test "normalizes non-map payload data and still injects strategy" do
      signal =
        Jido.Signal.new!("reasoning.cod.run", %{prompt: "placeholder"}, source: "/test")
        |> Map.put(:data, :not_a_map)

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               ChainOfDraft.handle_signal(signal, %{})

      assert params == %{strategy: :cod}
    end
  end

  describe "documentation contracts" do
    test "developer guide explains CoD plugin handoff to RunStrategy" do
      plugin_guide = File.read!("guides/developer/plugins_and_actions_composition.md")
      plugin_module_docs = File.read!("lib/jido_ai/plugins/reasoning/chain_of_draft.ex")

      assert plugin_guide =~ "### CoD Plugin Handoff (`reasoning.cod.run`)"
      assert plugin_guide =~ "{Jido.AI.Plugins.Reasoning.ChainOfDraft,"
      assert plugin_guide =~ "Jido.AI.Actions.Reasoning.RunStrategy"
      assert plugin_guide =~ "strategy: :cod"

      assert plugin_module_docs =~ "## Signal Contracts"
      assert plugin_module_docs =~ "## Plugin-To-Action Handoff"
      assert plugin_module_docs =~ "## Mount State Defaults"
    end

    test "examples index includes CoD plugin execution path" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Plugin Capability Pattern"
      assert examples_readme =~ "| Reasoning CoD plugin | Mount `Jido.AI.Plugins.Reasoning.ChainOfDraft`"
      assert examples_readme =~ "{Jido.AI.Plugins.Reasoning.ChainOfDraft,"
      assert examples_readme =~ "reasoning.cod.run"
      assert examples_readme =~ "Jido.AI.Actions.Reasoning.RunStrategy"
    end
  end
end
