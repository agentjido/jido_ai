defmodule Jido.AI.Runner.GEPA.Pareto.FrontierManagerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Pareto.{Frontier, FrontierManager}
  alias Jido.AI.Runner.GEPA.Population.Candidate

  # Test helper to create candidate with normalized objectives
  defp make_candidate(id, objectives) do
    %Candidate{
      id: id,
      prompt: "test prompt #{id}",
      generation: 1,
      created_at: System.monotonic_time(:millisecond),
      normalized_objectives: objectives,
      fitness: Enum.sum(Map.values(objectives)) / map_size(objectives)
    }
  end

  # Standard test configuration
  defp standard_config do
    [
      objectives: [:accuracy, :latency],
      objective_directions: %{accuracy: :maximize, latency: :minimize},
      reference_point: %{accuracy: 0.0, latency: 10.0}
    ]
  end

  describe "new/1" do
    test "creates frontier with valid configuration" do
      assert {:ok, %Frontier{} = frontier} = FrontierManager.new(standard_config())

      assert frontier.objectives == [:accuracy, :latency]
      assert frontier.objective_directions == %{accuracy: :maximize, latency: :minimize}
      assert frontier.reference_point == %{accuracy: 0.0, latency: 10.0}
      assert frontier.solutions == []
      assert frontier.archive == []
      assert frontier.hypervolume == 0.0
      assert frontier.generation == 0
    end

    test "creates frontier with four objectives" do
      config = [
        objectives: [:accuracy, :latency, :cost, :robustness],
        objective_directions: %{
          accuracy: :maximize,
          latency: :minimize,
          cost: :minimize,
          robustness: :maximize
        },
        reference_point: %{accuracy: 0.0, latency: 10.0, cost: 0.1, robustness: 0.0}
      ]

      assert {:ok, %Frontier{} = frontier} = FrontierManager.new(config)
      assert length(frontier.objectives) == 4
    end

    test "returns error when objectives missing" do
      config = Keyword.delete(standard_config(), :objectives)
      assert {:error, {:missing_required_option, :objectives}} = FrontierManager.new(config)
    end

    test "returns error when objective_directions missing" do
      config = Keyword.delete(standard_config(), :objective_directions)

      assert {:error, {:missing_required_option, :objective_directions}} =
               FrontierManager.new(config)
    end

    test "returns error when reference_point missing" do
      config = Keyword.delete(standard_config(), :reference_point)
      assert {:error, {:missing_required_option, :reference_point}} = FrontierManager.new(config)
    end

    test "returns error when objective lacks direction" do
      config =
        standard_config()
        |> Keyword.put(:objectives, [:accuracy, :latency, :cost])

      assert {:error, :missing_objective_direction} = FrontierManager.new(config)
    end

    test "returns error when objective lacks reference value" do
      config =
        standard_config()
        |> Keyword.put(:reference_point, %{accuracy: 0.0})

      assert {:error, :missing_reference_value} = FrontierManager.new(config)
    end

    test "returns error for invalid objective direction" do
      config =
        standard_config()
        |> Keyword.put(:objective_directions, %{accuracy: :invalid, latency: :minimize})

      assert {:error, {:invalid_objective_directions, _}} = FrontierManager.new(config)
    end

    test "returns error for non-numeric reference value" do
      config =
        standard_config()
        |> Keyword.put(:reference_point, %{accuracy: "not a number", latency: 10.0})

      assert {:error, {:non_numeric_reference_values, _}} = FrontierManager.new(config)
    end

    test "sets timestamps on creation" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      assert is_integer(frontier.created_at)
      assert is_integer(frontier.updated_at)
      assert frontier.created_at == frontier.updated_at
    end
  end

  describe "add_solution/3" do
    test "adds first solution to empty frontier" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})

      {:ok, updated} = FrontierManager.add_solution(frontier, candidate)

      assert length(updated.solutions) == 1
      assert hd(updated.solutions).id == "a"
    end

    test "adds multiple non-dominated solutions" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Trade-off: A better accuracy, B better latency
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      {:ok, frontier} = FrontierManager.add_solution(frontier, a)
      {:ok, frontier} = FrontierManager.add_solution(frontier, b)

      assert length(frontier.solutions) == 2
      ids = Enum.map(frontier.solutions, & &1.id) |> Enum.sort()
      assert ids == ["a", "b"]
    end

    test "rejects dominated solution" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # A dominates C (better in both objectives)
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.8})
      c = make_candidate("c", %{accuracy: 0.7, latency: 0.6})

      {:ok, frontier} = FrontierManager.add_solution(frontier, a)
      {:ok, frontier} = FrontierManager.add_solution(frontier, c)

      # C should not be added
      assert length(frontier.solutions) == 1
      assert hd(frontier.solutions).id == "a"
    end

    test "removes dominated solutions when adding dominating solution" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # B and C are non-dominated with each other
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})
      c = make_candidate("c", %{accuracy: 0.8, latency: 0.6})

      {:ok, frontier} = FrontierManager.add_solution(frontier, b)
      {:ok, frontier} = FrontierManager.add_solution(frontier, c)
      assert length(frontier.solutions) == 2

      # A dominates both B and C
      a = make_candidate("a", %{accuracy: 0.9, latency: 0.9})
      {:ok, frontier} = FrontierManager.add_solution(frontier, a)

      # Only A should remain
      assert length(frontier.solutions) == 1
      assert hd(frontier.solutions).id == "a"
    end

    test "returns error when candidate lacks normalized_objectives" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      candidate = %Candidate{
        id: "x",
        prompt: "test",
        generation: 1,
        created_at: System.monotonic_time(:millisecond),
        normalized_objectives: nil
      }

      assert {:error, :candidate_missing_normalized_objectives} =
               FrontierManager.add_solution(frontier, candidate)
    end

    test "triggers trimming when frontier exceeds max_size" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Create 10 non-dominated solutions in a trade-off pattern
      candidates =
        for i <- 1..10 do
          make_candidate("c#{i}", %{
            accuracy: 0.5 + i * 0.04,
            latency: 0.95 - i * 0.04
          })
        end

      # Add all candidates
      frontier =
        Enum.reduce(candidates, frontier, fn candidate, f ->
          {:ok, updated} = FrontierManager.add_solution(f, candidate)
          updated
        end)

      assert length(frontier.solutions) == 10

      # Add one more that maintains trade-off (doesn't dominate all others)
      # This one is better in accuracy but worse in latency than c10
      extra = make_candidate("extra", %{accuracy: 0.92, latency: 0.45})
      {:ok, frontier} = FrontierManager.add_solution(frontier, extra, max_size: 5)

      # Should be trimmed to 5
      assert length(frontier.solutions) == 5
    end

    test "updates timestamp when adding solution" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      initial_timestamp = frontier.updated_at

      # Ensure time passes
      Process.sleep(2)

      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})
      {:ok, updated} = FrontierManager.add_solution(frontier, candidate)

      assert updated.updated_at > initial_timestamp
    end
  end

  describe "remove_solution/2" do
    test "removes existing solution" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      {:ok, frontier} = FrontierManager.add_solution(frontier, a)
      {:ok, frontier} = FrontierManager.add_solution(frontier, b)
      assert length(frontier.solutions) == 2

      {:ok, frontier} = FrontierManager.remove_solution(frontier, "a")

      assert length(frontier.solutions) == 1
      assert hd(frontier.solutions).id == "b"
    end

    test "returns error when solution not found" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      assert {:error, :not_found} = FrontierManager.remove_solution(frontier, "nonexistent")
    end

    test "updates timestamp when removing solution" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})
      {:ok, frontier} = FrontierManager.add_solution(frontier, candidate)

      initial_timestamp = frontier.updated_at
      Process.sleep(2)

      {:ok, updated} = FrontierManager.remove_solution(frontier, "a")
      assert updated.updated_at > initial_timestamp
    end
  end

  describe "trim/2" do
    test "does not trim when under max_size" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      candidates = [
        make_candidate("a", %{accuracy: 0.9, latency: 0.5}),
        make_candidate("b", %{accuracy: 0.7, latency: 0.8})
      ]

      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.add_solution(f, c)
          updated
        end)

      {:ok, trimmed} = FrontierManager.trim(frontier, max_size: 10)
      assert length(trimmed.solutions) == 2
    end

    test "trims to max_size preserving diversity" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Create 20 non-dominated solutions
      candidates =
        for i <- 1..20 do
          make_candidate("c#{i}", %{
            accuracy: 0.5 + i * 0.02,
            latency: 0.95 - i * 0.02
          })
        end

      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.add_solution(f, c)
          updated
        end)

      assert length(frontier.solutions) == 20

      {:ok, trimmed} = FrontierManager.trim(frontier, max_size: 10)
      assert length(trimmed.solutions) == 10
    end

    test "preserves boundary solutions with infinite crowding distance" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Create solutions where first and last are boundaries
      candidates = [
        # Best accuracy
        make_candidate("boundary_1", %{accuracy: 1.0, latency: 0.1}),
        make_candidate("middle_1", %{accuracy: 0.7, latency: 0.5}),
        make_candidate("middle_2", %{accuracy: 0.6, latency: 0.6}),
        make_candidate("middle_3", %{accuracy: 0.5, latency: 0.7}),
        # Best latency
        make_candidate("boundary_2", %{accuracy: 0.3, latency: 0.9})
      ]

      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.add_solution(f, c)
          updated
        end)

      {:ok, trimmed} = FrontierManager.trim(frontier, max_size: 3)

      # Boundary solutions should be preserved
      ids = Enum.map(trimmed.solutions, & &1.id)
      assert "boundary_1" in ids
      assert "boundary_2" in ids
    end

    test "uses default max_size when not specified" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Create more than default (100) solutions
      candidates =
        for i <- 1..105 do
          make_candidate("c#{i}", %{
            accuracy: 0.5 + i * 0.004,
            latency: 0.95 - i * 0.004
          })
        end

      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.add_solution(f, c)
          updated
        end)

      {:ok, trimmed} = FrontierManager.trim(frontier)
      assert length(trimmed.solutions) == 100
    end
  end

  describe "archive_solution/3" do
    test "archives a solution" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})

      {:ok, frontier} = FrontierManager.archive_solution(frontier, candidate)

      assert length(frontier.archive) == 1
      assert hd(frontier.archive).id == "a"
    end

    test "does not archive duplicate solutions" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})

      {:ok, frontier} = FrontierManager.archive_solution(frontier, candidate)
      {:ok, frontier} = FrontierManager.archive_solution(frontier, candidate)

      assert length(frontier.archive) == 1
    end

    test "archives multiple different solutions" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      a = make_candidate("a", %{accuracy: 0.9, latency: 0.5})
      b = make_candidate("b", %{accuracy: 0.7, latency: 0.8})

      {:ok, frontier} = FrontierManager.archive_solution(frontier, a)
      {:ok, frontier} = FrontierManager.archive_solution(frontier, b)

      assert length(frontier.archive) == 2
    end

    test "trims archive when exceeding max_archive_size" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Create 15 candidates with varying fitness
      candidates =
        for i <- 1..15 do
          make_candidate("c#{i}", %{accuracy: i * 0.06, latency: 0.5})
        end

      # Archive all with max_archive_size=10
      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.archive_solution(f, c, max_archive_size: 10)
          updated
        end)

      # Should be trimmed to 10, keeping highest fitness
      assert length(frontier.archive) == 10

      # Check that higher fitness candidates were kept
      fitnesses = Enum.map(frontier.archive, & &1.fitness)
      assert Enum.all?(fitnesses, fn f -> f >= 0.3 end)
    end

    test "uses default max_archive_size when not specified" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Archive a solution without specifying max
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})
      {:ok, frontier} = FrontierManager.archive_solution(frontier, candidate)

      assert length(frontier.archive) == 1
    end
  end

  describe "get_pareto_optimal/1" do
    test "returns all solutions from frontier" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      candidates = [
        make_candidate("a", %{accuracy: 0.9, latency: 0.5}),
        make_candidate("b", %{accuracy: 0.7, latency: 0.8})
      ]

      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.add_solution(f, c)
          updated
        end)

      pareto_optimal = FrontierManager.get_pareto_optimal(frontier)

      assert length(pareto_optimal) == 2
      ids = Enum.map(pareto_optimal, & &1.id) |> Enum.sort()
      assert ids == ["a", "b"]
    end

    test "returns empty list for empty frontier" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      assert FrontierManager.get_pareto_optimal(frontier) == []
    end
  end

  describe "get_front/2" do
    test "returns candidates from specified front" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      candidates = [
        make_candidate("a", %{accuracy: 0.9, latency: 0.5}),
        make_candidate("b", %{accuracy: 0.7, latency: 0.8})
      ]

      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.add_solution(f, c)
          updated
        end)

      # Manually set fronts for testing
      frontier = %{frontier | fronts: %{1 => ["a"], 2 => ["b"]}}

      front_1 = FrontierManager.get_front(frontier, 1)
      assert length(front_1) == 1
      assert hd(front_1).id == "a"
    end

    test "returns empty list for non-existent front" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      assert FrontierManager.get_front(frontier, 99) == []
    end
  end

  describe "update_fronts/1" do
    test "updates fronts with non-dominated sorting" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Create solutions where some dominate others
      candidates = [
        # Best (Front 1)
        make_candidate("a", %{accuracy: 0.9, latency: 0.9}),
        # Best (Front 1, trade-off)
        make_candidate("b", %{accuracy: 0.95, latency: 0.5}),
        # Dominated (Front 2)
        make_candidate("c", %{accuracy: 0.7, latency: 0.7})
      ]

      # Add candidates manually to test update_fronts
      frontier = %{frontier | solutions: candidates}

      {:ok, updated} = FrontierManager.update_fronts(frontier)

      assert is_map(updated.fronts)
      assert Map.has_key?(updated.fronts, 1)

      # Front 1 should have candidates a and b
      front_1_ids = Map.get(updated.fronts, 1, [])
      assert length(front_1_ids) == 2
      assert "a" in front_1_ids
      assert "b" in front_1_ids
    end

    test "handles empty frontier" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      {:ok, updated} = FrontierManager.update_fronts(frontier)

      assert updated.fronts == %{}
    end

    test "updates timestamp" do
      {:ok, frontier} = FrontierManager.new(standard_config())
      candidate = make_candidate("a", %{accuracy: 0.8, latency: 0.7})
      frontier = %{frontier | solutions: [candidate]}

      initial_timestamp = frontier.updated_at
      Process.sleep(2)

      {:ok, updated} = FrontierManager.update_fronts(frontier)
      assert updated.updated_at > initial_timestamp
    end
  end

  describe "integration: complete workflow" do
    test "create, add, trim, archive workflow" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Add several non-dominated solutions
      candidates = [
        make_candidate("a", %{accuracy: 0.95, latency: 0.4}),
        make_candidate("b", %{accuracy: 0.8, latency: 0.7}),
        make_candidate("c", %{accuracy: 0.7, latency: 0.85})
      ]

      frontier =
        Enum.reduce(candidates, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.add_solution(f, c)
          updated
        end)

      assert length(frontier.solutions) == 3

      # Archive all solutions
      frontier =
        Enum.reduce(frontier.solutions, frontier, fn c, f ->
          {:ok, updated} = FrontierManager.archive_solution(f, c)
          updated
        end)

      assert length(frontier.archive) == 3

      # Trim frontier
      {:ok, frontier} = FrontierManager.trim(frontier, max_size: 2)
      assert length(frontier.solutions) == 2

      # Archive persists even after trimming frontier
      assert length(frontier.archive) == 3
    end

    test "adding dominated solution doesn't affect frontier" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Add a strong solution
      good = make_candidate("good", %{accuracy: 0.9, latency: 0.8})
      {:ok, frontier} = FrontierManager.add_solution(frontier, good)

      # Try to add a dominated solution
      poor = make_candidate("poor", %{accuracy: 0.7, latency: 0.6})
      {:ok, frontier} = FrontierManager.add_solution(frontier, poor)

      # Frontier should still only have the good solution
      assert length(frontier.solutions) == 1
      assert hd(frontier.solutions).id == "good"
    end

    test "frontier evolves correctly through multiple additions" do
      {:ok, frontier} = FrontierManager.new(standard_config())

      # Step 1: Add first solution
      a = make_candidate("a", %{accuracy: 0.7, latency: 0.8})
      {:ok, frontier} = FrontierManager.add_solution(frontier, a)
      assert length(frontier.solutions) == 1

      # Step 2: Add non-dominated solution (trade-off)
      b = make_candidate("b", %{accuracy: 0.9, latency: 0.5})
      {:ok, frontier} = FrontierManager.add_solution(frontier, b)
      assert length(frontier.solutions) == 2

      # Step 3: Add solution that dominates a
      c = make_candidate("c", %{accuracy: 0.85, latency: 0.9})
      {:ok, frontier} = FrontierManager.add_solution(frontier, c)

      # a should be removed, b and c should remain
      assert length(frontier.solutions) == 2
      ids = Enum.map(frontier.solutions, & &1.id) |> Enum.sort()
      assert ids == ["b", "c"]
    end
  end
end
