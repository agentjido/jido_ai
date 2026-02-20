defmodule Jido.AI.Examples.WeatherStrategySuiteTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapter

  alias Jido.AI.Examples.Weather.{
    AdaptiveAgent,
    AoTAgent,
    CoDAgent,
    CoTAgent,
    GoTAgent,
    Overview,
    ReActAgent,
    ToTAgent,
    TRMAgent
  }

  @normalized_strategy_docs [
    "lib/examples/strategies/aot.md",
    "lib/examples/strategies/adaptive.md",
    "lib/examples/strategies/cod.md",
    "lib/examples/strategies/cot.md",
    "lib/examples/strategies/got.md",
    "lib/examples/strategies/react.md",
    "lib/examples/strategies/tot.md",
    "lib/examples/strategies/trm.md"
  ]

  @legacy_strategy_docs [
    "examples/strategies/algorithm_of_thoughts.md",
    "lib/examples/strategies/algorithm_of_thoughts.md",
    "lib/examples/strategies/adaptive_strategy.md",
    "lib/examples/strategies/chain_of_draft.md",
    "lib/examples/strategies/chain_of_thought.md",
    "lib/examples/strategies/graph_of_thoughts.md",
    "lib/examples/strategies/react_agent.md",
    "lib/examples/strategies/tree_of_thoughts.md",
    "lib/examples/strategies/trm_strategy.md"
  ]

  @weather_matrix_rows [
    {"ReAct", "Jido.AI.Examples.Weather.ReActAgent", "lib/examples/strategies/react.md"},
    {"CoD", "Jido.AI.Examples.Weather.CoDAgent", "lib/examples/strategies/cod.md"},
    {"AoT", "Jido.AI.Examples.Weather.AoTAgent", "lib/examples/strategies/aot.md"},
    {"CoT", "Jido.AI.Examples.Weather.CoTAgent", "lib/examples/strategies/cot.md"},
    {"ToT", "Jido.AI.Examples.Weather.ToTAgent", "lib/examples/strategies/tot.md"},
    {"GoT", "Jido.AI.Examples.Weather.GoTAgent", "lib/examples/strategies/got.md"},
    {"TRM", "Jido.AI.Examples.Weather.TRMAgent", "lib/examples/strategies/trm.md"},
    {"Adaptive", "Jido.AI.Examples.Weather.AdaptiveAgent", "lib/examples/strategies/adaptive.md"}
  ]

  describe "overview" do
    test "returns all strategy modules" do
      assert Overview.agents() == %{
               react: ReActAgent,
               cod: CoDAgent,
               aot: AoTAgent,
               cot: CoTAgent,
               tot: ToTAgent,
               got: GoTAgent,
               trm: TRMAgent,
               adaptive: AdaptiveAgent
             }
    end
  end

  describe "strategy docs and index" do
    test "keeps only normalized strategy markdown paths" do
      strategy_docs = Path.wildcard("lib/examples/strategies/*.md")

      Enum.each(@normalized_strategy_docs, fn path ->
        assert path in strategy_docs
      end)

      Enum.each(@legacy_strategy_docs, fn path ->
        refute File.exists?(path)
      end)
    end

    test "documents a single weather matrix with cod parity and script categories" do
      examples_readme = File.read!("lib/examples/README.md")

      assert examples_readme =~ "## Weather Strategy Matrix"
      assert examples_readme =~ "| Strategy | Weather Module | Strategy Markdown | CLI Demo |"

      Enum.each(@weather_matrix_rows, fn {strategy, module_name, doc_path} ->
        assert examples_readme =~ strategy
        assert examples_readme =~ module_name
        assert examples_readme =~ doc_path
      end)

      assert examples_readme =~ "| CoD | `Jido.AI.Examples.Weather.CoDAgent`"
      assert examples_readme =~ "| AoT | `Jido.AI.Examples.Weather.AoTAgent` (`lib/examples/weather/aot_agent.ex`) |"
      assert examples_readme =~ "mix jido_ai --agent Jido.AI.Examples.Weather.AoTAgent"
      assert examples_readme =~ "Find the best weather-safe weekend option with one backup."
      assert examples_readme =~ "## Script Index"
      assert examples_readme =~ "| `browser_demo.exs` | Canonical demo |"
      assert examples_readme =~ "| `test_weather_agent.exs` | Utility verification |"
    end

    test "docs extras and readmes point to normalized strategy docs" do
      docs_extras = Mix.Project.config()[:docs] |> Keyword.fetch!(:extras)
      root_readme = File.read!("README.md")
      examples_readme = File.read!("lib/examples/README.md")

      Enum.each(@normalized_strategy_docs, fn path ->
        assert path in docs_extras
        assert root_readme =~ path
        assert examples_readme =~ path
      end)

      Enum.each(@legacy_strategy_docs, fn path ->
        refute path in docs_extras
        refute root_readme =~ path
        refute examples_readme =~ path
      end)
    end
  end

  describe "mix jido_ai adapter resolution" do
    test "uses each example module's declared cli adapter" do
      assert {:ok, Jido.AI.Reasoning.ReAct.CLIAdapter} = Adapter.resolve(nil, ReActAgent)
      assert {:ok, Jido.AI.Reasoning.ChainOfDraft.CLIAdapter} = Adapter.resolve(nil, CoDAgent)
      assert {:ok, Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter} = Adapter.resolve(nil, AoTAgent)
      assert {:ok, Jido.AI.Reasoning.ChainOfThought.CLIAdapter} = Adapter.resolve(nil, CoTAgent)
      assert {:ok, Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter} = Adapter.resolve(nil, ToTAgent)
      assert {:ok, Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter} = Adapter.resolve(nil, GoTAgent)
      assert {:ok, Jido.AI.Reasoning.TRM.CLIAdapter} = Adapter.resolve(nil, TRMAgent)
      assert {:ok, Jido.AI.Reasoning.Adaptive.CLIAdapter} = Adapter.resolve(nil, AdaptiveAgent)
    end
  end

  describe "helper entrypoints" do
    test "exports strategy-specific helper APIs" do
      Code.ensure_loaded!(ReActAgent)
      Code.ensure_loaded!(CoDAgent)
      Code.ensure_loaded!(AoTAgent)
      Code.ensure_loaded!(CoTAgent)
      Code.ensure_loaded!(ToTAgent)
      Code.ensure_loaded!(GoTAgent)
      Code.ensure_loaded!(TRMAgent)
      Code.ensure_loaded!(AdaptiveAgent)

      assert function_exported?(ReActAgent, :commute_plan_sync, 3)
      assert function_exported?(CoDAgent, :quick_plan_sync, 3)
      assert function_exported?(AoTAgent, :weekend_options_sync, 3)
      assert function_exported?(CoTAgent, :weather_decision_sync, 3)
      assert function_exported?(ToTAgent, :weekend_options_sync, 3)
      assert function_exported?(ToTAgent, :format_top_options, 2)
      assert function_exported?(GoTAgent, :multi_city_sync, 3)
      assert function_exported?(TRMAgent, :storm_readiness_sync, 3)
      assert function_exported?(AdaptiveAgent, :coach_sync, 3)
    end
  end
end
