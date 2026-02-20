defmodule Jido.AI.Examples.Weather.GoTAgent do
  @moduledoc """
  Graph-of-Thoughts weather synthesizer.

  Useful for combining weather insights across many locations and constraints.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.GoTAgent \\
        "Compare weather risks across NYC, Chicago, and Denver for a trip."
  """

  alias Jido.AI.Examples.Weather.LiveContext

  use Jido.AI.GoTAgent,
    name: "weather_got_agent",
    description: "Multi-location weather synthesis using Graph-of-Thoughts",
    max_nodes: 18,
    max_depth: 4,
    aggregation_strategy: :synthesis,
    generation_prompt: """
    Create thought nodes for weather planning:
    - location-specific risk
    - timing windows
    - transportation impact
    - packing implications
    """,
    connection_prompt: """
    Connect nodes when they share:
    - similar weather risk patterns
    - common travel constraints
    - opportunities for one reusable plan
    """,
    aggregation_prompt: """
    Produce a single recommendation that includes:
    - per-location highlights
    - cross-location patterns
    - one concise travel strategy
    """

  @doc "Returns the CLI adapter used by `mix jido_ai` for this example."
  @spec cli_adapter() :: module()
  def cli_adapter, do: Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter

  @doc """
  Synthesize weather guidance across multiple cities.
  """
  @spec multi_city_sync(pid(), [String.t()], keyword()) :: {:ok, any()} | {:error, term()}
  def multi_city_sync(pid, cities, opts \\ []) when is_list(cities) and cities != [] do
    city_list = Enum.join(cities, ", ")

    explore_sync(
      pid,
      "Compare weather-dependent travel risk across: #{city_list}. Provide a single strategy that works across all cities with city-specific adjustments.",
      opts
    )
  end

  @impl true
  def on_before_cmd(agent, {:got_start, %{prompt: prompt} = params}) do
    case LiveContext.enrich_prompt(prompt) do
      {:ok, enriched_prompt} -> super(agent, {:got_start, %{params | prompt: enriched_prompt}})
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_before_cmd(agent, action), do: super(agent, action)
end
