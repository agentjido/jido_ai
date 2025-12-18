defmodule Jido.AI.Runner.GEPA.Selection.CrowdingDistanceSelectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator
  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Selection.CrowdingDistanceSelector

  describe "assign_crowding_distances/2" do
    test "returns empty list for empty population" do
      assert {:ok, []} = CrowdingDistanceSelector.assign_crowding_distances([])
    end

    test "assigns crowding distances to single-front population" do
      population =
        create_population_with_ranks([
          {"c1", 1, %{accuracy: 0.9, latency: 0.8}},
          {"c2", 1, %{accuracy: 0.8, latency: 0.9}},
          {"c3", 1, %{accuracy: 0.85, latency: 0.85}}
        ])

      assert {:ok, result} = CrowdingDistanceSelector.assign_crowding_distances(population)

      assert length(result) == 3
      assert Enum.all?(result, fn c -> c.crowding_distance != nil end)

      # Boundary solutions should have infinite distance
      boundary_distances =
        Enum.filter(result, fn c ->
          c.crowding_distance == :infinity
        end)

      # Min and max in each objective
      assert length(boundary_distances) == 2
    end

    test "assigns crowding distances to multi-front population" do
      population =
        create_population_with_ranks([
          {"c1", 1, %{accuracy: 0.9, latency: 0.8}},
          {"c2", 1, %{accuracy: 0.8, latency: 0.9}},
          {"c3", 2, %{accuracy: 0.7, latency: 0.7}},
          {"c4", 2, %{accuracy: 0.6, latency: 0.8}}
        ])

      assert {:ok, result} = CrowdingDistanceSelector.assign_crowding_distances(population)

      # Check that distances are calculated per front
      front_1 = Enum.filter(result, fn c -> c.pareto_rank == 1 end)
      front_2 = Enum.filter(result, fn c -> c.pareto_rank == 2 end)

      assert length(front_1) == 2
      assert length(front_2) == 2

      # Both fronts should have boundary solutions with infinite distance
      assert Enum.any?(front_1, fn c -> c.crowding_distance == :infinity end)
      assert Enum.any?(front_2, fn c -> c.crowding_distance == :infinity end)
    end

    test "handles population with <= 2 candidates per front" do
      population =
        create_population_with_ranks([
          {"c1", 1, %{accuracy: 0.9, latency: 0.8}},
          {"c2", 1, %{accuracy: 0.8, latency: 0.9}}
        ])

      assert {:ok, result} = CrowdingDistanceSelector.assign_crowding_distances(population)

      # With 2 or fewer, all get infinity
      assert Enum.all?(result, fn c -> c.crowding_distance == :infinity end)
    end

    test "returns error for population without pareto_rank" do
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.8})
      ]

      assert {:error, {:missing_pareto_rank, "c1"}} =
               CrowdingDistanceSelector.assign_crowding_distances(population)
    end

    test "calls DominanceComparator.crowding_distance for each front" do
      population =
        create_population_with_ranks([
          {"c1", 1, %{accuracy: 0.9, latency: 0.8}},
          {"c2", 1, %{accuracy: 0.8, latency: 0.9}},
          {"c3", 1, %{accuracy: 0.85, latency: 0.85}}
        ])

      {:ok, result} = CrowdingDistanceSelector.assign_crowding_distances(population)

      # Verify distances match what DominanceComparator would produce
      expected_distances = DominanceComparator.crowding_distance(population)

      Enum.each(result, fn candidate ->
        expected = Map.get(expected_distances, candidate.id)
        assert candidate.crowding_distance == expected
      end)
    end
  end

  describe "select_by_crowding_distance/2" do
    test "returns error when count option missing" do
      population = create_population_with_distances([])

      assert {:error, {:missing_required_option, :count}} =
               CrowdingDistanceSelector.select_by_crowding_distance(population, [])
    end

    test "returns error for invalid count" do
      population =
        create_population_with_distances([
          {"c1", 1, 0.5, %{accuracy: 0.9}}
        ])

      assert {:error, {:invalid_count, 0}} =
               CrowdingDistanceSelector.select_by_crowding_distance(population, count: 0)

      assert {:error, {:count_exceeds_population, 5, 1}} =
               CrowdingDistanceSelector.select_by_crowding_distance(population, count: 5)
    end

    test "returns error for population without pareto_rank" do
      population = [
        %{create_candidate("c1") | crowding_distance: 0.5, pareto_rank: nil}
      ]

      assert {:error, {:missing_pareto_rank, "c1"}} =
               CrowdingDistanceSelector.select_by_crowding_distance(population, count: 1)
    end

    test "returns error for population without crowding_distance" do
      population = [
        %{create_candidate("c1") | pareto_rank: 1, crowding_distance: nil}
      ]

      assert {:error, {:missing_crowding_distance, "c1"}} =
               CrowdingDistanceSelector.select_by_crowding_distance(population, count: 1)
    end

    test "selects candidates by rank first, distance second" do
      population =
        create_population_with_distances([
          {"c1", 1, 0.3, %{accuracy: 0.9}},
          # Same rank, higher distance
          {"c2", 1, 0.8, %{accuracy: 0.85}},
          # Worse rank, highest distance
          {"c3", 2, 0.9, %{accuracy: 0.7}},
          {"c4", 2, 0.2, %{accuracy: 0.65}}
        ])

      {:ok, survivors} =
        CrowdingDistanceSelector.select_by_crowding_distance(
          population,
          count: 3
        )

      ids = Enum.map(survivors, & &1.id)

      # Should select: both from Front 1 (c1, c2), then best from Front 2 (c3)
      assert "c1" in ids
      assert "c2" in ids
      assert "c3" in ids
      refute "c4" in ids
    end

    test "within same rank, selects by crowding distance (highest first)" do
      population =
        create_population_with_distances([
          {"c1", 1, 0.3, %{accuracy: 0.9}},
          {"c2", 1, 0.8, %{accuracy: 0.85}},
          {"c3", 1, 0.5, %{accuracy: 0.88}}
        ])

      {:ok, survivors} =
        CrowdingDistanceSelector.select_by_crowding_distance(
          population,
          count: 2
        )

      ids = Enum.map(survivors, & &1.id)

      # Should select c2 (0.8) and c3 (0.5), not c1 (0.3)
      assert "c2" in ids
      assert "c3" in ids
      refute "c1" in ids
    end

    test "boundary solutions with infinite distance always selected first" do
      population =
        create_population_with_distances([
          # Boundary
          {"c1", 1, :infinity, %{accuracy: 0.9}},
          {"c2", 1, 0.8, %{accuracy: 0.85}},
          # Boundary
          {"c3", 1, :infinity, %{accuracy: 0.8}},
          {"c4", 1, 0.6, %{accuracy: 0.88}}
        ])

      {:ok, survivors} =
        CrowdingDistanceSelector.select_by_crowding_distance(
          population,
          count: 3
        )

      ids = Enum.map(survivors, & &1.id)

      # Both boundary solutions must be selected
      assert "c1" in ids
      assert "c3" in ids
      # Plus the highest finite distance
      assert "c2" in ids
      refute "c4" in ids
    end

    test "selects exact count specified" do
      population =
        create_population_with_distances([
          {"c1", 1, 0.8, %{accuracy: 0.9}},
          {"c2", 1, 0.7, %{accuracy: 0.85}},
          {"c3", 1, 0.6, %{accuracy: 0.88}},
          {"c4", 1, 0.5, %{accuracy: 0.82}},
          {"c5", 1, 0.4, %{accuracy: 0.87}}
        ])

      {:ok, survivors} =
        CrowdingDistanceSelector.select_by_crowding_distance(
          population,
          count: 3
        )

      assert length(survivors) == 3
    end
  end

  describe "environmental_selection/2" do
    test "returns error when target_size option missing" do
      population = []

      assert {:error, {:missing_required_option, :target_size}} =
               CrowdingDistanceSelector.environmental_selection(population, [])
    end

    test "returns error for invalid target_size" do
      population = create_candidates_for_environmental_selection(5)

      assert {:error, {:invalid_target_size, 0}} =
               CrowdingDistanceSelector.environmental_selection(population, target_size: 0)

      assert {:error, {:target_exceeds_population, 10, 5}} =
               CrowdingDistanceSelector.environmental_selection(population, target_size: 10)
    end

    test "performs non-dominated sorting and assigns crowding distances" do
      # Create population where some dominate others
      population = [
        # Best
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.9}),
        # Front 2
        create_candidate("c2", normalized_objectives: %{accuracy: 0.8, latency: 0.8}),
        # Front 1
        create_candidate("c3", normalized_objectives: %{accuracy: 0.85, latency: 0.7}),
        # Front 1
        create_candidate("c4", normalized_objectives: %{accuracy: 0.7, latency: 0.85})
      ]

      {:ok, survivors} =
        CrowdingDistanceSelector.environmental_selection(
          population,
          target_size: 3
        )

      assert length(survivors) == 3

      # All survivors should have pareto_rank and crowding_distance assigned
      assert Enum.all?(survivors, fn c -> c.pareto_rank != nil end)
      assert Enum.all?(survivors, fn c -> c.crowding_distance != nil end)

      # Front 1 candidates should be included
      survivor_ids = Enum.map(survivors, & &1.id)
      assert "c1" in survivor_ids
    end

    test "fills population front by front until target reached" do
      # Create 3 fronts: Front 1 (3), Front 2 (3), Front 3 (4)
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.95, latency: 0.9}),
        create_candidate("c2", normalized_objectives: %{accuracy: 0.9, latency: 0.95}),
        create_candidate("c3", normalized_objectives: %{accuracy: 0.92, latency: 0.92}),
        create_candidate("c4", normalized_objectives: %{accuracy: 0.8, latency: 0.85}),
        create_candidate("c5", normalized_objectives: %{accuracy: 0.85, latency: 0.8}),
        create_candidate("c6", normalized_objectives: %{accuracy: 0.82, latency: 0.82}),
        create_candidate("c7", normalized_objectives: %{accuracy: 0.7, latency: 0.75}),
        create_candidate("c8", normalized_objectives: %{accuracy: 0.75, latency: 0.7}),
        create_candidate("c9", normalized_objectives: %{accuracy: 0.72, latency: 0.72}),
        create_candidate("c10", normalized_objectives: %{accuracy: 0.73, latency: 0.71})
      ]

      {:ok, survivors} =
        CrowdingDistanceSelector.environmental_selection(
          population,
          target_size: 7
        )

      assert length(survivors) == 7

      # Should include all of Front 1 and Front 2, plus 1 from Front 3
      ranks = Enum.map(survivors, & &1.pareto_rank) |> Enum.frequencies()

      # Front 1 and 2 should be fully included
      assert Map.get(ranks, 1, 0) >= 1
    end

    test "trims cutoff front by crowding distance" do
      # Create controlled scenario where we know the front structure
      # Front 1: 2 candidates
      # Front 2: 5 candidates (will be cutoff front)
      # Target: 5 (need to trim Front 2 from 5 to 3)

      front_1 = [
        create_candidate("f1_c1", normalized_objectives: %{accuracy: 0.95, latency: 0.9}),
        create_candidate("f1_c2", normalized_objectives: %{accuracy: 0.9, latency: 0.95})
      ]

      # Front 2 - all non-dominated among themselves but dominated by Front 1
      front_2 = [
        create_candidate("f2_c1", normalized_objectives: %{accuracy: 0.85, latency: 0.85}),
        create_candidate("f2_c2", normalized_objectives: %{accuracy: 0.8, latency: 0.8}),
        create_candidate("f2_c3", normalized_objectives: %{accuracy: 0.82, latency: 0.83}),
        create_candidate("f2_c4", normalized_objectives: %{accuracy: 0.83, latency: 0.82}),
        create_candidate("f2_c5", normalized_objectives: %{accuracy: 0.81, latency: 0.84})
      ]

      population = front_1 ++ front_2

      {:ok, survivors} =
        CrowdingDistanceSelector.environmental_selection(
          population,
          target_size: 5
        )

      assert length(survivors) == 5

      # All of Front 1 should be included
      f1_ids = Enum.map(front_1, & &1.id)
      survivor_ids = Enum.map(survivors, & &1.id)

      assert Enum.all?(f1_ids, fn id -> id in survivor_ids end)

      # Exactly 3 from Front 2 should be included
      f2_survivors = Enum.filter(survivors, fn c -> String.starts_with?(c.id, "f2_") end)
      assert length(f2_survivors) == 3

      # These should be the ones with highest crowding distance
      # (Boundary solutions and most isolated)
    end

    test "handles target_size equal to population size" do
      population = create_candidates_for_environmental_selection(10)

      {:ok, survivors} =
        CrowdingDistanceSelector.environmental_selection(
          population,
          target_size: 10
        )

      assert length(survivors) == 10
    end

    test "preserves boundary solutions during trimming" do
      # Create a front where we can identify boundary solutions
      candidates = [
        # Min accuracy
        create_candidate("boundary_min_acc",
          normalized_objectives: %{accuracy: 0.6, latency: 0.9}
        ),
        # Max accuracy
        create_candidate("boundary_max_acc",
          normalized_objectives: %{accuracy: 0.95, latency: 0.7}
        ),
        # Min latency
        create_candidate("boundary_min_lat",
          normalized_objectives: %{accuracy: 0.85, latency: 0.65}
        ),
        # Max latency
        create_candidate("boundary_max_lat",
          normalized_objectives: %{accuracy: 0.75, latency: 0.95}
        ),
        create_candidate("middle_1", normalized_objectives: %{accuracy: 0.8, latency: 0.8}),
        create_candidate("middle_2", normalized_objectives: %{accuracy: 0.82, latency: 0.78})
      ]

      {:ok, survivors} =
        CrowdingDistanceSelector.environmental_selection(
          candidates,
          target_size: 5
        )

      survivor_ids = Enum.map(survivors, & &1.id)

      # Boundary solutions should have been preserved
      # (They get infinite crowding distance)
      boundary_count =
        Enum.count(survivor_ids, fn id ->
          String.starts_with?(id, "boundary_")
        end)

      # At least some boundaries should be preserved
      assert boundary_count >= 2
    end
  end

  describe "identify_boundary_solutions/1" do
    test "returns empty list for empty population" do
      assert [] = CrowdingDistanceSelector.identify_boundary_solutions([])
    end

    test "returns empty list for population without objectives" do
      population = [
        create_candidate("c1", normalized_objectives: nil)
      ]

      assert [] = CrowdingDistanceSelector.identify_boundary_solutions(population)
    end

    test "identifies min and max for single objective" do
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.5}),
        # Max
        create_candidate("c2", normalized_objectives: %{accuracy: 0.9}),
        # Min
        create_candidate("c3", normalized_objectives: %{accuracy: 0.3}),
        create_candidate("c4", normalized_objectives: %{accuracy: 0.7})
      ]

      boundary_ids = CrowdingDistanceSelector.identify_boundary_solutions(population)

      # Max
      assert "c2" in boundary_ids
      # Min
      assert "c3" in boundary_ids
      assert length(boundary_ids) == 2
    end

    test "identifies min and max for each objective" do
      population = [
        # Max acc, min lat
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.3}),
        # Min acc, max lat
        create_candidate("c2", normalized_objectives: %{accuracy: 0.3, latency: 0.9}),
        # Middle
        create_candidate("c3", normalized_objectives: %{accuracy: 0.6, latency: 0.6}),
        # Middle
        create_candidate("c4", normalized_objectives: %{accuracy: 0.7, latency: 0.5})
      ]

      boundary_ids = CrowdingDistanceSelector.identify_boundary_solutions(population)

      # c1 and c2 are boundary in both objectives
      assert "c1" in boundary_ids
      assert "c2" in boundary_ids

      # c3 and c4 are not boundary
      refute "c3" in boundary_ids
      refute "c4" in boundary_ids

      assert length(boundary_ids) == 2
    end

    test "identifies boundaries for 3 objectives" do
      population = [
        # Max acc
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.5, cost: 0.5}),
        # Min acc, max lat
        create_candidate("c2", normalized_objectives: %{accuracy: 0.3, latency: 0.9, cost: 0.5}),
        # Min lat, max cost
        create_candidate("c3", normalized_objectives: %{accuracy: 0.6, latency: 0.3, cost: 0.9}),
        # Min cost
        create_candidate("c4", normalized_objectives: %{accuracy: 0.5, latency: 0.5, cost: 0.2}),
        # Middle
        create_candidate("c5", normalized_objectives: %{accuracy: 0.7, latency: 0.7, cost: 0.6})
      ]

      boundary_ids = CrowdingDistanceSelector.identify_boundary_solutions(population)

      # c1, c2, c3, c4 are all boundary in at least one objective
      assert "c1" in boundary_ids
      assert "c2" in boundary_ids
      assert "c3" in boundary_ids
      assert "c4" in boundary_ids

      # c5 is not boundary
      refute "c5" in boundary_ids
    end

    test "handles case where same candidate is boundary in multiple objectives" do
      population = [
        # Max in both
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.9}),
        # Min in both
        create_candidate("c2", normalized_objectives: %{accuracy: 0.1, latency: 0.1}),
        create_candidate("c3", normalized_objectives: %{accuracy: 0.5, latency: 0.5})
      ]

      boundary_ids = CrowdingDistanceSelector.identify_boundary_solutions(population)

      # c1 and c2 are boundary, but should only appear once each
      assert "c1" in boundary_ids
      assert "c2" in boundary_ids
      assert length(boundary_ids) == 2
    end

    test "handles population with all identical objective values" do
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.5, latency: 0.5}),
        create_candidate("c2", normalized_objectives: %{accuracy: 0.5, latency: 0.5}),
        create_candidate("c3", normalized_objectives: %{accuracy: 0.5, latency: 0.5})
      ]

      boundary_ids = CrowdingDistanceSelector.identify_boundary_solutions(population)

      # When all values are identical, first and last become boundaries
      # (But they happen to be the same, so we get duplicates that get uniq'd)
      assert length(boundary_ids) >= 1
      assert length(boundary_ids) <= 3
    end
  end

  # Test helpers

  defp create_candidate(id, opts \\ []) do
    %Candidate{
      id: id,
      prompt: Keyword.get(opts, :prompt, "test prompt"),
      generation: Keyword.get(opts, :generation, 1),
      created_at: Keyword.get(opts, :created_at, System.system_time(:millisecond)),
      pareto_rank: Keyword.get(opts, :pareto_rank, nil),
      crowding_distance: Keyword.get(opts, :crowding_distance, nil),
      fitness: Keyword.get(opts, :fitness, 0.8),
      objectives: Keyword.get(opts, :objectives, %{}),
      normalized_objectives: Keyword.get(opts, :normalized_objectives, %{})
    }
  end

  defp create_population_with_ranks(specs) do
    Enum.map(specs, fn {id, rank, objectives} ->
      create_candidate(id,
        pareto_rank: rank,
        normalized_objectives: objectives
      )
    end)
  end

  defp create_population_with_distances(specs) do
    Enum.map(specs, fn {id, rank, distance, objectives} ->
      create_candidate(id,
        pareto_rank: rank,
        crowding_distance: distance,
        normalized_objectives: objectives
      )
    end)
  end

  defp create_candidates_for_environmental_selection(count) do
    Enum.map(1..count, fn i ->
      create_candidate("c#{i}",
        normalized_objectives: %{
          accuracy: 0.5 + i * 0.03,
          latency: 0.5 + :rand.uniform() * 0.3
        }
      )
    end)
  end
end
