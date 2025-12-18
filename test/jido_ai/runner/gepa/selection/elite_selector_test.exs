defmodule Jido.AI.Runner.GEPA.Selection.EliteSelectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Selection.EliteSelector

  describe "select_elites/2 - basic validation" do
    test "returns empty list for empty population" do
      assert {:ok, []} = EliteSelector.select_elites([])
    end

    test "returns error when population lacks pareto_rank" do
      population = [
        %{create_candidate("c1") | pareto_rank: nil, crowding_distance: 0.5}
      ]

      assert {:error, {:missing_pareto_rank, "c1"}} =
               EliteSelector.select_elites(population)
    end

    test "returns error when population lacks crowding_distance" do
      population = [
        %{create_candidate("c1") | pareto_rank: 1, crowding_distance: nil}
      ]

      assert {:error, {:missing_crowding_distance, "c1"}} =
               EliteSelector.select_elites(population)
    end
  end

  describe "select_elites/2 - with elite_ratio" do
    test "selects 15% of population by default" do
      population = create_population_with_metrics(100)

      {:ok, elites} = EliteSelector.select_elites(population)

      # 15% of 100
      assert length(elites) == 15
    end

    test "selects custom ratio of population" do
      population = create_population_with_metrics(100)

      {:ok, elites} = EliteSelector.select_elites(population, elite_ratio: 0.20)

      # 20% of 100
      assert length(elites) == 20
    end

    test "respects min_elites even with low ratio" do
      population = create_population_with_metrics(10)

      {:ok, elites} =
        EliteSelector.select_elites(
          population,
          # Would be 0.5 -> 0
          elite_ratio: 0.05,
          min_elites: 3
        )

      assert length(elites) == 3
    end

    test "selects at least 1 elite by default" do
      population = create_population_with_metrics(5)

      {:ok, elites} = EliteSelector.select_elites(population, elite_ratio: 0.01)

      assert length(elites) >= 1
    end
  end

  describe "select_elites/2 - with elite_count" do
    test "elite_count overrides elite_ratio" do
      population = create_population_with_metrics(100)

      {:ok, elites} =
        EliteSelector.select_elites(
          population,
          # Would select 20
          elite_ratio: 0.20,
          # But this takes precedence
          elite_count: 30
        )

      assert length(elites) == 30
    end

    test "handles elite_count greater than population" do
      population = create_population_with_metrics(10)

      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 20)

      # Should cap at population size
      assert length(elites) == 10
    end

    test "selects exact count specified" do
      population = create_population_with_metrics(50)

      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 12)

      assert length(elites) == 12
    end
  end

  describe "select_elites/2 - selection criteria" do
    test "prioritizes better Pareto rank" do
      population = [
        create_candidate_with_metrics("f1_c1", rank: 1, distance: 0.5),
        create_candidate_with_metrics("f1_c2", rank: 1, distance: 0.6),
        create_candidate_with_metrics("f2_c1", rank: 2, distance: 0.9),
        create_candidate_with_metrics("f2_c2", rank: 2, distance: 0.8),
        create_candidate_with_metrics("f3_c1", rank: 3, distance: 0.7)
      ]

      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 3)

      elite_ids = Enum.map(elites, & &1.id)

      # Should select both from Front 1, then best from Front 2
      assert "f1_c1" in elite_ids
      assert "f1_c2" in elite_ids
      assert "f2_c1" in elite_ids or "f2_c2" in elite_ids
    end

    test "uses crowding distance for tiebreaking within same rank" do
      population = [
        create_candidate_with_metrics("c1", rank: 1, distance: 0.3),
        create_candidate_with_metrics("c2", rank: 1, distance: 0.8),
        create_candidate_with_metrics("c3", rank: 1, distance: 0.5),
        create_candidate_with_metrics("c4", rank: 1, distance: 0.9),
        create_candidate_with_metrics("c5", rank: 1, distance: 0.4)
      ]

      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 3)

      elite_ids = Enum.map(elites, & &1.id)

      # Should select c4 (0.9), c2 (0.8), c3 (0.5)
      assert "c4" in elite_ids
      assert "c2" in elite_ids
      assert "c3" in elite_ids
      # 0.3
      refute "c1" in elite_ids
      # 0.4
      refute "c5" in elite_ids
    end

    test "boundary solutions with infinite distance always selected first" do
      population = [
        create_candidate_with_metrics("boundary_1", rank: 1, distance: :infinity),
        create_candidate_with_metrics("c2", rank: 1, distance: 0.9),
        create_candidate_with_metrics("boundary_2", rank: 1, distance: :infinity),
        create_candidate_with_metrics("c4", rank: 1, distance: 0.8),
        create_candidate_with_metrics("c5", rank: 1, distance: 0.7)
      ]

      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 3)

      elite_ids = Enum.map(elites, & &1.id)

      # Both boundary solutions must be selected
      assert "boundary_1" in elite_ids
      assert "boundary_2" in elite_ids
      # Plus the highest finite distance
      assert "c2" in elite_ids
    end

    test "all Front 1 included when elite_count >= |Front 1|" do
      population = [
        create_candidate_with_metrics("f1_c1", rank: 1, distance: 0.5),
        create_candidate_with_metrics("f1_c2", rank: 1, distance: 0.6),
        create_candidate_with_metrics("f1_c3", rank: 1, distance: 0.7),
        create_candidate_with_metrics("f2_c1", rank: 2, distance: 0.8),
        create_candidate_with_metrics("f2_c2", rank: 2, distance: 0.9)
      ]

      {:ok, elites} = EliteSelector.select_elites(population, elite_count: 4)

      front_1_ids =
        Enum.filter(elites, fn e -> e.pareto_rank == 1 end)
        |> Enum.map(& &1.id)

      # All 3 Front 1 candidates should be included
      assert length(front_1_ids) == 3
      assert "f1_c1" in front_1_ids
      assert "f1_c2" in front_1_ids
      assert "f1_c3" in front_1_ids
    end
  end

  describe "select_pareto_front_1/1" do
    test "returns empty list for empty population" do
      assert {:ok, []} = EliteSelector.select_pareto_front_1([])
    end

    test "returns all non-dominated solutions" do
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.8}),
        create_candidate("c2", normalized_objectives: %{accuracy: 0.8, latency: 0.9}),
        # Dominated
        create_candidate("c3", normalized_objectives: %{accuracy: 0.7, latency: 0.7})
      ]

      {:ok, front_1} = EliteSelector.select_pareto_front_1(population)

      # c1 and c2 are non-dominated, c3 is dominated by both
      assert length(front_1) == 2
      front_1_ids = Enum.map(front_1, & &1.id)
      assert "c1" in front_1_ids
      assert "c2" in front_1_ids
      refute "c3" in front_1_ids
    end

    test "returns all candidates when all are non-dominated" do
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.7}),
        create_candidate("c2", normalized_objectives: %{accuracy: 0.8, latency: 0.8}),
        create_candidate("c3", normalized_objectives: %{accuracy: 0.7, latency: 0.9})
      ]

      {:ok, front_1} = EliteSelector.select_pareto_front_1(population)

      # All three are non-dominated (form Pareto frontier)
      assert length(front_1) == 3
    end

    test "handles single candidate" do
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.9, latency: 0.8})
      ]

      {:ok, front_1} = EliteSelector.select_pareto_front_1(population)

      assert length(front_1) == 1
      assert hd(front_1).id == "c1"
    end
  end

  describe "select_elites_preserve_frontier/2" do
    test "returns error when elite_count missing" do
      population = create_population_with_metrics(10)

      assert {:error, {:missing_required_option, :elite_count}} =
               EliteSelector.select_elites_preserve_frontier(population, [])
    end

    test "includes all Front 1 when smaller than elite_count" do
      # Create population with known fronts
      population = [
        # Front 1 (3 candidates)
        create_candidate("f1_c1", normalized_objectives: %{accuracy: 0.95, latency: 0.9}),
        create_candidate("f1_c2", normalized_objectives: %{accuracy: 0.9, latency: 0.95}),
        create_candidate("f1_c3", normalized_objectives: %{accuracy: 0.92, latency: 0.92}),
        # Front 2 (3 candidates - all dominated by Front 1)
        create_candidate("f2_c1", normalized_objectives: %{accuracy: 0.85, latency: 0.85}),
        create_candidate("f2_c2", normalized_objectives: %{accuracy: 0.8, latency: 0.8}),
        create_candidate("f2_c3", normalized_objectives: %{accuracy: 0.82, latency: 0.83})
      ]

      {:ok, elites} =
        EliteSelector.select_elites_preserve_frontier(
          population,
          elite_count: 5
        )

      assert length(elites) == 5

      # Count Front 1 members in elites
      front_1_count =
        Enum.count(elites, fn e ->
          String.starts_with?(e.id, "f1_")
        end)

      # All 3 Front 1 candidates must be included
      assert front_1_count == 3
    end

    test "trims Front 1 by crowding distance when larger than elite_count" do
      # Create large Front 1
      front_1_candidates =
        Enum.map(1..10, fn i ->
          create_candidate("f1_c#{i}",
            normalized_objectives: %{
              accuracy: 0.85 + i * 0.01,
              latency: 0.85 - i * 0.008
            }
          )
        end)

      {:ok, elites} =
        EliteSelector.select_elites_preserve_frontier(
          front_1_candidates,
          elite_count: 6
        )

      assert length(elites) == 6

      # All elites should be from Front 1
      assert Enum.all?(elites, fn e -> String.starts_with?(e.id, "f1_") end)

      # Boundary solutions (extreme values) should be included
      # These would have infinite crowding distance
    end

    test "fills remaining slots with Front 2 by crowding distance" do
      population = [
        # Front 1 (2 candidates)
        create_candidate("f1_c1", normalized_objectives: %{accuracy: 0.95, latency: 0.9}),
        create_candidate("f1_c2", normalized_objectives: %{accuracy: 0.9, latency: 0.95}),
        # Front 2 (5 candidates)
        create_candidate("f2_c1", normalized_objectives: %{accuracy: 0.85, latency: 0.85}),
        create_candidate("f2_c2", normalized_objectives: %{accuracy: 0.8, latency: 0.88}),
        create_candidate("f2_c3", normalized_objectives: %{accuracy: 0.82, latency: 0.83}),
        create_candidate("f2_c4", normalized_objectives: %{accuracy: 0.88, latency: 0.8}),
        create_candidate("f2_c5", normalized_objectives: %{accuracy: 0.81, latency: 0.86})
      ]

      {:ok, elites} =
        EliteSelector.select_elites_preserve_frontier(
          population,
          elite_count: 5
        )

      assert length(elites) == 5

      # All Front 1 included
      front_1_count = Enum.count(elites, fn e -> String.starts_with?(e.id, "f1_") end)
      assert front_1_count == 2

      # 3 from Front 2 (most diverse)
      front_2_count = Enum.count(elites, fn e -> String.starts_with?(e.id, "f2_") end)
      assert front_2_count == 3
    end

    test "handles elite_count equal to Front 1 size" do
      population = [
        create_candidate("f1_c1", normalized_objectives: %{accuracy: 0.95, latency: 0.9}),
        create_candidate("f1_c2", normalized_objectives: %{accuracy: 0.9, latency: 0.95}),
        create_candidate("f1_c3", normalized_objectives: %{accuracy: 0.92, latency: 0.92}),
        create_candidate("f2_c1", normalized_objectives: %{accuracy: 0.8, latency: 0.8})
      ]

      {:ok, elites} =
        EliteSelector.select_elites_preserve_frontier(
          population,
          elite_count: 3
        )

      assert length(elites) == 3
      # All should be Front 1
      assert Enum.all?(elites, fn e -> String.starts_with?(e.id, "f1_") end)
    end
  end

  describe "select_diverse_elites/2" do
    test "returns error when elite_count missing" do
      population = create_population_with_metrics(10)

      assert {:error, {:missing_required_option, :elite_count}} =
               EliteSelector.select_diverse_elites(population, [])
    end

    test "avoids selecting near-duplicate candidates" do
      population = [
        # Very similar objectives (within default 0.01 threshold)
        create_candidate_with_metrics("c1",
          rank: 1,
          distance: 0.9,
          objectives: %{accuracy: 0.900, latency: 0.800}
        ),
        create_candidate_with_metrics("c2",
          rank: 1,
          distance: 0.8,
          # Very close to c1
          objectives: %{accuracy: 0.902, latency: 0.801}
        ),

        # Different objectives
        create_candidate_with_metrics("c3",
          rank: 1,
          distance: 0.7,
          objectives: %{accuracy: 0.850, latency: 0.850}
        ),
        create_candidate_with_metrics("c4",
          rank: 1,
          distance: 0.6,
          objectives: %{accuracy: 0.800, latency: 0.900}
        )
      ]

      {:ok, elites} =
        EliteSelector.select_diverse_elites(
          population,
          elite_count: 3,
          similarity_threshold: 0.01
        )

      elite_ids = Enum.map(elites, & &1.id)

      # c1 should be selected (higher distance)
      assert "c1" in elite_ids
      # c2 should be skipped (too similar to c1)
      refute "c2" in elite_ids
      # c3 and c4 should be selected (different)
      assert "c3" in elite_ids
      assert "c4" in elite_ids
    end

    test "uses custom similarity threshold" do
      population = [
        create_candidate_with_metrics("c1",
          rank: 1,
          distance: 0.9,
          objectives: %{accuracy: 0.900, latency: 0.800}
        ),
        create_candidate_with_metrics("c2",
          rank: 1,
          distance: 0.8,
          # 0.05 distance from c1
          objectives: %{accuracy: 0.950, latency: 0.800}
        ),
        create_candidate_with_metrics("c3",
          rank: 1,
          distance: 0.7,
          objectives: %{accuracy: 0.800, latency: 0.900}
        )
      ]

      # With strict threshold 0.03: c2 is diverse enough (0.05 > 0.03), so all 3 selected
      {:ok, elites_strict} =
        EliteSelector.select_diverse_elites(
          population,
          elite_count: 3,
          similarity_threshold: 0.03
        )

      elite_ids_strict = Enum.map(elites_strict, & &1.id)
      assert length(elites_strict) == 3
      assert "c1" in elite_ids_strict
      # 0.05 > 0.03, so diverse enough
      assert "c2" in elite_ids_strict
      assert "c3" in elite_ids_strict

      # With loose threshold 0.1: c2 is too similar (0.05 < 0.1), so only c1 and c3 selected
      {:ok, elites_loose} =
        EliteSelector.select_diverse_elites(
          population,
          elite_count: 3,
          similarity_threshold: 0.1
        )

      elite_ids_loose = Enum.map(elites_loose, & &1.id)
      # c1 selected first (highest distance in rank 1)
      assert "c1" in elite_ids_loose
      # c2 skipped (too similar to c1: 0.05 < 0.1)
      refute "c2" in elite_ids_loose
      # c3 selected (different from c1)
      assert "c3" in elite_ids_loose
      # Only 2 elites selected (couldn't find 3 diverse ones)
      assert length(elites_loose) == 2
    end

    test "prioritizes by rank, then distance, then generation" do
      population = [
        # Lower rank, lower distance, newer
        create_candidate_with_metrics("c1",
          rank: 1,
          distance: 0.5,
          generation: 5,
          objectives: %{accuracy: 0.90, latency: 0.80}
        ),

        # Higher rank, higher distance, older
        create_candidate_with_metrics("c2",
          rank: 2,
          distance: 0.9,
          generation: 1,
          objectives: %{accuracy: 0.85, latency: 0.85}
        ),

        # Same rank as c1, higher distance, older
        create_candidate_with_metrics("c3",
          rank: 1,
          distance: 0.7,
          generation: 2,
          objectives: %{accuracy: 0.80, latency: 0.90}
        )
      ]

      {:ok, elites} =
        EliteSelector.select_diverse_elites(
          population,
          elite_count: 2,
          similarity_threshold: 0.01
        )

      elite_ids = Enum.map(elites, & &1.id)

      # c3 should be selected first (rank 1, distance 0.7)
      # c1 should be selected second (rank 1, distance 0.5)
      # c2 should not be selected (rank 2)
      assert "c1" in elite_ids
      assert "c3" in elite_ids
      refute "c2" in elite_ids
    end

    test "handles case where fewer diverse candidates than requested" do
      # All candidates very similar
      population =
        Enum.map(1..10, fn i ->
          create_candidate_with_metrics("c#{i}",
            rank: 1,
            distance: 0.5,
            objectives: %{accuracy: 0.900 + i * 0.001, latency: 0.800}
          )
        end)

      {:ok, elites} =
        EliteSelector.select_diverse_elites(
          population,
          elite_count: 10,
          similarity_threshold: 0.01
        )

      # With threshold 0.01 and step 0.001, only ~10 candidates fit
      # But most will be filtered as duplicates
      assert length(elites) < 10
      assert length(elites) >= 1
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

  defp create_candidate_with_metrics(id, opts) do
    rank = Keyword.fetch!(opts, :rank)
    distance = Keyword.fetch!(opts, :distance)
    generation = Keyword.get(opts, :generation, 1)
    objectives = Keyword.get(opts, :objectives, %{accuracy: 0.8, latency: 0.8})

    create_candidate(id,
      pareto_rank: rank,
      crowding_distance: distance,
      generation: generation,
      normalized_objectives: objectives
    )
  end

  defp create_population_with_metrics(size) do
    Enum.map(1..size, fn i ->
      # Distribute across ranks
      rank = rem(i - 1, 3) + 1

      # Vary crowding distance
      distance = :rand.uniform()

      create_candidate_with_metrics("c#{i}",
        rank: rank,
        distance: distance,
        generation: rem(i, 5) + 1
      )
    end)
  end
end
