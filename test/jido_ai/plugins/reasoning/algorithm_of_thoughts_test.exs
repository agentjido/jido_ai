defmodule Jido.AI.Plugins.Reasoning.AlgorithmOfThoughtsTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts

  describe "plugin_spec/1" do
    test "returns valid plugin spec" do
      spec = AlgorithmOfThoughts.plugin_spec(%{})

      assert spec.module == AlgorithmOfThoughts
      assert spec.name == "reasoning_algorithm_of_thoughts"
      assert spec.state_key == :reasoning_aot
      assert spec.category == "ai"
      assert is_list(spec.actions)
      assert spec.actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end

    test "includes config in plugin spec" do
      config = %{default_model: :capable, timeout: 15_000}
      spec = AlgorithmOfThoughts.plugin_spec(config)

      assert spec.config == config
    end
  end

  describe "mount/2" do
    test "initializes state with defaults" do
      {:ok, state} = AlgorithmOfThoughts.mount(%Jido.Agent{}, %{})

      assert state.strategy == :aot
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end

    test "merges custom config into initial state, including AoT options" do
      {:ok, state} =
        AlgorithmOfThoughts.mount(%Jido.Agent{}, %{
          default_model: :fast,
          timeout: 5_000,
          options: %{profile: :long, search_style: :bfs, llm_timeout_ms: 2_000}
        })

      assert state.strategy == :aot
      assert state.default_model == :fast
      assert state.timeout == 5_000
      assert state.options == %{profile: :long, search_style: :bfs, llm_timeout_ms: 2_000}
    end

    test "mounted state validates against plugin schema" do
      {:ok, state} = AlgorithmOfThoughts.mount(%Jido.Agent{}, %{})

      assert {:ok, _parsed_state} = Zoi.parse(AlgorithmOfThoughts.schema(), state)
    end
  end

  describe "schema/0" do
    test "applies default values for AoT plugin state" do
      assert {:ok, state} = Zoi.parse(AlgorithmOfThoughts.schema(), %{})

      assert state.strategy == :aot
      assert state.default_model == :reasoning
      assert state.timeout == 30_000
      assert state.options == %{}
    end
  end

  describe "actions" do
    test "returns RunStrategy action" do
      actions = AlgorithmOfThoughts.actions()

      assert actions == [Jido.AI.Actions.Reasoning.RunStrategy]
    end
  end

  describe "signal routing" do
    test "routes reasoning.aot.run to RunStrategy" do
      routes = AlgorithmOfThoughts.signal_routes(%{})
      route_map = Map.new(routes)

      assert route_map["reasoning.aot.run"] == Jido.AI.Actions.Reasoning.RunStrategy
    end
  end

  describe "handle_signal/2" do
    test "forces strategy :aot and preserves AoT-specific options" do
      signal =
        Jido.Signal.new!(
          "reasoning.aot.run",
          %{
            prompt: "solve using algorithmic steps",
            strategy: :cot,
            timeout: 45_000,
            options: %{profile: :short, search_style: :dfs, require_explicit_answer: true}
          },
          source: "/test"
        )

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               AlgorithmOfThoughts.handle_signal(signal, %{})

      assert params.strategy == :aot
      assert params.prompt == "solve using algorithmic steps"
      assert params.timeout == 45_000
      assert params.options == %{profile: :short, search_style: :dfs, require_explicit_answer: true}
    end

    test "normalizes non-map payload data and still injects strategy" do
      signal =
        Jido.Signal.new!("reasoning.aot.run", %{prompt: "placeholder"}, source: "/test")
        |> Map.put(:data, :not_a_map)

      assert {:ok, {:override, {Jido.AI.Actions.Reasoning.RunStrategy, params}}} =
               AlgorithmOfThoughts.handle_signal(signal, %{})

      assert params == %{strategy: :aot}
    end
  end
end
