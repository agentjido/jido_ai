defmodule Jido.AI.Plugins.Reasoning.GraphOfThoughtsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Reasoning.GraphOfThoughts

  describe "plugin_spec/1" do
    test "returns valid plugin spec" do
      spec = GraphOfThoughts.plugin_spec(%{})

      assert spec.module == GraphOfThoughts
      assert spec.name == "reasoning_graph_of_thoughts"
      assert spec.state_key == :reasoning_got
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert spec.actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end

    test "includes config in plugin spec" do
      config = %{default_model: :capable, timeout: 15_000}
      spec = GraphOfThoughts.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = GraphOfThoughts.mount(%Jido.Agent{}, %{})

      assert state.strategy == :got
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end

    test "merges custom config into initial state, including GoT options" do
      {:ok, state} =
        GraphOfThoughts.mount(%Jido.Agent{}, %{
          default_model: :fast,
          timeout: 5_000,
          options: %{max_nodes: 24, max_depth: 6, aggregation_strategy: :weighted}
        })

      assert state.strategy == :got
      assert state.default_model == :fast
      assert state.timeout == 5_000
      assert state.options == %{max_nodes: 24, max_depth: 6, aggregation_strategy: :weighted}
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} = GraphOfThoughts.mount(%Jido.Agent{}, %{})

      assert {:ok, _parsed_state} = Zoi.parse(GraphOfThoughts.schema(), state)
    end
  end

  describe "schema/0" do
    test "applies default values for GoT plugin state" do
      assert {:ok, state} = Zoi.parse(GraphOfThoughts.schema(), %{})

      assert state.strategy == :got
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end
  end

  describe "actions" do
    test "returns RunStrategy action" do
      actions = GraphOfThoughts.actions()

      assert actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end
  end

  describe "signal routing" do
    test "routes reasoning.got.run to RunStrategy" do
      routes = GraphOfThoughts.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.got.run"] == Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "handle_signal/2" do
    test "forces strategy :got and preserves GoT options" do
      signal =
        Jido.Signal.new!(
          "reasoning.got.run",
          %{
            prompt: "connect weather constraints",
            strategy: :cot,
            timeout: 45_000,
            options: %{max_nodes: 24, max_depth: 6, aggregation_strategy: :weighted}
          },
          source: "/test"
        )

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               GraphOfThoughts.handle_signal(signal, %{})

      assert params.strategy == :got
      assert params.prompt == "connect weather constraints"
      assert params.timeout == 45_000
      assert params.options == %{max_nodes: 24, max_depth: 6, aggregation_strategy: :weighted}
    end

    test "normalizes non-map payload data and still injects strategy" do
      signal =
        Jido.Signal.new!("reasoning.got.run", %{prompt: "placeholder"}, source: "/test")
        |> Map.put(:data, :not_a_map)

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               GraphOfThoughts.handle_signal(signal, %{})

      assert params == %{strategy: :got}
    end
  end
end
