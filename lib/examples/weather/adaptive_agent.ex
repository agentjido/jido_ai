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

  alias Jido.AI.Examples.Weather.LiveContext

  use Jido.AI.AdaptiveAgent,
    name: "weather_adaptive_agent",
    description: "Adaptive weather assistant across all reasoning modes",
    tools: [
      Jido.Tools.Weather.Geocode,
      Jido.Tools.Weather.Forecast,
      Jido.Tools.Weather.HourlyForecast,
      Jido.Tools.Weather.CurrentConditions,
      Jido.Tools.Weather.LocationToGrid
    ],
    default_strategy: :cot,
    available_strategies: [:cot, :tot, :got, :trm]

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

  @impl true
  def on_before_cmd(agent, {:adaptive_start, %{prompt: prompt} = params}) do
    case LiveContext.enrich_prompt(prompt) do
      {:ok, enriched_prompt} -> super(agent, {:adaptive_start, %{params | prompt: enriched_prompt}})
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_before_cmd(agent, action), do: super(agent, action)
end
