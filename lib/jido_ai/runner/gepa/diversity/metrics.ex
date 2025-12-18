defmodule Jido.AI.Runner.GEPA.Diversity.Metrics do
  @moduledoc """
  Calculates diversity metrics for prompt populations.

  Provides multiple measures of population diversity:
  - **Pairwise Diversity**: Average distance between all prompt pairs
  - **Entropy**: Information-theoretic measure of variety
  - **Coverage**: Ratio of unique to total prompts
  - **Uniqueness Ratio**: Fraction below similarity threshold
  - **Clustering Coefficient**: How clustered the population is
  - **Convergence Risk**: Estimated risk of premature convergence

  ## Usage

      {:ok, metrics} = Metrics.calculate(prompts)
      metrics.pairwise_diversity  # => 0.65
      metrics.diversity_level     # => :healthy

      # With similarity matrix
      {:ok, matrix} = SimilarityDetector.build_matrix(prompts)
      {:ok, metrics} = Metrics.calculate_from_matrix(matrix)
  """

  alias Jido.AI.Runner.GEPA.Diversity.{DiversityMetrics, SimilarityDetector, SimilarityMatrix}

  # Diversity level thresholds
  @critical_threshold 0.15
  @low_threshold 0.30
  @moderate_threshold 0.50
  @healthy_threshold 0.70

  @doc """
  Calculates diversity metrics for a population.

  ## Parameters

  - `prompts` - List of prompts
  - `opts` - Options:
    - `:similarity_strategy` - Strategy for similarity calculation (default: :text)
    - `:similarity_threshold` - Threshold for uniqueness (default: 0.85)

  ## Returns

  - `{:ok, DiversityMetrics.t()}` - Computed metrics
  - `{:error, reason}` - If calculation fails

  ## Examples

      {:ok, metrics} = Metrics.calculate(prompts)
      case metrics.diversity_level do
        :critical -> "Need immediate intervention!"
        :low -> "Consider diversity promotion"
        _ -> "Diversity OK"
      end
  """
  @spec calculate(list(String.t() | map()), keyword()) ::
          {:ok, DiversityMetrics.t()} | {:error, term()}
  def calculate(prompts, opts \\ [])

  def calculate([], _opts), do: {:error, :empty_population}

  def calculate(prompts, _opts) when length(prompts) == 1 do
    # Single prompt = perfect diversity (no comparison possible)
    metrics = %DiversityMetrics{
      pairwise_diversity: 1.0,
      entropy: 0.0,
      coverage: 1.0,
      uniqueness_ratio: 1.0,
      clustering_coefficient: 0.0,
      convergence_risk: 0.0,
      diversity_level: :excellent,
      metadata: %{population_size: 1}
    }

    {:ok, metrics}
  end

  def calculate(prompts, opts) do
    strategy = Keyword.get(opts, :similarity_strategy, :text)

    with {:ok, matrix} <- SimilarityDetector.build_matrix(prompts, strategy: strategy) do
      calculate_from_matrix(matrix, opts)
    end
  end

  @doc """
  Calculates diversity metrics from a pre-computed similarity matrix.

  More efficient when you already have the matrix.

  ## Parameters

  - `matrix` - SimilarityMatrix struct
  - `opts` - Options (same as calculate/2)

  ## Returns

  - `{:ok, DiversityMetrics.t()}` - Computed metrics
  - `{:error, reason}` - If calculation fails
  """
  @spec calculate_from_matrix(SimilarityMatrix.t(), keyword()) ::
          {:ok, DiversityMetrics.t()} | {:error, term()}
  def calculate_from_matrix(%SimilarityMatrix{} = matrix, opts \\ []) do
    threshold = Keyword.get(opts, :similarity_threshold, 0.85)

    pairwise_div = calculate_pairwise_diversity(matrix)
    entropy = calculate_entropy(matrix)
    coverage = calculate_coverage(matrix, threshold)
    uniqueness = calculate_uniqueness_ratio(matrix, threshold)
    clustering = calculate_clustering_coefficient(matrix, threshold)
    conv_risk = calculate_convergence_risk(pairwise_div, clustering, coverage)
    level = assess_diversity_level(pairwise_div)

    metrics = %DiversityMetrics{
      pairwise_diversity: pairwise_div,
      entropy: entropy,
      coverage: coverage,
      uniqueness_ratio: uniqueness,
      clustering_coefficient: clustering,
      convergence_risk: conv_risk,
      diversity_level: level,
      metadata: %{
        population_size: length(matrix.prompt_ids),
        strategy_used: matrix.strategy_used,
        threshold_used: threshold
      }
    }

    {:ok, metrics}
  end

  @doc """
  Assesses whether diversity is acceptable.

  ## Parameters

  - `metrics` - DiversityMetrics struct
  - `min_diversity` - Minimum acceptable diversity (default: 0.3)

  ## Returns

  - `boolean()` - True if diversity is acceptable
  """
  @spec acceptable?(DiversityMetrics.t(), float()) :: boolean()
  def acceptable?(%DiversityMetrics{} = metrics, min_diversity \\ 0.3) do
    metrics.pairwise_diversity >= min_diversity
  end

  @doc """
  Determines if diversity promotion is needed.

  ## Parameters

  - `metrics` - DiversityMetrics struct
  - `threshold` - Promotion threshold (default: 0.25)

  ## Returns

  - `boolean()` - True if promotion needed
  """
  @spec needs_promotion?(DiversityMetrics.t(), float()) :: boolean()
  def needs_promotion?(%DiversityMetrics{} = metrics, threshold \\ 0.25) do
    metrics.pairwise_diversity < threshold or
      metrics.convergence_risk > 0.7 or
      metrics.diversity_level in [:critical, :low]
  end

  # Private functions

  defp calculate_pairwise_diversity(%SimilarityMatrix{scores: scores})
       when map_size(scores) == 0 do
    1.0
  end

  defp calculate_pairwise_diversity(%SimilarityMatrix{scores: scores}) do
    # Pairwise diversity = 1 - average similarity
    avg_similarity =
      scores
      |> Map.values()
      |> Enum.sum()
      |> Kernel./(map_size(scores))

    diversity = 1.0 - avg_similarity
    Float.round(max(0.0, diversity), 3)
  end

  defp calculate_entropy(%SimilarityMatrix{scores: scores, prompt_ids: ids}) do
    # Shannon entropy based on similarity distribution
    n = length(ids)

    if n <= 1 do
      0.0
    else
      # Group similarities into bins
      bins = create_similarity_bins(scores)

      # Calculate entropy
      total = map_size(scores)

      entropy =
        bins
        |> Enum.map(fn {_bin, count} ->
          p = count / total

          if p > 0 do
            -p * :math.log2(p)
          else
            0.0
          end
        end)
        |> Enum.sum()

      Float.round(entropy, 3)
    end
  end

  defp create_similarity_bins(scores) do
    # Create 10 bins: 0.0-0.1, 0.1-0.2, ..., 0.9-1.0
    bins = for i <- 0..9, into: %{}, do: {i, 0}

    Enum.reduce(scores, bins, fn {_pair, score}, acc ->
      bin = min(9, floor(score * 10))
      Map.update(acc, bin, 1, &(&1 + 1))
    end)
  end

  defp calculate_coverage(%SimilarityMatrix{prompt_ids: ids}, _threshold) do
    # Coverage = unique prompts / total prompts
    # A prompt is unique if it's not highly similar to any other
    n = length(ids)

    if n <= 1 do
      1.0
    else
      # For now, simple implementation: count of prompts
      # More sophisticated: use similarity threshold
      unique_count = n
      Float.round(unique_count / n, 3)
    end
  end

  defp calculate_uniqueness_ratio(%SimilarityMatrix{scores: scores}, threshold) do
    # Fraction of prompt pairs below similarity threshold
    if map_size(scores) == 0 do
      1.0
    else
      below_threshold =
        scores
        |> Enum.count(fn {_pair, score} -> score < threshold end)

      ratio = below_threshold / map_size(scores)
      Float.round(ratio, 3)
    end
  end

  defp calculate_clustering_coefficient(
         %SimilarityMatrix{scores: scores, prompt_ids: ids},
         threshold
       ) do
    # How clustered: proportion of high-similarity connections
    n = length(ids)

    if n <= 2 or map_size(scores) == 0 do
      0.0
    else
      high_similarity_count =
        scores
        |> Enum.count(fn {_pair, score} -> score >= threshold end)

      coefficient = high_similarity_count / map_size(scores)
      Float.round(coefficient, 3)
    end
  end

  defp calculate_convergence_risk(pairwise_div, clustering, coverage) do
    # Risk increases with:
    # - Low pairwise diversity
    # - High clustering
    # - Low coverage
    diversity_risk = 1.0 - pairwise_div
    clustering_risk = clustering
    coverage_risk = 1.0 - coverage

    risk = diversity_risk * 0.5 + clustering_risk * 0.3 + coverage_risk * 0.2
    Float.round(min(1.0, risk), 3)
  end

  defp assess_diversity_level(pairwise_diversity) do
    cond do
      pairwise_diversity < @critical_threshold -> :critical
      pairwise_diversity < @low_threshold -> :low
      pairwise_diversity < @moderate_threshold -> :moderate
      pairwise_diversity < @healthy_threshold -> :healthy
      true -> :excellent
    end
  end
end
