defmodule Jido.AI.Algorithms.ParallelTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.Parallel

  # ============================================================================
  # Test Algorithm Implementations
  # ============================================================================

  defmodule AlgorithmA do
    use Jido.AI.Algorithms.Base,
      name: "algorithm_a",
      description: "Returns :a value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :a, "value_a")}
    end
  end

  defmodule AlgorithmB do
    use Jido.AI.Algorithms.Base,
      name: "algorithm_b",
      description: "Returns :b value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :b, "value_b")}
    end
  end

  defmodule AlgorithmC do
    use Jido.AI.Algorithms.Base,
      name: "algorithm_c",
      description: "Returns :c value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :c, "value_c")}
    end
  end

  defmodule SlowAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "slow",
      description: "Takes time to execute"

    @impl true
    def execute(input, context) do
      delay = Map.get(context, :delay, 100)
      Process.sleep(delay)
      {:ok, Map.put(input, :slow, true)}
    end
  end

  defmodule ErrorAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "error",
      description: "Always fails"

    @impl true
    def execute(_input, _context) do
      {:error, :intentional_error}
    end
  end

  defmodule ConditionalAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "conditional",
      description: "Only executes for positive values"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :conditional, true)}
    end

    @impl true
    def can_execute?(input, _context) do
      Map.get(input, :value, 0) > 0
    end
  end

  defmodule NestedMapAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "nested",
      description: "Returns nested map"

    @impl true
    def execute(_input, context) do
      {:ok, %{nested: %{key: Map.get(context, :nested_value, "default")}}}
    end
  end

  defmodule RaisingAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "raising",
      description: "Raises exception"

    @impl true
    def execute(_input, _context) do
      raise "intentional exception"
    end
  end

  # ============================================================================
  # Module Setup Tests
  # ============================================================================

  describe "module setup" do
    test "uses Base correctly" do
      assert function_exported?(Parallel, :execute, 2)
      assert function_exported?(Parallel, :can_execute?, 2)
      assert function_exported?(Parallel, :metadata, 0)
    end

    test "metadata returns correct values" do
      metadata = Parallel.metadata()

      assert metadata.name == "parallel"
      assert metadata.description == "Executes algorithms concurrently and merges results"
    end
  end

  # ============================================================================
  # Execute Tests
  # ============================================================================

  describe "execute/2" do
    test "returns input unchanged for empty algorithm list" do
      input = %{value: 5}
      context = %{algorithms: []}

      assert {:ok, ^input} = Parallel.execute(input, context)
    end

    test "returns input unchanged when algorithms key is missing" do
      input = %{value: 5}
      context = %{}

      assert {:ok, ^input} = Parallel.execute(input, context)
    end

    test "executes single algorithm" do
      input = %{initial: true}
      context = %{algorithms: [AlgorithmA]}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.initial == true
      assert result.a == "value_a"
    end

    test "executes multiple algorithms concurrently" do
      input = %{initial: true}
      context = %{algorithms: [AlgorithmA, AlgorithmB, AlgorithmC]}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.initial == true
      assert result.a == "value_a"
      assert result.b == "value_b"
      assert result.c == "value_c"
    end

    test "algorithms receive the same input" do
      input = %{shared: "data"}
      context = %{algorithms: [AlgorithmA, AlgorithmB]}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.shared == "data"
    end
  end

  # ============================================================================
  # Merge Strategy Tests
  # ============================================================================

  describe "merge_strategy: :merge_maps" do
    test "merges result maps" do
      input = %{}
      context = %{algorithms: [AlgorithmA, AlgorithmB], merge_strategy: :merge_maps}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.a == "value_a"
      assert result.b == "value_b"
    end

    test "deep merges nested maps" do
      defmodule NestedA do
        use Jido.AI.Algorithms.Base, name: "nested_a", description: "Nested A"

        @impl true
        def execute(_input, _context) do
          {:ok, %{config: %{a: 1, shared: "from_a"}}}
        end
      end

      defmodule NestedB do
        use Jido.AI.Algorithms.Base, name: "nested_b", description: "Nested B"

        @impl true
        def execute(_input, _context) do
          {:ok, %{config: %{b: 2, shared: "from_b"}}}
        end
      end

      input = %{}
      context = %{algorithms: [NestedA, NestedB], merge_strategy: :merge_maps}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.config.a == 1
      assert result.config.b == 2
      # Later result wins
      assert result.config.shared == "from_b"
    end

    test "is the default strategy" do
      input = %{}
      context = %{algorithms: [AlgorithmA, AlgorithmB]}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.a == "value_a"
      assert result.b == "value_b"
    end
  end

  describe "merge_strategy: :collect" do
    test "returns list of results" do
      input = %{initial: true}
      context = %{algorithms: [AlgorithmA, AlgorithmB], merge_strategy: :collect}

      assert {:ok, results} = Parallel.execute(input, context)
      assert is_list(results)
      assert length(results) == 2
    end

    test "preserves order" do
      input = %{}
      context = %{algorithms: [AlgorithmA, AlgorithmB, AlgorithmC], merge_strategy: :collect}

      assert {:ok, results} = Parallel.execute(input, context)
      assert Enum.at(results, 0).a == "value_a"
      assert Enum.at(results, 1).b == "value_b"
      assert Enum.at(results, 2).c == "value_c"
    end
  end

  describe "merge_strategy: custom function" do
    test "uses custom merge function" do
      input = %{}

      merge_fn = fn results ->
        %{combined_keys: Enum.flat_map(results, &Map.keys/1) |> Enum.uniq()}
      end

      context = %{algorithms: [AlgorithmA, AlgorithmB], merge_strategy: merge_fn}

      assert {:ok, result} = Parallel.execute(input, context)
      assert :a in result.combined_keys
      assert :b in result.combined_keys
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "error_mode: :fail_fast" do
    test "returns first error encountered" do
      input = %{}
      context = %{algorithms: [AlgorithmA, ErrorAlgorithm, AlgorithmB], error_mode: :fail_fast}

      assert {:error, :intentional_error} = Parallel.execute(input, context)
    end

    test "is the default error mode" do
      input = %{}
      context = %{algorithms: [ErrorAlgorithm]}

      assert {:error, :intentional_error} = Parallel.execute(input, context)
    end

    test "returns success if no errors" do
      input = %{}
      context = %{algorithms: [AlgorithmA, AlgorithmB], error_mode: :fail_fast}

      assert {:ok, _result} = Parallel.execute(input, context)
    end
  end

  describe "error_mode: :collect_errors" do
    test "returns all errors" do
      defmodule ErrorA do
        use Jido.AI.Algorithms.Base, name: "error_a", description: "Error A"

        @impl true
        def execute(_input, _context), do: {:error, :error_a}
      end

      defmodule ErrorB do
        use Jido.AI.Algorithms.Base, name: "error_b", description: "Error B"

        @impl true
        def execute(_input, _context), do: {:error, :error_b}
      end

      input = %{}
      context = %{algorithms: [ErrorA, ErrorB], error_mode: :collect_errors}

      assert {:error, error_info} = Parallel.execute(input, context)
      assert :error_a in error_info.errors
      assert :error_b in error_info.errors
    end

    test "includes successful results with errors" do
      input = %{}
      context = %{algorithms: [AlgorithmA, ErrorAlgorithm], error_mode: :collect_errors}

      assert {:error, error_info} = Parallel.execute(input, context)
      assert :intentional_error in error_info.errors
      assert length(error_info.successful) == 1
    end

    test "returns success if no errors" do
      input = %{}
      context = %{algorithms: [AlgorithmA, AlgorithmB], error_mode: :collect_errors}

      assert {:ok, _result} = Parallel.execute(input, context)
    end
  end

  describe "error_mode: :ignore_errors" do
    test "returns only successful results" do
      input = %{}
      context = %{algorithms: [AlgorithmA, ErrorAlgorithm, AlgorithmB], error_mode: :ignore_errors}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.a == "value_a"
      assert result.b == "value_b"
    end

    test "returns error if all fail" do
      input = %{}
      context = %{algorithms: [ErrorAlgorithm], error_mode: :ignore_errors}

      assert {:error, :all_failed} = Parallel.execute(input, context)
    end
  end

  # ============================================================================
  # Concurrency Control Tests
  # ============================================================================

  describe "max_concurrency" do
    test "limits concurrent execution" do
      # Use slow algorithms to verify concurrency limiting works
      input = %{}

      context = %{
        algorithms: [SlowAlgorithm, SlowAlgorithm, SlowAlgorithm, SlowAlgorithm],
        max_concurrency: 2,
        delay: 50
      }

      start = System.monotonic_time(:millisecond)
      {:ok, _result} = Parallel.execute(input, context)
      duration = System.monotonic_time(:millisecond) - start

      # With max_concurrency: 2 and 4 tasks of 50ms each,
      # should take at least 100ms (2 batches) but not 200ms (sequential)
      assert duration >= 80
    end
  end

  describe "timeout" do
    test "handles task timeout" do
      defmodule VerySlowAlgorithm do
        use Jido.AI.Algorithms.Base, name: "very_slow", description: "Very slow"

        @impl true
        def execute(input, _context) do
          Process.sleep(10_000)
          {:ok, input}
        end
      end

      input = %{}
      context = %{algorithms: [VerySlowAlgorithm], timeout: 100}

      assert {:error, :timeout} = Parallel.execute(input, context)
    end

    test "timeout affects only slow tasks" do
      input = %{}

      context = %{
        algorithms: [AlgorithmA, SlowAlgorithm],
        timeout: 50,
        delay: 200,
        error_mode: :ignore_errors
      }

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.a == "value_a"
      refute Map.has_key?(result, :slow)
    end
  end

  # ============================================================================
  # Can Execute Tests
  # ============================================================================

  describe "can_execute?/2" do
    test "returns true for empty algorithm list" do
      assert Parallel.can_execute?(%{}, %{algorithms: []})
    end

    test "returns true when all algorithms can execute" do
      input = %{value: 5}
      context = %{algorithms: [AlgorithmA, ConditionalAlgorithm]}

      assert Parallel.can_execute?(input, context)
    end

    test "returns false when any algorithm cannot execute" do
      input = %{value: -5}
      context = %{algorithms: [AlgorithmA, ConditionalAlgorithm]}

      refute Parallel.can_execute?(input, context)
    end
  end

  # ============================================================================
  # Exception Handling Tests
  # ============================================================================

  describe "exception handling" do
    test "handles raised exceptions" do
      input = %{}
      context = %{algorithms: [RaisingAlgorithm]}

      assert {:error, {:exception, %RuntimeError{message: "intentional exception"}}} =
               Parallel.execute(input, context)
    end

    test "exceptions don't affect other tasks in ignore_errors mode" do
      input = %{}
      context = %{algorithms: [AlgorithmA, RaisingAlgorithm], error_mode: :ignore_errors}

      assert {:ok, result} = Parallel.execute(input, context)
      assert result.a == "value_a"
    end
  end

  # ============================================================================
  # Telemetry Tests
  # ============================================================================

  describe "telemetry" do
    setup do
      ref = make_ref()
      pid = self()
      handler_id = "test-handler-#{inspect(ref)}"

      :telemetry.attach_many(
        handler_id,
        [
          [:jido, :ai, :algorithm, :parallel, :start],
          [:jido, :ai, :algorithm, :parallel, :stop],
          [:jido, :ai, :algorithm, :parallel, :task, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits start and stop events" do
      input = %{}
      context = %{algorithms: [AlgorithmA]}

      {:ok, _} = Parallel.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :parallel, :start],
                      %{system_time: _, algorithm_count: 1}, %{algorithms: [AlgorithmA]}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :parallel, :stop], %{duration: _},
                      %{success_count: 1, error_count: 0}}
    end

    test "emits task stop events" do
      input = %{}
      context = %{algorithms: [AlgorithmA, AlgorithmB]}

      {:ok, _} = Parallel.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :parallel, :task, :stop], %{duration: _},
                      %{algorithm: AlgorithmA, status: :ok}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :parallel, :task, :stop], %{duration: _},
                      %{algorithm: AlgorithmB, status: :ok}}
    end

    test "emits error status for failed tasks" do
      input = %{}
      context = %{algorithms: [ErrorAlgorithm]}

      {:error, _} = Parallel.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :parallel, :task, :stop], %{duration: _},
                      %{algorithm: ErrorAlgorithm, status: :error}}
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration" do
    test "works with run_with_hooks" do
      input = %{}
      context = %{algorithms: [AlgorithmA, AlgorithmB]}

      {:ok, result} = Parallel.run_with_hooks(input, context)

      assert result.a == "value_a"
      assert result.b == "value_b"
    end
  end
end
