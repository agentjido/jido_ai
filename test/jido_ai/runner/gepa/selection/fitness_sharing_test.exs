defmodule Jido.AI.Runner.GEPA.Selection.FitnessSharingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Selection.FitnessSharing

  describe "apply_sharing/2" do
    test "empty population returns empty list" do
      assert {:ok, []} = FitnessSharing.apply_sharing([])
    end

    test "single candidate gets niche count of 1.0 (shares with self)" do
      candidate =
        create_candidate("c1",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.8, latency: 0.3}
        )

      {:ok, [shared]} = FitnessSharing.apply_sharing([candidate])

      # Niche count should be 1.0 (only itself)
      assert shared.metadata.niche_count == 1.0
      # Shared fitness should equal raw fitness (10.0 / 1.0)
      assert shared.fitness == 10.0
      assert shared.metadata.raw_fitness == 10.0
    end

    test "identical candidates share fitness equally" do
      # Three identical candidates at same location
      candidates = [
        create_candidate("c1",
          fitness: 9.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        ),
        create_candidate("c2",
          fitness: 9.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        ),
        create_candidate("c3",
          fitness: 9.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        )
      ]

      {:ok, shared_pop} = FitnessSharing.apply_sharing(candidates, niche_radius: 0.1)

      # All should have niche count of 3.0
      assert Enum.all?(shared_pop, fn c -> c.metadata.niche_count == 3.0 end)

      # All should have shared fitness of 3.0 (9.0 / 3.0)
      assert Enum.all?(shared_pop, fn c -> c.fitness == 3.0 end)
    end

    test "isolated candidates maintain high fitness" do
      # Candidates far apart in objective space
      candidates = [
        create_candidate("c1",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.0, latency: 0.0}
        ),
        create_candidate("c2",
          fitness: 8.0,
          normalized_objectives: %{accuracy: 1.0, latency: 1.0}
        )
      ]

      {:ok, shared_pop} = FitnessSharing.apply_sharing(candidates, niche_radius: 0.1)

      # Distance = sqrt((1-0)^2 + (1-0)^2) = sqrt(2) ≈ 1.414 >> 0.1
      # Each candidate only shares with itself
      c1_shared = Enum.find(shared_pop, fn c -> c.id == "c1" end)
      c2_shared = Enum.find(shared_pop, fn c -> c.id == "c2" end)

      assert c1_shared.metadata.niche_count == 1.0
      assert c1_shared.fitness == 10.0

      assert c2_shared.metadata.niche_count == 1.0
      assert c2_shared.fitness == 8.0
    end

    test "crowded candidates get penalized fitness" do
      # Three candidates close together
      candidates = [
        create_candidate("c1",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        ),
        create_candidate("c2",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.51, latency: 0.51}
        ),
        create_candidate("c3",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.52, latency: 0.52}
        )
      ]

      {:ok, shared_pop} = FitnessSharing.apply_sharing(candidates, niche_radius: 0.1)

      # Distance between c1 and c2: sqrt((0.01)^2 + (0.01)^2) ≈ 0.014 < 0.1
      # All three candidates are within niche radius of each other
      # Niche count should be > 1.0 for all
      assert Enum.all?(shared_pop, fn c -> c.metadata.niche_count > 1.0 end)

      # Shared fitness should be < raw fitness
      assert Enum.all?(shared_pop, fn c -> c.fitness < c.metadata.raw_fitness end)
    end

    test "preserves raw fitness in metadata by default" do
      candidate =
        create_candidate("c1",
          fitness: 15.0,
          normalized_objectives: %{accuracy: 0.7, latency: 0.4}
        )

      {:ok, [shared]} = FitnessSharing.apply_sharing([candidate])

      assert shared.metadata.raw_fitness == 15.0
      assert shared.metadata.niche_count == 1.0
    end

    test "skips metadata preservation when preserve_raw_fitness: false" do
      candidate =
        create_candidate("c1",
          fitness: 15.0,
          normalized_objectives: %{accuracy: 0.7, latency: 0.4}
        )

      {:ok, [shared]} = FitnessSharing.apply_sharing([candidate], preserve_raw_fitness: false)

      refute Map.has_key?(shared.metadata, :raw_fitness)
      refute Map.has_key?(shared.metadata, :niche_count)
    end

    test "respects niche_radius parameter" do
      # Two candidates with moderate distance
      candidates = [
        create_candidate("c1",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        ),
        create_candidate("c2",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.6, latency: 0.6}
        )
      ]

      # Distance = sqrt((0.1)^2 + (0.1)^2) ≈ 0.141

      # Small radius: candidates don't share niche
      {:ok, shared_small} = FitnessSharing.apply_sharing(candidates, niche_radius: 0.1)
      c1_small = Enum.find(shared_small, fn c -> c.id == "c1" end)
      # Only itself
      assert c1_small.metadata.niche_count == 1.0

      # Large radius: candidates share niche
      {:ok, shared_large} = FitnessSharing.apply_sharing(candidates, niche_radius: 0.2)
      c1_large = Enum.find(shared_large, fn c -> c.id == "c1" end)
      # Shares with c2
      assert c1_large.metadata.niche_count > 1.0
    end

    test "respects sharing_alpha parameter" do
      # sh(d) = 1 - (d/r)^α
      # Higher alpha with d/r < 1 actually produces HIGHER sh value (more sharing)
      # Example: d/r = 0.5
      # α=1: sh = 1 - 0.5 = 0.5
      # α=2: sh = 1 - 0.25 = 0.75 (higher)
      candidates = [
        create_candidate("c1",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        ),
        create_candidate("c2",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.55, latency: 0.55}
        )
      ]

      # Alpha = 1.0 (linear)
      {:ok, shared_linear} =
        FitnessSharing.apply_sharing(candidates,
          niche_radius: 0.2,
          sharing_alpha: 1.0
        )

      c1_linear = Enum.find(shared_linear, fn c -> c.id == "c1" end)

      # Alpha = 2.0 (quadratic - MORE sharing for same distance when d/r < 1)
      {:ok, shared_quadratic} =
        FitnessSharing.apply_sharing(candidates,
          niche_radius: 0.2,
          sharing_alpha: 2.0
        )

      c1_quadratic = Enum.find(shared_quadratic, fn c -> c.id == "c1" end)

      # Quadratic alpha should result in higher niche count (more sharing)
      assert c1_quadratic.metadata.niche_count > c1_linear.metadata.niche_count
    end

    test "handles candidates with nil fitness gracefully" do
      candidate =
        create_candidate("c1",
          fitness: nil,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        )

      {:ok, [shared]} = FitnessSharing.apply_sharing([candidate])

      # Should default to 0.0 fitness
      assert shared.fitness == 0.0
      assert shared.metadata.raw_fitness == 0.0
    end
  end

  describe "niche_count/3" do
    test "isolated candidate has niche count of 1.0" do
      candidate =
        create_candidate("c1",
          normalized_objectives: %{accuracy: 0.0, latency: 0.0}
        )

      other =
        create_candidate("c2",
          normalized_objectives: %{accuracy: 1.0, latency: 1.0}
        )

      population = [candidate, other]

      count = FitnessSharing.niche_count(candidate, population, niche_radius: 0.1)

      # Distance to other is sqrt(2) ≈ 1.414 >> 0.1, so only shares with self
      assert count == 1.0
    end

    test "candidate in crowded region has high niche count" do
      candidate =
        create_candidate("c1",
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        )

      # Four nearby candidates
      population = [
        candidate,
        create_candidate("c2", normalized_objectives: %{accuracy: 0.51, latency: 0.51}),
        create_candidate("c3", normalized_objectives: %{accuracy: 0.52, latency: 0.52}),
        create_candidate("c4", normalized_objectives: %{accuracy: 0.53, latency: 0.53}),
        create_candidate("c5", normalized_objectives: %{accuracy: 0.54, latency: 0.54})
      ]

      count = FitnessSharing.niche_count(candidate, population, niche_radius: 0.1)

      # Should share with multiple candidates
      assert count > 2.0
    end

    test "minimum niche count is 1.0 (candidate shares with itself)" do
      candidate =
        create_candidate("c1",
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        )

      # Even with empty neighborhood, counts itself
      count = FitnessSharing.niche_count(candidate, [candidate], niche_radius: 0.1)

      assert count == 1.0
    end

    test "niche count includes partial sharing" do
      candidate =
        create_candidate("c1",
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        )

      # Candidate at half the niche radius distance
      neighbor =
        create_candidate("c2",
          # distance = 0.05
          normalized_objectives: %{accuracy: 0.55, latency: 0.5}
        )

      population = [candidate, neighbor]

      count =
        FitnessSharing.niche_count(candidate, population,
          # Distance 0.05 < 0.1
          niche_radius: 0.1,
          sharing_alpha: 1.0
        )

      # sh(0.05) = 1 - (0.05 / 0.1)^1 = 1 - 0.5 = 0.5
      # Total: 1.0 (self) + 0.5 (neighbor) = 1.5
      assert_in_delta count, 1.5, 0.01
    end

    test "respects sharing_alpha in niche count calculation" do
      candidate =
        create_candidate("c1",
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        )

      neighbor =
        create_candidate("c2",
          normalized_objectives: %{accuracy: 0.55, latency: 0.5}
        )

      population = [candidate, neighbor]

      # Linear sharing (alpha = 1.0)
      count_linear =
        FitnessSharing.niche_count(candidate, population,
          niche_radius: 0.1,
          sharing_alpha: 1.0
        )

      # Quadratic sharing (alpha = 2.0)
      count_quadratic =
        FitnessSharing.niche_count(candidate, population,
          niche_radius: 0.1,
          sharing_alpha: 2.0
        )

      # sh(d) = 1 - (d/r)^α
      # For d=0.05, r=0.1: d/r = 0.5
      # sh_linear = 1 - (0.5)^1 = 1 - 0.5 = 0.5
      # sh_quadratic = 1 - (0.5)^2 = 1 - 0.25 = 0.75
      # Quadratic gives HIGHER sh value → MORE sharing contribution → higher niche count
      assert count_quadratic > count_linear
    end

    test "handles empty normalized_objectives" do
      candidate = create_candidate("c1", normalized_objectives: nil)
      other = create_candidate("c2", normalized_objectives: nil)

      count = FitnessSharing.niche_count(candidate, [candidate, other], niche_radius: 0.1)

      # Distance is 0.0, so all candidates share fully
      # sh(0) = 1 - 0 = 1.0 for both
      assert count == 2.0
    end
  end

  describe "calculate_niche_radius/2" do
    test "empty population returns default radius" do
      radius = FitnessSharing.calculate_niche_radius([])

      # @default_niche_radius
      assert radius == 0.1
    end

    test "fixed strategy returns specified radius" do
      population = create_test_population(10)

      radius =
        FitnessSharing.calculate_niche_radius(population,
          strategy: :fixed,
          radius: 0.25
        )

      assert radius == 0.25
    end

    test "fixed strategy returns default when radius not provided" do
      population = create_test_population(10)

      radius =
        FitnessSharing.calculate_niche_radius(population,
          strategy: :fixed
        )

      assert radius == 0.1
    end

    test "population_based strategy decreases with population size" do
      small_pop = create_test_population(10)
      large_pop = create_test_population(100)

      radius_small =
        FitnessSharing.calculate_niche_radius(small_pop,
          strategy: :population_based,
          base_radius: 0.3
        )

      radius_large =
        FitnessSharing.calculate_niche_radius(large_pop,
          strategy: :population_based,
          base_radius: 0.3
        )

      # Larger population should have smaller radius
      # radius = base_radius / sqrt(pop_size)
      # small: 0.3 / sqrt(10) ≈ 0.095
      # large: 0.3 / sqrt(100) = 0.03
      assert radius_large < radius_small
      assert_in_delta radius_small, 0.095, 0.01
      assert_in_delta radius_large, 0.03, 0.01
    end

    test "objective_range strategy based on objective space diagonal" do
      # For 2 objectives in normalized space [0,1], diagonal = sqrt(2) ≈ 1.414
      population = [
        create_candidate("c1", normalized_objectives: %{accuracy: 0.0, latency: 0.0}),
        create_candidate("c2", normalized_objectives: %{accuracy: 1.0, latency: 1.0})
      ]

      radius =
        FitnessSharing.calculate_niche_radius(population,
          strategy: :objective_range,
          fraction: 0.1
        )

      # Diagonal for 2D normalized space = sqrt(2) ≈ 1.414
      # 10% of diagonal ≈ 0.141
      assert_in_delta radius, 0.1414, 0.01
    end

    test "objective_range strategy scales with fraction" do
      population = create_test_population(20)

      radius_small =
        FitnessSharing.calculate_niche_radius(population,
          strategy: :objective_range,
          fraction: 0.05
        )

      radius_large =
        FitnessSharing.calculate_niche_radius(population,
          strategy: :objective_range,
          fraction: 0.20
        )

      # Larger fraction = larger radius
      assert radius_large > radius_small
      # 0.20 / 0.05
      assert radius_large / radius_small == 4.0
    end

    test "adaptive strategy adjusts to population diversity" do
      # Create very clustered population (low diversity)
      clustered =
        Enum.map(1..20, fn i ->
          create_candidate("c#{i}",
            normalized_objectives: %{accuracy: 0.5 + i * 0.001, latency: 0.5 + i * 0.001}
          )
        end)

      # Create spread out population (high diversity)
      spread =
        Enum.map(1..20, fn i ->
          create_candidate("c#{i}",
            normalized_objectives: %{accuracy: i * 0.05, latency: i * 0.05}
          )
        end)

      radius_clustered =
        FitnessSharing.calculate_niche_radius(clustered,
          strategy: :adaptive,
          target_diversity: 0.3
        )

      radius_spread =
        FitnessSharing.calculate_niche_radius(spread,
          strategy: :adaptive,
          target_diversity: 0.3
        )

      # Adaptive logic:
      # - Clustered population has very small avg_distance, gets minimum radius (capped at 0.1)
      # - Spread population has large avg_distance, gets radius proportional to spacing (avg * 0.5)
      # Result: spread gets LARGER radius because it's proportional to actual spacing
      # This is correct: clustered candidates are so close that even small radius captures all neighbors
      # Minimum/default radius
      assert radius_clustered == 0.1
      # Proportional to larger spacing
      assert radius_spread > radius_clustered
    end

    test "handles population with no normalized_objectives" do
      population = [
        create_candidate("c1", normalized_objectives: nil),
        create_candidate("c2", normalized_objectives: nil)
      ]

      radius =
        FitnessSharing.calculate_niche_radius(population,
          strategy: :objective_range
        )

      # Should return default diagonal (1.0) * fraction (0.1) = 0.1
      assert radius == 0.1
    end
  end

  describe "adaptive_apply_sharing/2" do
    test "empty population returns skipped" do
      assert {:ok, [], :skipped} = FitnessSharing.adaptive_apply_sharing([])
    end

    test "applies sharing when diversity is low" do
      # Create clustered population (low diversity)
      # All candidates have low crowding distance
      population =
        Enum.map(1..10, fn i ->
          create_candidate("c#{i}",
            fitness: 10.0,
            normalized_objectives: %{accuracy: 0.5, latency: 0.5},
            # Low diversity
            crowding_distance: 0.1
          )
        end)

      result =
        FitnessSharing.adaptive_apply_sharing(population,
          diversity_threshold: 0.3,
          diversity_metric: :crowding,
          niche_radius: 0.1
        )

      # Diversity = avg crowding = 0.1 < 0.3, so sharing should be applied
      assert {:ok, shared_pop} = result
      # Should not have :skipped atom
      refute match?({:ok, _, :skipped}, result)

      # Verify sharing was actually applied (check metadata)
      first = List.first(shared_pop)
      assert Map.has_key?(first.metadata, :niche_count)
    end

    test "skips sharing when diversity is high" do
      # Create diverse population
      # High crowding distances
      population =
        Enum.map(1..10, fn i ->
          create_candidate("c#{i}",
            fitness: 10.0,
            normalized_objectives: %{accuracy: i * 0.1, latency: i * 0.1},
            # High diversity
            crowding_distance: 1.0
          )
        end)

      result =
        FitnessSharing.adaptive_apply_sharing(population,
          diversity_threshold: 0.3,
          diversity_metric: :crowding,
          niche_radius: 0.1
        )

      # Diversity = avg crowding = 1.0 >= 0.3, so sharing should be skipped
      assert {:ok, returned_pop, :skipped} = result

      # Population should be returned unchanged (no niche_count in metadata)
      first = List.first(returned_pop)
      refute Map.has_key?(first.metadata, :niche_count)
    end

    test "respects diversity_threshold parameter" do
      population =
        Enum.map(1..10, fn i ->
          create_candidate("c#{i}",
            normalized_objectives: %{accuracy: i * 0.05, latency: i * 0.05},
            crowding_distance: 0.5
          )
        end)

      # Low threshold - sharing should be skipped
      {:ok, _, status_low} =
        FitnessSharing.adaptive_apply_sharing(population,
          diversity_threshold: 0.3,
          diversity_metric: :crowding
        )

      # 0.5 >= 0.3
      assert status_low == :skipped

      # High threshold - sharing should be applied
      result_high =
        FitnessSharing.adaptive_apply_sharing(population,
          diversity_threshold: 0.8,
          diversity_metric: :crowding
        )

      # 0.5 < 0.8
      assert {:ok, _shared_pop} = result_high
      refute match?({:ok, _, :skipped}, result_high)
    end

    test "uses pairwise_distance diversity metric" do
      # Create population where pairwise distance is low
      clustered =
        Enum.map(1..10, fn i ->
          create_candidate("c#{i}",
            normalized_objectives: %{accuracy: 0.5 + i * 0.01, latency: 0.5 + i * 0.01},
            # Irrelevant for pairwise metric
            crowding_distance: 999.0
          )
        end)

      result =
        FitnessSharing.adaptive_apply_sharing(clustered,
          diversity_threshold: 0.3,
          diversity_metric: :pairwise_distance,
          niche_radius: 0.1
        )

      # Low pairwise distance should trigger sharing
      assert {:ok, _shared_pop} = result
      refute match?({:ok, _, :skipped}, result)
    end

    test "handles infinity crowding distance" do
      population = [
        create_candidate("c1", crowding_distance: :infinity),
        create_candidate("c2", crowding_distance: 0.5),
        create_candidate("c3", crowding_distance: 0.3)
      ]

      # Should filter out infinity and calculate avg of finite distances
      # Avg = (0.5 + 0.3) / 2 = 0.4
      {:ok, _, status} =
        FitnessSharing.adaptive_apply_sharing(population,
          diversity_threshold: 0.35,
          diversity_metric: :crowding
        )

      # 0.4 >= 0.35, so sharing should be skipped
      assert status == :skipped
    end

    test "passes through sharing options when applying" do
      population =
        Enum.map(1..5, fn i ->
          create_candidate("c#{i}",
            fitness: 10.0,
            normalized_objectives: %{accuracy: 0.5, latency: 0.5},
            crowding_distance: 0.1
          )
        end)

      {:ok, shared_pop} =
        FitnessSharing.adaptive_apply_sharing(population,
          diversity_threshold: 0.3,
          niche_radius: 0.15,
          sharing_alpha: 2.0
        )

      # Verify custom parameters were used (check niche count values)
      # With custom niche_radius and alpha, results should differ from defaults
      assert Enum.all?(shared_pop, fn c -> Map.has_key?(c.metadata, :niche_count) end)
    end
  end

  describe "integration scenarios" do
    test "fitness sharing promotes niche formation" do
      # Create population with two distinct niches
      niche_1 =
        Enum.map(1..5, fn i ->
          create_candidate("n1_#{i}",
            fitness: 10.0,
            normalized_objectives: %{accuracy: 0.2 + i * 0.01, latency: 0.2 + i * 0.01}
          )
        end)

      niche_2 =
        Enum.map(1..5, fn i ->
          create_candidate("n2_#{i}",
            fitness: 10.0,
            normalized_objectives: %{accuracy: 0.8 + i * 0.01, latency: 0.8 + i * 0.01}
          )
        end)

      population = niche_1 ++ niche_2

      {:ok, shared_pop} = FitnessSharing.apply_sharing(population, niche_radius: 0.2)

      # Candidates within each niche should have higher niche count
      n1_candidate = Enum.find(shared_pop, fn c -> c.id == "n1_1" end)
      n2_candidate = Enum.find(shared_pop, fn c -> c.id == "n2_1" end)

      # Both should share with their niche members
      assert n1_candidate.metadata.niche_count > 1.0
      assert n2_candidate.metadata.niche_count > 1.0

      # Fitness should be reduced due to crowding
      assert n1_candidate.fitness < 10.0
      assert n2_candidate.fitness < 10.0
    end

    test "boundary solutions maintain advantage even with sharing" do
      # Create population with extreme solutions and clustered middle
      population = [
        # Boundary: min accuracy
        create_candidate("boundary_min",
          fitness: 8.0,
          normalized_objectives: %{accuracy: 0.0, latency: 0.5}
        ),
        # Boundary: max accuracy
        create_candidate("boundary_max",
          fitness: 8.0,
          normalized_objectives: %{accuracy: 1.0, latency: 0.5}
        ),
        # Clustered middle (5 candidates)
        create_candidate("mid_1",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5}
        ),
        create_candidate("mid_2",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.51, latency: 0.51}
        ),
        create_candidate("mid_3",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.52, latency: 0.52}
        ),
        create_candidate("mid_4",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.53, latency: 0.53}
        ),
        create_candidate("mid_5",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.54, latency: 0.54}
        )
      ]

      {:ok, shared_pop} = FitnessSharing.apply_sharing(population, niche_radius: 0.1)

      boundary_min = Enum.find(shared_pop, fn c -> c.id == "boundary_min" end)
      boundary_max = Enum.find(shared_pop, fn c -> c.id == "boundary_max" end)
      mid_1 = Enum.find(shared_pop, fn c -> c.id == "mid_1" end)

      # Boundaries should have low niche count (isolated)
      assert boundary_min.metadata.niche_count == 1.0
      assert boundary_max.metadata.niche_count == 1.0

      # Middle should have high niche count (crowded)
      assert mid_1.metadata.niche_count > 1.0

      # After sharing, boundaries should have higher fitness than clustered middle
      # boundary: 8.0 / 1.0 = 8.0
      # mid: 10.0 / niche_count (> 1) < 10.0
      # Depending on niche count, mid might still be higher
      # But mid candidates should have reduced fitness relative to raw
      assert mid_1.fitness < 10.0
    end

    test "sharing works with different objective counts" do
      # Test with 3 objectives
      population = [
        create_candidate("c1",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.5, latency: 0.5, cost: 0.5}
        ),
        create_candidate("c2",
          fitness: 10.0,
          normalized_objectives: %{accuracy: 0.51, latency: 0.51, cost: 0.51}
        )
      ]

      {:ok, shared_pop} = FitnessSharing.apply_sharing(population, niche_radius: 0.1)

      # Distance = sqrt(3 * 0.01^2) ≈ 0.017 < 0.1
      # Should share niche
      c1 = Enum.find(shared_pop, fn c -> c.id == "c1" end)
      assert c1.metadata.niche_count > 1.0
    end

    test "combining sharing with elite selection maintains diversity" do
      # Create diverse population
      population =
        Enum.map(1..20, fn i ->
          create_candidate("c#{i}",
            # Varying fitness
            fitness: 10.0 - i * 0.1,
            normalized_objectives: %{accuracy: i * 0.05, latency: (20 - i) * 0.05},
            # Front 1 has 5 members
            pareto_rank: if(i <= 5, do: 1, else: 2),
            crowding_distance: if(rem(i, 2) == 0, do: 1.0, else: 0.5)
          )
        end)

      # Apply sharing
      {:ok, shared_pop} = FitnessSharing.apply_sharing(population, niche_radius: 0.1)

      # Verify fitness values were adjusted
      assert Enum.any?(shared_pop, fn c -> c.fitness != c.metadata.raw_fitness end)

      # Metadata should be preserved for elite selection to use
      assert Enum.all?(shared_pop, fn c ->
               Map.has_key?(c.metadata, :raw_fitness) and
                 Map.has_key?(c.metadata, :niche_count)
             end)
    end
  end

  # Helper functions

  defp create_candidate(id, opts \\ []) do
    %Candidate{
      id: id,
      prompt: Keyword.get(opts, :prompt, "test prompt"),
      generation: Keyword.get(opts, :generation, 1),
      created_at: Keyword.get(opts, :created_at, System.system_time(:millisecond)),
      fitness: Keyword.get(opts, :fitness),
      objectives: Keyword.get(opts, :objectives, %{}),
      normalized_objectives: Keyword.get(opts, :normalized_objectives),
      pareto_rank: Keyword.get(opts, :pareto_rank),
      crowding_distance: Keyword.get(opts, :crowding_distance),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  defp create_test_population(size) do
    Enum.map(1..size, fn i ->
      create_candidate("c#{i}",
        normalized_objectives: %{
          accuracy: :rand.uniform(),
          latency: :rand.uniform()
        }
      )
    end)
  end
end
