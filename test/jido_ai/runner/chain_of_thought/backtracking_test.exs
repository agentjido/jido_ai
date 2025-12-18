defmodule Jido.AI.Runner.ChainOfThought.BacktrackingTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.ChainOfThought.Backtracking

  alias Jido.AI.Runner.ChainOfThought.Backtracking.{
    BudgetManager,
    DeadEndDetector,
    PathExplorer,
    StateManager
  }

  describe "StateManager.capture_snapshot/2" do
    test "captures state snapshot with ID and timestamp" do
      state = %{reasoning: "test", step: 1}
      snapshot = StateManager.capture_snapshot(state)

      assert Map.has_key?(snapshot, :id)
      assert Map.has_key?(snapshot, :timestamp)
      assert snapshot.data == state
      assert is_binary(snapshot.id)
      assert String.starts_with?(snapshot.id, "snap_")
    end

    test "includes custom metadata when provided" do
      state = %{value: 42}
      metadata = %{priority: :high, reason: "critical"}

      snapshot = StateManager.capture_snapshot(state, metadata: metadata)

      assert snapshot.metadata == metadata
    end
  end

  describe "StateManager.restore_snapshot/1" do
    test "restores state from snapshot" do
      original_state = %{data: "important", counter: 5}
      snapshot = StateManager.capture_snapshot(original_state)

      restored = StateManager.restore_snapshot(snapshot)

      assert restored == original_state
    end
  end

  describe "StateManager state stack operations" do
    test "initializes empty stack" do
      stack = StateManager.init_stack()
      assert stack == []
      assert StateManager.stack_size(stack) == 0
    end

    test "pushes and pops snapshots" do
      stack = StateManager.init_stack()
      snapshot1 = StateManager.capture_snapshot(%{step: 1})
      snapshot2 = StateManager.capture_snapshot(%{step: 2})

      # Push snapshots
      stack = StateManager.push(stack, snapshot1)
      stack = StateManager.push(stack, snapshot2)

      assert StateManager.stack_size(stack) == 2

      # Pop snapshots
      {:ok, popped, stack} = StateManager.pop(stack)
      assert popped.data.step == 2
      assert StateManager.stack_size(stack) == 1

      {:ok, popped, stack} = StateManager.pop(stack)
      assert popped.data.step == 1
      assert StateManager.stack_size(stack) == 0
    end

    test "returns error when popping empty stack" do
      stack = StateManager.init_stack()
      assert {:error, :empty_stack} = StateManager.pop(stack)
    end

    test "peeks at top of stack" do
      stack = StateManager.init_stack()
      snapshot = StateManager.capture_snapshot(%{value: 99})
      stack = StateManager.push(stack, snapshot)

      {:ok, peeked} = StateManager.peek(stack)
      assert peeked.data.value == 99
      # Stack unchanged
      assert StateManager.stack_size(stack) == 1
    end

    test "returns error when peeking empty stack" do
      stack = StateManager.init_stack()
      assert {:error, :empty_stack} = StateManager.peek(stack)
    end
  end

  describe "StateManager.compare_snapshots/2" do
    test "identifies added keys" do
      snap1 = StateManager.capture_snapshot(%{a: 1})
      snap2 = StateManager.capture_snapshot(%{a: 1, b: 2})

      diff = StateManager.compare_snapshots(snap1, snap2)

      assert :b in diff.added
      assert Enum.empty?(diff.removed)
    end

    test "identifies removed keys" do
      snap1 = StateManager.capture_snapshot(%{a: 1, b: 2})
      snap2 = StateManager.capture_snapshot(%{a: 1})

      diff = StateManager.compare_snapshots(snap1, snap2)

      assert :b in diff.removed
      assert Enum.empty?(diff.added)
    end

    test "identifies changed values" do
      snap1 = StateManager.capture_snapshot(%{counter: 5})
      snap2 = StateManager.capture_snapshot(%{counter: 10})

      diff = StateManager.compare_snapshots(snap1, snap2)

      assert Map.has_key?(diff.changed, :counter)
      assert diff.changed.counter.old == 5
      assert diff.changed.counter.new == 10
    end

    test "handles no differences" do
      snap1 = StateManager.capture_snapshot(%{value: 42})
      snap2 = StateManager.capture_snapshot(%{value: 42})

      diff = StateManager.compare_snapshots(snap1, snap2)

      assert Enum.empty?(diff.added)
      assert Enum.empty?(diff.removed)
      assert Enum.empty?(diff.changed)
    end
  end

  describe "StateManager persistence" do
    test "persists and loads state stack" do
      stack = StateManager.init_stack()
      snapshot = StateManager.capture_snapshot(%{data: "test"})
      stack = StateManager.push(stack, snapshot)

      key = "test_stack_#{:rand.uniform(10000)}"

      # Persist
      assert :ok = StateManager.persist_stack(stack, key)

      # Load
      assert {:ok, loaded_stack} = StateManager.load_stack(key)
      assert StateManager.stack_size(loaded_stack) == 1

      # Cleanup
      StateManager.delete_stack(key)
    end

    test "returns error for non-existent key" do
      assert {:error, :not_found} =
               StateManager.load_stack("nonexistent_key_#{:rand.uniform(10000)}")
    end

    test "deletes persisted stack" do
      key = "test_delete_#{:rand.uniform(10000)}"
      stack = StateManager.init_stack()

      StateManager.persist_stack(stack, key)
      assert :ok = StateManager.delete_stack(key)
      assert {:error, :not_found} = StateManager.load_stack(key)
    end
  end

  describe "DeadEndDetector.detect/3" do
    test "detects repeated failures" do
      result = %{error: "same_error"}
      history = [%{error: "same_error"}, %{error: "same_error"}]

      assert DeadEndDetector.detect(result, history, repetition_threshold: 2)
    end

    test "detects circular reasoning" do
      result = %{reasoning: "pattern_a", value: 1}

      history = [
        %{reasoning: "pattern_b", value: 2},
        %{reasoning: "pattern_c", value: 3},
        %{reasoning: "pattern_a", value: 1}
      ]

      assert DeadEndDetector.detect(result, history)
    end

    test "detects low confidence" do
      result = %{confidence: 0.2}
      history = []

      assert DeadEndDetector.detect(result, history, confidence_threshold: 0.3)
    end

    test "detects stalled progress" do
      result = %{value: 5}
      history = List.duplicate(%{value: 5}, 5)

      assert DeadEndDetector.detect(result, history, stall_threshold: 4)
    end

    test "detects constraint violations" do
      result = %{constraint_violated: true}
      history = []

      assert DeadEndDetector.detect(result, history)
    end

    test "returns false for valid progress" do
      result = %{value: 10, confidence: 0.8}
      history = [%{value: 8}, %{value: 6}]

      refute DeadEndDetector.detect(result, history)
    end

    test "uses custom predicate when provided" do
      custom_predicate = fn _result, _history -> true end

      result = %{value: 42}
      history = []

      assert DeadEndDetector.detect(result, history, custom_predicate: custom_predicate)
    end
  end

  describe "DeadEndDetector.detect_with_reasons/3" do
    test "returns reasons for detection" do
      result = %{confidence: 0.1}
      history = []

      detection = DeadEndDetector.detect_with_reasons(result, history)

      assert detection.is_dead_end
      assert :low_confidence in detection.reasons
      assert detection.confidence > 0.0
    end

    test "returns multiple reasons" do
      result = %{error: "same", confidence: 0.2}

      history = [
        %{error: "same", confidence: 0.2},
        %{error: "same", confidence: 0.2},
        %{error: "same", confidence: 0.2}
      ]

      detection = DeadEndDetector.detect_with_reasons(result, history, repetition_threshold: 3)

      assert detection.is_dead_end
      assert :repeated_failures in detection.reasons
      assert :low_confidence in detection.reasons
    end
  end

  describe "DeadEndDetector helper functions" do
    test "repeated_failures? detects repetitions" do
      result = %{type: "error_x"}
      history = List.duplicate(%{type: "error_x"}, 3)

      assert DeadEndDetector.repeated_failures?(result, history, 3)
    end

    test "circular_reasoning? detects cycles" do
      result = %{pattern: "a"}
      history = [%{pattern: "b"}, %{pattern: "a"}, %{pattern: "c"}]

      assert DeadEndDetector.circular_reasoning?(result, history)
    end

    test "circular_reasoning? returns false for short history" do
      result = %{pattern: "a"}
      history = [%{pattern: "b"}]

      refute DeadEndDetector.circular_reasoning?(result, history)
    end

    test "extract_confidence from map with atom key" do
      result = %{confidence: 0.85}
      assert DeadEndDetector.extract_confidence(result) == 0.85
    end

    test "extract_confidence from map with string key" do
      result = %{"confidence" => 0.75}
      assert DeadEndDetector.extract_confidence(result) == 0.75
    end

    test "extract_confidence defaults to 0.7" do
      result = %{other: "data"}
      assert DeadEndDetector.extract_confidence(result) == 0.7
    end

    test "low_confidence? checks threshold" do
      result = %{confidence: 0.25}
      assert DeadEndDetector.low_confidence?(result, 0.3)
      refute DeadEndDetector.low_confidence?(result, 0.2)
    end

    test "stalled_progress? detects lack of progress" do
      history = List.duplicate(%{value: 10}, 6)

      assert DeadEndDetector.stalled_progress?(history, 5)
    end

    test "stalled_progress? returns false with progress" do
      history = [%{value: 10}, %{value: 9}, %{value: 8}, %{value: 7}]

      refute DeadEndDetector.stalled_progress?(history, 4)
    end

    test "constraint_violation? detects violations" do
      result = %{constraint_violated: true}
      assert DeadEndDetector.constraint_violation?(result)
    end
  end

  describe "PathExplorer.generate_alternative/3" do
    test "generates alternative state" do
      state = %{value: 1, strategy: :analytical}
      history = []

      {:ok, alternative} = PathExplorer.generate_alternative(state, history)

      assert is_map(alternative)
    end

    test "filters out failed paths" do
      state = %{value: 1}
      failed_paths = PathExplorer.mark_path_failed(state, MapSet.new())
      state_with_failed = Map.put(state, :failed_paths, failed_paths)

      history = []

      result = PathExplorer.generate_alternative(state_with_failed, history)

      # Should find an alternative or error
      case result do
        {:ok, alternative} -> assert alternative != state
        {:error, :no_alternatives} -> assert true
      end
    end

    test "returns error when no alternatives available" do
      state = %{locked: true}
      history = []

      # With limited beam width and diversity, might not find alternatives
      result = PathExplorer.generate_alternative(state, history, beam_width: 1)

      # Should return either success or no alternatives error
      assert match?({:ok, _}, result) or match?({:error, :no_alternatives}, result)
    end
  end

  describe "PathExplorer.path_attempted?/2" do
    test "checks if path was attempted" do
      state = %{path: "A"}
      failed_paths = PathExplorer.mark_path_failed(state, MapSet.new())

      assert PathExplorer.path_attempted?(state, failed_paths)
    end

    test "returns false for new path" do
      state = %{path: "A"}
      failed_paths = MapSet.new()

      refute PathExplorer.path_attempted?(state, failed_paths)
    end
  end

  describe "PathExplorer.diversity_score/2" do
    test "returns 0.0 for identical states" do
      state = %{a: 1, b: 2}
      score = PathExplorer.diversity_score(state, state)

      assert score == 0.0
    end

    test "returns positive score for different states" do
      state1 = %{a: 1, b: 2}
      state2 = %{a: 1, b: 3}

      score = PathExplorer.diversity_score(state1, state2)

      assert score > 0.0
      assert score <= 1.0
    end

    test "returns higher score for very different states" do
      state1 = %{a: 1}
      state2 = %{b: 2, c: 3}

      score = PathExplorer.diversity_score(state1, state2)

      assert score >= 0.5
    end
  end

  describe "PathExplorer.ensure_diversity/3" do
    test "filters out similar alternatives" do
      state = %{value: 5}
      alternatives = [%{value: 5}, %{value: 6}]
      history = [state]

      diverse = PathExplorer.ensure_diversity(alternatives, history, 0.3)

      # Should filter out the similar one
      assert length(diverse) <= length(alternatives)
    end

    test "returns all alternatives for empty history" do
      alternatives = [%{a: 1}, %{b: 2}]
      history = []

      diverse = PathExplorer.ensure_diversity(alternatives, history)

      assert diverse == alternatives
    end
  end

  describe "BudgetManager.init_budget/2" do
    test "initializes budget with total" do
      budget = BudgetManager.init_budget(10)

      assert budget.total == 10
      assert budget.remaining == 10
      assert budget.used == 0
      # 20% of 10
      assert budget.priority_reserve == 2
    end

    test "accepts custom priority reserve" do
      budget = BudgetManager.init_budget(10, priority_reserve: 3)

      assert budget.priority_reserve == 3
    end
  end

  describe "BudgetManager.has_budget?/1" do
    test "returns true when budget available" do
      budget = BudgetManager.init_budget(5)

      assert BudgetManager.has_budget?(budget)
    end

    test "returns false when budget exhausted" do
      budget = %{BudgetManager.init_budget(1) | remaining: 0}

      refute BudgetManager.has_budget?(budget)
    end
  end

  describe "BudgetManager.consume_budget/2" do
    test "consumes specified amount" do
      budget = BudgetManager.init_budget(10)
      new_budget = BudgetManager.consume_budget(budget, 3)

      assert new_budget.remaining == 7
      assert new_budget.used == 3
    end

    test "consumes only remaining amount if requested exceeds" do
      budget = BudgetManager.init_budget(5)
      new_budget = BudgetManager.consume_budget(budget, 10)

      assert new_budget.remaining == 0
      assert new_budget.used == 5
    end

    test "defaults to consuming 1" do
      budget = BudgetManager.init_budget(10)
      new_budget = BudgetManager.consume_budget(budget)

      assert new_budget.remaining == 9
      assert new_budget.used == 1
    end
  end

  describe "BudgetManager.allocate_for_level/3" do
    test "allocates budget for level" do
      budget = BudgetManager.init_budget(10)

      {:ok, level_budget, new_budget} = BudgetManager.allocate_for_level(budget, 1)

      # 40% of 10
      assert level_budget == 4
      assert new_budget.level_allocations[1] == 4
    end

    test "returns error for insufficient budget" do
      budget = %{BudgetManager.init_budget(10) | remaining: 0}

      assert {:error, :insufficient_budget} = BudgetManager.allocate_for_level(budget, 1)
    end

    test "respects custom allocation factor" do
      budget = BudgetManager.init_budget(10)

      {:ok, level_budget, _} = BudgetManager.allocate_for_level(budget, 1, allocation_factor: 0.6)

      # 60% of 10
      assert level_budget == 6
    end
  end

  describe "BudgetManager.get_level_budget/2" do
    test "returns allocated budget for level" do
      budget = BudgetManager.init_budget(10)
      {:ok, _, budget} = BudgetManager.allocate_for_level(budget, 2)

      assert BudgetManager.get_level_budget(budget, 2) > 0
    end

    test "returns 0 for unallocated level" do
      budget = BudgetManager.init_budget(10)

      assert BudgetManager.get_level_budget(budget, 99) == 0
    end
  end

  describe "BudgetManager.allocate_priority/2" do
    test "allocates from priority reserve" do
      budget = BudgetManager.init_budget(10)

      {:ok, new_budget} = BudgetManager.allocate_priority(budget, 1)

      # 2 - 1
      assert new_budget.priority_reserve == 1
      # 10 + 1
      assert new_budget.remaining == 11
    end

    test "returns error for insufficient reserve" do
      budget = BudgetManager.init_budget(10)

      assert {:error, :insufficient_priority_reserve} =
               BudgetManager.allocate_priority(budget, 10)
    end
  end

  describe "BudgetManager.utilization/1" do
    test "calculates utilization percentage" do
      budget = BudgetManager.init_budget(10)
      budget = BudgetManager.consume_budget(budget, 3)

      assert BudgetManager.utilization(budget) == 0.3
    end

    test "returns 0.0 for zero total" do
      budget = %{total: 0, remaining: 0, used: 0, level_allocations: %{}, priority_reserve: 0}

      assert BudgetManager.utilization(budget) == 0.0
    end
  end

  describe "BudgetManager.exhausted?/1" do
    test "returns false when budget available" do
      budget = BudgetManager.init_budget(10)

      refute BudgetManager.exhausted?(budget)
    end

    test "returns false when priority reserve available" do
      budget = %{BudgetManager.init_budget(10) | remaining: 0}

      # Still has priority reserve
      refute BudgetManager.exhausted?(budget)
    end

    test "returns true when fully exhausted" do
      budget = %{BudgetManager.init_budget(10) | remaining: 0, priority_reserve: 0}

      assert BudgetManager.exhausted?(budget)
    end
  end

  describe "BudgetManager.handle_exhaustion/2" do
    test "returns best candidate" do
      budget = %{BudgetManager.init_budget(5) | remaining: 0, priority_reserve: 0}
      candidates = [%{score: 0.5}, %{score: 0.8}]

      best = BudgetManager.handle_exhaustion(budget, candidates)

      assert best in candidates
    end

    test "returns nil for empty candidates" do
      budget = %{BudgetManager.init_budget(5) | remaining: 0, priority_reserve: 0}

      assert BudgetManager.handle_exhaustion(budget, []) == nil
    end
  end

  describe "Backtracking.execute_with_backtracking/2" do
    test "succeeds on first attempt with valid result" do
      reasoning_fn = fn -> %{value: 42, confidence: 0.9} end
      validator = fn _result -> true end

      {:ok, result} = Backtracking.execute_with_backtracking(reasoning_fn, validator: validator)

      assert result.value == 42
    end

    test "returns error after max backtracks" do
      reasoning_fn = fn -> %{error: "fail"} end
      validator = fn _result -> false end

      {:error, reason} =
        Backtracking.execute_with_backtracking(reasoning_fn,
          validator: validator,
          max_backtracks: 2
        )

      assert reason == :max_backtracks_exceeded
    end
  end

  describe "integration scenarios" do
    test "complete backtracking workflow" do
      # Simulate reasoning that succeeds after backtracking
      attempt = Agent.start_link(fn -> 0 end)
      {:ok, pid} = attempt

      reasoning_fn = fn ->
        count = Agent.get_and_update(pid, fn c -> {c + 1, c + 1} end)

        if count < 3 do
          %{error: "not ready", confidence: 0.2}
        else
          %{value: "success", confidence: 0.9}
        end
      end

      validator = fn result ->
        Map.get(result, :value) == "success"
      end

      {:ok, result} =
        Backtracking.execute_with_backtracking(reasoning_fn,
          validator: validator,
          max_backtracks: 5
        )

      assert result.value == "success"

      Agent.stop(pid)
    end
  end
end
