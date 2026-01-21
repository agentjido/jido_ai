defmodule Jido.AI.Runner.GEPA.Selection.TournamentSelectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Selection.TournamentSelector

  describe "select/2 - basic validation" do
    test "returns error for empty population" do
      assert {:error, :empty_population} = TournamentSelector.select([], count: 5)
    end

    test "returns error for invalid population format" do
      assert {:error, :invalid_population_format} =
               TournamentSelector.select("not a list", count: 5)
    end

    test "returns error for missing count option" do
      population = create_population(10)

      assert {:error, {:missing_required_option, :count}} =
               TournamentSelector.select(population, [])
    end

    test "returns error for invalid count" do
      population = create_population(10)
      assert {:error, {:invalid_count, 0}} = TournamentSelector.select(population, count: 0)
      assert {:error, {:invalid_count, -5}} = TournamentSelector.select(population, count: -5)
    end

    test "returns error for candidates missing pareto_rank" do
      population = [
        create_candidate("c1", crowding_distance: 0.5, pareto_rank: nil)
      ]

      assert {:error, :candidates_missing_ranking} =
               TournamentSelector.select(population, count: 1)
    end

    test "returns error for candidates missing crowding_distance" do
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: nil)
      ]

      assert {:error, :candidates_missing_ranking} =
               TournamentSelector.select(population, count: 1)
    end

    test "returns error for tournament size less than 2" do
      population = create_population(10)

      assert {:error, {:invalid_tournament_size, 1, 10}} =
               TournamentSelector.select(population, count: 5, tournament_size: 1)
    end

    test "returns error for tournament size greater than population" do
      population = create_population(10)

      assert {:error, {:invalid_tournament_size, 15, 10}} =
               TournamentSelector.select(population, count: 5, tournament_size: 15)
    end

    test "returns error for invalid strategy" do
      population = create_population(10)

      assert {:error, {:invalid_strategy, :invalid}} =
               TournamentSelector.select(population, count: 5, strategy: :invalid)
    end
  end

  describe "select/2 - Pareto tournament" do
    test "selects requested number of parents" do
      population = create_population(20)

      assert {:ok, parents} = TournamentSelector.select(population, count: 10)
      assert length(parents) == 10
      assert Enum.all?(parents, &is_struct(&1, Candidate))
    end

    test "allows selecting more parents than population size (with replacement)" do
      population = create_population(5)

      assert {:ok, parents} = TournamentSelector.select(population, count: 10)
      assert length(parents) == 10
    end

    test "favors candidates with better Pareto rank over time" do
      # Create population with distinct ranks
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.6),
        create_candidate("c3", pareto_rank: 2, crowding_distance: 0.5),
        create_candidate("c4", pareto_rank: 2, crowding_distance: 0.6),
        create_candidate("c5", pareto_rank: 3, crowding_distance: 0.5),
        create_candidate("c6", pareto_rank: 3, crowding_distance: 0.6)
      ]

      # Run many selections to get statistical distribution
      {:ok, parents} = TournamentSelector.select(population, count: 100, tournament_size: 3)

      # Count selections by rank
      rank_counts =
        parents
        |> Enum.group_by(& &1.pareto_rank)
        |> Map.new(fn {rank, candidates} -> {rank, length(candidates)} end)

      rank1_count = Map.get(rank_counts, 1, 0)
      rank2_count = Map.get(rank_counts, 2, 0)
      rank3_count = Map.get(rank_counts, 3, 0)

      # Rank 1 should be selected most often
      assert rank1_count > rank2_count
      assert rank2_count > rank3_count
    end

    test "uses crowding distance as tiebreaker for same rank" do
      # All same rank, different crowding distances
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: 0.1),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.9)
      ]

      # Run many selections
      {:ok, parents} = TournamentSelector.select(population, count: 100, tournament_size: 2)

      # Count selections
      selection_counts =
        parents
        |> Enum.group_by(& &1.id)
        |> Map.new(fn {id, candidates} -> {id, length(candidates)} end)

      c1_count = Map.get(selection_counts, "c1", 0)
      c2_count = Map.get(selection_counts, "c2", 0)
      c3_count = Map.get(selection_counts, "c3", 0)

      # Higher crowding distance should be selected more often
      assert c3_count > c2_count
      assert c2_count > c1_count
    end

    test "larger tournament size increases selection pressure" do
      # Population with rank distribution
      population = create_ranked_population(50)

      # Small tournament (less pressure)
      {:ok, parents_small} = TournamentSelector.select(population, count: 100, tournament_size: 2)

      # Large tournament (more pressure)
      {:ok, parents_large} = TournamentSelector.select(population, count: 100, tournament_size: 7)

      # Calculate average rank for each
      avg_rank_small = Enum.sum(Enum.map(parents_small, & &1.pareto_rank)) / length(parents_small)
      avg_rank_large = Enum.sum(Enum.map(parents_large, & &1.pareto_rank)) / length(parents_large)

      # Larger tournament should select better (lower) average rank
      assert avg_rank_large < avg_rank_small
    end

    test "handles boundary solutions with infinite crowding distance" do
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: :infinity),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.3)
      ]

      # Boundary solution should win most tournaments
      {:ok, parents} = TournamentSelector.select(population, count: 50, tournament_size: 2)

      boundary_count = Enum.count(parents, fn p -> p.id == "c1" end)
      # Should win majority
      assert boundary_count > 25
    end

    test "works with default tournament size of 3" do
      population = create_population(20)

      assert {:ok, parents} = TournamentSelector.select(population, count: 10)
      assert length(parents) == 10
    end
  end

  describe "select/2 - diversity tournament" do
    test "selects requested number of parents" do
      population = create_population(20)

      assert {:ok, parents} =
               TournamentSelector.select(
                 population,
                 count: 10,
                 strategy: :diversity
               )

      assert length(parents) == 10
    end

    test "prioritizes crowding distance over rank" do
      population = [
        # Worse rank but better distance
        create_candidate("c1", pareto_rank: 2, crowding_distance: 0.9),
        # Better rank but worse distance
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.1),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.2)
      ]

      # Run many selections
      {:ok, parents} =
        TournamentSelector.select(
          population,
          count: 100,
          tournament_size: 2,
          strategy: :diversity
        )

      # Count selections
      selection_counts =
        parents
        |> Enum.group_by(& &1.id)
        |> Map.new(fn {id, candidates} -> {id, length(candidates)} end)

      c1_count = Map.get(selection_counts, "c1", 0)
      c2_count = Map.get(selection_counts, "c2", 0)

      # c1 has worse rank but better distance, should be selected more in diversity mode
      assert c1_count > c2_count
    end

    @tag :flaky
    test "favors boundary solutions with infinite distance" do
      population = [
        create_candidate("boundary", pareto_rank: 1, crowding_distance: :infinity),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.8),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.5)
      ]

      {:ok, parents} =
        TournamentSelector.select(
          population,
          count: 50,
          tournament_size: 2,
          strategy: :diversity
        )

      boundary_count = Enum.count(parents, fn p -> p.id == "boundary" end)
      # Should strongly favor boundary (probabilistic, so allow >= 30)
      assert boundary_count >= 30
    end

    test "uses rank as tiebreaker when distances equal" do
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c2", pareto_rank: 2, crowding_distance: 0.5),
        create_candidate("c3", pareto_rank: 3, crowding_distance: 0.5)
      ]

      {:ok, parents} =
        TournamentSelector.select(
          population,
          count: 100,
          tournament_size: 2,
          strategy: :diversity
        )

      rank_counts =
        parents
        |> Enum.group_by(& &1.pareto_rank)
        |> Map.new(fn {rank, candidates} -> {rank, length(candidates)} end)

      rank1_count = Map.get(rank_counts, 1, 0)
      rank2_count = Map.get(rank_counts, 2, 0)

      # Same distance, so better rank should win
      assert rank1_count > rank2_count
    end
  end

  describe "select/2 - adaptive tournament" do
    test "returns error for invalid min_tournament_size" do
      population = create_population(10)

      assert {:error, {:invalid_min_tournament_size, 1}} =
               TournamentSelector.select(
                 population,
                 count: 5,
                 strategy: :adaptive,
                 min_tournament_size: 1,
                 max_tournament_size: 5
               )
    end

    test "returns error for max_tournament_size greater than population" do
      population = create_population(10)

      assert {:error, {:invalid_max_tournament_size, 15, 10}} =
               TournamentSelector.select(
                 population,
                 count: 5,
                 strategy: :adaptive,
                 min_tournament_size: 2,
                 max_tournament_size: 15
               )
    end

    test "returns error when min > max" do
      population = create_population(10)

      assert {:error, {:min_greater_than_max, 7, 3}} =
               TournamentSelector.select(
                 population,
                 count: 5,
                 strategy: :adaptive,
                 min_tournament_size: 7,
                 max_tournament_size: 3
               )
    end

    test "uses minimum size for low diversity populations" do
      # Create low diversity population (all similar crowding distances)
      population =
        Enum.map(1..20, fn i ->
          create_candidate("c#{i}", pareto_rank: 1, crowding_distance: 0.5)
        end)

      assert {:ok, parents} =
               TournamentSelector.select(
                 population,
                 count: 10,
                 strategy: :adaptive,
                 min_tournament_size: 2,
                 max_tournament_size: 7,
                 diversity_threshold: 0.5
               )

      assert length(parents) == 10
      # Can't directly test tournament size, but should complete successfully
    end

    test "uses larger size for high diversity populations" do
      # Create high diversity population (varied crowding distances)
      population =
        Enum.map(1..20, fn i ->
          create_candidate("c#{i}", pareto_rank: 1, crowding_distance: i * 0.05)
        end)

      assert {:ok, parents} =
               TournamentSelector.select(
                 population,
                 count: 10,
                 strategy: :adaptive,
                 min_tournament_size: 2,
                 max_tournament_size: 7,
                 diversity_threshold: 0.3
               )

      assert length(parents) == 10
    end

    test "uses default values for adaptive parameters" do
      population = create_population(20)

      assert {:ok, parents} =
               TournamentSelector.select(
                 population,
                 count: 10,
                 strategy: :adaptive
               )

      assert length(parents) == 10
    end

    test "adapts tournament size based on diversity" do
      # Test that different diversity levels work
      low_div_pop = create_low_diversity_population(30)
      high_div_pop = create_high_diversity_population(30)

      assert {:ok, _} = TournamentSelector.select(low_div_pop, count: 10, strategy: :adaptive)
      assert {:ok, _} = TournamentSelector.select(high_div_pop, count: 10, strategy: :adaptive)
    end
  end

  describe "run_tournament/3" do
    test "returns single winner from tournament" do
      population = create_population(10)

      winner =
        TournamentSelector.run_tournament(
          population,
          3,
          &TournamentSelector.pareto_compare/2
        )

      assert is_struct(winner, Candidate)
      assert winner in population
    end

    test "winner is best according to comparator" do
      population = [
        create_candidate("c1", pareto_rank: 3, crowding_distance: 0.5),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c3", pareto_rank: 2, crowding_distance: 0.5)
      ]

      # Run tournament multiple times
      winners =
        Enum.map(1..20, fn _ ->
          TournamentSelector.run_tournament(
            population,
            3,
            &TournamentSelector.pareto_compare/2
          )
        end)

      # With tournament size 3 covering all candidates, rank 1 should always win
      assert Enum.all?(winners, fn w -> w.pareto_rank == 1 end)
    end

    test "uses custom comparator function" do
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: 0.1),
        create_candidate("c2", pareto_rank: 2, crowding_distance: 0.9)
      ]

      # Custom comparator: prefers higher crowding distance
      comparator = fn a, b -> a.crowding_distance > b.crowding_distance end

      winner = TournamentSelector.run_tournament(population, 2, comparator)

      # Should select c2 due to higher crowding distance
      assert winner.id == "c2"
    end
  end

  describe "pareto_compare/2" do
    test "prefers lower rank" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5)
      c2 = create_candidate("c2", pareto_rank: 2, crowding_distance: 0.5)

      assert TournamentSelector.pareto_compare(c1, c2) == true
      assert TournamentSelector.pareto_compare(c2, c1) == false
    end

    test "uses crowding distance for tiebreaking when ranks equal" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: 0.7)
      c2 = create_candidate("c2", pareto_rank: 1, crowding_distance: 0.3)

      assert TournamentSelector.pareto_compare(c1, c2) == true
      assert TournamentSelector.pareto_compare(c2, c1) == false
    end

    test "handles infinity crowding distance for boundary solutions" do
      boundary = create_candidate("boundary", pareto_rank: 1, crowding_distance: :infinity)
      regular = create_candidate("regular", pareto_rank: 1, crowding_distance: 0.9)

      assert TournamentSelector.pareto_compare(boundary, regular) == true
      assert TournamentSelector.pareto_compare(regular, boundary) == false
    end

    test "handles nil rank as infinity" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5)
      c2 = create_candidate("c2", pareto_rank: nil, crowding_distance: 0.5)

      # Candidate with actual rank beats nil rank
      assert TournamentSelector.pareto_compare(c1, c2) == true
      assert TournamentSelector.pareto_compare(c2, c1) == false
    end

    test "handles nil crowding distance as 0" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5)
      c2 = create_candidate("c2", pareto_rank: 1, crowding_distance: nil)

      assert TournamentSelector.pareto_compare(c1, c2) == true
      assert TournamentSelector.pareto_compare(c2, c1) == false
    end

    test "handles both infinity distances" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: :infinity)
      c2 = create_candidate("c2", pareto_rank: 2, crowding_distance: :infinity)

      # Should fall back to rank comparison
      assert TournamentSelector.pareto_compare(c1, c2) == true
      assert TournamentSelector.pareto_compare(c2, c1) == false
    end
  end

  describe "diversity_compare/2" do
    test "prefers higher crowding distance" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: 0.8)
      c2 = create_candidate("c2", pareto_rank: 1, crowding_distance: 0.3)

      assert TournamentSelector.diversity_compare(c1, c2) == true
      assert TournamentSelector.diversity_compare(c2, c1) == false
    end

    test "uses rank as tiebreaker when distances equal" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5)
      c2 = create_candidate("c2", pareto_rank: 2, crowding_distance: 0.5)

      assert TournamentSelector.diversity_compare(c1, c2) == true
      assert TournamentSelector.diversity_compare(c2, c1) == false
    end

    test "infinity distance beats finite distance" do
      boundary = create_candidate("boundary", pareto_rank: 2, crowding_distance: :infinity)
      regular = create_candidate("regular", pareto_rank: 1, crowding_distance: 0.9)

      # Boundary wins even with worse rank
      assert TournamentSelector.diversity_compare(boundary, regular) == true
      assert TournamentSelector.diversity_compare(regular, boundary) == false
    end

    test "handles both infinity distances using rank" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: :infinity)
      c2 = create_candidate("c2", pareto_rank: 2, crowding_distance: :infinity)

      assert TournamentSelector.diversity_compare(c1, c2) == true
      assert TournamentSelector.diversity_compare(c2, c1) == false
    end

    test "handles nil distance as 0" do
      c1 = create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5)
      c2 = create_candidate("c2", pareto_rank: 1, crowding_distance: nil)

      assert TournamentSelector.diversity_compare(c1, c2) == true
      assert TournamentSelector.diversity_compare(c2, c1) == false
    end
  end

  describe "population_diversity/1" do
    test "returns 0.0 for empty population" do
      assert TournamentSelector.population_diversity([]) == 0.0
    end

    test "returns 0.0 for single candidate" do
      population = [create_candidate("c1", pareto_rank: 1, crowding_distance: 0.5)]
      assert TournamentSelector.population_diversity(population) == 0.0
    end

    test "returns 0.0 for uniform distances" do
      population =
        Enum.map(1..10, fn i ->
          create_candidate("c#{i}", pareto_rank: 1, crowding_distance: 0.5)
        end)

      diversity = TournamentSelector.population_diversity(population)
      assert diversity == 0.0
    end

    test "returns higher value for varied distances" do
      # Create population with varied crowding distances
      population =
        Enum.map(1..10, fn i ->
          create_candidate("c#{i}", pareto_rank: 1, crowding_distance: i * 0.1)
        end)

      diversity = TournamentSelector.population_diversity(population)
      assert diversity > 0.0
      assert diversity <= 1.0
    end

    test "returns higher value for more variance" do
      low_var_pop = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: 0.45),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.50),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.55)
      ]

      high_var_pop = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: 0.1),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.9)
      ]

      low_diversity = TournamentSelector.population_diversity(low_var_pop)
      high_diversity = TournamentSelector.population_diversity(high_var_pop)

      assert high_diversity > low_diversity
    end

    test "filters out infinity distances" do
      population = [
        create_candidate("boundary", pareto_rank: 1, crowding_distance: :infinity),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.6)
      ]

      # Should calculate diversity using only finite distances
      diversity = TournamentSelector.population_diversity(population)
      assert is_float(diversity)
      assert diversity >= 0.0
      assert diversity <= 1.0
    end

    test "handles nil crowding distances" do
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: nil),
        create_candidate("c2", pareto_rank: 1, crowding_distance: 0.5),
        create_candidate("c3", pareto_rank: 1, crowding_distance: 0.6)
      ]

      # Should treat nil as 0.0 and calculate diversity
      diversity = TournamentSelector.population_diversity(population)
      assert is_float(diversity)
      assert diversity >= 0.0
    end

    test "returns 0.0 when all distances are infinity" do
      population = [
        create_candidate("c1", pareto_rank: 1, crowding_distance: :infinity),
        create_candidate("c2", pareto_rank: 1, crowding_distance: :infinity)
      ]

      assert TournamentSelector.population_diversity(population) == 0.0
    end

    test "diversity value is in range [0, 1]" do
      # Test various population patterns
      populations = [
        create_population(10),
        create_low_diversity_population(10),
        create_high_diversity_population(10),
        create_ranked_population(10)
      ]

      for population <- populations do
        diversity = TournamentSelector.population_diversity(population)
        assert diversity >= 0.0
        assert diversity <= 1.0
      end
    end
  end

  # Test helpers

  defp create_candidate(id, opts \\ []) do
    %Candidate{
      id: id,
      prompt: Keyword.get(opts, :prompt, "test prompt"),
      generation: Keyword.get(opts, :generation, 1),
      created_at: Keyword.get(opts, :created_at, System.system_time(:millisecond)),
      pareto_rank: Keyword.get(opts, :pareto_rank, 1),
      crowding_distance: Keyword.get(opts, :crowding_distance, 0.5),
      fitness: Keyword.get(opts, :fitness, 0.8),
      objectives: Keyword.get(opts, :objectives, %{accuracy: 0.8, latency: 100}),
      normalized_objectives:
        Keyword.get(opts, :normalized_objectives, %{accuracy: 0.8, latency: 0.6})
    }
  end

  defp create_population(size) do
    Enum.map(1..size, fn i ->
      create_candidate("candidate_#{i}",
        pareto_rank: rem(i, 3) + 1,
        crowding_distance: :rand.uniform()
      )
    end)
  end

  defp create_ranked_population(size) do
    # Create population with gradual rank distribution
    Enum.map(1..size, fn i ->
      rank = div(i - 1, div(size, 5)) + 1

      create_candidate("candidate_#{i}",
        pareto_rank: rank,
        crowding_distance: :rand.uniform()
      )
    end)
  end

  defp create_low_diversity_population(size) do
    # All candidates have similar crowding distance
    Enum.map(1..size, fn i ->
      create_candidate("candidate_#{i}",
        pareto_rank: rem(i, 3) + 1,
        crowding_distance: 0.5
      )
    end)
  end

  defp create_high_diversity_population(size) do
    # Candidates have widely varied crowding distances
    Enum.map(1..size, fn i ->
      create_candidate("candidate_#{i}",
        pareto_rank: rem(i, 3) + 1,
        crowding_distance: i / size
      )
    end)
  end
end
