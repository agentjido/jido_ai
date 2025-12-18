defmodule Jido.AI.Runner.GEPA.PopulationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Population
  alias Jido.AI.Runner.GEPA.Population.Candidate

  describe "new/1" do
    test "creates empty population with valid size" do
      assert {:ok, pop} = Population.new(size: 10)
      assert pop.size == 10
      assert pop.generation == 0
      assert pop.candidates == %{}
      assert pop.candidate_ids == []
      assert pop.best_fitness == 0.0
      assert pop.avg_fitness == 0.0
      assert pop.diversity == 1.0
      assert is_integer(pop.created_at)
      assert is_integer(pop.updated_at)
    end

    test "creates population with custom generation" do
      assert {:ok, pop} = Population.new(size: 5, generation: 3)
      assert pop.size == 5
      assert pop.generation == 3
    end

    test "returns error when size is missing" do
      assert {:error, :size_required} = Population.new([])
    end

    test "returns error when size is not positive" do
      assert {:error, {:invalid_size, 0}} = Population.new(size: 0)
      assert {:error, {:invalid_size, -1}} = Population.new(size: -1)
    end

    test "returns error when size is not an integer" do
      assert {:error, {:invalid_size, "10"}} = Population.new(size: "10")
    end
  end

  describe "add_candidate/2" do
    setup do
      {:ok, pop} = Population.new(size: 3)
      {:ok, population: pop}
    end

    test "adds candidate to empty population", %{population: pop} do
      candidate = %{prompt: "Test prompt", fitness: 0.85}

      assert {:ok, updated_pop} = Population.add_candidate(pop, candidate)
      assert length(updated_pop.candidate_ids) == 1
      assert updated_pop.best_fitness == 0.85
      assert updated_pop.avg_fitness == 0.85
    end

    test "adds multiple candidates", %{population: pop} do
      candidates = [
        %{prompt: "Prompt 1", fitness: 0.7},
        %{prompt: "Prompt 2", fitness: 0.9},
        %{prompt: "Prompt 3", fitness: 0.8}
      ]

      result =
        Enum.reduce(candidates, {:ok, pop}, fn candidate, {:ok, p} ->
          Population.add_candidate(p, candidate)
        end)

      assert {:ok, updated_pop} = result
      assert length(updated_pop.candidate_ids) == 3
      assert updated_pop.best_fitness == 0.9
      assert_in_delta updated_pop.avg_fitness, 0.8, 0.01
    end

    test "adds candidate without fitness", %{population: pop} do
      candidate = %{prompt: "Test prompt"}

      assert {:ok, updated_pop} = Population.add_candidate(pop, candidate)
      assert length(updated_pop.candidate_ids) == 1

      [cand] = Population.get_all(updated_pop)
      assert cand.fitness == nil
      assert cand.prompt == "Test prompt"
    end

    test "replaces worst candidate when at capacity", %{population: pop} do
      # Fill population to capacity
      pop =
        Enum.reduce(1..3, pop, fn i, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Prompt #{i}", fitness: i * 0.3})

          updated
        end)

      # Try to add better candidate
      assert {:ok, updated_pop} =
               Population.add_candidate(pop, %{prompt: "Better prompt", fitness: 0.95})

      assert length(updated_pop.candidate_ids) == 3
      assert updated_pop.best_fitness == 0.95

      # Check that worst candidate was removed
      prompts = Enum.map(Population.get_all(updated_pop), & &1.prompt)
      refute "Prompt 1" in prompts
      assert "Better prompt" in prompts
    end

    test "rejects candidate when at capacity and fitness not better", %{population: pop} do
      # Fill population
      pop =
        Enum.reduce(1..3, pop, fn i, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Prompt #{i}", fitness: i * 0.3})

          updated
        end)

      # Try to add worse candidate
      assert {:error, :population_full} =
               Population.add_candidate(pop, %{prompt: "Worse prompt", fitness: 0.2})
    end

    test "rejects candidate without fitness when at capacity", %{population: pop} do
      # Fill population
      pop =
        Enum.reduce(1..3, pop, fn i, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Prompt #{i}", fitness: i * 0.3})

          updated
        end)

      assert {:error, :population_full} =
               Population.add_candidate(pop, %{prompt: "No fitness prompt"})
    end

    test "preserves candidate metadata", %{population: pop} do
      candidate = %{
        prompt: "Test",
        fitness: 0.8,
        metadata: %{source: :mutation, parent_id: "test-123"}
      }

      assert {:ok, updated_pop} = Population.add_candidate(pop, candidate)
      [cand] = Population.get_all(updated_pop)
      assert cand.metadata.source == :mutation
      assert cand.metadata.parent_id == "test-123"
    end

    test "generates unique IDs for candidates", %{population: pop} do
      {:ok, pop} = Population.add_candidate(pop, %{prompt: "Test 1"})
      {:ok, pop} = Population.add_candidate(pop, %{prompt: "Test 2"})

      candidates = Population.get_all(pop)
      ids = Enum.map(candidates, & &1.id)
      assert length(Enum.uniq(ids)) == 2
    end

    test "accepts Candidate struct", %{population: pop} do
      candidate = %Candidate{
        id: "test-123",
        prompt: "Test prompt",
        fitness: 0.85,
        generation: 0,
        created_at: System.monotonic_time(:millisecond)
      }

      assert {:ok, updated_pop} = Population.add_candidate(pop, candidate)
      assert Map.has_key?(updated_pop.candidates, "test-123")
    end
  end

  describe "remove_candidate/2" do
    setup do
      {:ok, pop} = Population.new(size: 5)

      pop =
        Enum.reduce(1..3, pop, fn i, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Prompt #{i}", fitness: i * 0.3})

          updated
        end)

      [first_id | _] = pop.candidate_ids
      {:ok, population: pop, first_id: first_id}
    end

    test "removes existing candidate", %{population: pop, first_id: id} do
      assert {:ok, updated_pop} = Population.remove_candidate(pop, id)
      assert length(updated_pop.candidate_ids) == 2
      refute Map.has_key?(updated_pop.candidates, id)
    end

    test "returns error for non-existent candidate", %{population: pop} do
      assert {:error, {:candidate_not_found, "nonexistent"}} =
               Population.remove_candidate(pop, "nonexistent")
    end

    test "recalculates statistics after removal", %{population: pop, first_id: id} do
      assert {:ok, updated_pop} = Population.remove_candidate(pop, id)
      # first_id is the most recently added (0.9), so remaining are 0.3 and 0.6
      assert updated_pop.best_fitness == 0.6
      assert_in_delta updated_pop.avg_fitness, 0.45, 0.01
    end
  end

  describe "replace_candidate/3" do
    setup do
      {:ok, pop} = Population.new(size: 3)

      {:ok, pop} =
        Population.add_candidate(pop, %{prompt: "Old prompt", fitness: 0.5})

      [id] = pop.candidate_ids
      {:ok, population: pop, id: id}
    end

    test "replaces existing candidate", %{population: pop, id: id} do
      new_candidate = %{prompt: "New prompt", fitness: 0.8}

      assert {:ok, updated_pop} = Population.replace_candidate(pop, id, new_candidate)
      assert length(updated_pop.candidate_ids) == 1

      candidates = Population.get_all(updated_pop)
      assert Enum.any?(candidates, fn c -> c.prompt == "New prompt" end)
      refute Enum.any?(candidates, fn c -> c.prompt == "Old prompt" end)
    end

    test "returns error for non-existent candidate", %{population: pop} do
      assert {:error, {:candidate_not_found, "nonexistent"}} =
               Population.replace_candidate(pop, "nonexistent", %{prompt: "New"})
    end
  end

  describe "update_fitness/3" do
    setup do
      {:ok, pop} = Population.new(size: 3)
      {:ok, pop} = Population.add_candidate(pop, %{prompt: "Test"})
      [id] = pop.candidate_ids
      {:ok, population: pop, id: id}
    end

    test "updates fitness with float", %{population: pop, id: id} do
      assert {:ok, updated_pop} = Population.update_fitness(pop, id, 0.85)

      {:ok, candidate} = Population.get_candidate(updated_pop, id)
      assert candidate.fitness == 0.85
      assert is_integer(candidate.evaluated_at)
    end

    test "updates fitness with integer", %{population: pop, id: id} do
      assert {:ok, updated_pop} = Population.update_fitness(pop, id, 1)

      {:ok, candidate} = Population.get_candidate(updated_pop, id)
      assert candidate.fitness == 1.0
    end

    test "recalculates population statistics", %{population: pop, id: id} do
      assert {:ok, updated_pop} = Population.update_fitness(pop, id, 0.75)
      assert updated_pop.best_fitness == 0.75
      assert updated_pop.avg_fitness == 0.75
    end

    test "returns error for non-existent candidate", %{population: pop} do
      assert {:error, {:candidate_not_found, "nonexistent"}} =
               Population.update_fitness(pop, "nonexistent", 0.5)
    end
  end

  describe "get_best/2" do
    setup do
      {:ok, pop} = Population.new(size: 10)

      fitnesses = [0.5, 0.9, 0.3, 0.7, 0.8]

      pop =
        Enum.reduce(fitnesses, pop, fn fitness, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Prompt #{fitness}", fitness: fitness})

          updated
        end)

      {:ok, population: pop}
    end

    test "returns candidates sorted by fitness", %{population: pop} do
      best = Population.get_best(pop, limit: 3)

      assert length(best) == 3
      assert Enum.at(best, 0).fitness == 0.9
      assert Enum.at(best, 1).fitness == 0.8
      assert Enum.at(best, 2).fitness == 0.7
    end

    test "returns all candidates when limit exceeds population", %{population: pop} do
      best = Population.get_best(pop, limit: 100)
      assert length(best) == 5
    end

    test "filters by min_fitness", %{population: pop} do
      best = Population.get_best(pop, min_fitness: 0.7)

      assert length(best) == 3
      assert Enum.all?(best, fn c -> c.fitness >= 0.7 end)
    end

    test "returns empty list for empty population" do
      {:ok, pop} = Population.new(size: 5)
      assert Population.get_best(pop) == []
    end

    test "excludes candidates without fitness", %{population: pop} do
      {:ok, pop} = Population.add_candidate(pop, %{prompt: "No fitness"})

      best = Population.get_best(pop, limit: 10)
      assert length(best) == 5
      assert Enum.all?(best, fn c -> c.fitness != nil end)
    end

    test "uses default limit of 10", %{population: pop} do
      # Add more candidates
      pop =
        Enum.reduce(6..15, pop, fn i, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Prompt #{i}", fitness: i * 0.1})

          updated
        end)

      best = Population.get_best(pop)
      assert length(best) <= 10
    end
  end

  describe "get_candidate/2" do
    setup do
      {:ok, pop} = Population.new(size: 3)
      {:ok, pop} = Population.add_candidate(pop, %{prompt: "Test", fitness: 0.8})
      [id] = pop.candidate_ids
      {:ok, population: pop, id: id}
    end

    test "returns existing candidate", %{population: pop, id: id} do
      assert {:ok, candidate} = Population.get_candidate(pop, id)
      assert candidate.id == id
      assert candidate.prompt == "Test"
      assert candidate.fitness == 0.8
    end

    test "returns error for non-existent candidate", %{population: pop} do
      assert {:error, {:candidate_not_found, "nonexistent"}} =
               Population.get_candidate(pop, "nonexistent")
    end
  end

  describe "get_all/1" do
    test "returns all candidates" do
      {:ok, pop} = Population.new(size: 5)

      pop =
        Enum.reduce(1..3, pop, fn i, p ->
          {:ok, updated} = Population.add_candidate(p, %{prompt: "Prompt #{i}"})
          updated
        end)

      candidates = Population.get_all(pop)
      assert length(candidates) == 3
      assert Enum.all?(candidates, &is_struct(&1, Candidate))
    end

    test "returns empty list for empty population" do
      {:ok, pop} = Population.new(size: 5)
      assert Population.get_all(pop) == []
    end
  end

  describe "statistics/1" do
    test "returns correct statistics for populated population" do
      {:ok, pop} = Population.new(size: 10)

      # Add 3 evaluated and 2 unevaluated candidates
      pop =
        Enum.reduce(1..3, pop, fn i, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Evaluated #{i}", fitness: i * 0.3})

          updated
        end)

      pop =
        Enum.reduce(1..2, pop, fn i, p ->
          {:ok, updated} = Population.add_candidate(p, %{prompt: "Unevaluated #{i}"})
          updated
        end)

      stats = Population.statistics(pop)

      assert stats.size == 5
      assert stats.capacity == 10
      assert stats.evaluated == 3
      assert stats.unevaluated == 2
      assert stats.generation == 0
      assert_in_delta stats.best_fitness, 0.9, 0.01
      assert_in_delta stats.avg_fitness, 0.6, 0.01
      assert_in_delta stats.diversity, 1.0, 0.01
    end

    test "returns zero statistics for empty population" do
      {:ok, pop} = Population.new(size: 5)
      stats = Population.statistics(pop)

      assert stats.size == 0
      assert stats.capacity == 5
      assert stats.evaluated == 0
      assert stats.unevaluated == 0
      assert stats.best_fitness == 0.0
      assert stats.avg_fitness == 0.0
      assert stats.diversity == 1.0
    end

    test "calculates diversity correctly" do
      {:ok, pop} = Population.new(size: 10)

      # Add duplicate prompts (low diversity)
      pop =
        Enum.reduce(1..3, pop, fn _i, p ->
          {:ok, updated} = Population.add_candidate(p, %{prompt: "Same prompt"})
          updated
        end)

      stats = Population.statistics(pop)
      assert_in_delta stats.diversity, 0.33, 0.01

      # Add unique prompts (high diversity)
      pop =
        Enum.reduce(4..6, pop, fn i, p ->
          {:ok, updated} = Population.add_candidate(p, %{prompt: "Unique #{i}"})
          updated
        end)

      stats = Population.statistics(pop)
      # 4 unique prompts out of 6 total
      assert_in_delta stats.diversity, 0.66, 0.01
    end
  end

  describe "next_generation/1" do
    test "increments generation counter" do
      {:ok, pop} = Population.new(size: 5, generation: 0)
      assert {:ok, updated_pop} = Population.next_generation(pop)
      assert updated_pop.generation == 1

      assert {:ok, updated_pop} = Population.next_generation(updated_pop)
      assert updated_pop.generation == 2
    end

    test "updates timestamp" do
      {:ok, pop} = Population.new(size: 5)
      initial_updated_at = pop.updated_at

      Process.sleep(10)

      assert {:ok, updated_pop} = Population.next_generation(pop)
      assert updated_pop.updated_at > initial_updated_at
    end
  end

  describe "save/2 and load/1" do
    @tag :tmp_dir
    test "saves and loads population", %{tmp_dir: tmp_dir} do
      {:ok, pop} = Population.new(size: 5, generation: 2)

      pop =
        Enum.reduce(1..3, pop, fn i, p ->
          {:ok, updated} =
            Population.add_candidate(p, %{prompt: "Prompt #{i}", fitness: i * 0.3})

          updated
        end)

      path = Path.join(tmp_dir, "test_population.pop")

      # Save
      assert :ok = Population.save(pop, path)
      assert File.exists?(path)

      # Load
      assert {:ok, loaded_pop} = Population.load(path)

      # Verify loaded data
      assert loaded_pop.size == pop.size
      assert loaded_pop.generation == pop.generation
      assert length(loaded_pop.candidate_ids) == length(pop.candidate_ids)
      assert loaded_pop.best_fitness == pop.best_fitness
      assert_in_delta loaded_pop.avg_fitness, pop.avg_fitness, 0.01

      # Verify candidates
      original_candidates = Population.get_all(pop)
      loaded_candidates = Population.get_all(loaded_pop)
      assert length(loaded_candidates) == length(original_candidates)
    end

    test "returns error for non-existent file" do
      assert {:error, {:file_not_found, "/nonexistent/path.pop"}} =
               Population.load("/nonexistent/path.pop")
    end

    @tag :tmp_dir
    test "returns error for invalid format", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "invalid.pop")
      File.write!(path, "invalid data")

      # Enhanced error handling returns more specific error type
      assert {:error, {:deserialization_failed, _}} = Population.load(path)
    end

    @tag :tmp_dir
    test "returns error for unsupported version", %{tmp_dir: tmp_dir} do
      path = Path.join(tmp_dir, "future_version.pop")
      data = %{version: 999, population: %{}}
      binary = :erlang.term_to_binary(data)
      File.write!(path, binary)

      assert {:error, {:unsupported_version, 999}} = Population.load(path)
    end
  end

  describe "recalculate_statistics/1" do
    test "updates best_fitness correctly" do
      {:ok, pop} = Population.new(size: 5)

      pop =
        Enum.reduce([0.3, 0.7, 0.9, 0.5], pop, fn fitness, p ->
          {:ok, updated} = Population.add_candidate(p, %{prompt: "Test", fitness: fitness})
          updated
        end)

      assert pop.best_fitness == 0.9
    end

    test "updates avg_fitness correctly" do
      {:ok, pop} = Population.new(size: 5)

      pop =
        Enum.reduce([0.4, 0.6, 0.8], pop, fn fitness, p ->
          {:ok, updated} = Population.add_candidate(p, %{prompt: "Test", fitness: fitness})
          updated
        end)

      # Average of 0.4, 0.6, 0.8 = 0.6
      assert_in_delta pop.avg_fitness, 0.6, 0.01
    end

    test "handles population with no evaluated candidates" do
      {:ok, pop} = Population.new(size: 5)
      {:ok, pop} = Population.add_candidate(pop, %{prompt: "Test"})

      assert pop.best_fitness == 0.0
      assert pop.avg_fitness == 0.0
    end
  end
end
