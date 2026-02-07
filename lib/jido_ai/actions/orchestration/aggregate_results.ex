defmodule Jido.AI.Actions.Orchestration.AggregateResults do
  @moduledoc """
  Aggregate results from multiple child agents or parallel executions.

  This action combines results using various strategies, from simple
  merging to LLM-powered summarization.

  ## Parameters

  * `results` (required) - List of result maps to aggregate
  * `strategy` (optional) - Aggregation strategy (default: `:merge`)
  * `model` (optional) - Model for LLM summarization

  ## Strategies

  * `:merge` - Deep merge all results
  * `:best` - Select result with highest score/confidence
  * `:vote` - Majority vote for categorical results
  * `:llm_summarize` - Use LLM to synthesize results

  ## Examples

      {:ok, result} = Jido.Exec.run(AggregateResults, %{
        results: [
          %{source: :worker_1, data: %{count: 10}},
          %{source: :worker_2, data: %{count: 15}}
        ],
        strategy: :merge
      })

      # LLM summarization
      {:ok, result} = Jido.Exec.run(AggregateResults, %{
        results: [
          %{source: :analyst_1, analysis: "Market is bullish..."},
          %{source: :analyst_2, analysis: "Cautious outlook..."}
        ],
        strategy: :llm_summarize,
        model: "anthropic:claude-haiku-4-5"
      })

  ## Result

      %{
        aggregated: <combined result>,
        sources: [:worker_1, :worker_2],
        strategy: :merge
      }
  """

  use Jido.Action,
    name: "aggregate_results",
    description: "Aggregate results from multiple sources",
    category: "orchestration",
    tags: ["orchestration", "aggregation", "results"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        results: Zoi.list(Zoi.map(), description: "List of result maps to aggregate"),
        strategy:
          Zoi.any(description: "Aggregation strategy: :merge, :best, :vote, :llm_summarize")
          |> Zoi.default(:merge),
        model: Zoi.string(description: "Model for LLM summarization") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers

  @impl Jido.Action
  def run(params, _context) do
    results = params.results
    strategy = params[:strategy] || :merge
    sources = Enum.map(results, fn r -> r[:source] || :unknown end)

    case aggregate(results, strategy, params) do
      {:ok, aggregated} ->
        {:ok, %{aggregated: aggregated, sources: sources, strategy: strategy}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp aggregate(results, :merge, _params) do
    merged =
      results
      |> Enum.map(&Map.delete(&1, :source))
      |> Enum.reduce(%{}, &deep_merge/2)

    {:ok, merged}
  end

  defp aggregate(results, :best, _params) do
    best =
      results
      |> Enum.max_by(fn r -> r[:score] || r[:confidence] || 0 end, fn -> nil end)

    {:ok, best}
  end

  defp aggregate(results, :vote, _params) do
    votes =
      results
      |> Enum.map(fn r -> r[:decision] || r[:value] || r[:result] end)
      |> Enum.frequencies()

    {winner, _count} = Enum.max_by(votes, fn {_k, v} -> v end, fn -> {nil, 0} end)
    {:ok, %{decision: winner, votes: votes}}
  end

  defp aggregate(results, :llm_summarize, params) do
    with {:ok, model} <- Helpers.resolve_model(params[:model], :fast) do
      prompt = build_summarize_prompt(results)

      case ReqLLM.Generation.generate_text(model, [%{role: :user, content: prompt}]) do
        {:ok, response} ->
          {:ok, %{summary: Helpers.extract_text(response), inputs: results}}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp aggregate(_results, strategy, _params) do
    {:error, {:unknown_strategy, strategy}}
  end

  defp build_summarize_prompt(results) do
    results_text =
      results
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {r, i} ->
        "Result #{i} (from #{r[:source] || "unknown"}):\n#{inspect(r, pretty: true)}"
      end)

    """
    Synthesize these results from multiple agents into a coherent summary:

    #{results_text}

    Provide a clear, unified summary that captures the key insights from all sources.
    """
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _k, lv, rv when is_map(lv) and is_map(rv) -> deep_merge(lv, rv)
      _k, _lv, rv -> rv
    end)
  end

  defp deep_merge(_left, right), do: right
end
