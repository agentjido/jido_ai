defmodule Jido.AI.Runner.GEPA.Pareto.FrontierManager do
  @moduledoc """
  Manages the Pareto frontier for multi-objective prompt optimization.

  This module implements Task 2.1.3 of GEPA Stage 2, providing operations
  for maintaining a set of non-dominated solutions that represent optimal
  trade-offs between competing objectives.

  ## Key Operations

  **Creation**: Initialize frontier with objectives and reference point

  **Addition**: Add new solutions while maintaining Pareto optimality
  - Reject dominated solutions
  - Remove solutions dominated by new addition
  - Trigger trimming if frontier exceeds max size

  **Trimming**: Maintain diversity while limiting frontier size
  - Preserve boundary solutions (extreme objective values)
  - Keep solutions with highest crowding distance
  - Maintain representative sample of the Pareto frontier

  **Archiving**: Store historical best solutions
  - Enables warm-starting future optimization runs
  - Provides fallback when frontier is trimmed
  - Maintains diversity across generations

  ## Usage

      # Create a frontier
      {:ok, frontier} = FrontierManager.new(
        objectives: [:accuracy, :latency, :cost, :robustness],
        objective_directions: %{
          accuracy: :maximize,
          latency: :minimize,
          cost: :minimize,
          robustness: :maximize
        },
        reference_point: %{
          accuracy: 0.0,
          latency: 10.0,
          cost: 0.1,
          robustness: 0.0
        }
      )

      # Add a solution
      {:ok, frontier} = FrontierManager.add_solution(frontier, candidate)

      # Trim to max size
      {:ok, frontier} = FrontierManager.trim(frontier, max_size: 100)

      # Archive a solution
      {:ok, frontier} = FrontierManager.archive_solution(frontier, candidate)

      # Get Pareto optimal solutions
      pareto_optimal = FrontierManager.get_pareto_optimal(frontier)
  """

  alias Jido.AI.Runner.GEPA.Pareto.{DominanceComparator, Frontier}
  alias Jido.AI.Runner.GEPA.Population.Candidate

  require Logger

  @default_max_size 100
  @default_max_archive_size 500

  @doc """
  Creates a new Pareto frontier.

  ## Arguments

  - `opts` - Options:
    - `:objectives` - List of objective names (required)
    - `:objective_directions` - Map of objective -> :maximize/:minimize (required)
    - `:reference_point` - Reference point for hypervolume (required)
    - `:max_size` - Maximum frontier size (default: 100)
    - `:max_archive_size` - Maximum archive size (default: 500)

  ## Returns

  - `{:ok, frontier}` - Successfully created frontier
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> FrontierManager.new(
      ...>   objectives: [:accuracy, :latency],
      ...>   objective_directions: %{accuracy: :maximize, latency: :minimize},
      ...>   reference_point: %{accuracy: 0.0, latency: 10.0}
      ...> )
      {:ok, %Frontier{}}
  """
  @spec new(keyword()) :: {:ok, Frontier.t()} | {:error, term()}
  def new(opts) do
    with {:ok, objectives} <- fetch_required(opts, :objectives),
         {:ok, objective_directions} <- fetch_required(opts, :objective_directions),
         {:ok, reference_point} <- fetch_required(opts, :reference_point),
         :ok <- validate_objectives(objectives, objective_directions),
         :ok <- validate_reference_point(reference_point, objectives) do
      now = System.monotonic_time(:millisecond)

      frontier = %Frontier{
        solutions: [],
        fronts: %{},
        hypervolume: 0.0,
        reference_point: reference_point,
        objectives: objectives,
        objective_directions: objective_directions,
        archive: [],
        generation: 0,
        created_at: now,
        updated_at: now
      }

      {:ok, frontier}
    end
  end

  @doc """
  Adds a solution to the frontier.

  The solution is added only if it is not dominated by existing solutions.
  Solutions dominated by the new solution are removed.

  ## Arguments

  - `frontier` - The current frontier
  - `candidate` - Candidate to add (must have `normalized_objectives`)
  - `opts` - Options:
    - `:max_size` - Trigger trimming if exceeded (default: 100)

  ## Returns

  - `{:ok, frontier}` - Updated frontier
  - `{:error, reason}` - Addition failed

  ## Examples

      iex> {:ok, frontier} = FrontierManager.add_solution(frontier, candidate)
  """
  @spec add_solution(Frontier.t(), Candidate.t(), keyword()) ::
          {:ok, Frontier.t()} | {:error, term()}
  def add_solution(frontier, candidate, opts \\ [])

  def add_solution(
        %Frontier{} = _frontier,
        %Candidate{normalized_objectives: nil} = _candidate,
        _opts
      ) do
    {:error, :candidate_missing_normalized_objectives}
  end

  def add_solution(%Frontier{} = frontier, %Candidate{} = candidate, opts) do
    # Check if candidate is dominated by any existing solution
    dominated_by =
      Enum.filter(frontier.solutions, fn existing ->
        DominanceComparator.dominates?(existing, candidate)
      end)

    if length(dominated_by) > 0 do
      # Candidate is dominated, don't add but still return success
      Logger.debug("Candidate #{candidate.id} is dominated, not adding to frontier")
      {:ok, frontier}
    else
      # Remove solutions dominated by candidate
      solutions_to_keep =
        Enum.reject(frontier.solutions, fn existing ->
          DominanceComparator.dominates?(candidate, existing)
        end)

      # Add candidate
      new_solutions = [candidate | solutions_to_keep]

      Logger.debug(
        "Added candidate #{candidate.id} to frontier (#{length(new_solutions)} solutions)"
      )

      # Update frontier
      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: Calculate hypervolume once Phase 4 (HypervolumeCalculator) is implemented
      updated_frontier = %{
        frontier
        | solutions: new_solutions,
          updated_at: System.monotonic_time(:millisecond)
      }

      # Check if trimming needed
      max_size = Keyword.get(opts, :max_size, @default_max_size)

      if length(new_solutions) > max_size do
        Logger.debug("Frontier size #{length(new_solutions)} exceeds max #{max_size}, trimming")
        trim(updated_frontier, Keyword.put(opts, :max_size, max_size))
      else
        {:ok, updated_frontier}
      end
    end
  end

  @doc """
  Removes a solution from the frontier by ID.

  ## Arguments

  - `frontier` - The current frontier
  - `candidate_id` - ID of candidate to remove

  ## Returns

  - `{:ok, frontier}` - Updated frontier
  - `{:error, :not_found}` - Candidate not in frontier

  ## Examples

      iex> {:ok, frontier} = FrontierManager.remove_solution(frontier, "candidate_123")
  """
  @spec remove_solution(Frontier.t(), String.t()) :: {:ok, Frontier.t()} | {:error, term()}
  def remove_solution(%Frontier{} = frontier, candidate_id) when is_binary(candidate_id) do
    case Enum.find(frontier.solutions, fn c -> c.id == candidate_id end) do
      nil ->
        {:error, :not_found}

      _found ->
        new_solutions = Enum.reject(frontier.solutions, fn c -> c.id == candidate_id end)

        # credo:disable-for-next-line Credo.Check.Design.TagTODO
        # TODO: Recalculate hypervolume once Phase 4 is implemented
        updated_frontier = %{
          frontier
          | solutions: new_solutions,
            updated_at: System.monotonic_time(:millisecond)
        }

        Logger.debug("Removed candidate #{candidate_id} from frontier")
        {:ok, updated_frontier}
    end
  end

  @doc """
  Trims the frontier to a maximum size using diversity-preserving selection.

  Uses crowding distance to maintain diversity. Boundary solutions (extreme
  objective values) are never removed.

  ## Arguments

  - `frontier` - The current frontier
  - `opts` - Options:
    - `:max_size` - Maximum number of solutions to keep (default: 100)

  ## Returns

  - `{:ok, frontier}` - Trimmed frontier

  ## Examples

      iex> {:ok, frontier} = FrontierManager.trim(frontier, max_size: 50)
  """
  @spec trim(Frontier.t(), keyword()) :: {:ok, Frontier.t()}
  def trim(%Frontier{} = frontier, opts \\ []) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)

    if length(frontier.solutions) <= max_size do
      {:ok, frontier}
    else
      # Calculate crowding distance
      distances = DominanceComparator.crowding_distance(frontier.solutions)

      # Sort by crowding distance (keep highest)
      # Boundary solutions (infinite distance) are kept first
      sorted_solutions =
        Enum.sort_by(frontier.solutions, fn solution ->
          case Map.get(distances, solution.id) do
            # Keep boundaries first
            :infinity -> {0, :infinity}
            # Then by decreasing distance
            dist when is_float(dist) -> {1, -dist}
            # Fallback for missing distances
            _ -> {2, 0}
          end
        end)

      # Keep top max_size solutions
      trimmed_solutions = Enum.take(sorted_solutions, max_size)

      Logger.debug(
        "Trimmed frontier from #{length(frontier.solutions)} to #{length(trimmed_solutions)} solutions"
      )

      # credo:disable-for-next-line Credo.Check.Design.TagTODO
      # TODO: Recalculate hypervolume once Phase 4 is implemented
      {:ok,
       %{frontier | solutions: trimmed_solutions, updated_at: System.monotonic_time(:millisecond)}}
    end
  end

  @doc """
  Archives a solution for historical preservation.

  Archives maintain best solutions seen across all generations for
  warm-starting future optimizations.

  ## Arguments

  - `frontier` - The current frontier
  - `candidate` - Candidate to archive
  - `opts` - Options:
    - `:max_archive_size` - Maximum archive size (default: 500)

  ## Returns

  - `{:ok, frontier}` - Updated frontier with archived solution

  ## Examples

      iex> {:ok, frontier} = FrontierManager.archive_solution(frontier, candidate)
  """
  @spec archive_solution(Frontier.t(), Candidate.t(), keyword()) :: {:ok, Frontier.t()}
  def archive_solution(%Frontier{} = frontier, %Candidate{} = candidate, opts \\ []) do
    # Check if already in archive
    if Enum.any?(frontier.archive, fn c -> c.id == candidate.id end) do
      {:ok, frontier}
    else
      new_archive = [candidate | frontier.archive]

      # Trim archive if too large
      max_archive_size = Keyword.get(opts, :max_archive_size, @default_max_archive_size)

      trimmed_archive =
        if length(new_archive) > max_archive_size do
          # Keep best solutions by aggregate fitness
          new_archive
          |> Enum.sort_by(&(&1.fitness || 0.0), :desc)
          |> Enum.take(max_archive_size)
        else
          new_archive
        end

      Logger.debug(
        "Archived candidate #{candidate.id} (archive size: #{length(trimmed_archive)})"
      )

      {:ok,
       %{frontier | archive: trimmed_archive, updated_at: System.monotonic_time(:millisecond)}}
    end
  end

  @doc """
  Gets all non-dominated solutions (Front 1 / Pareto optimal).

  ## Arguments

  - `frontier` - The frontier

  ## Returns

  List of Pareto optimal candidates

  ## Examples

      iex> pareto_optimal = FrontierManager.get_pareto_optimal(frontier)
      iex> length(pareto_optimal)
      12
  """
  @spec get_pareto_optimal(Frontier.t()) :: list(Candidate.t())
  def get_pareto_optimal(%Frontier{} = frontier) do
    frontier.solutions
  end

  @doc """
  Gets solutions from a specific Pareto front by rank.

  ## Arguments

  - `frontier` - The frontier
  - `rank` - Front number (1 = non-dominated, 2 = dominated by front 1, etc.)

  ## Returns

  List of candidates in the specified front

  ## Examples

      iex> front_2 = FrontierManager.get_front(frontier, 2)
      iex> length(front_2)
      8
  """
  @spec get_front(Frontier.t(), pos_integer()) :: list(Candidate.t())
  def get_front(%Frontier{} = frontier, rank) when is_integer(rank) and rank > 0 do
    front_ids = Map.get(frontier.fronts, rank, [])

    Enum.filter(frontier.solutions, fn c -> c.id in front_ids end)
  end

  @doc """
  Updates the frontier's front classification using non-dominated sorting.

  This should be called after adding/removing multiple solutions to
  update the `fronts` field with current Pareto ranking.

  ## Arguments

  - `frontier` - The frontier

  ## Returns

  - `{:ok, frontier}` - Updated frontier with classified fronts

  ## Examples

      iex> {:ok, frontier} = FrontierManager.update_fronts(frontier)
  """
  @spec update_fronts(Frontier.t()) :: {:ok, Frontier.t()}
  def update_fronts(%Frontier{} = frontier) do
    if Enum.empty?(frontier.solutions) do
      {:ok, %{frontier | fronts: %{}}}
    else
      # Perform non-dominated sorting
      fronts = DominanceComparator.fast_non_dominated_sort(frontier.solutions)

      # Convert fronts from %{rank => [candidates]} to %{rank => [ids]}
      fronts_with_ids =
        fronts
        |> Enum.map(fn {rank, candidates} ->
          ids = Enum.map(candidates, & &1.id)
          {rank, ids}
        end)
        |> Map.new()

      {:ok,
       %{frontier | fronts: fronts_with_ids, updated_at: System.monotonic_time(:millisecond)}}
    end
  end

  # Private helper functions

  @spec fetch_required(keyword(), atom()) :: {:ok, term()} | {:error, term()}
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_required_option, key}}
    end
  end

  @spec validate_objectives(list(atom()), map()) :: :ok | {:error, term()}
  defp validate_objectives(objectives, directions)
       when is_list(objectives) and is_map(directions) do
    if Enum.all?(objectives, fn obj -> Map.has_key?(directions, obj) end) do
      # Validate direction values
      invalid_directions =
        directions
        |> Enum.filter(fn {_obj, dir} -> dir not in [:maximize, :minimize] end)

      if Enum.empty?(invalid_directions) do
        :ok
      else
        {:error, {:invalid_objective_directions, invalid_directions}}
      end
    else
      {:error, :missing_objective_direction}
    end
  end

  defp validate_objectives(_objectives, _directions) do
    {:error, :invalid_objectives_format}
  end

  @spec validate_reference_point(map(), list(atom())) :: :ok | {:error, term()}
  defp validate_reference_point(reference, objectives)
       when is_map(reference) and is_list(objectives) do
    if Enum.all?(objectives, fn obj -> Map.has_key?(reference, obj) end) do
      # Validate all reference values are numeric
      non_numeric =
        reference
        |> Enum.filter(fn {_obj, val} -> not is_number(val) end)

      if Enum.empty?(non_numeric) do
        :ok
      else
        {:error, {:non_numeric_reference_values, non_numeric}}
      end
    else
      {:error, :missing_reference_value}
    end
  end

  defp validate_reference_point(_reference, _objectives) do
    {:error, :invalid_reference_point_format}
  end
end
