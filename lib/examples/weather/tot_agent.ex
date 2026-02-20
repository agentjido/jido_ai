defmodule Jido.AI.Examples.Weather.ToTAgent do
  @moduledoc """
  Tree-of-Thoughts weather planner.

  Useful for exploring multiple alternatives when weather is uncertain.

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.Weather.ToTAgent \\
        "Plan three weekend options for Boston if weather is uncertain."
  """

  use Jido.AI.ToTAgent,
    name: "weather_tot_agent",
    description: "Weather scenario planner using Tree-of-Thoughts",
    branching_factor: 3,
    max_depth: 4,
    top_k: 3,
    min_depth: 2,
    max_nodes: 90,
    max_duration_ms: 25_000

  def cli_adapter, do: Jido.AI.Reasoning.TreeOfThoughts.CLIAdapter

  @doc """
  Produce weather-resilient weekend options for a location.
  """
  @spec weekend_options_sync(pid(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def weekend_options_sync(pid, location, opts \\ []) do
    explore_sync(
      pid,
      "Create three weather-resilient weekend plans for #{location}. Include a sunny option, mixed-conditions option, and rain-first option.",
      opts
    )
  end

  @doc """
  Formats top-ranked candidate plans for quick CLI/demo display.
  """
  @spec format_top_options(map(), pos_integer()) :: String.t()
  def format_top_options(result, limit \\ 3)

  def format_top_options(%{} = result, limit) do
    result
    |> Jido.AI.Reasoning.TreeOfThoughts.Result.top_candidates(limit)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {candidate, idx} ->
      score = format_score(candidate[:score])
      content = candidate[:content] || "(no content)"
      "#{idx}. #{content} (score: #{score})"
    end)
  end

  def format_top_options(_result, _limit), do: ""

  defp format_score(score) when is_number(score), do: :erlang.float_to_binary(score * 1.0, decimals: 2)
  defp format_score(_), do: "n/a"
end
