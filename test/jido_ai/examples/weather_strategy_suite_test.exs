defmodule Jido.AI.Examples.WeatherStrategySuiteTest do
  use ExUnit.Case, async: true

  alias Jido.AI.CLI.Adapter

  alias Jido.AI.Examples.Weather.{
    AdaptiveAgent,
    CoTAgent,
    GoTAgent,
    Overview,
    ReActAgent,
    ToTAgent,
    TRMAgent
  }

  describe "overview" do
    test "returns all strategy modules" do
      assert Overview.agents() == %{
               react: ReActAgent,
               cot: CoTAgent,
               tot: ToTAgent,
               got: GoTAgent,
               trm: TRMAgent,
               adaptive: AdaptiveAgent
             }
    end
  end

  describe "mix jido_ai adapter resolution" do
    test "uses each example module's declared cli adapter" do
      assert {:ok, Jido.AI.Reasoning.ReAct.CLIAdapter} = Adapter.resolve(nil, ReActAgent)
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
      Code.ensure_loaded!(CoTAgent)
      Code.ensure_loaded!(ToTAgent)
      Code.ensure_loaded!(GoTAgent)
      Code.ensure_loaded!(TRMAgent)
      Code.ensure_loaded!(AdaptiveAgent)

      assert function_exported?(ReActAgent, :commute_plan_sync, 3)
      assert function_exported?(CoTAgent, :weather_decision_sync, 3)
      assert function_exported?(ToTAgent, :weekend_options_sync, 3)
      assert function_exported?(ToTAgent, :format_top_options, 2)
      assert function_exported?(GoTAgent, :multi_city_sync, 3)
      assert function_exported?(TRMAgent, :storm_readiness_sync, 3)
      assert function_exported?(AdaptiveAgent, :coach_sync, 3)
    end
  end
end
