defmodule Jido.AI.Examples.Weather.AoTAgent do
  @moduledoc """
  Algorithm-of-Thoughts weather planner.

  Uses single-pass algorithmic exploration to evaluate weather-aware options.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.AoTAgent \\
        "Find the best weather-safe weekend option with a fallback plan."
  """

  alias Jido.AI.Examples.Weather.LiveContext

  use Jido.AI.AoTAgent,
    name: "weather_aot_agent",
    description: "Weather assistant using Algorithm-of-Thoughts search",
    profile: :standard,
    search_style: :dfs,
    require_explicit_answer: true

  @doc "Returns the CLI adapter used by `mix jido_ai` for this example."
  @spec cli_adapter() :: module()
  def cli_adapter, do: Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter

  @doc "Get weather-aware options using AoT exploration."
  @spec weekend_options_sync(pid(), String.t(), keyword()) :: {:ok, any()} | {:error, term()}
  def weekend_options_sync(pid, request, opts \\ []) do
    explore_sync(
      pid,
      "Use algorithm-of-thoughts search to compare weather-aware options and choose one: #{request}",
      opts
    )
  end

  @impl true
  def on_before_cmd(agent, {:aot_start, %{prompt: prompt} = params}) do
    case LiveContext.enrich_prompt(prompt) do
      {:ok, enriched_prompt} -> super(agent, {:aot_start, %{params | prompt: enriched_prompt}})
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def on_before_cmd(agent, action), do: super(agent, action)
end
