defmodule Jido.AI.Runner.GEPA.Convergence.BudgetManager do
  @moduledoc """
  Tracks budget consumption and enforces limits across optimization runs.

  Manages computational budgets to prevent runaway optimization and ensure
  resource-constrained execution. Supports multiple budget types and flexible
  allocation strategies.

  ## Budget Types

  - **Evaluation Budget**: Maximum number of prompt evaluations
  - **Cost Budget**: Maximum cost in dollars (or other currency)
  - **Generation Budget**: Maximum number of optimization generations
  - **Time Budget**: Maximum wall-clock time in seconds

  ## Allocation Strategies

  - **Total Budget**: Fixed total across entire run
  - **Per-Generation Budget**: Fixed allocation per generation
  - **Carryover**: Unused budget from previous generation carries forward

  ## Configuration

  - `:max_evaluations` - Maximum total evaluations (default: nil = unlimited)
  - `:max_cost` - Maximum cost in dollars (default: nil = unlimited)
  - `:max_generations` - Maximum generations (default: nil = unlimited)
  - `:max_time_seconds` - Maximum time in seconds (default: nil = unlimited)
  - `:budget_per_generation` - Fixed allocation per generation (default: nil)
  - `:allow_carryover` - Allow unused budget to carry forward (default: false)

  ## Example

      iex> manager = BudgetManager.new(max_evaluations: 1000, max_generations: 50)
      iex> manager = BudgetManager.record_consumption(manager, evaluations: 20, cost: 0.05)
      iex> BudgetManager.budget_exhausted?(manager)
      false
      iex> BudgetManager.remaining_evaluations(manager)
      980
  """

  use TypedStruct

  typedstruct module: BudgetRecord do
    @moduledoc """
    Record of budget consumption for a single generation.

    ## Fields

    - `:generation` - Generation number
    - `:evaluations` - Evaluations consumed this generation
    - `:cost` - Cost incurred this generation
    - `:time_elapsed` - Time elapsed this generation (seconds)
    - `:timestamp` - When recorded
    """

    field(:generation, non_neg_integer(), enforce: true)
    field(:evaluations, non_neg_integer(), default: 0)
    field(:cost, float(), default: 0.0)
    field(:time_elapsed, float(), default: 0.0)
    field(:timestamp, DateTime.t(), default: DateTime.utc_now())
  end

  typedstruct do
    field(:consumption_history, list(BudgetRecord.t()), default: [])
    field(:evaluations_consumed, non_neg_integer(), default: 0)
    field(:cost_consumed, float(), default: 0.0)
    field(:time_consumed, float(), default: 0.0)
    field(:current_generation, non_neg_integer(), default: 0)
    field(:max_evaluations, non_neg_integer() | nil, default: nil)
    field(:max_cost, float() | nil, default: nil)
    field(:max_generations, non_neg_integer() | nil, default: nil)
    field(:max_time_seconds, float() | nil, default: nil)
    field(:budget_per_generation, non_neg_integer() | nil, default: nil)
    field(:allow_carryover, boolean(), default: false)
    field(:carryover_balance, non_neg_integer(), default: 0)
    field(:budget_exhausted, boolean(), default: false)
    field(:start_time, DateTime.t() | nil, default: nil)
    field(:max_history, pos_integer(), default: 100)
    field(:config, map(), default: %{})
  end

  @doc """
  Creates a new budget manager with given configuration.

  ## Options

  - `:max_evaluations` - Maximum total evaluations (default: nil = unlimited)
  - `:max_cost` - Maximum cost in dollars (default: nil = unlimited)
  - `:max_generations` - Maximum generations (default: nil = unlimited)
  - `:max_time_seconds` - Maximum time in seconds (default: nil = unlimited)
  - `:budget_per_generation` - Fixed allocation per generation (default: nil)
  - `:allow_carryover` - Allow unused budget to carry forward (default: false)
  - `:max_history` - Maximum history to keep (default: 100)

  ## Examples

      iex> manager = BudgetManager.new(max_evaluations: 1000)
      %BudgetManager{max_evaluations: 1000}

      iex> manager = BudgetManager.new(max_cost: 10.0, budget_per_generation: 50)
      %BudgetManager{max_cost: 10.0, budget_per_generation: 50}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_evaluations: Keyword.get(opts, :max_evaluations),
      max_cost: Keyword.get(opts, :max_cost),
      max_generations: Keyword.get(opts, :max_generations),
      max_time_seconds: Keyword.get(opts, :max_time_seconds),
      budget_per_generation: Keyword.get(opts, :budget_per_generation),
      allow_carryover: Keyword.get(opts, :allow_carryover, false),
      max_history: Keyword.get(opts, :max_history, 100),
      start_time: DateTime.utc_now(),
      config: Map.new(opts)
    }
  end

  @doc """
  Records budget consumption for the current generation.

  ## Parameters

  - `manager` - Current manager state
  - `opts` - Consumption details:
    - `:evaluations` - Evaluations consumed (default: 0)
    - `:cost` - Cost incurred (default: 0.0)
    - `:time_elapsed` - Time elapsed in seconds (default: 0.0)
    - `:generation` - Optional generation number (default: auto-increment)

  ## Returns

  Updated manager with consumption recorded and budget status updated

  ## Examples

      iex> manager = BudgetManager.new(max_evaluations: 100)
      iex> manager = BudgetManager.record_consumption(manager, evaluations: 10, cost: 0.05)
      iex> manager.evaluations_consumed
      10
  """
  @spec record_consumption(t(), keyword()) :: t()
  def record_consumption(%__MODULE__{} = manager, opts \\ []) do
    evaluations = Keyword.get(opts, :evaluations, 0)
    cost = Keyword.get(opts, :cost, 0.0)
    time_elapsed = Keyword.get(opts, :time_elapsed, 0.0)
    generation = Keyword.get(opts, :generation, manager.current_generation + 1)

    # Create record
    record = %BudgetRecord{
      generation: generation,
      evaluations: evaluations,
      cost: cost,
      time_elapsed: time_elapsed
    }

    # Update history
    history = [record | manager.consumption_history]
    history = Enum.take(history, manager.max_history)

    # Update totals
    manager = %{
      manager
      | consumption_history: history,
        evaluations_consumed: manager.evaluations_consumed + evaluations,
        cost_consumed: manager.cost_consumed + cost,
        time_consumed: manager.time_consumed + time_elapsed,
        current_generation: generation
    }

    # Update carryover if using per-generation budget
    manager = update_carryover(manager, evaluations)

    # Check if budget exhausted
    check_budget_exhaustion(manager)
  end

  @doc """
  Checks if any budget has been exhausted.

  ## Examples

      iex> manager = BudgetManager.new(max_evaluations: 100)
      iex> BudgetManager.budget_exhausted?(manager)
      false
  """
  @spec budget_exhausted?(t()) :: boolean()
  def budget_exhausted?(%__MODULE__{} = manager) do
    manager.budget_exhausted
  end

  @doc """
  Returns remaining evaluation budget.

  ## Examples

      iex> manager = BudgetManager.new(max_evaluations: 100)
      iex> manager = BudgetManager.record_consumption(manager, evaluations: 20)
      iex> BudgetManager.remaining_evaluations(manager)
      80
  """
  @spec remaining_evaluations(t()) :: non_neg_integer() | :unlimited
  def remaining_evaluations(%__MODULE__{max_evaluations: nil}) do
    :unlimited
  end

  def remaining_evaluations(%__MODULE__{} = manager) do
    max(0, manager.max_evaluations - manager.evaluations_consumed)
  end

  @doc """
  Returns remaining cost budget.

  ## Examples

      iex> manager = BudgetManager.new(max_cost: 10.0)
      iex> manager = BudgetManager.record_consumption(manager, cost: 2.5)
      iex> BudgetManager.remaining_cost(manager)
      7.5
  """
  @spec remaining_cost(t()) :: float() | :unlimited
  def remaining_cost(%__MODULE__{max_cost: nil}) do
    :unlimited
  end

  def remaining_cost(%__MODULE__{} = manager) do
    max(0.0, manager.max_cost - manager.cost_consumed)
  end

  @doc """
  Returns remaining generation budget.

  ## Examples

      iex> manager = BudgetManager.new(max_generations: 50)
      iex> manager = BudgetManager.record_consumption(manager, evaluations: 10)
      iex> BudgetManager.remaining_generations(manager)
      49
  """
  @spec remaining_generations(t()) :: non_neg_integer() | :unlimited
  def remaining_generations(%__MODULE__{max_generations: nil}) do
    :unlimited
  end

  def remaining_generations(%__MODULE__{} = manager) do
    max(0, manager.max_generations - manager.current_generation)
  end

  @doc """
  Returns remaining time budget in seconds.

  ## Examples

      iex> manager = BudgetManager.new(max_time_seconds: 3600.0)
      iex> manager = BudgetManager.record_consumption(manager, time_elapsed: 120.0)
      iex> BudgetManager.remaining_time(manager)
      3480.0
  """
  @spec remaining_time(t()) :: float() | :unlimited
  def remaining_time(%__MODULE__{max_time_seconds: nil}) do
    :unlimited
  end

  def remaining_time(%__MODULE__{} = manager) do
    max(0.0, manager.max_time_seconds - manager.time_consumed)
  end

  @doc """
  Returns available budget for next generation.

  Accounts for per-generation limits and carryover if enabled.

  ## Examples

      iex> manager = BudgetManager.new(max_evaluations: 1000)
      iex> BudgetManager.available_budget(manager)
      1000

      iex> manager = BudgetManager.new(budget_per_generation: 50)
      iex> BudgetManager.available_budget(manager)
      50
  """
  @spec available_budget(t()) :: non_neg_integer() | :unlimited
  def available_budget(%__MODULE__{budget_per_generation: nil} = manager) do
    remaining_evaluations(manager)
  end

  def available_budget(%__MODULE__{} = manager) do
    base = manager.budget_per_generation

    if manager.allow_carryover do
      base + manager.carryover_balance
    else
      base
    end
  end

  @doc """
  Returns total time elapsed since start.

  ## Examples

      iex> manager = BudgetManager.new()
      iex> BudgetManager.total_time_elapsed(manager)
      0.0
  """
  @spec total_time_elapsed(t()) :: float()
  def total_time_elapsed(%__MODULE__{start_time: nil}) do
    0.0
  end

  def total_time_elapsed(%__MODULE__{} = manager) do
    DateTime.diff(DateTime.utc_now(), manager.start_time, :millisecond) / 1000.0
  end

  @doc """
  Resets the budget manager, clearing consumption history and counters.

  ## Examples

      iex> manager = BudgetManager.new(max_evaluations: 100)
      iex> manager = BudgetManager.record_consumption(manager, evaluations: 50)
      iex> manager = BudgetManager.reset(manager)
      iex> manager.evaluations_consumed
      0
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = manager) do
    %{
      manager
      | consumption_history: [],
        evaluations_consumed: 0,
        cost_consumed: 0.0,
        time_consumed: 0.0,
        current_generation: 0,
        carryover_balance: 0,
        budget_exhausted: false,
        start_time: DateTime.utc_now()
    }
  end

  # Private functions

  defp update_carryover(%{budget_per_generation: nil} = manager, _evaluations) do
    manager
  end

  defp update_carryover(%{allow_carryover: false} = manager, _evaluations) do
    %{manager | carryover_balance: 0}
  end

  defp update_carryover(manager, evaluations) do
    # Calculate unused budget
    allocated = manager.budget_per_generation + manager.carryover_balance
    unused = max(0, allocated - evaluations)

    %{manager | carryover_balance: unused}
  end

  defp check_budget_exhaustion(manager) do
    evaluations_exhausted =
      manager.max_evaluations != nil and
        manager.evaluations_consumed >= manager.max_evaluations

    cost_exhausted =
      manager.max_cost != nil and
        manager.cost_consumed >= manager.max_cost

    generations_exhausted =
      manager.max_generations != nil and
        manager.current_generation >= manager.max_generations

    time_exhausted =
      manager.max_time_seconds != nil and
        manager.time_consumed >= manager.max_time_seconds

    exhausted =
      evaluations_exhausted or
        cost_exhausted or
        generations_exhausted or
        time_exhausted

    %{manager | budget_exhausted: exhausted}
  end
end
