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
end
