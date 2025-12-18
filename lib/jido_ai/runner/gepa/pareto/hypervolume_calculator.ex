defmodule Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculator do
  @moduledoc """
  Calculates hypervolume indicator for Pareto frontier quality assessment.

  The hypervolume indicator measures the volume of objective space dominated
  by a set of solutions relative to a reference point. It is the most popular
  quality indicator for multi-objective optimization because:

  1. **Weakly Pareto compliant**: Maximizing hypervolume leads to Pareto optimal sets
  2. **Sensitive to convergence and diversity**: Rewards both proximity to optimal front and spread
  3. **Unambiguous**: No free parameters beyond reference point

  ## Algorithm

  Uses While-Fonseca-Gomes (WFG) algorithm with complexity:
  - O(N log N) for 2 objectives
  - O(N log N) for 3 objectives
  - O(N^(M-2) log N) for M objectives

  ## Reference Point Selection

  The reference point should be dominated by all solutions:
  - For maximize objectives: use minimum possible value (e.g., 0.0)
  - For minimize objectives: use maximum acceptable value (e.g., 10.0)

  In normalized space (after MultiObjectiveEvaluator.normalize), all objectives
  are transformed to maximization with values in [0, 1]. The reference point
  should typically be slightly below the minimum observed values (e.g., -0.1).

  ## Usage

      # Calculate hypervolume
      {:ok, hv} = HypervolumeCalculator.calculate(
        solutions,
        reference_point: %{accuracy: 0.0, latency: 0.0, cost: 0.0},
        objectives: [:accuracy, :latency, :cost]
      )

      # Calculate contribution of each solution
      contributions = HypervolumeCalculator.contribution(
        solutions,
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      )

      # Auto-select reference point
      reference = HypervolumeCalculator.auto_reference_point(
        candidates,
        objectives: [:accuracy, :latency],
        objective_directions: %{accuracy: :maximize, latency: :minimize},
        margin: 0.1
      )
  """

  alias Jido.AI.Runner.GEPA.Population.Candidate

  require Logger

  @type hypervolume :: float()
  @type contribution_map :: %{String.t() => float()}

  @doc """
  Calculate hypervolume of a set of solutions.

  ## Arguments

  - `solutions` - List of candidates with `normalized_objectives`
  - `opts` - Options:
    - `:reference_point` - Reference point map (required)
    - `:objectives` - List of objective names (required)

  ## Returns

  - `{:ok, hypervolume}` - Successfully calculated hypervolume
  - `{:error, reason}` - Validation or calculation failed

  ## Examples

      # Calculate hypervolume for a set of solutions
      solutions = [candidate1, candidate2, candidate3]
      HypervolumeCalculator.calculate(
        solutions,
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      )
      # => {:ok, 0.752}
  """
  @spec calculate(list(Candidate.t()), keyword()) :: {:ok, hypervolume()} | {:error, term()}
  def calculate(solutions, opts) do
    with {:ok, reference_point} <- fetch_required(opts, :reference_point),
         {:ok, objectives} <- fetch_required(opts, :objectives),
         :ok <- validate_solutions(solutions),
         :ok <- validate_reference_point(reference_point, objectives) do
      # Filter solutions without normalized objectives
      valid_solutions =
        Enum.filter(solutions, fn s ->
          s.normalized_objectives != nil
        end)

      if Enum.empty?(valid_solutions) do
        {:ok, 0.0}
      else
        case length(objectives) do
          1 -> calculate_1d(valid_solutions, reference_point, objectives)
          2 -> calculate_2d(valid_solutions, reference_point, objectives)
          3 -> calculate_3d_wfg(valid_solutions, reference_point, objectives)
          _ -> calculate_nd_wfg(valid_solutions, reference_point, objectives)
        end
      end
    end
  end

  @doc """
  Calculate hypervolume contribution of each solution.

  The contribution is the hypervolume lost if a solution is removed from
  the frontier. Solutions with higher contribution are more valuable for
  maintaining diversity and convergence.

  ## Arguments

  - `solutions` - List of candidates with `normalized_objectives`
  - `opts` - Options:
    - `:reference_point` - Reference point map (required)
    - `:objectives` - List of objective names (required)

  ## Returns

  Map of candidate_id => contribution

  ## Examples

      # Calculate contribution for each solution
      contributions = HypervolumeCalculator.contribution(
        solutions,
        reference_point: %{accuracy: 0.0, latency: 0.0},
        objectives: [:accuracy, :latency]
      )
      # => %{"cand_1" => 0.25, "cand_2" => 0.30, "cand_3" => 0.22}
  """
  @spec contribution(list(Candidate.t()), keyword()) :: contribution_map()
  def contribution(solutions, opts) do
    case calculate(solutions, opts) do
      {:ok, total_hv} ->
        # Calculate hypervolume without each solution
        Enum.map(solutions, fn solution ->
          remaining = Enum.reject(solutions, fn s -> s.id == solution.id end)

          case calculate(remaining, opts) do
            {:ok, hv_without} ->
              # Contribution = total - without
              contrib = max(0.0, total_hv - hv_without)
              {solution.id, Float.round(contrib, 6)}

            {:error, _} ->
              {solution.id, 0.0}
          end
        end)
        |> Map.new()

      {:error, _} ->
        # Return zero contribution for all on error
        solutions
        |> Enum.map(fn s -> {s.id, 0.0} end)
        |> Map.new()
    end
  end

  @doc """
  Automatically select reference point from population statistics.

  Uses the nadir point (worst value in each objective) with a margin.
  The nadir point ensures all solutions dominate the reference point.

  ## Arguments

  - `candidates` - List of candidates with `normalized_objectives`
  - `opts` - Options:
    - `:objectives` - List of objective names (required)
    - `:objective_directions` - Map of objective => :maximize/:minimize (required)
    - `:margin` - Margin below minimum values (default: 0.1)

  ## Returns

  Map of objective => reference value

  ## Examples

      # Automatically select reference point
      reference = HypervolumeCalculator.auto_reference_point(
        candidates,
        objectives: [:accuracy, :latency],
        objective_directions: %{accuracy: :maximize, latency: :minimize},
        margin: 0.1
      )
      # => %{accuracy: -0.05, latency: -0.08}
  """
  @spec auto_reference_point(list(Candidate.t()), keyword()) :: map()
  def auto_reference_point(candidates, opts) do
    objectives = Keyword.fetch!(opts, :objectives)
    _objective_directions = Keyword.fetch!(opts, :objective_directions)
    margin = Keyword.get(opts, :margin, 0.1)

    # Filter candidates with normalized objectives
    valid_candidates =
      Enum.filter(candidates, fn c ->
        c.normalized_objectives != nil
      end)

    if Enum.empty?(valid_candidates) do
      # Default reference point if no valid candidates
      Enum.map(objectives, fn obj -> {obj, 0.0} end) |> Map.new()
    else
      # Find nadir point (worst value in each objective)
      Enum.map(objectives, fn obj ->
        values =
          Enum.map(valid_candidates, fn c ->
            Map.get(c.normalized_objectives, obj, 0.0)
          end)

        # In normalized space, all objectives are transformed to maximization
        # Reference point should be below minimum values
        min_val = Enum.min(values)
        reference_value = max(0.0, min_val - margin)

        {obj, reference_value}
      end)
      |> Map.new()
    end
  end

  @doc """
  Calculate hypervolume improvement between two frontiers.

  ## Arguments

  - `current_frontier` - Current Pareto frontier
  - `previous_frontier` - Previous generation's frontier
  - `opts` - Options (objectives, reference_point)

  ## Returns

  `{:ok, improvement_ratio, current_hv}` where improvement_ratio = current_hv / previous_hv

  ## Examples

      # Calculate improvement between frontiers
      HypervolumeCalculator.improvement(current, previous, opts)
      # => {:ok, 1.15, 0.823}  # 15% improvement
  """
  @spec improvement(map(), map(), keyword()) :: {:ok, float(), float()} | {:error, term()}
  def improvement(current_frontier, previous_frontier, opts) do
    with {:ok, current_hv} <- calculate(current_frontier.solutions, opts),
         {:ok, previous_hv} <- calculate(previous_frontier.solutions, opts) do
      ratio =
        if previous_hv > 0.0 do
          current_hv / previous_hv
        else
          if current_hv > 0.0, do: :infinity, else: 1.0
        end

      rounded_ratio = if ratio == :infinity, do: :infinity, else: Float.round(ratio, 4)
      {:ok, rounded_ratio, Float.round(current_hv, 6)}
    end
  end

  # Private implementation functions

  @spec calculate_1d(list(Candidate.t()), map(), list(atom())) :: {:ok, hypervolume()}
  defp calculate_1d(solutions, reference_point, objectives) do
    [obj] = objectives
    ref_val = Map.get(reference_point, obj, 0.0)

    # Find maximum value in the objective
    max_val =
      solutions
      |> Enum.map(fn s -> Map.get(s.normalized_objectives, obj, 0.0) end)
      |> Enum.max()

    hv = max(0.0, max_val - ref_val)
    {:ok, Float.round(hv, 6)}
  end

  @spec calculate_2d(list(Candidate.t()), map(), list(atom())) :: {:ok, hypervolume()}
  defp calculate_2d(solutions, reference_point, objectives) do
    [obj1, obj2] = objectives
    ref_x = Map.get(reference_point, obj1, 0.0)
    ref_y = Map.get(reference_point, obj2, 0.0)

    # Sort by first objective (descending for maximization)
    sorted =
      Enum.sort_by(solutions, fn s ->
        -Map.get(s.normalized_objectives, obj1, 0.0)
      end)

    # Sweep line algorithm: track maximum y seen so far
    {hypervolume, _} =
      Enum.reduce(sorted, {0.0, ref_y}, fn solution, {hv, max_y_so_far} ->
        x = Map.get(solution.normalized_objectives, obj1, 0.0)
        y = Map.get(solution.normalized_objectives, obj2, 0.0)

        # Only add area if this solution improves on the current maximum y
        if y > max_y_so_far do
          # Width: from current x to reference x
          # Height: from new y to previous maximum y
          width = max(0.0, x - ref_x)
          height = max(0.0, y - max_y_so_far)
          area = width * height

          {hv + area, y}
        else
          # This solution is dominated in obj2, contributes no new area
          {hv, max_y_so_far}
        end
      end)

    {:ok, Float.round(hypervolume, 6)}
  end

  @spec calculate_3d_wfg(list(Candidate.t()), map(), list(atom())) :: {:ok, hypervolume()}
  defp calculate_3d_wfg(solutions, reference_point, objectives) do
    # Use WFG recursive algorithm for 3D
    hv = wfg_recursive(solutions, reference_point, objectives, 0)
    {:ok, Float.round(hv, 6)}
  end

  @spec calculate_nd_wfg(list(Candidate.t()), map(), list(atom())) :: {:ok, hypervolume()}
  defp calculate_nd_wfg(solutions, reference_point, objectives) do
    # Use WFG recursive algorithm for N dimensions
    hv = wfg_recursive(solutions, reference_point, objectives, 0)
    {:ok, Float.round(hv, 6)}
  end

  @spec wfg_recursive(list(Candidate.t()), map(), list(atom()), non_neg_integer()) :: float()
  defp wfg_recursive([], _reference, _objectives, _depth), do: 0.0

  defp wfg_recursive(solutions, reference, [objective], _depth) do
    # Base case: single objective remaining
    # Find maximum value and calculate 1D hypervolume
    max_val =
      solutions
      |> Enum.map(fn s -> Map.get(s.normalized_objectives, objective, 0.0) end)
      |> Enum.max()

    ref_val = Map.get(reference, objective, 0.0)
    max(0.0, max_val - ref_val)
  end

  defp wfg_recursive(solutions, reference, objectives, depth) do
    [current_obj | remaining_objs] = Enum.drop(objectives, depth)
    ref_val = Map.get(reference, current_obj, 0.0)

    # Sort by current objective (descending)
    sorted =
      Enum.sort_by(solutions, fn s ->
        -Map.get(s.normalized_objectives, current_obj, 0.0)
      end)

    # Use inclusion-exclusion principle
    # Process solutions from best to worst in current objective
    {hv, _prev_val} =
      Enum.reduce(sorted, {0.0, ref_val}, fn solution, {acc_hv, prev_val} ->
        sol_val = Map.get(solution.normalized_objectives, current_obj, 0.0)

        if sol_val <= prev_val do
          # Already covered by a previous solution
          {acc_hv, prev_val}
        else
          # This solution contributes new area
          slice_width = sol_val - prev_val

          # Find all solutions that could contribute in remaining dimensions
          # These are solutions whose current_obj value is >= sol_val
          # (they extend from this slice onwards)
          slice_solutions =
            Enum.filter(sorted, fn s ->
              Map.get(s.normalized_objectives, current_obj, 0.0) >= sol_val
            end)

          # Recursively calculate hypervolume in remaining dimensions
          slice_hv =
            if length(remaining_objs) > 0 do
              wfg_recursive(slice_solutions, reference, objectives, depth + 1)
            else
              # No more dimensions, unit hypervolume
              1.0
            end

          contrib = slice_width * slice_hv
          {acc_hv + contrib, sol_val}
        end
      end)

    hv
  end

  # Validation helpers

  @spec fetch_required(keyword(), atom()) :: {:ok, term()} | {:error, term()}
  defp fetch_required(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_required_option, key}}
    end
  end

  @spec validate_solutions(list(Candidate.t())) :: :ok | {:error, term()}
  defp validate_solutions(solutions) when is_list(solutions), do: :ok
  defp validate_solutions(_), do: {:error, :invalid_solutions_format}

  @spec validate_reference_point(map(), list(atom())) :: :ok | {:error, term()}
  defp validate_reference_point(reference, objectives)
       when is_map(reference) and is_list(objectives) do
    if Enum.all?(objectives, fn obj -> Map.has_key?(reference, obj) end) do
      # Validate all values are numeric
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

  defp validate_reference_point(_, _), do: {:error, :invalid_reference_point_format}
end
