defmodule Jido.AI.Examples.Weather.AdaptiveAgent do
  @moduledoc """
  Adaptive weather orchestrator.

  Automatically chooses the best reasoning strategy based on the user request:
  direct advice, structured analysis, alternatives, synthesis, or recursive
  refinement.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.AdaptiveAgent \\
        "I need a weather-aware commute and backup plan for tomorrow."
  """

  use Jido.AI.AdaptiveAgent,
    name: "weather_adaptive_agent",
    description: "Adaptive weather assistant across all reasoning modes",
    default_strategy: :react,
    available_strategies: [:react, :cot, :tot, :got, :trm]

  @doc "Returns the CLI adapter used by `mix jido_ai` for this example."
  @spec cli_adapter() :: module()
  def cli_adapter, do: Jido.AI.Reasoning.Adaptive.CLIAdapter

  @doc """
  Ask for weather guidance and let the agent pick the strategy.
  """
  @spec coach_sync(pid(), String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def coach_sync(pid, request, opts \\ []) do
    ask_sync(
      pid,
      "Handle this weather planning request with the most appropriate reasoning strategy: #{request}",
      opts
    )
  end
end
