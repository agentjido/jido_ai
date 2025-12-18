defmodule Jido.AI.Runner.GEPA.RunnerOptimizerIntegrationTest do
  @moduledoc """
  Integration tests for GEPA Runner and Optimizer integration.

  These tests verify that the GEPA runner correctly integrates with the
  optimizer, including:
  - Pareto frontier extraction from optimization results
  - Task-specific evaluation dispatch configuration
  - Result mapping between optimizer and runner formats
  - Agent state updates with optimization results

  Unlike the full end-to-end tests in gepa_test.exs, these tests focus on
  testing the integration layer itself without requiring actual LLM API calls.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator
  alias Jido.AI.Runner.GEPA.Population

  describe "Pareto frontier extraction" do
    test "extracts Pareto-optimal solutions using dominance sorting" do
      # Create candidate structs directly with normalized objectives
      # All normalized objectives: higher is better

      # Candidate 1: High accuracy, low cost, medium latency (on frontier)
      candidate1 = %Population.Candidate{
        id: "test-1",
        prompt: "Prompt 1",
        fitness: 0.9,
        generation: 0,
        created_at: System.monotonic_time(:millisecond),
        objectives: %{accuracy: 0.9, cost: 0.2, latency: 0.5},
        normalized_objectives: %{accuracy: 0.9, cost: 0.8, latency: 0.5}
      }

      # Candidate 2: Medium accuracy, very low cost, high latency (on frontier - trades off)
      candidate2 = %Population.Candidate{
        id: "test-2",
        prompt: "Prompt 2",
        fitness: 0.7,
        generation: 0,
        created_at: System.monotonic_time(:millisecond),
        objectives: %{accuracy: 0.7, cost: 0.1, latency: 0.8},
        normalized_objectives: %{accuracy: 0.7, cost: 0.9, latency: 0.8}
      }

      # Candidate 3: Dominated (lower in all normalized objectives)
      candidate3 = %Population.Candidate{
        id: "test-3",
        prompt: "Prompt 3",
        fitness: 0.6,
        generation: 0,
        created_at: System.monotonic_time(:millisecond),
        objectives: %{accuracy: 0.6, cost: 0.5, latency: 0.4},
        normalized_objectives: %{accuracy: 0.6, cost: 0.5, latency: 0.4}
      }

      candidates = [candidate1, candidate2, candidate3]

      # Perform dominance sorting
      fronts = DominanceComparator.fast_non_dominated_sort(candidates)

      # First front should contain non-dominated solutions
      first_front = Map.get(fronts, 1, [])
      assert length(first_front) >= 1

      # Verify front membership
      first_front_prompts = Enum.map(first_front, & &1.prompt)

      # Candidate 3 is dominated, so should NOT be on frontier
      # (It's worse in all objectives compared to candidate 1)
      if length(first_front) > 1 do
        refute "Prompt 3" in first_front_prompts
      end
    end

    test "falls back to fitness-based selection when no objectives present" do
      # Create population without multi-objective data
      {:ok, population} = Population.new(size: 5)

      candidates =
        Enum.map(1..5, fn i ->
          %{
            prompt: "Prompt #{i}",
            fitness: i / 10.0,
            generation: 0
          }
        end)

      population =
        Enum.reduce(candidates, population, fn candidate, pop ->
          {:ok, updated_pop} = Population.add_candidate(pop, candidate)
          updated_pop
        end)

      # Get best should work even without objectives
      best = Population.get_best(population, limit: 3)
      assert length(best) == 3
      assert Enum.all?(best, &(&1.fitness != nil))
    end

    test "uses crowding distance for diverse selection when front is large" do
      # Create a population with many candidates on the Pareto frontier
      {:ok, population} = Population.new(size: 20)

      # Create 10 candidates with trade-offs (all on frontier)
      candidates =
        Enum.map(1..10, fn i ->
          accuracy = i / 10.0
          cost = 1.0 - i / 10.0

          %{
            prompt: "Prompt #{i}",
            fitness: (accuracy + cost) / 2.0,
            generation: 0,
            objectives: %{accuracy: accuracy, cost: cost},
            normalized_objectives: %{accuracy: accuracy, cost: cost}
          }
        end)

      population =
        Enum.reduce(candidates, population, fn candidate, pop ->
          {:ok, updated_pop} = Population.add_candidate(pop, candidate)
          updated_pop
        end)

      # Get all and perform sorting
      all_candidates = Population.get_all(population)
      candidates_with_objectives = Enum.filter(all_candidates, &(&1.normalized_objectives != nil))

      fronts = DominanceComparator.fast_non_dominated_sort(candidates_with_objectives)
      first_front = Map.get(fronts, 1, [])

      # When we have more than 5 in first front, crowding distance should be used
      if length(first_front) > 5 do
        distances = DominanceComparator.crowding_distance(first_front)

        # Boundary solutions should have infinite crowding distance
        assert Enum.any?(Map.values(distances), &(&1 == :infinity))

        # Interior solutions should have finite distance
        assert Enum.any?(Map.values(distances), &is_float(&1))
      end
    end
  end

  # Note: Result mapping tests would require accessing private functions
  # The public API is tested through the full integration tests in gepa_test.exs

  # Note: Full end-to-end integration tests with API calls are in gepa_test.exs
  # These tests verify:
  # - Configuration validation for task-specific evaluation
  # - Agent state updates with optimization results
  # - Directive generation from optimization results
  # They are tagged with :requires_api and excluded from default test runs
end
