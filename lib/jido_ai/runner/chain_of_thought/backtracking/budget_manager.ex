defmodule Jido.AI.Runner.ChainOfThought.Backtracking.BudgetManager do
  @moduledoc """
  Manages backtracking budget to prevent excessive exploration.

  Provides:
  - Backtrack budget system with configurable limits
  - Budget allocation across reasoning depth levels
  - Budget exhaustion handling with best-effort results
  - Priority-based budget allocation for critical decision points
  """

  require Logger

  @default_total_budget 10
  # 40% of remaining budget per level
  @default_level_allocation 0.4

  @type budget :: %{
          total: non_neg_integer(),
          remaining: non_neg_integer(),
          used: non_neg_integer(),
          level_allocations: map(),
          priority_reserve: non_neg_integer()
        }

  @doc """
  Initializes backtrack budget.

  ## Parameters

  - `total_budget` - Total budget available (default: 10)
  - `opts` - Options:
    - `:priority_reserve` - Budget reserved for high priority (default: 20% of total)
    - `:level_allocation_factor` - Factor for per-level allocation (default: 0.4)

  ## Returns

  Budget struct

  ## Examples

      budget = BudgetManager.init_budget(10)
      # => %{total: 10, remaining: 10, used: 0, ...}
  """
  @spec init_budget(non_neg_integer(), keyword()) :: budget()
  def init_budget(total_budget \\ @default_total_budget, opts \\ []) do
    priority_reserve = Keyword.get(opts, :priority_reserve, trunc(total_budget * 0.2))

    %{
      total: total_budget,
      remaining: total_budget,
      used: 0,
      level_allocations: %{},
      priority_reserve: priority_reserve
    }
  end

  @doc """
  Checks if budget is available.

  ## Parameters

  - `budget` - Current budget

  ## Returns

  Boolean indicating if budget available
  """
  @spec has_budget?(budget()) :: boolean()
  def has_budget?(%{remaining: remaining}) do
    remaining > 0
  end

  @doc """
  Consumes budget.

  ## Parameters

  - `budget` - Current budget
  - `amount` - Amount to consume (default: 1)

  ## Returns

  Updated budget

  ## Examples

      new_budget = BudgetManager.consume_budget(budget, 1)
  """
  @spec consume_budget(budget(), non_neg_integer()) :: budget()
  def consume_budget(budget, amount \\ 1) do
    consumed = min(amount, budget.remaining)

    Logger.debug(
      "Consuming #{consumed} budget (#{budget.remaining} -> #{budget.remaining - consumed})"
    )

    %{
      budget
      | remaining: budget.remaining - consumed,
        used: budget.used + consumed
    }
  end

  @doc """
  Allocates budget for specific depth level.

  ## Parameters

  - `budget` - Current budget
  - `level` - Depth level
  - `opts` - Options:
    - `:allocation_factor` - Allocation factor (default: 0.4)

  ## Returns

  - `{:ok, level_budget, updated_budget}` - Budget allocated
  - `{:error, :insufficient_budget}` - Not enough budget

  ## Examples

      {:ok, level_budget, new_budget} = BudgetManager.allocate_for_level(budget, 1)
  """
  @spec allocate_for_level(budget(), non_neg_integer(), keyword()) ::
          {:ok, non_neg_integer(), budget()} | {:error, :insufficient_budget}
  def allocate_for_level(budget, level, opts \\ []) do
    allocation_factor = Keyword.get(opts, :allocation_factor, @default_level_allocation)

    # Calculate allocation (percentage of remaining)
    level_budget = trunc(budget.remaining * allocation_factor)

    if level_budget > 0 do
      new_allocations = Map.put(budget.level_allocations, level, level_budget)

      updated_budget = %{
        budget
        | level_allocations: new_allocations
      }

      Logger.debug("Allocated #{level_budget} budget for level #{level}")

      {:ok, level_budget, updated_budget}
    else
      {:error, :insufficient_budget}
    end
  end

  @doc """
  Gets allocated budget for level.

  ## Parameters

  - `budget` - Current budget
  - `level` - Depth level

  ## Returns

  Allocated budget for level (0 if not allocated)
  """
  @spec get_level_budget(budget(), non_neg_integer()) :: non_neg_integer()
  def get_level_budget(budget, level) do
    Map.get(budget.level_allocations, level, 0)
  end

  @doc """
  Allocates priority budget for critical decision points.

  ## Parameters

  - `budget` - Current budget
  - `amount` - Amount to allocate from priority reserve

  ## Returns

  - `{:ok, updated_budget}` - Budget allocated
  - `{:error, :insufficient_priority_reserve}` - Not enough reserve

  ## Examples

      {:ok, new_budget} = BudgetManager.allocate_priority(budget, 2)
  """
  @spec allocate_priority(budget(), non_neg_integer()) ::
          {:ok, budget()} | {:error, :insufficient_priority_reserve}
  def allocate_priority(budget, amount) do
    if budget.priority_reserve >= amount do
      updated_budget = %{
        budget
        | priority_reserve: budget.priority_reserve - amount,
          remaining: budget.remaining + amount
      }

      Logger.info("Allocated #{amount} priority budget")

      {:ok, updated_budget}
    else
      {:error, :insufficient_priority_reserve}
    end
  end

  @doc """
  Calculates budget utilization percentage.

  ## Parameters

  - `budget` - Current budget

  ## Returns

  Utilization percentage (0.0 to 1.0)
  """
  @spec utilization(budget()) :: float()
  def utilization(%{total: total, used: used}) do
    if total == 0, do: 0.0, else: used / total
  end

  @doc """
  Checks if budget is exhausted.

  ## Parameters

  - `budget` - Current budget

  ## Returns

  Boolean indicating if exhausted
  """
  @spec exhausted?(budget()) :: boolean()
  def exhausted?(%{remaining: remaining, priority_reserve: reserve}) do
    remaining == 0 and reserve == 0
  end

  @doc """
  Handles budget exhaustion with best-effort strategy.

  ## Parameters

  - `budget` - Exhausted budget
  - `candidates` - List of candidate solutions

  ## Returns

  Best candidate from available options
  """
  @spec handle_exhaustion(budget(), list()) :: term()
  def handle_exhaustion(budget, candidates) do
    Logger.warning("Budget exhausted (used #{budget.used}/#{budget.total})")

    # Return best candidate based on simple scoring
    if Enum.empty?(candidates) do
      nil
    else
      # Prefer first candidate as best-effort
      List.first(candidates)
    end
  end

  @doc """
  Reallocates unused budget from completed levels.

  ## Parameters

  - `budget` - Current budget
  - `completed_levels` - List of completed level numbers

  ## Returns

  Updated budget with reallocated resources
  """
  @spec reallocate_unused(budget(), list(non_neg_integer())) :: budget()
  def reallocate_unused(budget, completed_levels) do
    # Sum up unused budget from completed levels
    unused =
      completed_levels
      |> Enum.map(&get_level_budget(budget, &1))
      |> Enum.sum()

    if unused > 0 do
      # Remove completed level allocations
      new_allocations =
        Enum.reduce(completed_levels, budget.level_allocations, fn level, acc ->
          Map.delete(acc, level)
        end)

      # Add unused back to remaining
      updated_budget = %{
        budget
        | level_allocations: new_allocations,
          remaining: budget.remaining + unused
      }

      Logger.debug("Reallocated #{unused} unused budget")

      updated_budget
    else
      budget
    end
  end

  @doc """
  Estimates required budget for exploration.

  ## Parameters

  - `state` - Current state
  - `opts` - Estimation options:
    - `:depth` - Expected exploration depth
    - `:branching_factor` - Average branches per node

  ## Returns

  Estimated budget required
  """
  @spec estimate_required_budget(map(), keyword()) :: non_neg_integer()
  def estimate_required_budget(_state, opts \\ []) do
    depth = Keyword.get(opts, :depth, 3)
    branching_factor = Keyword.get(opts, :branching_factor, 2)

    # Exponential estimate: branching_factor ^ depth
    trunc(:math.pow(branching_factor, depth))
  end

  @doc """
  Creates budget report.

  ## Parameters

  - `budget` - Current budget

  ## Returns

  Report map with budget statistics
  """
  @spec report(budget()) :: map()
  def report(budget) do
    %{
      total: budget.total,
      remaining: budget.remaining,
      used: budget.used,
      utilization: utilization(budget),
      priority_reserve: budget.priority_reserve,
      level_allocations: budget.level_allocations,
      exhausted: exhausted?(budget)
    }
  end

  @doc """
  Adjusts budget based on success rate.

  ## Parameters

  - `budget` - Current budget
  - `success_rate` - Recent success rate (0.0 to 1.0)

  ## Returns

  Adjusted budget

  ## Examples

      # High success rate = reduce budget
      adjusted = BudgetManager.adjust_by_success_rate(budget, 0.8)

      # Low success rate = increase priority reserve
      adjusted = BudgetManager.adjust_by_success_rate(budget, 0.2)
  """
  @spec adjust_by_success_rate(budget(), float()) :: budget()
  def adjust_by_success_rate(budget, success_rate) do
    cond do
      # High success rate: can afford to reduce exploration
      success_rate > 0.7 ->
        reduction = trunc(budget.remaining * 0.2)
        %{budget | remaining: max(1, budget.remaining - reduction)}

      # Low success rate: allocate more from priority reserve
      success_rate < 0.3 and budget.priority_reserve > 0 ->
        boost = min(2, budget.priority_reserve)

        %{
          budget
          | remaining: budget.remaining + boost,
            priority_reserve: budget.priority_reserve - boost
        }

      # Normal success rate: no adjustment
      true ->
        budget
    end
  end
end
