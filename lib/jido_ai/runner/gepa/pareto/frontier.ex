defmodule Jido.AI.Runner.GEPA.Pareto.Frontier do
  @moduledoc """
  Data structure representing the Pareto frontier for multi-objective optimization.

  The Pareto frontier contains the set of non-dominated solutions discovered
  during prompt evolution. Each solution represents a different trade-off
  between competing objectives (accuracy, latency, cost, robustness).

  ## Fields

  - `solutions` - List of non-dominated candidates currently on the frontier
  - `fronts` - Map of front_number => list of candidate IDs for ranking
  - `hypervolume` - Measure of objective space dominated by the frontier
  - `reference_point` - Reference point for hypervolume calculation
  - `objectives` - List of objective names being optimized
  - `objective_directions` - Direction (:maximize or :minimize) for each objective
  - `archive` - Historical best solutions for warm-starting future runs
  - `generation` - Generation number when frontier was last updated
  - `created_at` - Timestamp when frontier was created
  - `updated_at` - Timestamp when frontier was last modified

  ## Example

      reference_point = %{
        accuracy: 0.0,     # Min possible accuracy
        latency: 10.0,     # Max acceptable latency (seconds)
        cost: 0.1,         # Max acceptable cost ($)
        robustness: 0.0    # Min possible robustness
      }

      {:ok, frontier} = FrontierManager.new(
        objectives: [:accuracy, :latency, :cost, :robustness],
        objective_directions: %{
          accuracy: :maximize,
          latency: :minimize,
          cost: :minimize,
          robustness: :maximize
        },
        reference_point: reference_point
      )
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.Population.Candidate

  typedstruct do
    @typedoc "Pareto frontier for multi-objective prompt optimization"

    field(:solutions, list(Candidate.t()), default: [])
    # Non-dominated solutions currently on the frontier

    field(:fronts, map(), default: %{})
    # Front number -> list of candidate IDs
    # Example: %{1 => ["cand_1", "cand_2"], 2 => ["cand_3"]}
    # Front 1 = non-dominated (Pareto optimal)
    # Front 2 = dominated only by Front 1, etc.

    field(:hypervolume, float(), default: 0.0)
    # Current hypervolume of the frontier (objective space dominated)
    # Will be properly calculated once HypervolumeCalculator is implemented (Phase 4)

    field(:reference_point, map(), enforce: true)
    # Reference point for hypervolume calculation
    # For maximize objectives: use minimum possible value (e.g., 0.0)
    # For minimize objectives: use maximum acceptable value (e.g., 10.0 seconds)
    # Example: %{accuracy: 0.0, latency: 10.0, cost: 0.1, robustness: 0.0}

    field(:objectives, list(atom()), enforce: true)
    # List of objective names: [:accuracy, :latency, :cost, :robustness]

    field(:objective_directions, map(), enforce: true)
    # Direction (:maximize or :minimize) for each objective
    # Example: %{accuracy: :maximize, latency: :minimize, cost: :minimize, robustness: :maximize}

    field(:archive, list(Candidate.t()), default: [])
    # Historical best solutions for warm-starting future optimization runs
    # Maintains high-quality solutions even if temporarily removed from frontier

    field(:generation, non_neg_integer(), default: 0)
    # Generation number when frontier was last updated

    field(:created_at, integer(), enforce: true)
    # Monotonic timestamp when frontier was created

    field(:updated_at, integer(), enforce: true)
    # Monotonic timestamp when frontier was last modified
  end
end
