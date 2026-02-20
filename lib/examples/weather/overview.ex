defmodule Jido.AI.Examples.Weather.Overview do
  @moduledoc """
  Strategy-specific weather agents that are easy to run from `mix jido_ai`.

  This module is a lightweight index for the weather examples in `lib/examples`.

  ## Included Agents

  - ReAct: `Jido.AI.Examples.Weather.ReActAgent`
  - Chain-of-Thought: `Jido.AI.Examples.Weather.CoTAgent`
  - Tree-of-Thoughts: `Jido.AI.Examples.Weather.ToTAgent`
  - Graph-of-Thoughts: `Jido.AI.Examples.Weather.GoTAgent`
  - TRM: `Jido.AI.Examples.Weather.TRMAgent`
  - Adaptive: `Jido.AI.Examples.Weather.AdaptiveAgent`
  """

  @type strategy :: :react | :cot | :tot | :got | :trm | :adaptive

  @doc """
  Returns the strategy -> module map for the weather example suite.
  """
  @spec agents() :: %{strategy() => module()}
  def agents do
    %{
      react: Jido.AI.Examples.Weather.ReActAgent,
      cot: Jido.AI.Examples.Weather.CoTAgent,
      tot: Jido.AI.Examples.Weather.ToTAgent,
      got: Jido.AI.Examples.Weather.GoTAgent,
      trm: Jido.AI.Examples.Weather.TRMAgent,
      adaptive: Jido.AI.Examples.Weather.AdaptiveAgent
    }
  end

  @doc """
  Handy CLI commands for trying each weather strategy.
  """
  @spec cli_examples() :: [String.t()]
  def cli_examples do
    [
      ~s(mix jido_ai --agent Jido.AI.Examples.Weather.ReActAgent "Do I need an umbrella in Seattle tomorrow morning?"),
      ~s(mix jido_ai --agent Jido.AI.Examples.Weather.CoTAgent "How should I decide between biking and transit in rainy weather?"),
      ~s(mix jido_ai --agent Jido.AI.Examples.Weather.ToTAgent "Plan three weekend options for Boston if weather is uncertain."),
      ~s(mix jido_ai --agent Jido.AI.Examples.Weather.GoTAgent "Compare weather risks across NYC, Chicago, and Denver for a trip."),
      ~s(mix jido_ai --agent Jido.AI.Examples.Weather.TRMAgent "Stress test this storm-prep plan and improve it."),
      ~s(mix jido_ai --agent Jido.AI.Examples.Weather.AdaptiveAgent "I need a weather-aware commute and backup plan for tomorrow.")
    ]
  end
end
