defmodule Jido.AI.Accuracy.ComputeBudgeter do
  @moduledoc """
  Allocates and tracks compute resources based on difficulty estimates.

  The ComputeBudgeter maps difficulty levels to specific compute parameters
  and tracks usage to enforce budget limits.

  ## Configuration

  - `:easy_budget` - Custom budget for easy tasks (default: uses ComputeBudget.easy/0)
  - `:medium_budget` - Custom budget for medium tasks (default: uses ComputeBudget.medium/0)
  - `:hard_budget` - Custom budget for hard tasks (default: uses ComputeBudget.hard/0)
  - `:global_limit` - Optional total budget limit across all allocations
  - `:custom_allocations` - Map of custom difficulty levels to budgets

  ## Budget Tracking

  The budgeter tracks:
  - Total budget used
  - Number of allocations made
  - Per-allocation costs

  ## Usage

      # Create a budgeter with default settings
      {:ok, budgeter} = ComputeBudgeter.new(%{})

      # Allocate based on difficulty estimate
      {:ok, budget, budgeter} = ComputeBudgeter.allocate(budgeter, difficulty_estimate)

      # Check remaining budget
      {:ok, remaining} = ComputeBudgeter.remaining_budget(budgeter)

      # Check if budget is exhausted
      exhausted? = ComputeBudgeter.budget_exhausted?(budgeter)

      # Get usage statistics
      stats = ComputeBudgeter.get_usage_stats(budgeter)

  ## Global Limits

  When a global limit is set, allocations that would exceed the limit
  will return an error:

      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})

      # After using 98 units...
      {:error, :budget_exhausted} = ComputeBudgeter.allocate(budgeter, difficulty_estimate)

  ## Custom Allocation Strategies

  You can provide custom budgets for specific difficulty levels or
  implement custom allocation logic:

      {:ok, budgeter} = ComputeBudgeter.new(%{
        hard_budget: ComputeBudget.new!(%{num_candidates: 15}),
        custom_allocations: %{
          :very_hard => ComputeBudget.new!(%{num_candidates: 20})
        }
      })

  """

  import Jido.AI.Accuracy.Helpers, only: [get_attr: 3]

  alias Jido.AI.Accuracy.{ComputeBudget, DifficultyEstimate}

  @type t :: %__MODULE__{
          easy_budget: ComputeBudget.t(),
          medium_budget: ComputeBudget.t(),
          hard_budget: ComputeBudget.t(),
          global_limit: float() | nil,
          used_budget: float(),
          allocation_count: non_neg_integer(),
          custom_allocations: map()
        }

  defstruct [
    :easy_budget,
    :medium_budget,
    :hard_budget,
    :global_limit,
    used_budget: 0.0,
    allocation_count: 0,
    custom_allocations: %{}
  ]

  @doc """
  Creates a new ComputeBudgeter.

  ## Parameters

  - `attrs` - Map with budgeter configuration:
    - `:easy_budget` (optional) - Custom ComputeBudget for easy tasks
    - `:medium_budget` (optional) - Custom ComputeBudget for medium tasks
    - `:hard_budget` (optional) - Custom ComputeBudget for hard tasks
    - `:global_limit` (optional) - Total budget limit
    - `:custom_allocations` (optional) - Map of custom allocations

  ## Returns

  - `{:ok, budgeter}` on success
  - `{:error, reason}` on validation failure

  ## Examples

      {:ok, budgeter} = ComputeBudgeter.new(%{
        global_limit: 100.0
      })

      {:ok, budgeter} = ComputeBudgeter.new(%{
        hard_budget: ComputeBudget.new!(%{num_candidates: 15})
      })

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    easy_budget = get_attr(attrs, :easy_budget, ComputeBudget.easy())
    medium_budget = get_attr(attrs, :medium_budget, ComputeBudget.medium())
    hard_budget = get_attr(attrs, :hard_budget, ComputeBudget.hard())
    global_limit = get_attr(attrs, :global_limit, nil)
    custom_allocations = get_attr(attrs, :custom_allocations, %{})

    with {:ok, _} <- validate_budget(easy_budget),
         {:ok, _} <- validate_budget(medium_budget),
         {:ok, _} <- validate_budget(hard_budget),
         {:ok, _} <- validate_global_limit(global_limit) do
      budgeter = %__MODULE__{
        easy_budget: easy_budget,
        medium_budget: medium_budget,
        hard_budget: hard_budget,
        global_limit: global_limit,
        used_budget: 0.0,
        allocation_count: 0,
        custom_allocations: custom_allocations
      }

      {:ok, budgeter}
    end
  end

  @doc """
  Creates a new ComputeBudgeter, raising on error.

  ## Examples

      budgeter = ComputeBudgeter.new!(%{global_limit: 100.0})

  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, budgeter} -> budgeter
      {:error, reason} -> raise ArgumentError, "Invalid ComputeBudgeter: #{format_error(reason)}"
    end
  end

  @doc """
  Allocates a compute budget based on difficulty estimate.

  Returns the budget and an updated budgeter with tracked usage.

  ## Parameters

  - `budgeter` - The budgeter struct
  - `difficulty_or_level` - Either a DifficultyEstimate or a level atom
  - `opts` - Optional allocation options

  ## Returns

  - `{:ok, budget, updated_budgeter}` on success
  - `{:error, :budget_exhausted}` if allocation would exceed global limit
  - `{:error, reason}` for other errors

  ## Examples

      {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})
      {:ok, budget, budgeter} = ComputeBudgeter.allocate(budgeter, estimate)

      # Or use level directly
      {:ok, budget, budgeter} = ComputeBudgeter.allocate(budgeter, :hard)

  """
  @spec allocate(t(), DifficultyEstimate.t() | DifficultyEstimate.level(), keyword()) ::
          {:ok, ComputeBudget.t(), t()} | {:error, term()}
  def allocate(budgeter, difficulty_or_level, opts \\ [])

  def allocate(%__MODULE__{} = budgeter, %DifficultyEstimate{} = difficulty, opts) do
    allocate(budgeter, difficulty.level, opts)
  end

  def allocate(%__MODULE__{} = budgeter, level, opts) when level in [:easy, :medium, :hard] do
    # Get the budget for this level
    budget = budget_for_level(budgeter, level, opts)

    # Check if we have enough budget
    cost = ComputeBudget.cost(budget)

    if has_budget?(budgeter, cost) do
      updated_budgeter = track_allocation(budgeter, cost)
      {:ok, budget, updated_budgeter}
    else
      {:error, :budget_exhausted}
    end
  end

  def allocate(%__MODULE__{} = budgeter, custom_level, _opts) when is_atom(custom_level) do
    # Check for custom allocation
    case Map.get(budgeter.custom_allocations, custom_level) do
      nil ->
        {:error, {:unknown_level, custom_level}}

      budget ->
        cost = ComputeBudget.cost(budget)

        if has_budget?(budgeter, cost) do
          updated_budgeter = track_allocation(budgeter, cost)
          {:ok, budget, updated_budgeter}
        else
          {:error, :budget_exhausted}
        end
    end
  end

  @doc """
  Allocates a budget specifically for easy tasks.

  ## Examples

      {:ok, budget, budgeter} = ComputeBudgeter.allocate_for_easy(budgeter)

  """
  @spec allocate_for_easy(t()) :: {:ok, ComputeBudget.t(), t()} | {:error, term()}
  def allocate_for_easy(%__MODULE__{} = budgeter) do
    allocate(budgeter, :easy)
  end

  @doc """
  Allocates a budget specifically for medium tasks.

  ## Examples

      {:ok, budget, budgeter} = ComputeBudgeter.allocate_for_medium(budgeter)

  """
  @spec allocate_for_medium(t()) :: {:ok, ComputeBudget.t(), t()} | {:error, term()}
  def allocate_for_medium(%__MODULE__{} = budgeter) do
    allocate(budgeter, :medium)
  end

  @doc """
  Allocates a budget specifically for hard tasks.

  ## Examples

      {:ok, budget, budgeter} = ComputeBudgeter.allocate_for_hard(budgeter)

  """
  @spec allocate_for_hard(t()) :: {:ok, ComputeBudget.t(), t()} | {:error, term()}
  def allocate_for_hard(%__MODULE__{} = budgeter) do
    allocate(budgeter, :hard)
  end

  @doc """
  Allocates a custom budget with specific parameters.

  ## Parameters

  - `budgeter` - The budgeter struct
  - `num_candidates` - Number of candidates
  - `opts` - Additional options (use_prm, use_search, etc.)

  ## Returns

  - `{:ok, budget, updated_budgeter}` on success
  - `{:error, reason}` on failure

  ## Examples

      {:ok, budget, budgeter} = ComputeBudgeter.custom_allocation(budgeter, 7,
        use_prm: true,
        use_search: false
      )

  """
  @spec custom_allocation(t(), pos_integer(), keyword()) ::
          {:ok, ComputeBudget.t(), t()} | {:error, term()}
  def custom_allocation(%__MODULE__{} = _budgeter, num_candidates, _opts)
      when not is_integer(num_candidates) or num_candidates <= 0 do
    {:error, :invalid_num_candidates}
  end

  def custom_allocation(%__MODULE__{} = budgeter, num_candidates, opts)
      when is_integer(num_candidates) and num_candidates > 0 do
    attrs =
      %{num_candidates: num_candidates}
      |> maybe_put_attr(:use_prm, Keyword.get(opts, :use_prm, false))
      |> maybe_put_attr(:use_search, Keyword.get(opts, :use_search, false))
      |> maybe_put_attr(:max_refinements, Keyword.get(opts, :max_refinements, 0))
      |> maybe_put_attr(:search_iterations, Keyword.get(opts, :search_iterations))
      |> maybe_put_attr(:prm_threshold, Keyword.get(opts, :prm_threshold))

    case ComputeBudget.new(attrs) do
      {:ok, budget} ->
        cost = ComputeBudget.cost(budget)

        if has_budget?(budgeter, cost) do
          updated_budgeter = track_allocation(budgeter, cost)
          {:ok, budget, updated_budgeter}
        else
          {:error, :budget_exhausted}
        end

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Checks if the budgeter has sufficient budget for a given cost.

  ## Examples

      ComputeBudgeter.check_budget(budgeter, 10.0)
      # => {:ok, :within_limit}

      ComputeBudgeter.check_budget(budgeter, 1000.0)
      # => {:error, :would_exceed_limit}

  """
  @spec check_budget(t(), float()) :: {:ok, :within_limit} | {:error, :would_exceed_limit}
  def check_budget(%__MODULE__{} = budgeter, cost) when is_number(cost) and cost >= 0 do
    if has_budget?(budgeter, cost) do
      {:ok, :within_limit}
    else
      {:error, :would_exceed_limit}
    end
  end

  @doc """
  Returns the remaining budget.

  If no global limit is set, returns :infinity.

  ## Examples

      {:ok, remaining} = ComputeBudgeter.remaining_budget(budgeter)

  """
  @spec remaining_budget(t()) :: {:ok, float() | :infinity}
  def remaining_budget(%__MODULE__{global_limit: nil}), do: {:ok, :infinity}

  def remaining_budget(%__MODULE__{} = budgeter) do
    remaining = budgeter.global_limit - budgeter.used_budget
    {:ok, max(0.0, remaining)}
  end

  @doc """
  Checks if the budget is exhausted.

  Returns true if:
  - No global limit is set (always false - infinite budget)
  - Global limit exists and used >= limit

  ## Examples

      exhausted? = ComputeBudgeter.budget_exhausted?(budgeter)

  """
  @spec budget_exhausted?(t()) :: boolean()
  def budget_exhausted?(%__MODULE__{global_limit: nil}), do: false

  def budget_exhausted?(%__MODULE__{} = budgeter) do
    budgeter.used_budget >= budgeter.global_limit
  end

  @doc """
  Tracks usage for an allocation (internal function).

  Returns `{:ok, updated_budgeter}` on success or `{:error, :invalid_cost}` if cost is invalid.

  """
  @spec track_usage(t(), float()) :: {:ok, t()} | {:error, term()}
  def track_usage(%__MODULE__{} = budgeter, cost) when is_number(cost) and cost >= 0 do
    {:ok, %{budgeter | used_budget: budgeter.used_budget + cost}}
  end

  def track_usage(%__MODULE__{}, _cost), do: {:error, :invalid_cost}

  @doc """
  Resets the budget tracking.

  Clears used budget and allocation count while preserving configuration.

  ## Examples

      budgeter = ComputeBudgeter.reset_budget(budgeter)

  """
  @spec reset_budget(t()) :: t()
  def reset_budget(%__MODULE__{} = budgeter) do
    %{budgeter | used_budget: 0.0, allocation_count: 0}
  end

  @doc """
  Gets usage statistics for the budgeter.

  ## Returns

  A map with:
  - `:used_budget` - Total budget used
  - `:allocation_count` - Number of allocations
  - `:remaining_budget` - Remaining budget or :infinity
  - `:average_cost` - Average cost per allocation

  ## Examples

      stats = ComputeBudgeter.get_usage_stats(budgeter)

  """
  @spec get_usage_stats(t()) :: map()
  def get_usage_stats(%__MODULE__{} = budgeter) do
    {:ok, remaining} = remaining_budget(budgeter)

    avg_cost =
      if budgeter.allocation_count > 0 do
        budgeter.used_budget / budgeter.allocation_count
      else
        0.0
      end

    %{
      used_budget: budgeter.used_budget,
      allocation_count: budgeter.allocation_count,
      remaining_budget: remaining,
      average_cost: avg_cost
    }
  end

  @doc """
  Gets the budget for a specific difficulty level.

  ## Examples

      budget = ComputeBudgeter.budget_for_level(budgeter, :easy)

  """
  @spec budget_for_level(t(), DifficultyEstimate.level(), keyword()) :: ComputeBudget.t()
  def budget_for_level(budgeter, level, opts \\ [])

  def budget_for_level(%__MODULE__{} = budgeter, level, _opts) when level in [:easy, :medium, :hard] do
    case level do
      :easy -> budgeter.easy_budget
      :medium -> budgeter.medium_budget
      :hard -> budgeter.hard_budget
    end
  end

  # Private functions

  defp validate_budget(%ComputeBudget{}), do: {:ok, :valid}
  defp validate_budget(_), do: {:error, :invalid_budget}

  defp validate_global_limit(nil), do: {:ok, :valid}
  defp validate_global_limit(limit) when is_number(limit) and limit > 0, do: {:ok, :valid}
  defp validate_global_limit(_), do: {:error, :invalid_global_limit}

  defp has_budget?(%__MODULE__{global_limit: nil}, _cost), do: true

  defp has_budget?(%__MODULE__{} = budgeter, cost) do
    budgeter.used_budget + cost <= budgeter.global_limit
  end

  defp track_allocation(%__MODULE__{} = budgeter, cost) when is_number(cost) and cost >= 0 do
    %{budgeter | used_budget: budgeter.used_budget + cost, allocation_count: budgeter.allocation_count + 1}
  end

  defp maybe_put_attr(attrs, _key, nil), do: attrs
  defp maybe_put_attr(attrs, key, value), do: Map.put(attrs, key, value)
  defp format_error(atom) when is_atom(atom), do: atom
end
