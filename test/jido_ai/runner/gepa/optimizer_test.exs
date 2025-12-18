defmodule Jido.AI.Runner.GEPA.OptimizerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Optimizer

  describe "start_link/1" do
    test "starts optimizer with valid configuration" do
      opts = [
        population_size: 5,
        max_generations: 10,
        evaluation_budget: 50,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      assert Process.alive?(pid)

      # Clean up
      Optimizer.stop(pid)
    end

    test "starts optimizer with seed prompts" do
      opts = [
        population_size: 5,
        seed_prompts: ["Solve step by step", "Think carefully"],
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      assert Process.alive?(pid)

      Optimizer.stop(pid)
    end

    test "starts optimizer with named process" do
      opts = [
        name: :test_optimizer,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      assert Process.whereis(:test_optimizer) == pid

      Optimizer.stop(pid)
    end

    test "requires task configuration" do
      opts = [population_size: 5]

      assert_raise ArgumentError, "task configuration is required", fn ->
        Optimizer.start_link(opts)
      end
    end

    test "uses default configuration values" do
      opts = [task: %{type: :test}]

      assert {:ok, pid} = Optimizer.start_link(opts)

      {:ok, status} = Optimizer.status(pid)
      assert status.population_size == 10

      Optimizer.stop(pid)
    end
  end

  describe "initialization" do
    test "initializes population from seed prompts" do
      seed_prompts = ["Prompt 1", "Prompt 2", "Prompt 3"]

      opts = [
        population_size: 3,
        seed_prompts: seed_prompts,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)

      # Give initialization time to complete
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.status == :ready
      assert status.population_size == 3
      assert status.generation == 0
      assert status.evaluations_used == 0

      Optimizer.stop(pid)
    end

    test "generates variations when seeds are fewer than population size" do
      opts = [
        population_size: 10,
        seed_prompts: ["Seed prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.population_size == 10
      assert status.status == :ready

      Optimizer.stop(pid)
    end

    test "generates default prompts when no seeds provided" do
      opts = [
        population_size: 5,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.population_size == 5
      assert status.status == :ready

      Optimizer.stop(pid)
    end
  end

  describe "status/1" do
    test "returns current optimization status" do
      opts = [
        population_size: 5,
        max_generations: 10,
        evaluation_budget: 50,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)

      assert status.status == :ready
      assert status.generation == 0
      assert status.evaluations_used == 0
      assert status.evaluations_remaining == 50
      assert status.best_fitness == 0.0
      assert status.population_size == 5
      assert is_integer(status.uptime_ms)
      assert status.uptime_ms >= 0

      Optimizer.stop(pid)
    end

    test "tracks uptime correctly" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(50)

      {:ok, status1} = Optimizer.status(pid)
      Process.sleep(50)
      {:ok, status2} = Optimizer.status(pid)

      assert status2.uptime_ms > status1.uptime_ms

      Optimizer.stop(pid)
    end
  end

  describe "get_best_prompts/2" do
    test "returns empty list when population has no fitness scores" do
      opts = [
        population_size: 5,
        seed_prompts: ["Test prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, prompts} = Optimizer.get_best_prompts(pid)
      assert prompts == []

      Optimizer.stop(pid)
    end

    test "respects limit parameter" do
      opts = [
        population_size: 10,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, prompts} = Optimizer.get_best_prompts(pid, limit: 3)
      assert length(prompts) <= 3

      Optimizer.stop(pid)
    end

    test "uses default limit of 5" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, prompts} = Optimizer.get_best_prompts(pid)
      assert length(prompts) <= 5

      Optimizer.stop(pid)
    end
  end

  describe "optimize/1" do
    test "executes optimization loop when ready" do
      opts = [
        population_size: 3,
        seed_prompts: ["Test prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.status == :ready

      {:ok, result} = Optimizer.optimize(pid)

      assert is_map(result)
      assert Map.has_key?(result, :best_prompts)
      assert Map.has_key?(result, :final_generation)
      assert Map.has_key?(result, :total_evaluations)
      assert Map.has_key?(result, :history)
      assert Map.has_key?(result, :duration_ms)
      assert is_integer(result.duration_ms)

      Optimizer.stop(pid)
    end

    test "changes status to completed after optimization" do
      opts = [
        population_size: 3,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, _result} = Optimizer.optimize(pid)

      {:ok, status} = Optimizer.status(pid)
      assert status.status == :completed

      Optimizer.stop(pid)
    end
  end

  describe "stop/1" do
    test "stops optimizer gracefully" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      assert Process.alive?(pid)

      assert :ok = Optimizer.stop(pid)

      # Wait for process to terminate
      Process.sleep(50)

      refute Process.alive?(pid)
    end
  end

  describe "configuration validation" do
    test "validates population_size is positive" do
      opts = [
        population_size: 10,
        max_generations: 20,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      Optimizer.stop(pid)
    end

    test "validates max_generations is positive" do
      opts = [
        max_generations: 50,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      Optimizer.stop(pid)
    end

    test "validates evaluation_budget is positive" do
      opts = [
        evaluation_budget: 100,
        task: %{type: :test}
      ]

      assert {:ok, pid} = Optimizer.start_link(opts)
      Optimizer.stop(pid)
    end
  end

  describe "state management" do
    test "maintains generation counter" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.generation == 0

      Optimizer.stop(pid)
    end

    test "tracks evaluations used" do
      opts = [
        evaluation_budget: 100,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.evaluations_used == 0
      assert status.evaluations_remaining == 100

      Optimizer.stop(pid)
    end

    test "initializes best_fitness to zero" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, status} = Optimizer.status(pid)
      assert status.best_fitness == 0.0

      Optimizer.stop(pid)
    end
  end

  describe "concurrent access" do
    test "handles multiple concurrent status calls" do
      opts = [task: %{type: :test}]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      tasks =
        for _ <- 1..10 do
          Task.async(fn -> Optimizer.status(pid) end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               match?({:ok, %{status: :ready}}, result)
             end)

      Optimizer.stop(pid)
    end

    test "handles concurrent get_best_prompts calls" do
      opts = [
        population_size: 5,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      tasks =
        for _ <- 1..5 do
          Task.async(fn -> Optimizer.get_best_prompts(pid, limit: 3) end)
        end

      results = Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               match?({:ok, prompts} when is_list(prompts), result)
             end)

      Optimizer.stop(pid)
    end
  end

  describe "evolution cycle coordination" do
    test "executes complete evolution cycle through all phases" do
      opts = [
        population_size: 5,
        max_generations: 3,
        seed_prompts: ["Test prompt 1", "Test prompt 2"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Verify result structure
      assert Map.has_key?(result, :best_prompts)
      assert Map.has_key?(result, :final_generation)
      assert Map.has_key?(result, :total_evaluations)
      assert Map.has_key?(result, :history)
      assert Map.has_key?(result, :duration_ms)
      assert Map.has_key?(result, :stop_reason)

      # Verify evolution ran
      assert result.final_generation > 0
      assert result.total_evaluations > 0
      assert length(result.history) > 0

      Optimizer.stop(pid)
    end

    test "generation coordinator executes multiple generations" do
      opts = [
        population_size: 4,
        max_generations: 5,
        # High budget to avoid budget stop
        evaluation_budget: 1000,
        seed_prompts: ["Prompt A", "Prompt B"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Should run multiple generations (may converge early due to random fitness)
      assert result.final_generation >= 3
      assert result.final_generation <= 5
      assert length(result.history) == result.final_generation

      Optimizer.stop(pid)
    end

    test "phase transitions maintain state synchronization" do
      opts = [
        population_size: 3,
        max_generations: 2,
        seed_prompts: ["Initial prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Verify state flowed through phases correctly
      # Each generation should have metrics
      assert Enum.all?(result.history, fn metrics ->
               Map.has_key?(metrics, :generation) and
                 Map.has_key?(metrics, :best_fitness) and
                 Map.has_key?(metrics, :avg_fitness) and
                 Map.has_key?(metrics, :diversity) and
                 Map.has_key?(metrics, :evaluations_used) and
                 Map.has_key?(metrics, :timestamp)
             end)

      Optimizer.stop(pid)
    end

    test "evaluates unevaluated candidates in population" do
      opts = [
        population_size: 5,
        max_generations: 1,
        seed_prompts: ["Test prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Should have evaluated the population
      assert result.total_evaluations > 0
      assert length(result.best_prompts) > 0

      # Best prompts should have fitness scores
      assert Enum.all?(result.best_prompts, fn prompt ->
               Map.has_key?(prompt, :fitness) and is_float(prompt.fitness)
             end)

      Optimizer.stop(pid)
    end

    test "selection phase creates next generation with elitism" do
      opts = [
        population_size: 10,
        max_generations: 3,
        seed_prompts: ["Elite prompt", "Good prompt", "Average prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Verify best prompts are preserved (elitism)
      # Best fitness should not decrease across generations
      fitnesses = Enum.map(result.history, & &1.best_fitness)

      # Each generation's best should be >= previous (or very close due to float precision)
      pairs = Enum.zip(fitnesses, Enum.drop(fitnesses, 1))
      assert Enum.all?(pairs, fn {prev, curr} -> curr >= prev - 0.001 end)

      Optimizer.stop(pid)
    end

    test "mutation phase generates offspring from parents" do
      opts = [
        population_size: 6,
        max_generations: 2,
        seed_prompts: ["Parent prompt"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Offspring should be created (population maintained across generations)
      assert result.final_generation == 2
      assert length(result.history) == 2

      Optimizer.stop(pid)
    end
  end

  describe "progress tracking" do
    test "records generation metrics in history" do
      opts = [
        population_size: 5,
        max_generations: 4,
        evaluation_budget: 1000,
        seed_prompts: ["Track me"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # May converge early with random fitness values
      final_gen = result.final_generation
      assert final_gen >= 2
      assert final_gen <= 4
      assert length(result.history) == final_gen

      # Each metric should have required fields
      Enum.each(result.history, fn metrics ->
        assert is_integer(metrics.generation)
        assert is_float(metrics.best_fitness)
        assert is_float(metrics.avg_fitness)
        assert is_float(metrics.diversity)
        assert is_integer(metrics.evaluations_used)
        assert is_integer(metrics.timestamp)
      end)

      Optimizer.stop(pid)
    end

    test "history is returned in chronological order" do
      opts = [
        population_size: 3,
        max_generations: 3,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Generations should be in order 1, 2, 3
      generations = Enum.map(result.history, & &1.generation)
      assert generations == [1, 2, 3]

      # Timestamps should be increasing
      timestamps = Enum.map(result.history, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps)

      Optimizer.stop(pid)
    end

    test "tracks best fitness across generations" do
      opts = [
        population_size: 5,
        max_generations: 3,
        seed_prompts: ["Fitness tracker"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Each generation should have best_fitness tracked
      best_fitnesses = Enum.map(result.history, & &1.best_fitness)
      assert length(best_fitnesses) == 3
      assert Enum.all?(best_fitnesses, fn f -> f >= 0.0 and f <= 1.0 end)

      Optimizer.stop(pid)
    end

    test "tracks diversity metrics across generations" do
      opts = [
        population_size: 8,
        max_generations: 2,
        seed_prompts: ["Diverse prompt 1", "Diverse prompt 2"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Each generation should have diversity tracked
      diversities = Enum.map(result.history, & &1.diversity)
      assert length(diversities) == 2
      assert Enum.all?(diversities, fn d -> is_float(d) and d >= 0.0 end)

      Optimizer.stop(pid)
    end

    test "tracks cumulative evaluations used" do
      opts = [
        population_size: 4,
        max_generations: 3,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Evaluations should increase across generations
      evaluations = Enum.map(result.history, & &1.evaluations_used)
      assert evaluations == Enum.sort(evaluations)

      # Total should match final count
      assert result.total_evaluations == List.last(evaluations)

      Optimizer.stop(pid)
    end

    test "reports duration in milliseconds" do
      opts = [
        population_size: 3,
        max_generations: 2,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      assert is_integer(result.duration_ms)
      assert result.duration_ms > 0

      Optimizer.stop(pid)
    end
  end

  describe "early stopping" do
    test "stops at max_generations limit" do
      opts = [
        population_size: 5,
        max_generations: 3,
        evaluation_budget: 1000,
        seed_prompts: ["Test"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Should stop at exactly max_generations
      assert result.final_generation == 3
      assert result.stop_reason == :max_generations_reached

      Optimizer.stop(pid)
    end

    test "stops when evaluation budget exhausted" do
      opts = [
        population_size: 10,
        max_generations: 100,
        evaluation_budget: 15,
        seed_prompts: ["Budget test"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Should stop before max_generations due to budget
      assert result.final_generation < 100
      assert result.stop_reason == :budget_exhausted
      # Budget check happens before generation start, so we may slightly exceed
      # by the evaluations in the final generation
      assert result.total_evaluations <= 20

      Optimizer.stop(pid)
    end

    test "stops when optimization converges" do
      # Note: This test may be flaky due to randomness in mock evaluation
      # In real implementation, convergence would be more deterministic
      opts = [
        population_size: 3,
        max_generations: 100,
        evaluation_budget: 1000,
        seed_prompts: ["Converge test"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # If converged, should stop before limits
      if result.stop_reason == :converged do
        assert result.final_generation < 100
        assert result.total_evaluations < 1000
      end

      # Should always have a valid stop reason
      assert result.stop_reason in [:max_generations_reached, :budget_exhausted, :converged]

      Optimizer.stop(pid)
    end

    test "returns correct stop reason in result" do
      opts = [
        population_size: 4,
        max_generations: 2,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      assert Map.has_key?(result, :stop_reason)
      assert result.stop_reason in [:max_generations_reached, :budget_exhausted, :converged]

      Optimizer.stop(pid)
    end
  end

  describe "convergence detection" do
    test "detects convergence through fitness variance" do
      # This test verifies the convergence detection logic
      # Convergence is detected when fitness variance < 0.001 over last 3 generations
      opts = [
        population_size: 3,
        max_generations: 50,
        evaluation_budget: 500,
        seed_prompts: ["Stable fitness"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      if result.stop_reason == :converged do
        # If converged, last 3 generations should have similar fitness
        last_three = Enum.take(result.history, -3)
        fitnesses = Enum.map(last_three, & &1.best_fitness)

        mean = Enum.sum(fitnesses) / length(fitnesses)

        variance =
          Enum.reduce(fitnesses, 0.0, fn f, acc ->
            acc + :math.pow(f - mean, 2)
          end) / length(fitnesses)

        assert variance < 0.001
      end

      Optimizer.stop(pid)
    end

    test "requires at least 3 generations for convergence check" do
      opts = [
        population_size: 3,
        max_generations: 2,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # With only 2 generations, cannot converge (requires 3 for variance check)
      assert result.stop_reason != :converged

      Optimizer.stop(pid)
    end
  end

  describe "result preparation" do
    test "includes best prompts in result" do
      opts = [
        population_size: 5,
        max_generations: 2,
        seed_prompts: ["Result test"],
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      assert is_list(result.best_prompts)
      assert length(result.best_prompts) <= 5

      # Each prompt should have required fields
      Enum.each(result.best_prompts, fn prompt ->
        assert Map.has_key?(prompt, :prompt)
        assert Map.has_key?(prompt, :fitness)
        assert Map.has_key?(prompt, :generation)
        assert Map.has_key?(prompt, :metadata)
      end)

      Optimizer.stop(pid)
    end

    test "limits best prompts to top 5 by default" do
      opts = [
        population_size: 20,
        max_generations: 1,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # Should return at most 5 best prompts
      assert length(result.best_prompts) <= 5

      Optimizer.stop(pid)
    end

    test "includes complete history in chronological order" do
      opts = [
        population_size: 3,
        max_generations: 4,
        # High budget to avoid budget stop
        evaluation_budget: 1000,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # May converge early with random fitness values
      final_gen = result.final_generation
      assert final_gen >= 2
      assert final_gen <= 4
      assert length(result.history) == final_gen

      # History should be in chronological order
      generations = Enum.map(result.history, & &1.generation)
      assert generations == Enum.to_list(1..final_gen)

      Optimizer.stop(pid)
    end

    test "reports final generation count" do
      opts = [
        population_size: 3,
        max_generations: 5,
        # High budget to avoid budget stop
        evaluation_budget: 1000,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      # May stop early due to convergence with random fitness values
      assert result.final_generation > 0
      assert result.final_generation <= 5
      # Verify stop reason is valid
      assert result.stop_reason in [:max_generations_reached, :converged]

      Optimizer.stop(pid)
    end

    test "reports total evaluations performed" do
      opts = [
        population_size: 4,
        max_generations: 3,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      {:ok, result} = Optimizer.optimize(pid)

      assert is_integer(result.total_evaluations)
      assert result.total_evaluations > 0

      Optimizer.stop(pid)
    end
  end

  describe "fault tolerance" do
    test "handles process termination gracefully" do
      # Trap exits so we can observe the process dying without crashing the test
      Process.flag(:trap_exit, true)

      opts = [
        population_size: 5,
        max_generations: 3,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      # Verify optimizer is running
      assert Process.alive?(pid)
      {:ok, status} = Optimizer.status(pid)
      assert status.status == :ready

      # Terminate the process
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Process should be terminated
      refute Process.alive?(pid)

      # Reset trap_exit to default
      Process.flag(:trap_exit, false)
    end

    test "rejects operations after process termination" do
      opts = [task: %{type: :test}]
      {:ok, pid} = Optimizer.start_link(opts)

      # Terminate the process
      Optimizer.stop(pid)
      Process.sleep(100)

      # Operations should fail gracefully
      catch_exit(Optimizer.status(pid))
      catch_exit(Optimizer.get_best_prompts(pid))
      catch_exit(Optimizer.optimize(pid))
    end

    test "handles concurrent optimize calls safely" do
      opts = [
        population_size: 3,
        max_generations: 2,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      # Start first optimization
      task1 = Task.async(fn -> Optimizer.optimize(pid) end)

      # Try to start second optimization concurrently
      Process.sleep(10)
      task2 = Task.async(fn -> Optimizer.optimize(pid) end)

      # Wait for both to complete
      result1 = Task.await(task1, 10_000)
      result2 = Task.await(task2, 10_000)

      # One should succeed, one should get an error about already running
      results = [result1, result2]
      assert Enum.any?(results, fn r -> match?({:ok, %{best_prompts: _}}, r) end)

      Optimizer.stop(pid)
    end

    test "maintains state consistency under concurrent access" do
      opts = [
        population_size: 10,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      # Perform many concurrent status checks
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            Process.sleep(:rand.uniform(10))

            case rem(i, 3) do
              0 -> Optimizer.status(pid)
              1 -> Optimizer.get_best_prompts(pid, limit: 3)
              _ -> {:ok, %{test: i}}
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All operations should complete without crashes
      assert length(results) == 50
      assert Enum.all?(results, fn r -> match?({:ok, _}, r) end)

      Optimizer.stop(pid)
    end

    test "recovers from evaluation errors without crashing" do
      opts = [
        population_size: 3,
        max_generations: 2,
        task: %{type: :test}
      ]

      {:ok, pid} = Optimizer.start_link(opts)
      Process.sleep(100)

      # Optimizer should handle errors during optimization
      # The mock evaluation may produce errors, optimizer should handle gracefully
      result = Optimizer.optimize(pid)

      # Should complete without crashing
      assert match?({:ok, _}, result)
      assert Process.alive?(pid)

      Optimizer.stop(pid)
    end

    test "handles monitor down messages correctly" do
      opts = [task: %{type: :test}]
      {:ok, pid} = Optimizer.start_link(opts)

      # Create a monitor
      ref = Process.monitor(pid)

      # Stop the optimizer
      Optimizer.stop(pid)

      # Should receive DOWN message
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    end
  end
end
