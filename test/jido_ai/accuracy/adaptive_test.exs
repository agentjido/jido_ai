defmodule Jido.AI.Accuracy.AdaptiveTest do
  @moduledoc """
  Integration tests for adaptive compute budgeting.

  These tests verify that difficulty estimation, compute budgeting,
  and adaptive self-consistency work together correctly.
  """

  use ExUnit.Case, async: false

  @moduletag :integration
  @moduletag :adaptive

  alias Jido.AI.Accuracy.{
    DifficultyEstimate,
    ComputeBudgeter,
    ComputeBudget,
    AdaptiveSelfConsistency,
    Candidate,
    Estimators.HeuristicDifficulty
  }

  describe "7.4.1 Adaptive Budgeting Tests" do
    setup do
      # Create a budgeter with a reasonable global limit
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 100.0})

      # Create heuristic estimator for fast testing
      {:ok, heuristic} = HeuristicDifficulty.new(%{})

      # Create consistent and varied generators for testing
      consistent_generator = fn _query ->
        {:ok,
          Candidate.new!(%{
            id: Uniq.UUID.uuid4(),
            content: "The answer is: 42",
            model: "test"
          })}
      end

      varied_generator = fn _query ->
        {:ok,
          Candidate.new!(%{
            id: Uniq.UUID.uuid4(),
            content: "Answer #{:rand.uniform(1000)}",
            model: "test"
          })}
      end

      %{
        budgeter: budgeter,
        heuristic: heuristic,
        consistent_generator: consistent_generator,
        varied_generator: varied_generator
      }
    end

    test "7.4.1.2 easy questions get minimal compute", context do
      # Simple math question should be classified as easy
      query = "What is 2+2?"

      # Verify difficulty estimation
      assert {:ok, estimate} = HeuristicDifficulty.estimate(context.heuristic, query, %{})
      assert estimate.level == :easy
      assert estimate.score < 0.35

      # Verify budget allocation
      assert {:ok, budget, updated_budgeter} =
               ComputeBudgeter.allocate(context.budgeter, estimate)

      # Easy budget: 3 candidates, no PRM, no search
      assert budget.num_candidates == 3
      assert budget.use_prm == false
      assert budget.use_search == false
      assert ComputeBudget.cost(budget) == 3.0

      # Verify budget tracking
      assert updated_budgeter.used_budget == 3.0
      assert updated_budgeter.allocation_count == 1
    end

    test "7.4.1.3 hard questions get more compute", context do
      # Complex reasoning question with multiple hard indicators
      query =
        "Analyze the quantum mechanical principles behind entanglement. Explain why Bell's theorem demonstrates non-locality. Compare and contrast this with classical physics. What are the implications for modern cryptography?"

      # Verify difficulty estimation
      assert {:ok, estimate} = HeuristicDifficulty.estimate(context.heuristic, query, %{})
      # The heuristic should classify this as hard due to length, complexity, and domain
      assert estimate.level == :hard
      assert estimate.score > 0.65

      # Verify budget allocation
      assert {:ok, budget, _updated_budgeter} =
               ComputeBudgeter.allocate(context.budgeter, estimate)

      # Hard budget: 10 candidates, PRM, search enabled
      assert budget.num_candidates == 10
      assert budget.use_prm == true
      assert budget.use_search == true
      assert budget.search_iterations == 50

      # Cost = 10 + 5 (PRM) + 0.5 (search) + 2 (refinements) = 17.5
      cost = ComputeBudget.cost(budget)
      assert_in_delta cost, 17.5, 0.1
    end

    test "7.4.1.4 global budget is respected", _context do
      # Create budgeter with low limit
      {:ok, limited_budgeter} = ComputeBudgeter.new(%{global_limit: 20.0})

      # Easy question costs 3.0
      assert {:ok, _budget1, budgeter1} =
               ComputeBudgeter.allocate_for_easy(limited_budgeter)

      # Another easy: 3.0 + 3.0 = 6.0
      assert {:ok, _budget2, budgeter2} = ComputeBudgeter.allocate_for_easy(budgeter1)

      # Another easy: 6.0 + 3.0 = 9.0
      assert {:ok, _budget3, budgeter3} = ComputeBudgeter.allocate_for_easy(budgeter2)

      # Medium: 9.0 + 8.5 = 17.5
      assert {:ok, _budget4, budgeter4} = ComputeBudgeter.allocate_for_medium(budgeter3)

      # Total used: 17.5, remaining: 2.5
      # Another medium (8.5) would exceed
      assert {:error, :budget_exhausted} =
               ComputeBudgeter.allocate_for_medium(budgeter4)
    end

    test "7.4.1.5 budget exhaustion handled gracefully", _context do
      # Create budgeter with very low limit
      {:ok, limited_budgeter} = ComputeBudgeter.new(%{global_limit: 5.0})

      # First allocation (easy: 3.0) succeeds
      assert {:ok, _budget, budgeter} = ComputeBudgeter.allocate_for_easy(limited_budgeter)

      # Used: 3.0, remaining: 2.0
      # Hard allocation (17.5) would exceed
      assert {:error, :budget_exhausted} =
               ComputeBudgeter.allocate_for_hard(budgeter)

      # But we can still check remaining budget
      assert {:ok, remaining} = ComputeBudgeter.remaining_budget(budgeter)
      assert remaining == 2.0
    end

    test "medium questions get medium compute", context do
      # Medium difficulty question
      query = "Explain the process of photosynthesis in plants."

      # Verify difficulty estimation
      assert {:ok, estimate} = HeuristicDifficulty.estimate(context.heuristic, query, %{})
      assert estimate.level == :medium

      # Verify budget allocation
      assert {:ok, budget, _updated_budgeter} =
               ComputeBudgeter.allocate(context.budgeter, estimate)

      # Medium budget: 5 candidates, PRM, no search
      assert budget.num_candidates == 5
      assert budget.use_prm == true
      assert budget.use_search == false

      # Cost = 5 + 2.5 (PRM) + 1 (refinement) = 8.5
      cost = ComputeBudget.cost(budget)
      assert_in_delta cost, 8.5, 0.1
    end
  end

  describe "7.4.2 Cost-Effectiveness Tests" do
    setup do
      adapter = AdaptiveSelfConsistency.new!(%{
        min_candidates: 3,
        max_candidates: 20,
        batch_size: 3,
        early_stop_threshold: 0.8
      })

      # Consistent generator triggers early stopping
      consistent_generator = fn _query ->
        {:ok,
          Candidate.new!(%{
            id: Uniq.UUID.uuid4(),
            content: "The answer is: 42",
            model: "test"
          })}
      end

      # Varied generator prevents early stopping
      varied_generator = fn _query ->
        {:ok,
          Candidate.new!(%{
            id: Uniq.UUID.uuid4(),
            content: "Answer #{:rand.uniform(1000)}",
            model: "test"
          })}
      end

      %{
        adapter: adapter,
        consistent_generator: consistent_generator,
        varied_generator: varied_generator
      }
    end

    test "7.4.2.1 adaptive vs fixed budgeting - easy uses fewer candidates", context do
      # Easy difficulty with adaptive self-consistency
      {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})

      # Run adaptive self-consistency
      {:ok, _result, metadata} = AdaptiveSelfConsistency.run(
        context.adapter,
        "What is 2+2?",
        difficulty_estimate: estimate,
        generator: context.consistent_generator
      )

      # With consistent answers, early stopping should kick in
      # Actual N should be much less than max
      assert metadata.actual_n <= 5  # Easy max is 5
      assert metadata.actual_n >= 3  # Min candidates
      assert metadata.early_stopped == true
    end

    test "7.4.2.2 early stopping saves compute with consensus", context do
      # With consistent generator, all answers are identical
      {:ok, estimate} = DifficultyEstimate.new(%{level: :medium, score: 0.5})

      {:ok, _result, metadata} = AdaptiveSelfConsistency.run(
        context.adapter,
        "Test query",
        difficulty_estimate: estimate,
        generator: context.consistent_generator
      )

      # Early stopping should occur
      assert metadata.early_stopped == true
      # Should stop at min_candidates due to 100% consensus
      assert metadata.actual_n == 3
      # Consensus should be high
      assert metadata.consensus >= 0.99
    end

    test "7.4.2.3 no early stopping without consensus", context do
      # With varied generator, answers differ
      {:ok, estimate} = DifficultyEstimate.new(%{level: :medium, score: 0.5})

      {:ok, _result, metadata} = AdaptiveSelfConsistency.run(
        context.adapter,
        "Test query",
        difficulty_estimate: estimate,
        generator: context.varied_generator
      )

      # Without consensus, generates up to max_n for medium (10)
      # because it keeps trying to find consensus
      assert metadata.actual_n == 10  # max_n for medium
      # No early stopping
      assert metadata.early_stopped == false
      # Consensus should be low (no clear majority)
      assert metadata.consensus < 0.8
    end

    test "heuristic vs LLM estimation comparison" do
      query = "What is the capital of France?"

      # Heuristic estimation (fast)
      {:ok, heuristic} = HeuristicDifficulty.new(%{})

      {heuristic_time, {:ok, heuristic_estimate}} =
        :timer.tc(fn -> HeuristicDifficulty.estimate(heuristic, query, %{}) end)

      # Heuristic should be very fast (< 10ms = 10000 microseconds)
      assert heuristic_time < 10_000

      # Both should produce valid estimates
      assert heuristic_estimate.level in [:easy, :medium, :hard]
      assert is_number(heuristic_estimate.score)
      assert heuristic_estimate.score >= 0.0
      assert heuristic_estimate.score <= 1.0

      # Simple factual question should be easy
      assert heuristic_estimate.level == :easy
    end

    test "hard question gets higher N than easy question", context do
      # Easy question
      {:ok, easy_estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})

      {:ok, _easy_result, easy_metadata} = AdaptiveSelfConsistency.run(
        context.adapter,
        "What is 2+2?",
        difficulty_estimate: easy_estimate,
        generator: context.varied_generator
      )

      # Hard question
      {:ok, hard_estimate} = DifficultyEstimate.new(%{level: :hard, score: 0.8})

      {:ok, _hard_result, hard_metadata} = AdaptiveSelfConsistency.run(
        context.adapter,
        "Explain quantum entanglement",
        difficulty_estimate: hard_estimate,
        generator: context.varied_generator
      )

      # Hard should use more candidates than easy
      assert easy_metadata.actual_n <= 5  # Easy max
      assert hard_metadata.actual_n >= 10  # Hard min
      assert hard_metadata.actual_n > easy_metadata.actual_n
    end
  end

  describe "7.4.3 Performance Tests" do
    @tag :performance
    test "7.4.3.1 heuristic difficulty estimation is fast" do
      {:ok, heuristic} = HeuristicDifficulty.new(%{})

      # Typical query
      query = "What is the capital of France?"

      # Measure time for 100 estimations
      iterations = 100

      {total_time, _results} =
        :timer.tc(fn ->
          for _i <- 1..iterations do
            HeuristicDifficulty.estimate(heuristic, query, %{})
          end
        end)

      avg_time_us = total_time / iterations
      avg_time_ms = avg_time_us / 1000

      # Average should be very fast (< 1ms)
      assert avg_time_ms < 1.0,
             "Heuristic estimation took #{avg_time_ms}ms average, expected < 1ms"
    end

    @tag :performance
    test "7.4.3.2 budget allocation has minimal overhead" do
      {:ok, budgeter} = ComputeBudgeter.new(%{})
      {:ok, estimate} = DifficultyEstimate.new(%{level: :medium, score: 0.5})

      # Measure time for 1000 allocations
      iterations = 1000

      {total_time, _results} =
        :timer.tc(fn ->
          for _i <- 1..iterations do
            ComputeBudgeter.allocate(budgeter, estimate)
          end
        end)

      avg_time_us = total_time / iterations
      avg_time_ms = avg_time_us / 1000

      # Average should be very fast (< 1ms)
      assert avg_time_ms < 1.0,
             "Budget allocation took #{avg_time_ms}ms average, expected < 1ms"
    end

    @tag :performance
    test "7.4.3.3 difficulty estimation scales with query length" do
      {:ok, heuristic} = HeuristicDifficulty.new(%{})

      # Short query
      short_query = "What is 2+2?"

      # Long query
      long_query =
        String.duplicate("Explain the history of the Roman Empire including its military conquests, political structure, economic systems, cultural achievements, and eventual decline. ", 10)

      # Both should be fast
      {short_time, _} = :timer.tc(fn -> HeuristicDifficulty.estimate(heuristic, short_query, %{}) end)
      {long_time, _} = :timer.tc(fn -> HeuristicDifficulty.estimate(heuristic, long_query, %{}) end)

      # Convert to ms
      short_time_ms = short_time / 1000
      long_time_ms = long_time / 1000

      # Both should complete in reasonable time
      assert short_time_ms < 10, "Short query took #{short_time_ms}ms"
      assert long_time_ms < 50, "Long query took #{long_time_ms}ms"
    end
  end

  describe "end-to-end adaptive workflow" do
    test "full workflow: estimate -> budget -> generate with early stop" do
      # 1. Create components
      {:ok, estimator} = HeuristicDifficulty.new(%{})
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 50.0})

      # 2. Simple query (easy)
      query = "What is 5 + 7?"

      # 3. Estimate difficulty
      assert {:ok, estimate} = HeuristicDifficulty.estimate(estimator, query, %{})
      assert estimate.level == :easy

      # 4. Allocate budget
      assert {:ok, budget, _budgeter} = ComputeBudgeter.allocate(budgeter, estimate)
      assert budget.num_candidates == 3

      # 5. Run adaptive self-consistency with consistent generator
      consistent_generator = fn _ ->
        {:ok, Candidate.new!(%{id: Uniq.UUID.uuid4(), content: "The answer is: 12", model: "test"})}
      end

      adapter = AdaptiveSelfConsistency.new!(%{early_stop_threshold: 0.8})

      assert {:ok, result, metadata} =
               AdaptiveSelfConsistency.run(adapter, query,
                 difficulty_estimate: estimate,
                 generator: consistent_generator
               )

      # 6. Verify results
      assert result != nil
      assert metadata.actual_n == 3  # Min candidates with early stop
      assert metadata.early_stopped == true
      assert metadata.consensus >= 0.8
      assert metadata.difficulty_level == :easy
    end

    test "full workflow with budget tracking across multiple queries" do
      # Create budgeter with tracking
      {:ok, budgeter} = ComputeBudgeter.new(%{global_limit: 30.0})

      # First query (easy)
      assert {:ok, budget1, budgeter1} = ComputeBudgeter.allocate_for_easy(budgeter)
      assert budget1.num_candidates == 3

      # Second query (medium)
      assert {:ok, budget2, budgeter2} = ComputeBudgeter.allocate_for_medium(budgeter1)
      assert budget2.num_candidates == 5

      # Check remaining
      assert {:ok, remaining} = ComputeBudgeter.remaining_budget(budgeter2)
      # Used: 3 + 8.5 = 11.5, remaining: 18.5
      assert_in_delta remaining, 18.5, 0.1

      # Third query (hard) - should succeed
      assert {:ok, budget3, budgeter3} = ComputeBudgeter.allocate_for_hard(budgeter2)
      assert budget3.num_candidates == 10

      # Check stats
      stats = ComputeBudgeter.get_usage_stats(budgeter3)
      assert stats.allocation_count == 3
      assert_in_delta stats.used_budget, 29.0, 0.1

      # Fourth query (hard) - should fail
      assert {:error, :budget_exhausted} = ComputeBudgeter.allocate_for_hard(budgeter3)
    end
  end
end
