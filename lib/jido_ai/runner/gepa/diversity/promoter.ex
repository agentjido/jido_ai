defmodule Jido.AI.Runner.GEPA.Diversity.Promoter do
  @moduledoc """
  Promotes population diversity through targeted interventions.

  When diversity drops below acceptable levels, this module applies
  strategies to increase variation:

  1. **Random Injection**: Add completely new random prompts
  2. **Adaptive Mutation Rate**: Increase mutation intensity
  3. **Targeted Diversification**: Mutate highly similar prompts

  ## Usage

      # Check if promotion needed
      if Metrics.needs_promotion?(metrics) do
        {:ok, new_prompts} = Promoter.promote_diversity(population, metrics)
      end

      # Calculate adaptive mutation rate
      mutation_rate = Promoter.adaptive_mutation_rate(metrics)
  """

  alias Jido.AI.Runner.GEPA.Diversity.DiversityMetrics

  @default_base_mutation_rate 0.1
  @max_mutation_rate 0.5
  @min_diversity_target 0.4

  @doc """
  Promotes diversity in a population through various strategies.

  ## Parameters

  - `prompts` - Current population of prompts
  - `metrics` - DiversityMetrics for the population
  - `opts` - Options:
    - `:strategy` - :random_injection | :adaptive_mutation | :targeted_diversification | :all (default)
    - `:injection_count` - Number of random prompts to inject (default: auto)
    - `:base_prompt` - Template for generating variations (default: nil)

  ## Returns

  - `{:ok, promoted_prompts}` - Population with diversity-promoting changes
  - `{:error, reason}` - If promotion fails

  ## Examples

      {:ok, new_population} = Promoter.promote_diversity(prompts, metrics)
  """
  @spec promote_diversity(list(String.t() | map()), DiversityMetrics.t(), keyword()) ::
          {:ok, list(String.t() | map())} | {:error, term()}
  def promote_diversity(prompts, metrics, opts \\ [])

  def promote_diversity([], _metrics, _opts), do: {:error, :empty_population}

  def promote_diversity(prompts, %DiversityMetrics{} = metrics, opts) do
    strategy = Keyword.get(opts, :strategy, :all)

    case strategy do
      :random_injection ->
        apply_random_injection(prompts, metrics, opts)

      :adaptive_mutation ->
        # Mutation rate is calculated separately
        {:ok, prompts}

      :targeted_diversification ->
        apply_targeted_diversification(prompts, metrics, opts)

      :all ->
        # Apply multiple strategies
        with {:ok, injected} <- apply_random_injection(prompts, metrics, opts) do
          apply_targeted_diversification(injected, metrics, opts)
        end

      _ ->
        {:error, {:unknown_strategy, strategy}}
    end
  end

  @doc """
  Calculates adaptive mutation rate based on diversity level.

  Lower diversity → higher mutation rate to promote exploration.

  ## Parameters

  - `metrics` - DiversityMetrics struct
  - `base_rate` - Base mutation rate (default: 0.1)

  ## Returns

  - `float()` - Adapted mutation rate (0.0-0.5)

  ## Examples

      rate = Promoter.adaptive_mutation_rate(metrics)
      # If diversity critical: ~0.4-0.5
      # If diversity low: ~0.2-0.3
      # If diversity healthy: ~0.1
  """
  @spec adaptive_mutation_rate(DiversityMetrics.t(), float()) :: float()
  def adaptive_mutation_rate(
        %DiversityMetrics{} = metrics,
        base_rate \\ @default_base_mutation_rate
      ) do
    diversity = metrics.pairwise_diversity
    convergence_risk = metrics.convergence_risk

    # Calculate multiplier based on diversity and convergence risk
    multiplier =
      cond do
        metrics.diversity_level == :critical ->
          # Maximum exploration
          4.0

        metrics.diversity_level == :low ->
          # High exploration
          2.5

        convergence_risk > 0.7 ->
          # Moderate exploration
          2.0

        diversity < @min_diversity_target ->
          # Mild exploration boost
          1.5

        true ->
          # Normal mutation rate
          1.0
      end

    # Apply multiplier and cap at max rate
    adapted_rate = base_rate * multiplier
    Float.round(min(adapted_rate, @max_mutation_rate), 3)
  end

  @doc """
  Suggests how many prompts should be replaced/injected based on diversity.

  ## Parameters

  - `metrics` - DiversityMetrics struct
  - `population_size` - Current population size

  ## Returns

  - `non_neg_integer()` - Number of prompts to inject
  """
  @spec injection_count(DiversityMetrics.t(), pos_integer()) :: non_neg_integer()
  def injection_count(%DiversityMetrics{} = metrics, population_size) do
    ratio =
      case metrics.diversity_level do
        # Replace 30%
        :critical -> 0.3
        # Replace 20%
        :low -> 0.2
        # Replace 10%
        :moderate -> 0.1
        # No injection needed
        _ -> 0.0
      end

    max(0, floor(population_size * ratio))
  end

  # Private functions

  defp apply_random_injection(prompts, metrics, opts) do
    count = Keyword.get(opts, :injection_count) || injection_count(metrics, length(prompts))

    if count == 0 do
      {:ok, prompts}
    else
      # Generate random variations
      base_prompt = Keyword.get(opts, :base_prompt) || extract_base_prompt(prompts)
      new_prompts = generate_random_variations(base_prompt, count)

      # Replace lowest diversity prompts
      updated = replace_least_diverse(prompts, new_prompts, count)
      {:ok, updated}
    end
  end

  defp apply_targeted_diversification(prompts, _metrics, _opts) do
    # For now, just return prompts unchanged
    # Full implementation would identify and mutate similar clusters
    {:ok, prompts}
  end

  defp extract_base_prompt(prompts) do
    # Use first prompt as template, or create generic
    case prompts do
      [first | _] when is_binary(first) -> first
      [%{text: text} | _] -> text
      [%{prompt: text} | _] -> text
      _ -> "Solve this problem step by step."
    end
  end

  defp generate_random_variations(base_prompt, count) do
    # Generate simple variations by adding randomized elements
    variations = [
      "with clear explanations",
      "showing all intermediate steps",
      "using examples to illustrate",
      "with detailed reasoning",
      "explaining your thought process",
      "step by step with justification",
      "with thorough analysis",
      "considering multiple approaches",
      "with careful attention to detail",
      "systematically and methodically"
    ]

    Enum.take_random(variations, count)
    |> Enum.map(fn variation ->
      "#{base_prompt} #{variation}"
    end)
  end

  defp replace_least_diverse(prompts, new_prompts, count) do
    # Simple implementation: replace last N prompts
    # More sophisticated: use similarity matrix to identify least diverse
    population_size = length(prompts)
    keep_count = max(0, population_size - count)

    Enum.take(prompts, keep_count) ++ new_prompts
  end
end
