defmodule Jido.AI.Algorithms.Algorithm do
  @moduledoc """
  Defines the behavior interface that all algorithms must implement.

  Algorithms in Jido.AI define how AI operations are sequenced, parallelized,
  or composed. This behavior provides a consistent interface for implementing
  different execution patterns.

  ## Required Callbacks

  Every algorithm must implement:

  - `execute/2` - Main execution function that processes input and returns result
  - `can_execute?/2` - Checks if the algorithm can run with given input/context
  - `metadata/0` - Returns algorithm metadata (name, description, etc.)

  ## Optional Hooks

  Algorithms can optionally implement these hooks for customization:

  - `before_execute/2` - Called before execute, can modify input
  - `after_execute/2` - Called after execute, can modify result
  - `on_error/2` - Called on error, can trigger retry or custom handling

  ## Usage

  Implement this behavior directly or use `Jido.AI.Algorithms.Base` for
  a more convenient starting point with default implementations.

      defmodule MyApp.Algorithms.Custom do
        @behaviour Jido.AI.Algorithms.Algorithm

        @impl true
        def execute(input, context) do
          # Process input and return result
          {:ok, %{result: input[:value] * 2}}
        end

        @impl true
        def can_execute?(_input, _context), do: true

        @impl true
        def metadata do
          %{
            name: "custom",
            description: "Custom algorithm implementation"
          }
        end
      end

  ## Context

  The context map is passed through the algorithm execution and can contain:

  - `:algorithms` - List of sub-algorithms for composite algorithms
  - `:timeout` - Execution timeout in milliseconds
  - `:max_concurrency` - Maximum parallel tasks (for parallel algorithms)
  - `:error_mode` - Error handling mode (`:fail_fast`, `:collect_errors`, etc.)
  - Custom keys as needed by specific algorithm implementations

  ## Error Handling

  Algorithms should return `{:error, reason}` tuples for failures. The `on_error/2`
  hook can be implemented to provide custom error handling:

  - `{:retry, opts}` - Retry execution with options (delay, max_attempts, etc.)
  - `{:fail, reason}` - Fail with the given reason

  ## Telemetry

  Algorithm implementations should emit telemetry events for observability:

  - `[:jido, :ai, :algorithm, :execute, :start]` - Execution started
  - `[:jido, :ai, :algorithm, :execute, :stop]` - Execution completed
  - `[:jido, :ai, :algorithm, :execute, :exception]` - Execution failed
  """

  # ============================================================================
  # Type Specifications
  # ============================================================================

  @typedoc "An algorithm module that implements this behavior"
  @type t :: module()

  @typedoc "Input map passed to the algorithm"
  @type input :: map()

  @typedoc "Execution context containing configuration and state"
  @type context :: map()

  @typedoc "Result of algorithm execution"
  @type result :: {:ok, map()} | {:error, term()}

  @typedoc "Error handling response from on_error callback"
  @type error_response :: {:retry, keyword()} | {:fail, term()}

  @typedoc "Algorithm metadata map with required name and description"
  @type metadata :: %{
          required(:name) => String.t(),
          required(:description) => String.t(),
          optional(atom()) => term()
        }

  # ============================================================================
  # Required Callbacks
  # ============================================================================

  @doc """
  Executes the algorithm with the given input and context.

  This is the main entry point for algorithm execution. The input contains
  the data to process, and the context contains execution configuration.

  ## Arguments

    * `input` - Map containing input data for the algorithm
    * `context` - Map containing execution context and configuration

  ## Returns

    * `{:ok, result}` - Successful execution with result map
    * `{:error, reason}` - Failed execution with error reason

  ## Examples

      iex> MyAlgorithm.execute(%{value: 10}, %{})
      {:ok, %{result: 20}}

      iex> MyAlgorithm.execute(%{}, %{})
      {:error, :missing_value}
  """
  @callback execute(input :: input(), context :: context()) :: result()

  @doc """
  Checks if the algorithm can execute with the given input and context.

  This allows algorithms to validate preconditions before execution.
  Return `true` if execution can proceed, `false` otherwise.

  ## Arguments

    * `input` - Map containing input data to validate
    * `context` - Map containing execution context

  ## Returns

    * `true` - Algorithm can execute
    * `false` - Algorithm cannot execute (preconditions not met)

  ## Examples

      iex> MyAlgorithm.can_execute?(%{value: 10}, %{})
      true

      iex> MyAlgorithm.can_execute?(%{}, %{})
      false
  """
  @callback can_execute?(input :: input(), context :: context()) :: boolean()

  @doc """
  Returns metadata about the algorithm.

  This should return a map containing at minimum:

    * `:name` - String name of the algorithm
    * `:description` - String description of what it does

  Additional metadata keys can be included as needed.

  ## Returns

    A map containing algorithm metadata.

  ## Examples

      iex> MyAlgorithm.metadata()
      %{name: "my_algorithm", description: "Does something useful", version: "1.0"}
  """
  @callback metadata() :: metadata()

  # ============================================================================
  # Optional Callbacks (Hooks)
  # ============================================================================

  @doc """
  Called before `execute/2` to allow input modification or validation.

  This hook can transform the input or perform additional validation
  before the main execution. Return `{:ok, modified_input}` to proceed
  or `{:error, reason}` to abort execution.

  ## Arguments

    * `input` - Original input map
    * `context` - Execution context

  ## Returns

    * `{:ok, input}` - Proceed with (possibly modified) input
    * `{:error, reason}` - Abort execution with error

  ## Examples

      def before_execute(input, _context) do
        # Add timestamp to input
        {:ok, Map.put(input, :started_at, DateTime.utc_now())}
      end
  """
  @callback before_execute(input :: input(), context :: context()) ::
              {:ok, input()} | {:error, term()}

  @doc """
  Called after successful `execute/2` to allow result modification.

  This hook can transform the result or perform post-processing.
  Return `{:ok, modified_result}` to return the modified result
  or `{:error, reason}` to convert success to failure.

  ## Arguments

    * `result` - Result map from execute/2
    * `context` - Execution context

  ## Returns

    * `{:ok, result}` - Return (possibly modified) result
    * `{:error, reason}` - Convert to error

  ## Examples

      def after_execute(result, _context) do
        # Add completion timestamp
        {:ok, Map.put(result, :completed_at, DateTime.utc_now())}
      end
  """
  @callback after_execute(result :: map(), context :: context()) ::
              {:ok, map()} | {:error, term()}

  @doc """
  Called when `execute/2` returns an error.

  This hook allows custom error handling, including retry logic.
  Return `{:retry, opts}` to retry execution or `{:fail, reason}`
  to fail with the given reason.

  ## Arguments

    * `error` - The error term from execute/2
    * `context` - Execution context

  ## Returns

    * `{:retry, opts}` - Retry execution with options
      * `:delay` - Delay in milliseconds before retry
      * `:max_attempts` - Maximum retry attempts
    * `{:fail, reason}` - Fail with the given reason

  ## Examples

      def on_error(:timeout, context) do
        attempt = Map.get(context, :attempt, 1)
        if attempt < 3 do
          {:retry, delay: 1000, max_attempts: 3}
        else
          {:fail, :max_retries_exceeded}
        end
      end

      def on_error(error, _context) do
        {:fail, error}
      end
  """
  @callback on_error(error :: term(), context :: context()) :: error_response()

  # Mark optional callbacks
  @optional_callbacks before_execute: 2, after_execute: 2, on_error: 2
end
