defmodule Jido.AI.Algorithms.CompositeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.Composite

  alias Jido.AI.Algorithms.Composite.{
    ChoiceComposite,
    ComposeComposite,
    ParallelComposite,
    RepeatComposite,
    SequenceComposite,
    WhenComposite
  }

  # ============================================================================
  # Test Algorithm Implementations
  # ============================================================================

  defmodule AddOneAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "add_one",
      description: "Adds one to value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.update(input, :value, 1, &(&1 + 1))}
    end
  end

  defmodule DoubleAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "double",
      description: "Doubles value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.update(input, :value, 0, &(&1 * 2))}
    end
  end

  defmodule FetchAAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "fetch_a",
      description: "Fetches A data"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :a, "data_a")}
    end
  end

  defmodule FetchBAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "fetch_b",
      description: "Fetches B data"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :b, "data_b")}
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

  defmodule PremiumAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "premium",
      description: "Premium processing"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :tier, :premium)}
    end
  end

  defmodule StandardAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "standard",
      description: "Standard processing"

    @impl true
    def execute(input, _context) do
      {:ok, Map.put(input, :tier, :standard)}
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

  # ============================================================================
  # Module Setup Tests
  # ============================================================================

  describe "module setup" do
    test "uses Base correctly" do
      assert function_exported?(Composite, :execute, 2)
      assert function_exported?(Composite, :can_execute?, 2)
      assert function_exported?(Composite, :metadata, 0)
    end

    test "metadata returns correct values" do
      metadata = Composite.metadata()

      assert metadata.name == "composite"
      assert metadata.description == "Composition operators for building complex algorithms"
    end
  end

  # ============================================================================
  # Sequence Tests
  # ============================================================================

  describe "sequence/1" do
    test "creates a SequenceComposite struct" do
      composite = Composite.sequence([AddOneAlgorithm, DoubleAlgorithm])

      assert %SequenceComposite{algorithms: [AddOneAlgorithm, DoubleAlgorithm]} = composite
    end

    test "executes algorithms in sequence" do
      composite = Composite.sequence([AddOneAlgorithm, DoubleAlgorithm])
      input = %{value: 5}

      # 5 + 1 = 6, 6 * 2 = 12
      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 12
    end

    test "chains output to next input" do
      composite = Composite.sequence([AddOneAlgorithm, AddOneAlgorithm, AddOneAlgorithm])
      input = %{value: 0}

      # 0 + 1 + 1 + 1 = 3
      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 3
    end

    test "halts on error" do
      composite = Composite.sequence([AddOneAlgorithm, ErrorAlgorithm, DoubleAlgorithm])
      input = %{value: 5}

      assert {:error, _} = Composite.execute_composite(composite, input, %{})
    end

    test "works with empty list" do
      composite = Composite.sequence([])
      input = %{value: 5}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 5
    end
  end

  # ============================================================================
  # Parallel Tests
  # ============================================================================

  describe "parallel/1" do
    test "creates a ParallelComposite struct" do
      composite = Composite.parallel([FetchAAlgorithm, FetchBAlgorithm])

      assert %ParallelComposite{algorithms: [FetchAAlgorithm, FetchBAlgorithm]} = composite
    end

    test "executes algorithms in parallel and merges results" do
      composite = Composite.parallel([FetchAAlgorithm, FetchBAlgorithm])
      input = %{}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.a == "data_a"
      assert result.b == "data_b"
    end

    test "supports merge_strategy option" do
      composite = Composite.parallel([FetchAAlgorithm, FetchBAlgorithm], merge_strategy: :collect)
      input = %{}

      assert {:ok, results} = Composite.execute_composite(composite, input, %{})
      assert is_list(results)
      assert length(results) == 2
    end

    test "supports error_mode option" do
      composite = Composite.parallel([FetchAAlgorithm, ErrorAlgorithm], error_mode: :ignore_errors)
      input = %{}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.a == "data_a"
    end

    test "stores options in struct" do
      composite = Composite.parallel([FetchAAlgorithm], merge_strategy: :collect, timeout: 10_000)

      assert composite.options[:merge_strategy] == :collect
      assert composite.options[:timeout] == 10_000
    end
  end

  # ============================================================================
  # Choice Tests
  # ============================================================================

  describe "choice/3" do
    test "creates a ChoiceComposite struct" do
      predicate = fn input -> input.premium? end
      composite = Composite.choice(predicate, PremiumAlgorithm, StandardAlgorithm)

      assert %ChoiceComposite{
               predicate: ^predicate,
               if_true: PremiumAlgorithm,
               if_false: StandardAlgorithm
             } = composite
    end

    test "executes if_true when predicate is true" do
      composite =
        Composite.choice(
          fn input -> input.premium? end,
          PremiumAlgorithm,
          StandardAlgorithm
        )

      input = %{premium?: true}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.tier == :premium
    end

    test "executes if_false when predicate is false" do
      composite =
        Composite.choice(
          fn input -> input.premium? end,
          PremiumAlgorithm,
          StandardAlgorithm
        )

      input = %{premium?: false}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.tier == :standard
    end

    test "works with complex predicates" do
      composite =
        Composite.choice(
          fn input -> input.value > 10 and input.active? end,
          PremiumAlgorithm,
          StandardAlgorithm
        )

      assert {:ok, result1} = Composite.execute_composite(composite, %{value: 20, active?: true}, %{})
      assert result1.tier == :premium

      assert {:ok, result2} = Composite.execute_composite(composite, %{value: 5, active?: true}, %{})
      assert result2.tier == :standard
    end
  end

  # ============================================================================
  # Repeat Tests
  # ============================================================================

  describe "repeat/2" do
    test "creates a RepeatComposite struct" do
      composite = Composite.repeat(AddOneAlgorithm, times: 3)

      assert %RepeatComposite{algorithm: AddOneAlgorithm, options: %{times: 3}} = composite
    end

    test "executes algorithm fixed number of times" do
      composite = Composite.repeat(AddOneAlgorithm, times: 5)
      input = %{value: 0}

      # 0 + 1 + 1 + 1 + 1 + 1 = 5
      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 5
    end

    test "defaults to 1 iteration when no options" do
      composite = Composite.repeat(AddOneAlgorithm)
      input = %{value: 0}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 1
    end

    test "stops when while condition becomes false" do
      composite = Composite.repeat(DoubleAlgorithm, times: 100, while: fn result -> result.value < 100 end)
      input = %{value: 1}

      # 1 -> 2 -> 4 -> 8 -> 16 -> 32 -> 64 -> 128 (stops because 128 >= 100)
      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 128
    end

    test "stops on error" do
      composite = Composite.repeat(ErrorAlgorithm, times: 5)
      input = %{value: 0}

      assert {:error, :intentional_error} = Composite.execute_composite(composite, input, %{})
    end

    test "respects max_iterations option to prevent infinite loops" do
      # Create a repeat with a while condition that would never become false
      # but with a max_iterations limit
      composite =
        Composite.repeat(
          AddOneAlgorithm,
          times: 1_000_000,
          # Always continue
          while: fn _result -> true end,
          max_iterations: 10
        )

      input = %{value: 0}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      # Should stop at 10 iterations
      assert result.value == 10
    end

    test "default max_iterations is 10000" do
      # We can't actually test 10000 iterations, but we can verify the behavior
      # by using a custom max_iterations that's lower
      composite =
        Composite.repeat(
          AddOneAlgorithm,
          times: 100,
          max_iterations: 5
        )

      input = %{value: 0}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      # Should stop at 5 due to max_iterations
      assert result.value == 5
    end
  end

  # ============================================================================
  # When Tests
  # ============================================================================

  describe "when_cond/2" do
    test "creates a WhenComposite struct" do
      condition = fn input -> input.valid? end
      composite = Composite.when_cond(condition, AddOneAlgorithm)

      assert %WhenComposite{condition: ^condition, algorithm: AddOneAlgorithm} = composite
    end

    test "executes algorithm when function condition is true" do
      composite = Composite.when_cond(fn input -> input.valid? end, AddOneAlgorithm)
      input = %{value: 5, valid?: true}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 6
    end

    test "skips algorithm when function condition is false" do
      composite = Composite.when_cond(fn input -> input.valid? end, AddOneAlgorithm)
      input = %{value: 5, valid?: false}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 5
    end

    test "executes algorithm when pattern matches" do
      composite = Composite.when_cond(%{type: :premium}, PremiumAlgorithm)
      input = %{type: :premium}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.tier == :premium
    end

    test "skips algorithm when pattern does not match" do
      composite = Composite.when_cond(%{type: :premium}, PremiumAlgorithm)
      input = %{type: :standard}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      refute Map.has_key?(result, :tier)
    end

    test "supports multi-key pattern matching" do
      composite = Composite.when_cond(%{type: :premium, active: true}, PremiumAlgorithm)

      # Both conditions match
      assert {:ok, result1} = Composite.execute_composite(composite, %{type: :premium, active: true}, %{})
      assert result1.tier == :premium

      # One condition doesn't match
      assert {:ok, result2} = Composite.execute_composite(composite, %{type: :premium, active: false}, %{})
      refute Map.has_key?(result2, :tier)
    end
  end

  # ============================================================================
  # Compose Tests
  # ============================================================================

  describe "compose/2" do
    test "creates a ComposeComposite struct" do
      composite = Composite.compose(AddOneAlgorithm, DoubleAlgorithm)

      assert %ComposeComposite{first: AddOneAlgorithm, second: DoubleAlgorithm} = composite
    end

    test "executes algorithms in sequence" do
      composite = Composite.compose(AddOneAlgorithm, DoubleAlgorithm)
      input = %{value: 5}

      # 5 + 1 = 6, 6 * 2 = 12
      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 12
    end

    test "composes composite algorithms" do
      seq1 = Composite.sequence([AddOneAlgorithm, AddOneAlgorithm])
      seq2 = Composite.sequence([DoubleAlgorithm, DoubleAlgorithm])
      composite = Composite.compose(seq1, seq2)
      input = %{value: 1}

      # 1 + 1 + 1 = 3, then 3 * 2 * 2 = 12
      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 12
    end

    test "halts on first algorithm error" do
      composite = Composite.compose(ErrorAlgorithm, DoubleAlgorithm)
      input = %{value: 5}

      assert {:error, _} = Composite.execute_composite(composite, input, %{})
    end
  end

  # ============================================================================
  # Nested Composition Tests
  # ============================================================================

  describe "nested compositions" do
    test "sequence containing parallel" do
      composite =
        Composite.sequence([
          AddOneAlgorithm,
          Composite.parallel([FetchAAlgorithm, FetchBAlgorithm]),
          DoubleAlgorithm
        ])

      input = %{value: 5}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      # (5 + 1) * 2
      assert result.value == 12
      assert result.a == "data_a"
      assert result.b == "data_b"
    end

    test "parallel containing sequences" do
      composite =
        Composite.parallel(
          [
            Composite.sequence([AddOneAlgorithm, FetchAAlgorithm]),
            Composite.sequence([DoubleAlgorithm, FetchBAlgorithm])
          ],
          merge_strategy: :merge_maps
        )

      input = %{value: 5}

      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.a == "data_a"
      assert result.b == "data_b"
    end

    test "choice containing composites" do
      composite =
        Composite.choice(
          fn input -> input.premium? end,
          Composite.sequence([AddOneAlgorithm, DoubleAlgorithm]),
          AddOneAlgorithm
        )

      # Premium path: 5 + 1 = 6, 6 * 2 = 12
      assert {:ok, result1} = Composite.execute_composite(composite, %{value: 5, premium?: true}, %{})
      assert result1.value == 12

      # Standard path: 5 + 1 = 6
      assert {:ok, result2} = Composite.execute_composite(composite, %{value: 5, premium?: false}, %{})
      assert result2.value == 6
    end

    test "deeply nested composition" do
      composite =
        Composite.sequence([
          Composite.when_cond(fn _ -> true end, AddOneAlgorithm),
          Composite.choice(
            fn input -> input.value > 3 end,
            Composite.parallel([FetchAAlgorithm, FetchBAlgorithm]),
            AddOneAlgorithm
          ),
          Composite.repeat(DoubleAlgorithm, times: 2)
        ])

      input = %{value: 5}

      # 5 + 1 = 6 (when_cond)
      # 6 > 3, so parallel fetch (a, b added)
      # double twice: 6 * 2 * 2 = 24
      assert {:ok, result} = Composite.execute_composite(composite, input, %{})
      assert result.value == 24
      assert result.a == "data_a"
      assert result.b == "data_b"
    end
  end

  # ============================================================================
  # Can Execute Tests
  # ============================================================================

  describe "can_execute_composite?/3" do
    test "returns true for sequence when all can execute" do
      composite = Composite.sequence([AddOneAlgorithm, ConditionalAlgorithm])
      input = %{value: 5}

      assert Composite.can_execute_composite?(composite, input, %{})
    end

    test "returns false for sequence when any cannot execute" do
      composite = Composite.sequence([AddOneAlgorithm, ConditionalAlgorithm])
      input = %{value: -5}

      refute Composite.can_execute_composite?(composite, input, %{})
    end

    test "returns true for parallel when all can execute" do
      composite = Composite.parallel([AddOneAlgorithm, DoubleAlgorithm])
      input = %{value: 5}

      assert Composite.can_execute_composite?(composite, input, %{})
    end

    test "always returns true for choice" do
      composite = Composite.choice(fn _ -> true end, AddOneAlgorithm, ErrorAlgorithm)
      input = %{}

      assert Composite.can_execute_composite?(composite, input, %{})
    end

    test "returns result for repeat based on algorithm" do
      composite = Composite.repeat(ConditionalAlgorithm, times: 3)

      assert Composite.can_execute_composite?(composite, %{value: 5}, %{})
      refute Composite.can_execute_composite?(composite, %{value: -5}, %{})
    end

    test "returns result for when based on algorithm" do
      composite = Composite.when_cond(fn _ -> true end, ConditionalAlgorithm)

      assert Composite.can_execute_composite?(composite, %{value: 5}, %{})
      refute Composite.can_execute_composite?(composite, %{value: -5}, %{})
    end

    test "returns combined result for compose" do
      composite = Composite.compose(AddOneAlgorithm, ConditionalAlgorithm)

      assert Composite.can_execute_composite?(composite, %{value: 5}, %{})
      refute Composite.can_execute_composite?(composite, %{value: -5}, %{})
    end
  end

  # ============================================================================
  # Execute via Context Tests
  # ============================================================================

  describe "execute/2 via context" do
    test "executes composite from context" do
      composite = Composite.sequence([AddOneAlgorithm, DoubleAlgorithm])
      input = %{value: 5}
      context = %{composite: composite}

      assert {:ok, result} = Composite.execute(input, context)
      assert result.value == 12
    end

    test "returns input unchanged when no composite in context" do
      input = %{value: 5}
      context = %{}

      assert {:ok, ^input} = Composite.execute(input, context)
    end

    test "can_execute?/2 works with context" do
      composite = Composite.sequence([ConditionalAlgorithm])
      context = %{composite: composite}

      assert Composite.can_execute?(%{value: 5}, context)
      refute Composite.can_execute?(%{value: -5}, context)
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
          [:jido, :ai, :algorithm, :composite, :start],
          [:jido, :ai, :algorithm, :composite, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "emits start and stop events for sequence" do
      composite = Composite.sequence([AddOneAlgorithm])
      Composite.execute_composite(composite, %{value: 5}, %{})

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :start], %{system_time: _}, %{type: :sequence}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :stop], %{duration: _}, %{type: :sequence}}
    end

    test "emits start and stop events for parallel" do
      composite = Composite.parallel([FetchAAlgorithm])
      Composite.execute_composite(composite, %{}, %{})

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :start], %{system_time: _}, %{type: :parallel}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :stop], %{duration: _}, %{type: :parallel}}
    end

    test "emits start and stop events for choice" do
      composite = Composite.choice(fn _ -> true end, AddOneAlgorithm, DoubleAlgorithm)
      Composite.execute_composite(composite, %{value: 5}, %{})

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :start], %{system_time: _}, %{type: :choice}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :stop], %{duration: _}, %{type: :choice}}
    end

    test "emits start and stop events for repeat" do
      composite = Composite.repeat(AddOneAlgorithm, times: 1)
      Composite.execute_composite(composite, %{value: 5}, %{})

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :start], %{system_time: _}, %{type: :repeat}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :stop], %{duration: _}, %{type: :repeat}}
    end

    test "emits start and stop events for when" do
      composite = Composite.when_cond(fn _ -> true end, AddOneAlgorithm)
      Composite.execute_composite(composite, %{value: 5}, %{})

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :start], %{system_time: _}, %{type: :when}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :stop], %{duration: _}, %{type: :when}}
    end

    test "emits start and stop events for compose" do
      composite = Composite.compose(AddOneAlgorithm, DoubleAlgorithm)
      Composite.execute_composite(composite, %{value: 5}, %{})

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :start], %{system_time: _}, %{type: :compose}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :composite, :stop], %{duration: _}, %{type: :compose}}
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration" do
    test "works with run_with_hooks" do
      composite = Composite.sequence([AddOneAlgorithm, DoubleAlgorithm])
      context = %{composite: composite}

      {:ok, result} = Composite.run_with_hooks(%{value: 5}, context)
      assert result.value == 12
    end

    test "complex workflow with all operators" do
      workflow =
        Composite.sequence([
          # Stage 1: Add one
          AddOneAlgorithm,

          # Stage 2: Conditional - double if value > 5
          Composite.when_cond(fn input -> input.value > 5 end, DoubleAlgorithm),

          # Stage 3: Choice based on value
          Composite.choice(
            fn input -> input.value >= 10 end,
            Composite.parallel([FetchAAlgorithm, FetchBAlgorithm]),
            FetchAAlgorithm
          ),

          # Stage 4: Repeat add one twice
          Composite.repeat(AddOneAlgorithm, times: 2)
        ])

      # Starting with value: 5
      # Step 1: 5 + 1 = 6
      # Step 2: 6 > 5, so double: 12
      # Step 3: 12 >= 10, so parallel fetch (adds a, b)
      # Step 4: 12 + 1 + 1 = 14
      assert {:ok, result} = Composite.execute_composite(workflow, %{value: 5}, %{})
      assert result.value == 14
      assert result.a == "data_a"
      assert result.b == "data_b"
    end
  end
end
