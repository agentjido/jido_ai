defmodule Jido.AI.Accuracy.ComputeBudget do
  @moduledoc """
  Represents a compute allocation for generation.

  A ComputeBudget contains parameters for self-consistency sampling,
  process reward model (PRM) verification, search iterations, and
  refinement steps.

  ## Fields

  - `:num_candidates` - Number of candidates to generate (N)
  - `:use_prm` - Whether to use Process Reward Model for verification
  - `:use_search` - Whether to use search/revision
  - `:max_refinements` - Maximum number of refinement iterations
  - `:search_iterations` - Number of search iterations (if search enabled)
  - `:prm_threshold` - PRM confidence threshold for acceptance
  - `:cost` - Computed cost of this allocation for budget tracking
  - `:metadata` - Additional metadata

  ## Budget Levels

  ### Easy Budget
  - num_candidates: 3
  - use_prm: false
  - use_search: false
  - Used for simple factual questions, direct lookup

  ### Medium Budget
  - num_candidates: 5
  - use_prm: true
  - use_search: false
  - max_refinements: 1
  - Used for queries requiring some reasoning

  ### Hard Budget
  - num_candidates: 10
  - use_prm: true
  - use_search: true
  - search_iterations: 50
  - max_refinements: 2
  - Used for complex reasoning, multi-step tasks

  ## Usage

      # Get preset budget for difficulty level
      budget = ComputeBudget.easy()
      budget.num_candidates
      # => 3

      budget = ComputeBudget.hard()
      budget.use_search
      # => true

      # Create custom budget
      {:ok, budget} = ComputeBudget.new(%{
        num_candidates: 7,
        use_prm: true,
        use_search: false
      })

      # Calculate cost
      ComputeBudget.cost(budget)
      # => 7.0

  ## Cost Model

  The budget cost is calculated as:
  - Base: num_candidates × 1.0
  - PRM: num_candidates × 0.5 (if enabled)
  - Search: search_iterations × 0.01 (if enabled)
  - Refinements: max_refinements × 1.0

  Example costs:
  - Easy: 3 × 1.0 = 3.0
  - Medium: 5 × 1.0 + 5 × 0.5 + 1 × 1.0 = 8.5
  - Hard: 10 × 1.0 + 10 × 0.5 + 50 × 0.01 + 2 × 1.0 = 17.5
  """

  import Jido.AI.Accuracy.Helpers, only: [get_attr: 2, get_attr: 3]

  @type t :: %__MODULE__{
          num_candidates: pos_integer(),
          use_prm: boolean(),
          use_search: boolean(),
          max_refinements: non_neg_integer(),
          search_iterations: pos_integer() | nil,
          prm_threshold: float() | nil,
          cost: float(),
          metadata: map()
        }

  # Cost factors for budget calculation
  @cost_per_candidate 1.0
  @cost_per_prm_step 0.5
  @cost_per_search_iteration 0.01
  @cost_per_refinement 1.0

  # Default values
  @default_prm_threshold 0.5

  defstruct [
    :num_candidates,
    :use_prm,
    :use_search,
    :max_refinements,
    :search_iterations,
    :prm_threshold,
    :cost,
    metadata: %{}
  ]

  @doc """
  Creates a new ComputeBudget from the given attributes.

  ## Parameters

  - `attrs` - Map with budget attributes:
    - `:num_candidates` (required) - Number of candidates to generate
    - `:use_prm` (optional) - Whether to use PRM (default: false)
    - `:use_search` (optional) - Whether to use search (default: false)
    - `:max_refinements` (optional) - Max refinement iterations (default: 0)
    - `:search_iterations` (optional) - Search iterations (default: 50 if search enabled)
    - `:prm_threshold` (optional) - PRM threshold (default: 0.5)
    - `:metadata` (optional) - Additional metadata (default: %{})

  ## Returns

  - `{:ok, budget}` on success
  - `{:error, reason}` on validation failure

  ## Examples

      {:ok, budget} = ComputeBudget.new(%{
        num_candidates: 5,
        use_prm: true
      })

      {:error, :invalid_num_candidates} = ComputeBudget.new(%{
        num_candidates: -1
      })

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    num_candidates = get_attr(attrs, :num_candidates)

    with {:ok, validated_num} <- validate_num_candidates(num_candidates) do
      use_prm = get_attr(attrs, :use_prm, false)
      use_search = get_attr(attrs, :use_search, false)
      max_refinements = get_attr(attrs, :max_refinements, 0)
      search_iterations = get_attr(attrs, :search_iterations, nil)
      prm_threshold = get_attr(attrs, :prm_threshold, @default_prm_threshold)
      metadata = get_attr(attrs, :metadata, %{})
      # Derive search_iterations if not provided but search is enabled
      search_iterations =
        if use_search and is_nil(search_iterations) do
          50
        else
          search_iterations
        end

      budget = %__MODULE__{
        num_candidates: validated_num,
        use_prm: use_prm,
        use_search: use_search,
        max_refinements: max_refinements,
        search_iterations: search_iterations,
        prm_threshold: prm_threshold,
        cost: calculate_cost(validated_num, use_prm, use_search, search_iterations, max_refinements),
        metadata: metadata
      }

      {:ok, budget}
    end
  end

  @doc """
  Creates a new ComputeBudget, raising on error.

  ## Examples

      budget = ComputeBudget.new!(%{num_candidates: 5})

  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, budget} -> budget
      {:error, reason} -> raise ArgumentError, "Invalid ComputeBudget: #{format_error(reason)}"
    end
  end

  @doc """
  Returns a preset budget for easy tasks.

  Easy budget: N=3, no PRM, no search

  ## Examples

      budget = ComputeBudget.easy()
      budget.num_candidates
      # => 3

  """
  @spec easy() :: t()
  def easy do
    new!(%{
      num_candidates: 3,
      use_prm: false,
      use_search: false,
      max_refinements: 0
    })
  end

  @doc """
  Returns a preset budget for medium tasks.

  Medium budget: N=5, with PRM, no search, 1 refinement

  ## Examples

      budget = ComputeBudget.medium()
      budget.num_candidates
      # => 5
      budget.use_prm
      # => true

  """
  @spec medium() :: t()
  def medium do
    new!(%{
      num_candidates: 5,
      use_prm: true,
      use_search: false,
      max_refinements: 1,
      prm_threshold: 0.5
    })
  end

  @doc """
  Returns a preset budget for hard tasks.

  Hard budget: N=10, with PRM, with search, 2 refinements

  ## Examples

      budget = ComputeBudget.hard()
      budget.num_candidates
      # => 10
      budget.use_search
      # => true

  """
  @spec hard() :: t()
  def hard do
    new!(%{
      num_candidates: 10,
      use_prm: true,
      use_search: true,
      max_refinements: 2,
      search_iterations: 50,
      prm_threshold: 0.5
    })
  end

  @doc """
  Gets the budget for a given difficulty level.

  ## Parameters

  - `level` - Difficulty level (:easy, :medium, :hard)

  ## Returns

  A ComputeBudget preset for the given level.

  ## Examples

      budget = ComputeBudget.for_level(:easy)
      budget = ComputeBudget.for_level(:hard)

  """
  @spec for_level(Jido.AI.Accuracy.DifficultyEstimate.level()) :: t()
  def for_level(:easy), do: easy()
  def for_level(:medium), do: medium()
  def for_level(:hard), do: hard()

  @doc """
  Returns the cost of a budget allocation.

  The cost is computed during construction but can also be calculated
  from a budget struct.

  ## Examples

      budget = ComputeBudget.hard()
      ComputeBudget.cost(budget)
      # => 17.5

  """
  @spec cost(t()) :: float()
  def cost(%__MODULE__{} = budget), do: budget.cost

  @doc """
  Returns the number of candidates for the budget.

  """
  @spec num_candidates(t()) :: pos_integer()
  def num_candidates(%__MODULE__{} = budget), do: budget.num_candidates

  @doc """
  Checks if PRM is enabled for this budget.

  """
  @spec use_prm?(t()) :: boolean()
  def use_prm?(%__MODULE__{} = budget), do: budget.use_prm

  @doc """
  Checks if search is enabled for this budget.

  """
  @spec use_search?(t()) :: boolean()
  def use_search?(%__MODULE__{} = budget), do: budget.use_search

  @doc """
  Converts the budget to a map for serialization.

  ## Examples

      budget = ComputeBudget.medium()
      map = ComputeBudget.to_map(budget)

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = budget) do
    %{
      "num_candidates" => budget.num_candidates,
      "use_prm" => budget.use_prm,
      "use_search" => budget.use_search,
      "max_refinements" => budget.max_refinements,
      "search_iterations" => budget.search_iterations,
      "prm_threshold" => budget.prm_threshold,
      "cost" => budget.cost,
      "metadata" => budget.metadata
    }
  end

  @doc """
  Creates a budget from a map.

  ## Examples

      map = %{"num_candidates" => 5, "use_prm" => true}
      {:ok, budget} = ComputeBudget.from_map(map)

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    attrs =
      %{}
      |> maybe_put_num_candidates(Map.get(map, "num_candidates"))
      |> maybe_put_boolean(:use_prm, Map.get(map, "use_prm"))
      |> maybe_put_boolean(:use_search, Map.get(map, "use_search"))
      |> maybe_put_non_neg_int(:max_refinements, Map.get(map, "max_refinements"))
      |> maybe_put_nullable_int(:search_iterations, Map.get(map, "search_iterations"))
      |> maybe_put_nullable_float(:prm_threshold, Map.get(map, "prm_threshold"))
      |> maybe_put_map(:metadata, Map.get(map, "metadata"))

    new(attrs)
  end

  # Private functions

  defp validate_num_candidates(num) when is_integer(num) and num > 0, do: {:ok, num}
  defp validate_num_candidates(_), do: {:error, :invalid_num_candidates}

  defp calculate_cost(num_candidates, use_prm, use_search, search_iterations, max_refinements) do
    base_cost = num_candidates * @cost_per_candidate
    prm_cost = if use_prm, do: num_candidates * @cost_per_prm_step, else: 0
    search_cost = if use_search and search_iterations, do: search_iterations * @cost_per_search_iteration, else: 0
    refinement_cost = max_refinements * @cost_per_refinement

    base_cost + prm_cost + search_cost + refinement_cost
  end

  defp maybe_put_num_candidates(attrs, nil), do: attrs
  defp maybe_put_num_candidates(attrs, value), do: Map.put(attrs, :num_candidates, value)

  defp maybe_put_boolean(attrs, _key, nil), do: attrs
  defp maybe_put_boolean(attrs, key, value) when is_boolean(value), do: Map.put(attrs, key, value)
  defp maybe_put_boolean(attrs, _key, _value), do: attrs

  defp maybe_put_non_neg_int(attrs, _key, nil), do: attrs

  defp maybe_put_non_neg_int(attrs, key, value) when is_integer(value) and value >= 0 do
    Map.put(attrs, key, value)
  end

  defp maybe_put_non_neg_int(attrs, _key, _value), do: attrs

  defp maybe_put_nullable_int(attrs, _key, nil), do: attrs

  defp maybe_put_nullable_int(attrs, key, value) when is_integer(value) and value > 0 do
    Map.put(attrs, key, value)
  end

  defp maybe_put_nullable_int(attrs, _key, _value), do: attrs

  defp maybe_put_nullable_float(attrs, _key, nil), do: attrs

  defp maybe_put_nullable_float(attrs, key, value) when is_number(value) do
    Map.put(attrs, key, value / 1)
  end

  defp maybe_put_nullable_float(attrs, _key, _value), do: attrs

  defp maybe_put_map(attrs, _key, nil), do: attrs
  defp maybe_put_map(attrs, key, value) when is_map(value), do: Map.put(attrs, key, value)
  defp maybe_put_map(attrs, _key, _value), do: attrs
  defp format_error(atom) when is_atom(atom), do: atom
end
