defmodule Jido.AI.GEPA.Selection do
  @moduledoc """
  Implements Pareto-optimal selection for multi-objective optimization in GEPA.

  The Selection module helps choose which prompt variants survive to the next
  generation by balancing multiple competing objectives (e.g., accuracy vs. cost).

  ## Pareto Dominance

  A variant A **dominates** variant B if:
  - A is at least as good as B on all objectives
  - A is strictly better than B on at least one objective

  The **Pareto front** is the set of all non-dominated variants - these represent
  the best trade-offs between objectives.

  ## Usage

      # Define objectives
      objectives = [
        {:accuracy, :maximize},
        {:token_cost, :minimize}
      ]

      # Find the Pareto front
      pareto_variants = Selection.pareto_front(variants, objectives)

      # Select survivors for next generation
      survivors = Selection.select_survivors(variants, 5, objectives: objectives)

  ## Objectives

  Each objective is a tuple of `{metric, direction}`:
  - `metric` - The field to compare (`:accuracy`, `:token_cost`, `:latency_ms`)
  - `direction` - `:maximize` (higher is better) or `:minimize` (lower is better)

  Default objectives: `[{:accuracy, :maximize}, {:token_cost, :minimize}]`
  """

  alias Jido.AI.GEPA.PromptVariant

  @type objective :: {atom(), :maximize | :minimize}
  @type objectives :: [objective()]

  @default_objectives [
    {:accuracy, :maximize},
    {:token_cost, :minimize}
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Checks if variant A dominates variant B according to the given objectives.

  A dominates B if:
  - A is at least as good as B on ALL objectives
  - A is strictly better than B on AT LEAST ONE objective

  ## Parameters

  - `variant_a` - First PromptVariant
  - `variant_b` - Second PromptVariant
  - `objectives` - List of `{metric, direction}` tuples

  ## Returns

  `true` if A dominates B, `false` otherwise.

  ## Examples

      iex> a = %PromptVariant{accuracy: 0.9, token_cost: 100}
      iex> b = %PromptVariant{accuracy: 0.8, token_cost: 150}
      iex> Selection.dominates?(a, b, [{:accuracy, :maximize}, {:token_cost, :minimize}])
      true  # A is better on both objectives

      iex> a = %PromptVariant{accuracy: 0.9, token_cost: 200}
      iex> b = %PromptVariant{accuracy: 0.8, token_cost: 100}
      iex> Selection.dominates?(a, b, [{:accuracy, :maximize}, {:token_cost, :minimize}])
      false  # A is better on accuracy but worse on cost - neither dominates
  """
  @spec dominates?(PromptVariant.t(), PromptVariant.t(), objectives()) :: boolean()
  def dominates?(%PromptVariant{} = variant_a, %PromptVariant{} = variant_b, objectives)
      when is_list(objectives) do
    # Must be at least as good on all objectives
    at_least_as_good_on_all =
      Enum.all?(objectives, fn {metric, direction} ->
        compare_metric(variant_a, variant_b, metric, direction) in [:gt, :eq]
      end)

    # Must be strictly better on at least one objective
    strictly_better_on_one =
      Enum.any?(objectives, fn {metric, direction} ->
        compare_metric(variant_a, variant_b, metric, direction) == :gt
      end)

    at_least_as_good_on_all and strictly_better_on_one
  end

  def dominates?(_, _, _), do: false

  @doc """
  Finds the Pareto front - the set of non-dominated variants.

  A variant is in the Pareto front if no other variant dominates it.
  These represent the best trade-offs between objectives.

  ## Parameters

  - `variants` - List of PromptVariants to analyze
  - `objectives` - List of `{metric, direction}` tuples (default: accuracy↑, cost↓)

  ## Returns

  List of non-dominated PromptVariants (the Pareto front).

  ## Examples

      iex> variants = [high_acc_high_cost, low_acc_low_cost, dominated_variant]
      iex> Selection.pareto_front(variants, [{:accuracy, :maximize}, {:token_cost, :minimize}])
      [high_acc_high_cost, low_acc_low_cost]  # Both are non-dominated
  """
  @spec pareto_front([PromptVariant.t()], objectives()) :: [PromptVariant.t()]
  def pareto_front(variants, objectives \\ @default_objectives) when is_list(variants) do
    # Filter to only evaluated variants
    evaluated = Enum.filter(variants, &PromptVariant.evaluated?/1)

    # Find non-dominated variants
    Enum.filter(evaluated, fn variant ->
      not Enum.any?(evaluated, fn other ->
        other.id != variant.id and dominates?(other, variant, objectives)
      end)
    end)
  end

  @doc """
  Selects variants to survive to the next generation.

  Uses Pareto-based selection: first takes the Pareto front, then fills
  remaining slots with the best remaining variants (by crowding distance
  or weighted score).

  ## Parameters

  - `variants` - List of PromptVariants to select from
  - `count` - Number of survivors to select
  - `opts` - Options:
    - `:objectives` - List of `{metric, direction}` tuples (default: accuracy↑, cost↓)
    - `:strategy` - Selection strategy (default: `:pareto_first`)
    - `:weights` - Weights for weighted selection (default: equal weights)

  ## Strategies

  - `:pareto_first` - Take entire Pareto front, fill with best remaining
  - `:nsga2` - NSGA-II style with crowding distance for diversity
  - `:weighted` - Simple weighted sum of objectives

  ## Returns

  List of `count` selected PromptVariants.

  ## Examples

      iex> Selection.select_survivors(variants, 5, objectives: objectives)
      [v1, v2, v3, v4, v5]
  """
  @spec select_survivors([PromptVariant.t()], non_neg_integer(), keyword()) :: [PromptVariant.t()]
  def select_survivors(variants, count, opts \\ []) when is_list(variants) and count >= 0 do
    objectives = Keyword.get(opts, :objectives, @default_objectives)
    strategy = Keyword.get(opts, :strategy, :pareto_first)

    # Filter to evaluated variants
    evaluated = Enum.filter(variants, &PromptVariant.evaluated?/1)

    case strategy do
      :pareto_first -> pareto_first_select(evaluated, count, objectives)
      :nsga2 -> nsga2_select(evaluated, count, objectives)
      :weighted -> weighted_select(evaluated, count, objectives, opts)
      _ -> pareto_first_select(evaluated, count, objectives)
    end
  end

  @doc """
  Calculates crowding distance for each variant.

  Crowding distance measures how close a variant is to its neighbors in
  objective space. Higher crowding distance means more isolated (diverse).
  Used in NSGA-II selection to maintain diversity.

  ## Parameters

  - `variants` - List of PromptVariants
  - `objectives` - List of `{metric, direction}` tuples

  ## Returns

  Map of `variant_id => crowding_distance`.

  ## Examples

      iex> Selection.crowding_distance(variants, objectives)
      %{"pv_123" => 0.5, "pv_456" => 1.2, "pv_789" => :infinity}
  """
  @spec crowding_distance([PromptVariant.t()], objectives()) :: %{String.t() => number() | :infinity}
  def crowding_distance(variants, objectives \\ @default_objectives) when is_list(variants) do
    if length(variants) <= 2 do
      # With 0-2 variants, all have infinite distance
      Map.new(variants, fn v -> {v.id, :infinity} end)
    else
      # Initialize distances to 0
      distances = Map.new(variants, fn v -> {v.id, 0.0} end)

      # Add contribution from each objective
      Enum.reduce(objectives, distances, fn {metric, direction}, acc ->
        add_objective_distance(variants, metric, direction, acc)
      end)
    end
  end

  @doc """
  Returns the default objectives used for selection.

  Default: `[{:accuracy, :maximize}, {:token_cost, :minimize}]`
  """
  @spec default_objectives() :: objectives()
  def default_objectives, do: @default_objectives

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp compare_metric(variant_a, variant_b, metric, direction) do
    val_a = Map.get(variant_a, metric)
    val_b = Map.get(variant_b, metric)
    compare_values(val_a, val_b, direction)
  end

  # Helper functions to reduce cyclomatic complexity
  defp compare_values(nil, _, _), do: :eq
  defp compare_values(_, nil, _), do: :eq
  defp compare_values(a, b, direction) when a == b, do: :eq
  defp compare_values(a, b, :maximize) when a > b, do: :gt
  defp compare_values(_, _, :maximize), do: :lt
  defp compare_values(a, b, :minimize) when a < b, do: :gt
  defp compare_values(_, _, :minimize), do: :lt

  # Pareto-first selection: take Pareto front, then best remaining
  defp pareto_first_select(variants, count, objectives) do
    cond do
      Enum.empty?(variants) or count == 0 ->
        []

      true ->
        front = pareto_front(variants, objectives)
        fill_from_front(front, variants, count, objectives)
    end
  end

  defp fill_from_front(front, variants, count, objectives) do
    if length(front) >= count do
      pick_by_crowding(front, count, objectives)
    else
      fill_remaining(front, variants, count, objectives)
    end
  end

  defp fill_remaining(front, variants, count, objectives) do
    remaining_count = count - length(front)
    non_front = variants -- front

    if Enum.empty?(non_front) do
      front
    else
      additional = pareto_first_select(non_front, remaining_count, objectives)
      front ++ additional
    end
  end

  # NSGA-II style selection with non-dominated sorting and crowding distance
  defp nsga2_select(variants, count, objectives) do
    if Enum.empty?(variants) or count == 0 do
      []
    else
      do_nsga2_select(variants, count, objectives, [])
    end
  end

  defp do_nsga2_select(remaining, count, objectives, selected) do
    needed = count - length(selected)

    if needed <= 0 or Enum.empty?(remaining) do
      Enum.take(selected, count)
    else
      # Get current Pareto front
      front = pareto_front(remaining, objectives)

      if length(front) <= needed do
        # Take entire front, continue with remaining
        new_remaining = remaining -- front
        do_nsga2_select(new_remaining, count, objectives, selected ++ front)
      else
        # Front is larger than needed - use crowding distance
        picked = pick_by_crowding(front, needed, objectives)
        selected ++ picked
      end
    end
  end

  # Simple weighted sum selection
  defp weighted_select(variants, count, objectives, opts) do
    weights = Keyword.get(opts, :weights, default_weights(objectives))

    variants
    |> Enum.map(fn v -> {v, weighted_score(v, objectives, weights)} end)
    |> Enum.sort_by(fn {_v, score} -> score end, :desc)
    |> Enum.take(count)
    |> Enum.map(fn {v, _score} -> v end)
  end

  defp default_weights(objectives) do
    # Equal weights for all objectives
    weight = 1.0 / length(objectives)
    Map.new(objectives, fn {metric, _} -> {metric, weight} end)
  end

  defp weighted_score(variant, objectives, weights) do
    Enum.reduce(objectives, 0.0, fn {metric, direction}, acc ->
      value = Map.get(variant, metric) || 0
      weight = Map.get(weights, metric, 0)

      # Normalize and adjust for direction
      normalized =
        case direction do
          :maximize -> value
          :minimize -> if value > 0, do: 1.0 / value, else: 1.0
        end

      acc + normalized * weight
    end)
  end

  # Pick variants by crowding distance (higher distance = more diverse)
  defp pick_by_crowding(variants, count, objectives) do
    distances = crowding_distance(variants, objectives)

    variants
    |> Enum.sort_by(fn v ->
      dist = Map.get(distances, v.id, 0)
      # Sort infinity first, then by distance descending
      case dist do
        :infinity -> {0, 0}
        n -> {1, -n}
      end
    end)
    |> Enum.take(count)
  end

  # Add crowding distance contribution from one objective
  defp add_objective_distance(variants, metric, direction, distances) do
    sorted = sort_by_metric(variants, metric, direction)
    range = calculate_range(sorted, metric)

    if range == 0 do
      distances
    else
      distances_with_boundaries = add_boundary_distances(sorted, distances)
      add_interior_distances(sorted, metric, range, distances_with_boundaries)
    end
  end

  defp sort_by_metric(variants, metric, direction) do
    Enum.sort_by(variants, fn v ->
      val = Map.get(v, metric) || 0
      if direction == :maximize, do: -val, else: val
    end)
  end

  defp calculate_range(sorted, metric) do
    values = Enum.map(sorted, fn v -> Map.get(v, metric) || 0 end)
    Enum.max(values) - Enum.min(values)
  end

  defp add_boundary_distances(sorted, distances) do
    first_id = hd(sorted).id
    last_id = List.last(sorted).id

    distances
    |> Map.put(first_id, :infinity)
    |> Map.put(last_id, :infinity)
  end

  defp add_interior_distances(sorted, metric, range, distances) do
    sorted
    |> Enum.with_index()
    |> Enum.reduce(distances, fn {variant, idx}, acc ->
      add_interior_distance(variant, idx, sorted, metric, range, acc)
    end)
  end

  defp add_interior_distance(variant, idx, sorted, metric, range, acc) do
    is_boundary = idx == 0 or idx == length(sorted) - 1

    if is_boundary do
      acc
    else
      contribution = calculate_contribution(sorted, idx, metric, range)
      current = Map.get(acc, variant.id)

      case current do
        :infinity -> acc
        n when is_number(n) -> Map.put(acc, variant.id, n + contribution)
      end
    end
  end

  defp calculate_contribution(sorted, idx, metric, range) do
    prev_val = Map.get(Enum.at(sorted, idx - 1), metric) || 0
    next_val = Map.get(Enum.at(sorted, idx + 1), metric) || 0
    abs(next_val - prev_val) / range
  end
end
