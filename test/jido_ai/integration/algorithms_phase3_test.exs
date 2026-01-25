defmodule Jido.AI.Integration.AlgorithmsPhase3Test do
  @moduledoc """
  Integration tests for Phase 3 Algorithm Framework.

  These tests verify that all Phase 3 components work together correctly,
  including algorithm composition, error propagation, and performance
  characteristics.
  """
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.{Composite, Hybrid, Parallel, Sequential}

  # ============================================================================
  # Test Algorithm Implementations
  # ============================================================================

  defmodule AddAlgorithm do
    @moduledoc "Adds a value to input"
    use Jido.AI.Algorithms.Base,
      name: "add",
      description: "Adds a configurable value"

    @impl true
    def execute(input, context) do
      amount = Map.get(context, :add_amount, 1)
      {:ok, Map.update(input, :value, amount, &(&1 + amount))}
    end
  end

  defmodule MultiplyAlgorithm do
    @moduledoc "Multiplies input value"
    use Jido.AI.Algorithms.Base,
      name: "multiply",
      description: "Multiplies by a configurable value"

    @impl true
    def execute(input, context) do
      factor = Map.get(context, :multiply_factor, 2)
      {:ok, Map.update(input, :value, 0, &(&1 * factor))}
    end
  end

  defmodule FetchDataAlgorithm do
    @moduledoc "Fetches named data"
    use Jido.AI.Algorithms.Base,
      name: "fetch_data",
      description: "Fetches data with configurable key"

    @impl true
    def execute(input, context) do
      key = Map.get(context, :data_key, :data)
      value = Map.get(context, :data_value, "fetched")
      {:ok, Map.put(input, key, value)}
    end
  end

  defmodule SlowAlgorithm do
    @moduledoc "Simulates slow operation"
    use Jido.AI.Algorithms.Base,
      name: "slow",
      description: "Takes time to execute"

    @impl true
    def execute(input, context) do
      delay = Map.get(context, :delay, 100)
      Process.sleep(delay)
      {:ok, Map.put(input, :slow_completed, true)}
    end
  end

  defmodule ErrorAlgorithm do
    @moduledoc "Always fails with configurable error"
    use Jido.AI.Algorithms.Base,
      name: "error",
      description: "Fails with configurable error"

    @impl true
    def execute(_input, context) do
      reason = Map.get(context, :error_reason, :intentional_error)
      {:error, reason}
    end
  end

  defmodule ConditionalErrorAlgorithm do
    @moduledoc "Fails only when condition is met"
    use Jido.AI.Algorithms.Base,
      name: "conditional_error",
      description: "Fails based on input condition"

    @impl true
    def execute(input, context) do
      if Map.get(input, :should_fail, false) do
        reason = Map.get(context, :error_reason, :conditional_error)
        {:error, reason}
      else
        {:ok, Map.put(input, :conditional_passed, true)}
      end
    end
  end

  defmodule RetryableAlgorithm do
    @moduledoc "Succeeds after N attempts"
    use Jido.AI.Algorithms.Base,
      name: "retryable",
      description: "Fails first N-1 times, then succeeds"

    @impl true
    def execute(input, _context) do
      attempts_key = :retry_attempts
      current = Map.get(input, attempts_key, 0) + 1
      max_failures = Map.get(input, :max_failures, 2)

      input = Map.put(input, attempts_key, current)

      if current <= max_failures do
        {:error, {:attempt_failed, current}}
      else
        {:ok, Map.put(input, :retry_succeeded, true)}
      end
    end
  end

  defmodule CounterAlgorithm do
    @moduledoc "Increments a counter in process dictionary for tracking"
    use Jido.AI.Algorithms.Base,
      name: "counter",
      description: "Tracks execution count"

    @impl true
    def execute(input, context) do
      counter_key = Map.get(context, :counter_key, :default_counter)
      current = Process.get(counter_key, 0)
      Process.put(counter_key, current + 1)
      {:ok, Map.put(input, :counter_value, current + 1)}
    end
  end

  # ============================================================================
  # Algorithm Composition Integration Tests
  # ============================================================================

  describe "algorithm composition integration" do
    test "sequential of parallel algorithms" do
      # Stage 1: Parallel fetch of multiple data sources
      # Stage 2: Sequential processing of combined data

      input = %{value: 10}

      # Use Hybrid to run parallel then sequential
      context = %{
        stages: [
          %{
            algorithms: [
              # These will be executed in parallel
              FetchDataAlgorithm,
              FetchDataAlgorithm
            ],
            mode: :parallel,
            merge_strategy: :merge_maps
          },
          %{
            algorithms: [AddAlgorithm, MultiplyAlgorithm],
            mode: :sequential
          }
        ]
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      # Value: (10 + 1) * 2 = 22
      assert result.value == 22
      # Should also have data from parallel stage
      assert Map.has_key?(result, :data)
    end

    test "parallel of sequential algorithms using Composite" do
      # Run two sequential pipelines in parallel

      seq1 = Composite.sequence([AddAlgorithm, MultiplyAlgorithm])
      seq2 = Composite.sequence([MultiplyAlgorithm, AddAlgorithm])

      parallel = Composite.parallel([seq1, seq2], merge_strategy: :collect)

      input = %{value: 5}

      assert {:ok, results} = Composite.execute_composite(parallel, input, %{})
      assert is_list(results)
      assert length(results) == 2

      # Seq1: (5 + 1) * 2 = 12
      # Seq2: (5 * 2) + 1 = 11
      values = Enum.map(results, & &1.value)
      assert Enum.sort(values) == [11, 12]
    end

    test "complex nested compositions" do
      # Build a complex workflow:
      # 1. Validate (conditional)
      # 2. Choice based on input
      # 3. Parallel fetch
      # 4. Sequential processing

      workflow =
        Composite.sequence([
          # Step 1: Add one (validation placeholder)
          AddAlgorithm,

          # Step 2: Choice - if value > 5, multiply; else add again
          Composite.choice(
            fn input -> input.value > 5 end,
            MultiplyAlgorithm,
            AddAlgorithm
          ),

          # Step 3: Parallel fetch (using two fetch algorithms)
          Composite.parallel([FetchDataAlgorithm, FetchDataAlgorithm]),

          # Step 4: Final multiply
          MultiplyAlgorithm
        ])

      # Starting with 5: 5 + 1 = 6, 6 > 5 so multiply: 12, fetch (no value change), 12 * 2 = 24
      assert {:ok, result} = Composite.execute_composite(workflow, %{value: 5}, %{})
      assert result.value == 24

      # Starting with 3: 3 + 1 = 4, 4 <= 5 so add: 5, fetch, 5 * 2 = 10
      assert {:ok, result2} = Composite.execute_composite(workflow, %{value: 3}, %{})
      assert result2.value == 10
    end

    test "hybrid stages with composite algorithms" do
      # Hybrid with composite algorithms as stage members

      input = %{value: 2}

      # Create a composite that doubles and adds
      double_and_add = Composite.compose(MultiplyAlgorithm, AddAlgorithm)

      # Note: Hybrid expects modules, not composite structs, so we use Composite
      # for nested workflows instead
      # This test verifies the pattern - use Composite for nested workflows
      composite_workflow =
        Composite.sequence([
          double_and_add,
          Composite.parallel([AddAlgorithm, MultiplyAlgorithm])
        ])

      # 2 * 2 = 4, 4 + 1 = 5, then parallel (both get 5): merge results
      assert {:ok, result} = Composite.execute_composite(composite_workflow, input, %{})
      # Parallel merges: AddAlgorithm gives value: 6, MultiplyAlgorithm gives value: 10
      # Last one wins in merge_maps
      assert result.value == 10
    end

    test "deeply nested composition with all algorithm types" do
      # Test a very deep nesting to ensure no stack issues

      inner_seq = Composite.sequence([AddAlgorithm, AddAlgorithm])
      inner_parallel = Composite.parallel([FetchDataAlgorithm])
      inner_choice = Composite.choice(fn _ -> true end, AddAlgorithm, MultiplyAlgorithm)
      inner_repeat = Composite.repeat(AddAlgorithm, times: 2)

      middle =
        Composite.sequence([
          inner_seq,
          inner_parallel,
          inner_choice,
          inner_repeat
        ])

      outer =
        Composite.compose(
          Composite.when_cond(fn _ -> true end, middle),
          MultiplyAlgorithm
        )

      # 0 -> seq(+1,+1)=2 -> parallel(fetch) -> choice(+1)=3 -> repeat(+1,+1)=5 -> *2=10
      assert {:ok, result} = Composite.execute_composite(outer, %{value: 0}, %{})
      assert result.value == 10
    end
  end

  # ============================================================================
  # Error Propagation Integration Tests
  # ============================================================================

  describe "error propagation integration" do
    test "error in sequential stops chain" do
      input = %{value: 5}

      context = %{
        algorithms: [AddAlgorithm, ErrorAlgorithm, MultiplyAlgorithm]
      }

      assert {:error, error} = Sequential.execute(input, context)
      assert error.reason == :intentional_error
      assert error.step_index == 1
    end

    test "error in parallel with fail_fast" do
      input = %{value: 5}

      context = %{
        algorithms: [AddAlgorithm, ErrorAlgorithm, MultiplyAlgorithm],
        error_mode: :fail_fast
      }

      assert {:error, :intentional_error} = Parallel.execute(input, context)
    end

    test "error in parallel with collect_errors" do
      input = %{value: 5}

      context = %{
        algorithms: [AddAlgorithm, ErrorAlgorithm, MultiplyAlgorithm],
        error_mode: :collect_errors
      }

      assert {:error, %{errors: errors, successful: successes}} = Parallel.execute(input, context)
      assert length(errors) == 1
      assert length(successes) == 2
    end

    test "error in parallel with ignore_errors" do
      input = %{value: 5}

      context = %{
        algorithms: [AddAlgorithm, ErrorAlgorithm, MultiplyAlgorithm],
        error_mode: :ignore_errors
      }

      assert {:ok, result} = Parallel.execute(input, context)
      # AddAlgorithm: value 6, MultiplyAlgorithm: value 10 - last wins
      assert result.value == 10
    end

    test "fallback execution on error in hybrid" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ErrorAlgorithm], mode: :sequential}
        ],
        fallbacks: %{
          ErrorAlgorithm => %{fallbacks: [AddAlgorithm]}
        }
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.value == 6
    end

    test "multiple fallback levels" do
      input = %{value: 5}

      context = %{
        stages: [
          %{algorithms: [ErrorAlgorithm], mode: :sequential}
        ],
        fallbacks: %{
          ErrorAlgorithm => %{fallbacks: [ErrorAlgorithm, ErrorAlgorithm, AddAlgorithm]}
        }
      }

      assert {:ok, result} = Hybrid.execute(input, context)
      assert result.value == 6
    end

    test "error propagation through nested composite" do
      workflow =
        Composite.sequence([
          AddAlgorithm,
          Composite.choice(
            fn input -> input.value > 5 end,
            ErrorAlgorithm,
            AddAlgorithm
          ),
          MultiplyAlgorithm
        ])

      # Value 5 + 1 = 6 > 5, so ErrorAlgorithm is chosen
      assert {:error, :intentional_error} = Composite.execute_composite(workflow, %{value: 5}, %{})

      # Value 3 + 1 = 4 <= 5, so AddAlgorithm is chosen, continues to multiply
      assert {:ok, result} = Composite.execute_composite(workflow, %{value: 3}, %{})
      # (3 + 1 + 1) * 2
      assert result.value == 10
    end

    test "error in repeat stops iteration" do
      workflow = Composite.repeat(ConditionalErrorAlgorithm, times: 5)

      # First iteration fails
      assert {:error, :conditional_error} =
               Composite.execute_composite(workflow, %{should_fail: true}, %{})

      # All iterations succeed when condition is false
      assert {:ok, result} =
               Composite.execute_composite(workflow, %{should_fail: false}, %{})

      assert result.conditional_passed == true
    end
  end

  # ============================================================================
  # Performance Integration Tests
  # ============================================================================

  describe "performance integration" do
    test "parallel speedup vs sequential" do
      # Run 4 slow algorithms - parallel should be faster than sequential
      delay = 50

      slow_context = %{delay: delay}

      algorithms = [SlowAlgorithm, SlowAlgorithm, SlowAlgorithm, SlowAlgorithm]

      # Sequential timing
      seq_start = System.monotonic_time(:millisecond)
      {:ok, _} = Sequential.execute(%{}, Map.put(slow_context, :algorithms, algorithms))
      seq_duration = System.monotonic_time(:millisecond) - seq_start

      # Parallel timing
      par_start = System.monotonic_time(:millisecond)
      {:ok, _} = Parallel.execute(%{}, Map.put(slow_context, :algorithms, algorithms))
      par_duration = System.monotonic_time(:millisecond) - par_start

      # Parallel should be at least 2x faster (with 4 concurrent tasks)
      # Allow some margin for test environment variance
      assert par_duration < seq_duration,
             "Parallel (#{par_duration}ms) should be faster than sequential (#{seq_duration}ms)"
    end

    test "concurrency limits respected" do
      # Track concurrent execution count
      test_pid = self()

      defmodule ConcurrencyTracker do
        use Jido.AI.Algorithms.Base,
          name: "concurrency_tracker",
          description: "Tracks concurrent executions"

        @impl true
        def execute(input, context) do
          tracker_pid = context.tracker_pid
          send(tracker_pid, {:started, self()})
          Process.sleep(50)
          send(tracker_pid, {:finished, self()})
          {:ok, input}
        end
      end

      algorithms = List.duplicate(ConcurrencyTracker, 10)

      context = %{
        algorithms: algorithms,
        max_concurrency: 2,
        tracker_pid: test_pid,
        timeout: 10_000
      }

      # Start parallel execution in a separate process
      task = Task.async(fn -> Parallel.execute(%{}, context) end)

      # Collect messages to verify max concurrent
      messages = collect_concurrency_messages(20)

      Task.await(task, 15_000)

      # Analyze concurrency - at any point, should have at most 2 concurrent
      max_concurrent = calculate_max_concurrent(messages)

      assert max_concurrent <= 2,
             "Max concurrent (#{max_concurrent}) should not exceed limit (2)"
    end

    test "timeout handling across compositions" do
      defmodule TimeoutAlgorithm do
        use Jido.AI.Algorithms.Base,
          name: "timeout",
          description: "Takes too long"

        @impl true
        def execute(_input, _context) do
          Process.sleep(5_000)
          {:ok, %{completed: true}}
        end
      end

      context = %{
        algorithms: [TimeoutAlgorithm],
        timeout: 100
      }

      assert {:error, :timeout} = Parallel.execute(%{}, context)
    end

    test "resource cleanup on failure in parallel" do
      # Verify that failed tasks don't leave orphaned processes
      initial_process_count = length(Process.list())

      defmodule FailingWithCleanup do
        use Jido.AI.Algorithms.Base,
          name: "failing_cleanup",
          description: "Fails but should cleanup"

        @impl true
        def execute(_input, _context) do
          Process.sleep(10)
          {:error, :cleanup_test}
        end
      end

      context = %{
        algorithms: List.duplicate(FailingWithCleanup, 10),
        error_mode: :fail_fast
      }

      {:error, _} = Parallel.execute(%{}, context)

      # Give time for cleanup
      Process.sleep(50)

      final_process_count = length(Process.list())

      # Should not have significant process leak (allow small variance)
      assert final_process_count <= initial_process_count + 5,
             "Process count increased by #{final_process_count - initial_process_count}"
    end

    test "hybrid stage execution maintains order" do
      # Verify stages execute in order - use Composite for better control

      input = %{execution_order: []}

      defmodule OrderTracker1 do
        use Jido.AI.Algorithms.Base,
          name: "order_tracker_1",
          description: "Tracks execution order - stage 1"

        @impl true
        def execute(input, _context) do
          order = Map.get(input, :execution_order, [])
          {:ok, Map.put(input, :execution_order, order ++ [:stage_1])}
        end
      end

      defmodule OrderTracker2 do
        use Jido.AI.Algorithms.Base,
          name: "order_tracker_2",
          description: "Tracks execution order - stage 2"

        @impl true
        def execute(input, _context) do
          order = Map.get(input, :execution_order, [])
          {:ok, Map.put(input, :execution_order, order ++ [:stage_2])}
        end
      end

      defmodule OrderTracker3 do
        use Jido.AI.Algorithms.Base,
          name: "order_tracker_3",
          description: "Tracks execution order - stage 3"

        @impl true
        def execute(input, _context) do
          order = Map.get(input, :execution_order, [])
          {:ok, Map.put(input, :execution_order, order ++ [:stage_3])}
        end
      end

      # Use Composite.sequence to ensure order
      workflow = Composite.sequence([OrderTracker1, OrderTracker2, OrderTracker3])

      assert {:ok, result} = Composite.execute_composite(workflow, input, %{})
      assert result.execution_order == [:stage_1, :stage_2, :stage_3]
    end
  end

  # ============================================================================
  # Cross-Module Integration Tests
  # ============================================================================

  describe "cross-module integration" do
    test "all algorithm types work together" do
      # Create a workflow that uses Sequential, Parallel, Hybrid, and Composite

      input = %{value: 1}

      # Sequential first
      {:ok, seq_result} = Sequential.execute(input, %{algorithms: [AddAlgorithm]})
      # 1 + 1 = 2
      assert seq_result.value == 2

      # Then Parallel - both algorithms run on the same input
      # MultiplyAlgorithm: value 2 * 2 = 4
      # FetchDataAlgorithm: adds :data key, value unchanged (2)
      # With merge_maps, the order of results depends on task completion
      # FetchDataAlgorithm result gets merged last so value stays 2
      {:ok, par_result} =
        Parallel.execute(seq_result, %{
          algorithms: [MultiplyAlgorithm, FetchDataAlgorithm],
          merge_strategy: :merge_maps
        })

      # FetchDataAlgorithm doesn't modify value, so it's still 2 after merge
      # (the last result in the merge wins, and FetchDataAlgorithm's value is 2)
      assert Map.has_key?(par_result, :data)

      # Then Hybrid - apply multiply to get to a known state
      {:ok, hybrid_result} =
        Hybrid.execute(par_result, %{
          stages: [
            %{algorithms: [MultiplyAlgorithm], mode: :sequential}
          ]
        })

      # Whatever value was * 2
      multiplied_value = hybrid_result.value

      # Finally Composite
      composite = Composite.sequence([AddAlgorithm])
      {:ok, final} = Composite.execute_composite(composite, hybrid_result, %{})
      # multiplied_value + 1
      assert final.value == multiplied_value + 1
    end

    test "telemetry events fire correctly across integrations" do
      ref = make_ref()
      pid = self()
      handler_id = "integration-test-#{inspect(ref)}"

      events = [
        [:jido, :ai, :algorithm, :sequential, :step, :start],
        [:jido, :ai, :algorithm, :sequential, :step, :stop],
        [:jido, :ai, :algorithm, :parallel, :start],
        [:jido, :ai, :algorithm, :parallel, :stop],
        [:jido, :ai, :algorithm, :hybrid, :start],
        [:jido, :ai, :algorithm, :hybrid, :stop],
        [:jido, :ai, :algorithm, :composite, :start],
        [:jido, :ai, :algorithm, :composite, :stop]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, _measurements, _metadata, _config ->
          send(pid, {:telemetry, event})
        end,
        nil
      )

      # Execute various algorithms
      Sequential.execute(%{value: 1}, %{algorithms: [AddAlgorithm]})
      Parallel.execute(%{value: 1}, %{algorithms: [AddAlgorithm]})
      Hybrid.execute(%{value: 1}, %{stages: [AddAlgorithm]})
      Composite.execute_composite(Composite.sequence([AddAlgorithm]), %{value: 1}, %{})

      :telemetry.detach(handler_id)

      # Verify we received telemetry for each type
      assert_received {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :start]}
      assert_received {:telemetry, [:jido, :ai, :algorithm, :parallel, :start]}
      assert_received {:telemetry, [:jido, :ai, :algorithm, :hybrid, :start]}
      assert_received {:telemetry, [:jido, :ai, :algorithm, :composite, :start]}
    end

    test "context is properly passed through all layers" do
      defmodule ContextChecker do
        use Jido.AI.Algorithms.Base,
          name: "context_checker",
          description: "Checks context values"

        @impl true
        def execute(input, context) do
          custom_value = Map.get(context, :custom_key, :not_found)
          {:ok, Map.put(input, :found_context, custom_value)}
        end
      end

      context = %{
        custom_key: :custom_value,
        algorithms: [ContextChecker]
      }

      # Sequential should pass context
      assert {:ok, result1} = Sequential.execute(%{}, context)
      assert result1.found_context == :custom_value

      # Parallel should pass context
      assert {:ok, result2} = Parallel.execute(%{}, context)
      assert result2.found_context == :custom_value

      # Hybrid should pass context
      hybrid_context = Map.put(context, :stages, [%{algorithms: [ContextChecker], mode: :sequential}])
      assert {:ok, result3} = Hybrid.execute(%{}, hybrid_context)
      assert result3.found_context == :custom_value

      # Composite should pass context
      composite = Composite.sequence([ContextChecker])
      assert {:ok, result4} = Composite.execute_composite(composite, %{}, context)
      assert result4.found_context == :custom_value
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp collect_concurrency_messages(count, acc \\ [])
  defp collect_concurrency_messages(0, acc), do: Enum.reverse(acc)

  defp collect_concurrency_messages(count, acc) do
    receive do
      msg -> collect_concurrency_messages(count - 1, [msg | acc])
    after
      5_000 -> Enum.reverse(acc)
    end
  end

  defp calculate_max_concurrent(messages) do
    messages
    |> Enum.reduce({0, 0}, fn
      {:started, _pid}, {current, max} -> {current + 1, max(current + 1, max)}
      {:finished, _pid}, {current, max} -> {current - 1, max}
    end)
    |> elem(1)
  end
end
