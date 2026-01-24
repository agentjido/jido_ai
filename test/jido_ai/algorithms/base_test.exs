defmodule Jido.AI.Algorithms.BaseTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.Algorithm

  # ============================================================================
  # Test Algorithm Implementations
  # ============================================================================

  # Minimal implementation using Base with only required execute/2
  defmodule MinimalBaseAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "minimal_base",
      description: "A minimal algorithm using Base"

    @impl true
    def execute(input, _context) do
      {:ok, %{doubled: input[:value] * 2}}
    end
  end

  # Full implementation with metadata extras and overrides
  defmodule FullBaseAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "full_base",
      description: "A full algorithm with overrides",
      version: "1.0.0",
      author: "Test Suite"

    @impl true
    def execute(input, _context) do
      {:ok, %{result: input[:value] * 2}}
    end

    @impl true
    def can_execute?(input, _context) do
      is_number(input[:value])
    end

    @impl true
    def before_execute(input, _context) do
      {:ok, Map.put(input, :preprocessed, true)}
    end

    @impl true
    def after_execute(result, _context) do
      {:ok, Map.put(result, :postprocessed, true)}
    end

    @impl true
    def on_error(error, _context) do
      case error do
        :retryable -> {:retry, delay: 100, max_attempts: 3}
        other -> {:fail, other}
      end
    end
  end

  # Algorithm with before_execute that returns error
  defmodule BeforeErrorAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "before_error",
      description: "Algorithm that fails in before_execute"

    @impl true
    def execute(_input, _context) do
      {:ok, %{should_not_reach: true}}
    end

    @impl true
    def before_execute(_input, _context) do
      {:error, :validation_failed}
    end
  end

  # Algorithm with execute that returns error
  defmodule ExecuteErrorAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "execute_error",
      description: "Algorithm that fails in execute"

    @impl true
    def execute(_input, _context) do
      {:error, :execution_failed}
    end
  end

  # Algorithm with after_execute that returns error
  defmodule AfterErrorAlgorithm do
    use Jido.AI.Algorithms.Base,
      name: "after_error",
      description: "Algorithm that fails in after_execute"

    @impl true
    def execute(input, _context) do
      {:ok, %{value: input[:value]}}
    end

    @impl true
    def after_execute(_result, _context) do
      {:error, :postprocessing_failed}
    end
  end

  # ============================================================================
  # __using__ Macro Tests
  # ============================================================================

  describe "__using__ macro" do
    test "injects Algorithm behavior" do
      behaviours = MinimalBaseAlgorithm.__info__(:attributes)[:behaviour]
      assert Algorithm in behaviours
    end

    test "requires name option" do
      assert_raise ArgumentError, ~r/Missing required :name option/, fn ->
        defmodule MissingName do
          use Jido.AI.Algorithms.Base,
            description: "Missing name"

          def execute(_input, _context), do: {:ok, %{}}
        end
      end
    end

    test "requires description option" do
      assert_raise ArgumentError, ~r/Missing required :description option/, fn ->
        defmodule MissingDescription do
          use Jido.AI.Algorithms.Base,
            name: "missing_desc"

          def execute(_input, _context), do: {:ok, %{}}
        end
      end
    end
  end

  # ============================================================================
  # Default Metadata Tests
  # ============================================================================

  describe "default metadata/0" do
    test "returns name and description from opts" do
      metadata = MinimalBaseAlgorithm.metadata()

      assert metadata.name == "minimal_base"
      assert metadata.description == "A minimal algorithm using Base"
    end

    test "includes additional opts in metadata" do
      metadata = FullBaseAlgorithm.metadata()

      assert metadata.name == "full_base"
      assert metadata.description == "A full algorithm with overrides"
      assert metadata.version == "1.0.0"
      assert metadata.author == "Test Suite"
    end
  end

  # ============================================================================
  # Default Optional Callback Tests
  # ============================================================================

  describe "default can_execute?/2" do
    test "returns true by default" do
      assert MinimalBaseAlgorithm.can_execute?(%{}, %{})
      assert MinimalBaseAlgorithm.can_execute?(%{any: "input"}, %{})
    end
  end

  describe "default before_execute/2" do
    test "returns {:ok, input} unchanged" do
      input = %{value: 42, extra: "data"}
      assert {:ok, ^input} = MinimalBaseAlgorithm.before_execute(input, %{})
    end
  end

  describe "default after_execute/2" do
    test "returns {:ok, result} unchanged" do
      result = %{computed: 84, status: "done"}
      assert {:ok, ^result} = MinimalBaseAlgorithm.after_execute(result, %{})
    end
  end

  # ============================================================================
  # Override Tests
  # ============================================================================

  describe "defoverridable" do
    test "can_execute?/2 can be overridden" do
      assert FullBaseAlgorithm.can_execute?(%{value: 10}, %{})
      assert FullBaseAlgorithm.can_execute?(%{value: 3.14}, %{})
      refute FullBaseAlgorithm.can_execute?(%{value: "not a number"}, %{})
      refute FullBaseAlgorithm.can_execute?(%{}, %{})
    end

    test "before_execute/2 can be overridden" do
      {:ok, result} = FullBaseAlgorithm.before_execute(%{value: 5}, %{})

      assert result.value == 5
      assert result.preprocessed == true
    end

    test "after_execute/2 can be overridden" do
      {:ok, result} = FullBaseAlgorithm.after_execute(%{result: 10}, %{})

      assert result.result == 10
      assert result.postprocessed == true
    end

    test "metadata/0 can be overridden" do
      defmodule CustomMetadataAlgorithm do
        use Jido.AI.Algorithms.Base,
          name: "custom",
          description: "Custom metadata"

        @impl true
        def execute(_input, _context), do: {:ok, %{}}

        @impl true
        def metadata do
          %{
            name: "completely_custom",
            description: "Overridden metadata",
            custom_field: true
          }
        end
      end

      metadata = CustomMetadataAlgorithm.metadata()

      assert metadata.name == "completely_custom"
      assert metadata.custom_field == true
    end
  end

  # ============================================================================
  # run_with_hooks/3 Tests
  # ============================================================================

  describe "run_with_hooks/3" do
    test "executes full flow with defaults" do
      result = MinimalBaseAlgorithm.run_with_hooks(%{value: 5}, %{})

      assert {:ok, %{doubled: 10}} = result
    end

    test "calls hooks in order with overrides" do
      result = FullBaseAlgorithm.run_with_hooks(%{value: 5}, %{})

      assert {:ok, final} = result
      assert final.result == 10
      assert final.postprocessed == true
    end

    test "stops on before_execute error" do
      result = BeforeErrorAlgorithm.run_with_hooks(%{value: 5}, %{})

      assert {:error, :validation_failed} = result
    end

    test "stops on execute error" do
      result = ExecuteErrorAlgorithm.run_with_hooks(%{value: 5}, %{})

      assert {:error, :execution_failed} = result
    end

    test "stops on after_execute error" do
      result = AfterErrorAlgorithm.run_with_hooks(%{value: 5}, %{})

      assert {:error, :postprocessing_failed} = result
    end

    test "passes context through all hooks" do
      defmodule ContextTrackingAlgorithm do
        use Jido.AI.Algorithms.Base,
          name: "context_tracker",
          description: "Tracks context flow"

        @impl true
        def execute(input, context) do
          {:ok, Map.put(input, :execute_context, context)}
        end

        @impl true
        def before_execute(input, context) do
          {:ok, Map.put(input, :before_context, context)}
        end

        @impl true
        def after_execute(result, context) do
          {:ok, Map.put(result, :after_context, context)}
        end
      end

      context = %{trace_id: "abc123"}
      {:ok, result} = ContextTrackingAlgorithm.run_with_hooks(%{}, context)

      assert result.before_context == context
      assert result.execute_context == context
      assert result.after_context == context
    end
  end

  # ============================================================================
  # handle_error/2 Tests
  # ============================================================================

  describe "handle_error/2" do
    test "uses default on_error returning {:fail, error}" do
      result = MinimalBaseAlgorithm.handle_error(:some_error, %{})

      assert {:fail, :some_error} = result
    end

    test "delegates to overridden on_error" do
      result = FullBaseAlgorithm.handle_error(:retryable, %{})

      assert {:retry, opts} = result
      assert opts[:delay] == 100
      assert opts[:max_attempts] == 3
    end

    test "overridden on_error can return fail" do
      result = FullBaseAlgorithm.handle_error(:permanent_error, %{})

      assert {:fail, :permanent_error} = result
    end
  end

  # ============================================================================
  # default on_error/2 Tests
  # ============================================================================

  describe "default on_error/2" do
    test "returns {:fail, error}" do
      result = MinimalBaseAlgorithm.on_error(:any_error, %{})

      assert {:fail, :any_error} = result
    end
  end

  # ============================================================================
  # merge_context/2 Tests
  # ============================================================================

  describe "merge_context/2" do
    test "merges map into context" do
      context = %{existing: "value"}
      additions = %{new: "addition", step: 1}

      result = MinimalBaseAlgorithm.merge_context(context, additions)

      assert result.existing == "value"
      assert result.new == "addition"
      assert result.step == 1
    end

    test "merges keyword list into context" do
      context = %{existing: "value"}
      additions = [new: "addition", step: 1]

      result = MinimalBaseAlgorithm.merge_context(context, additions)

      assert result.existing == "value"
      assert result.new == "addition"
      assert result.step == 1
    end

    test "additions override existing keys" do
      context = %{key: "original"}
      additions = %{key: "updated"}

      result = MinimalBaseAlgorithm.merge_context(context, additions)

      assert result.key == "updated"
    end
  end

  # ============================================================================
  # Integration Pattern Tests
  # ============================================================================

  describe "integration patterns" do
    test "algorithm can check executability before running" do
      algorithm = FullBaseAlgorithm
      input = %{value: 5}
      context = %{}

      result =
        if algorithm.can_execute?(input, context) do
          algorithm.run_with_hooks(input, context)
        else
          {:error, :cannot_execute}
        end

      assert {:ok, %{result: 10, postprocessed: true}} = result
    end

    test "algorithm can handle errors with retry logic" do
      algorithm = FullBaseAlgorithm

      # Simulate error handling flow
      error = :retryable
      context = %{attempt: 1}

      case algorithm.handle_error(error, context) do
        {:retry, opts} ->
          assert opts[:delay] == 100
          assert opts[:max_attempts] == 3

        {:fail, _reason} ->
          flunk("Expected retry, got fail")
      end
    end

    test "multiple algorithms can be composed" do
      algorithms = [MinimalBaseAlgorithm, FullBaseAlgorithm]

      # All implement the behavior
      Enum.each(algorithms, fn algo ->
        assert function_exported?(algo, :execute, 2)
        assert function_exported?(algo, :run_with_hooks, 2)
        assert function_exported?(algo, :handle_error, 2)
        assert function_exported?(algo, :merge_context, 2)
      end)
    end
  end
end
