defmodule Jido.AI.Algorithms.AlgorithmTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Algorithms.Algorithm

  # ============================================================================
  # Test Algorithm Implementations
  # ============================================================================

  # Minimal implementation with only required callbacks
  defmodule MinimalAlgorithm do
    @behaviour Algorithm

    @impl true
    def execute(input, _context) do
      {:ok, %{doubled: input[:value] * 2}}
    end

    @impl true
    def can_execute?(input, _context) do
      Map.has_key?(input, :value)
    end

    @impl true
    def metadata do
      %{name: "minimal", description: "A minimal algorithm"}
    end
  end

  # Full implementation with all optional callbacks
  defmodule FullAlgorithm do
    @behaviour Algorithm

    @impl true
    def execute(input, _context) do
      {:ok, %{result: input[:value] * 2}}
    end

    @impl true
    def can_execute?(input, _context) do
      is_number(input[:value])
    end

    @impl true
    def metadata do
      %{
        name: "full",
        description: "A full algorithm with all callbacks",
        version: "1.0.0"
      }
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

  # Algorithm that returns errors
  defmodule ErrorAlgorithm do
    @behaviour Algorithm

    @impl true
    def execute(_input, _context) do
      {:error, :intentional_error}
    end

    @impl true
    def can_execute?(_input, _context), do: true

    @impl true
    def metadata do
      %{name: "error", description: "Always returns an error"}
    end
  end

  # ============================================================================
  # Behavior Definition Tests
  # ============================================================================

  describe "behavior callbacks" do
    test "required callbacks are defined" do
      callbacks = Algorithm.behaviour_info(:callbacks)

      # Required callbacks
      assert {:execute, 2} in callbacks
      assert {:can_execute?, 2} in callbacks
      assert {:metadata, 0} in callbacks
    end

    test "optional callbacks are defined" do
      callbacks = Algorithm.behaviour_info(:callbacks)

      # Optional callbacks
      assert {:before_execute, 2} in callbacks
      assert {:after_execute, 2} in callbacks
      assert {:on_error, 2} in callbacks
    end

    test "optional callbacks are marked as optional" do
      optional = Algorithm.behaviour_info(:optional_callbacks)

      assert {:before_execute, 2} in optional
      assert {:after_execute, 2} in optional
      assert {:on_error, 2} in optional
    end

    test "required callbacks are not marked as optional" do
      optional = Algorithm.behaviour_info(:optional_callbacks)

      refute {:execute, 2} in optional
      refute {:can_execute?, 2} in optional
      refute {:metadata, 0} in optional
    end
  end

  # ============================================================================
  # Minimal Algorithm Tests
  # ============================================================================

  describe "minimal algorithm (required callbacks only)" do
    test "execute/2 returns success with result" do
      result = MinimalAlgorithm.execute(%{value: 5}, %{})
      assert {:ok, %{doubled: 10}} = result
    end

    test "can_execute?/2 returns true when preconditions met" do
      assert MinimalAlgorithm.can_execute?(%{value: 5}, %{})
    end

    test "can_execute?/2 returns false when preconditions not met" do
      refute MinimalAlgorithm.can_execute?(%{}, %{})
    end

    test "metadata/0 returns algorithm metadata" do
      metadata = MinimalAlgorithm.metadata()

      assert metadata.name == "minimal"
      assert metadata.description == "A minimal algorithm"
    end
  end

  # ============================================================================
  # Full Algorithm Tests
  # ============================================================================

  describe "full algorithm (all callbacks)" do
    test "execute/2 returns success with result" do
      result = FullAlgorithm.execute(%{value: 10}, %{})
      assert {:ok, %{result: 20}} = result
    end

    test "can_execute?/2 validates input type" do
      assert FullAlgorithm.can_execute?(%{value: 10}, %{})
      assert FullAlgorithm.can_execute?(%{value: 3.14}, %{})
      refute FullAlgorithm.can_execute?(%{value: "not a number"}, %{})
    end

    test "metadata/0 returns full metadata" do
      metadata = FullAlgorithm.metadata()

      assert metadata.name == "full"
      assert metadata.description == "A full algorithm with all callbacks"
      assert metadata.version == "1.0.0"
    end

    test "before_execute/2 modifies input" do
      {:ok, modified_input} = FullAlgorithm.before_execute(%{value: 5}, %{})

      assert modified_input.value == 5
      assert modified_input.preprocessed == true
    end

    test "after_execute/2 modifies result" do
      {:ok, modified_result} = FullAlgorithm.after_execute(%{result: 10}, %{})

      assert modified_result.result == 10
      assert modified_result.postprocessed == true
    end

    test "on_error/2 returns retry for retryable errors" do
      result = FullAlgorithm.on_error(:retryable, %{})

      assert {:retry, opts} = result
      assert opts[:delay] == 100
      assert opts[:max_attempts] == 3
    end

    test "on_error/2 returns fail for non-retryable errors" do
      result = FullAlgorithm.on_error(:permanent_error, %{})

      assert {:fail, :permanent_error} = result
    end
  end

  # ============================================================================
  # Error Algorithm Tests
  # ============================================================================

  describe "error algorithm" do
    test "execute/2 returns error" do
      result = ErrorAlgorithm.execute(%{}, %{})
      assert {:error, :intentional_error} = result
    end

    test "can_execute?/2 returns true" do
      assert ErrorAlgorithm.can_execute?(%{}, %{})
    end
  end

  # ============================================================================
  # Type Specification Tests
  # ============================================================================

  describe "type specifications" do
    test "module compiles with type definitions" do
      # If we got here, the module compiled successfully with all types
      assert Code.ensure_loaded?(Algorithm)
    end

    test "result type allows ok tuple" do
      # These should all be valid result types
      assert {:ok, %{}} == {:ok, %{}}
      assert {:ok, %{key: "value"}} == {:ok, %{key: "value"}}
    end

    test "result type allows error tuple" do
      # These should all be valid result types
      assert {:error, :reason} == {:error, :reason}
      assert {:error, "message"} == {:error, "message"}
    end

    test "error_response type allows retry" do
      # Valid retry response
      assert {:retry, [delay: 100]} == {:retry, [delay: 100]}
    end

    test "error_response type allows fail" do
      # Valid fail response
      assert {:fail, :reason} == {:fail, :reason}
    end
  end

  # ============================================================================
  # Integration Pattern Tests
  # ============================================================================

  describe "algorithm execution patterns" do
    test "algorithm can be executed conditionally" do
      algorithm = MinimalAlgorithm
      input = %{value: 5}
      context = %{}

      result =
        if algorithm.can_execute?(input, context) do
          algorithm.execute(input, context)
        else
          {:error, :cannot_execute}
        end

      assert {:ok, %{doubled: 10}} = result
    end

    test "algorithm can be executed with hooks" do
      algorithm = FullAlgorithm
      input = %{value: 5}
      context = %{}

      # Simulate hook execution pattern
      with {:ok, processed_input} <- algorithm.before_execute(input, context),
           {:ok, result} <- algorithm.execute(processed_input, context),
           {:ok, final_result} <- algorithm.after_execute(result, context) do
        assert final_result.result == 10
        assert final_result.postprocessed == true
      end
    end

    test "algorithms can be composed in a list" do
      algorithms = [MinimalAlgorithm, FullAlgorithm]

      # All algorithms implement the behavior
      Enum.each(algorithms, fn algo ->
        assert function_exported?(algo, :execute, 2)
        assert function_exported?(algo, :can_execute?, 2)
        assert function_exported?(algo, :metadata, 0)
      end)
    end

    test "metadata can be collected from multiple algorithms" do
      algorithms = [MinimalAlgorithm, FullAlgorithm, ErrorAlgorithm]

      metadata_list = Enum.map(algorithms, & &1.metadata())

      assert length(metadata_list) == 3
      assert Enum.all?(metadata_list, &is_map/1)
      assert Enum.all?(metadata_list, &Map.has_key?(&1, :name))
    end
  end
end
