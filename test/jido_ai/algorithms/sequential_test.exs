defmodule Jido.AI.Algorithms.SequentialTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.Sequential

  # ============================================================================
  # Test Algorithm Implementations
  # ============================================================================

  defmodule DoubleAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "double",
      description: "Doubles the value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.update!(input, :value, &(&1 * 2))}
    end
  end

  defmodule AddTenAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "add_ten",
      description: "Adds 10 to the value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.update!(input, :value, &(&1 + 10))}
    end
  end

  defmodule SquareAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "square",
      description: "Squares the value"

    @impl true
    def execute(input, _context) do
      {:ok, Map.update!(input, :value, &(&1 * &1))}
    end
  end

  defmodule ErrorAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "error",
      description: "Always returns an error"

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
      {:ok, input}
    end

    @impl true
    def can_execute?(input, _context) do
      Map.get(input, :value, 0) > 0
    end
  end

  defmodule TrackingAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "tracking",
      description: "Tracks step info"

    @impl true
    def execute(input, context) do
      step_info = %{
        step_index: context[:step_index],
        step_name: context[:step_name],
        total_steps: context[:total_steps]
      }

      {:ok, Map.put(input, :step_info, step_info)}
    end
  end

  defmodule RaisingAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "raising",
      description: "Raises an exception"

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
      assert function_exported?(Sequential, :execute, 2)
      assert function_exported?(Sequential, :can_execute?, 2)
      assert function_exported?(Sequential, :metadata, 0)
      assert function_exported?(Sequential, :run_with_hooks, 2)
    end

    test "metadata returns correct values" do
      metadata = Sequential.metadata()

      assert metadata.name == "sequential"
      assert metadata.description == "Executes algorithms in sequence, chaining outputs to inputs"
    end
  end

  # ============================================================================
  # Execute Tests
  # ============================================================================

  describe "execute/2" do
    test "returns input unchanged for empty algorithm list" do
      input = %{value: 5}
      context = %{algorithms: []}

      assert {:ok, ^input} = Sequential.execute(input, context)
    end

    test "returns input unchanged when algorithms key is missing" do
      input = %{value: 5}
      context = %{}

      assert {:ok, ^input} = Sequential.execute(input, context)
    end

    test "executes single algorithm" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm]}

      assert {:ok, %{value: 10}} = Sequential.execute(input, context)
    end

    test "chains multiple algorithms in order" do
      input = %{value: 5}
      # 5 -> double -> 10 -> add_ten -> 20 -> square -> 400
      context = %{algorithms: [DoubleAlgorithm, AddTenAlgorithm, SquareAlgorithm]}

      assert {:ok, %{value: 400}} = Sequential.execute(input, context)
    end

    test "passes output to next algorithm input" do
      input = %{value: 3}
      # 3 -> double -> 6 -> double -> 12 -> double -> 24
      context = %{algorithms: [DoubleAlgorithm, DoubleAlgorithm, DoubleAlgorithm]}

      assert {:ok, %{value: 24}} = Sequential.execute(input, context)
    end

    test "halts on first error" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm, ErrorAlgorithm, AddTenAlgorithm]}

      assert {:error, error} = Sequential.execute(input, context)
      assert error.reason == :intentional_error
      assert error.step_index == 1
      assert error.step_name == "error"
      assert error.algorithm == ErrorAlgorithm
    end

    test "error includes step information" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm, AddTenAlgorithm, ErrorAlgorithm]}

      assert {:error, error} = Sequential.execute(input, context)
      assert error.step_index == 2
      assert error.step_name == "error"
    end

    test "handles exceptions gracefully" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm, RaisingAlgorithm]}

      assert {:error, error} = Sequential.execute(input, context)
      assert error.step_index == 1
      assert %RuntimeError{message: "intentional exception"} = error.reason
    end
  end

  # ============================================================================
  # Can Execute Tests
  # ============================================================================

  describe "can_execute?/2" do
    test "returns true for empty algorithm list" do
      assert Sequential.can_execute?(%{}, %{algorithms: []})
    end

    test "returns true when algorithms key is missing" do
      assert Sequential.can_execute?(%{}, %{})
    end

    test "returns true when all algorithms can execute" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm, AddTenAlgorithm]}

      assert Sequential.can_execute?(input, context)
    end

    test "returns false when any algorithm cannot execute" do
      input = %{value: -5}
      context = %{algorithms: [DoubleAlgorithm, ConditionalAlgorithm]}

      refute Sequential.can_execute?(input, context)
    end

    test "checks all algorithms" do
      input = %{value: 5}
      context = %{algorithms: [ConditionalAlgorithm, ConditionalAlgorithm]}

      assert Sequential.can_execute?(input, context)
    end
  end

  # ============================================================================
  # Step Tracking Tests
  # ============================================================================

  describe "step tracking" do
    test "provides step_index in context" do
      input = %{value: 5}
      context = %{algorithms: [TrackingAlgorithm]}

      {:ok, result} = Sequential.execute(input, context)

      assert result.step_info.step_index == 0
    end

    test "provides step_name in context" do
      input = %{value: 5}
      context = %{algorithms: [TrackingAlgorithm]}

      {:ok, result} = Sequential.execute(input, context)

      assert result.step_info.step_name == "tracking"
    end

    test "provides total_steps in context" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm, TrackingAlgorithm, AddTenAlgorithm]}

      {:ok, result} = Sequential.execute(input, context)

      assert result.step_info.total_steps == 3
      assert result.step_info.step_index == 1
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
          [:jido, :ai, :algorithm, :sequential, :step, :start],
          [:jido, :ai, :algorithm, :sequential, :step, :stop],
          [:jido, :ai, :algorithm, :sequential, :step, :exception]
        ],
        fn event, measurements, metadata, _config ->
          send(pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :ok
    end

    test "emits start and stop events for successful steps" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm]}

      {:ok, _} = Sequential.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :start],
                      %{system_time: _}, %{step_index: 0, step_name: "double", algorithm: DoubleAlgorithm}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :stop],
                      %{duration: _}, %{step_index: 0, step_name: "double", algorithm: DoubleAlgorithm}}
    end

    test "emits events for each step" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm, AddTenAlgorithm]}

      {:ok, _} = Sequential.execute(input, context)

      # First step
      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :start],
                      _, %{step_index: 0}}
      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :stop],
                      _, %{step_index: 0}}

      # Second step
      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :start],
                      _, %{step_index: 1}}
      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :stop],
                      _, %{step_index: 1}}
    end

    test "emits exception event on error" do
      input = %{value: 5}
      context = %{algorithms: [ErrorAlgorithm]}

      {:error, _} = Sequential.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :start],
                      _, %{step_index: 0}}

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :exception],
                      %{duration: _}, %{step_index: 0, error: :intentional_error}}
    end

    test "emits exception event on raised exception" do
      input = %{value: 5}
      context = %{algorithms: [RaisingAlgorithm]}

      {:error, _} = Sequential.execute(input, context)

      assert_receive {:telemetry, [:jido, :ai, :algorithm, :sequential, :step, :exception],
                      %{duration: _}, %{error: %RuntimeError{}}}
    end
  end

  # ============================================================================
  # Integration Tests
  # ============================================================================

  describe "integration" do
    test "works with run_with_hooks" do
      input = %{value: 5}
      context = %{algorithms: [DoubleAlgorithm, AddTenAlgorithm]}

      {:ok, result} = Sequential.run_with_hooks(input, context)

      assert result.value == 20
    end

    test "complex pipeline with mixed algorithms" do
      input = %{value: 2}
      # 2 -> double -> 4 -> square -> 16 -> add_ten -> 26 -> double -> 52
      context = %{algorithms: [DoubleAlgorithm, SquareAlgorithm, AddTenAlgorithm, DoubleAlgorithm]}

      {:ok, result} = Sequential.execute(input, context)

      assert result.value == 52
    end

    test "can be nested in another sequential" do
      # This tests that Sequential can be used as an algorithm in another Sequential
      defmodule InnerPipeline do
        use Jido.AI.Algorithms.Base,
          name: "inner_pipeline",
          description: "Inner pipeline"

        @impl true
        def execute(input, _context) do
          inner_context = %{
            algorithms: [
              Jido.AI.Algorithms.SequentialTest.DoubleAlgorithm,
              Jido.AI.Algorithms.SequentialTest.AddTenAlgorithm
            ]
          }

          Sequential.execute(input, inner_context)
        end
      end

      input = %{value: 5}
      # 5 -> InnerPipeline(double -> 10 -> add_ten -> 20) -> 20
      context = %{algorithms: [InnerPipeline]}

      {:ok, result} = Sequential.execute(input, context)

      assert result.value == 20
    end
  end
end
