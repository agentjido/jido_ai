defmodule Jido.AI.Algorithms.Base do
  @moduledoc """
  Provides a convenient base for implementing algorithms.

  This module uses a `__using__` macro to inject the Algorithm behavior
  and provide default implementations for optional callbacks, reducing
  boilerplate in algorithm implementations.

  ## Usage

  Use this module in your algorithm implementation:

      defmodule MyApp.Algorithms.Custom do
        use Jido.AI.Algorithms.Base,
          name: "custom",
          description: "A custom algorithm implementation"

        @impl true
        def execute(input, context) do
          # Your algorithm logic here
          {:ok, %{result: input[:value] * 2}}
        end
      end

  ## Options

  The following options can be passed to `use Jido.AI.Algorithms.Base`:

    * `:name` - (required) String name of the algorithm
    * `:description` - (required) String description of what the algorithm does
    * Additional keys are included in the metadata map

  ## Default Implementations

  The following callbacks have default implementations that can be overridden:

    * `can_execute?/2` - Returns `true` by default
    * `before_execute/2` - Returns `{:ok, input}` by default (pass-through)
    * `after_execute/2` - Returns `{:ok, result}` by default (pass-through)
    * `on_error/2` - Returns `{:fail, error}` by default (no retry)

  ## Helper Functions

  The following helper functions are injected into your module:

    * `run_with_hooks/3` - Executes the algorithm with before/after hooks
    * `handle_error/3` - Processes errors through the on_error callback
    * `merge_context/2` - Merges additional context into existing context

  ## Example with Overrides

      defmodule MyApp.Algorithms.Validated do
        use Jido.AI.Algorithms.Base,
          name: "validated",
          description: "Algorithm with input validation"

        @impl true
        def execute(input, _context) do
          {:ok, %{doubled: input[:value] * 2}}
        end

        @impl true
        def can_execute?(input, _context) do
          is_number(input[:value])
        end

        @impl true
        def before_execute(input, _context) do
          {:ok, Map.put(input, :validated_at, DateTime.utc_now())}
        end
      end
  """

  # ============================================================================
  # Using Macro
  # ============================================================================

  @doc """
  Injects the Algorithm behavior and default implementations.

  ## Options

    * `:name` - (required) String name of the algorithm
    * `:description` - (required) String description
    * Additional keys are merged into metadata

  ## Example

      use Jido.AI.Algorithms.Base,
        name: "my_algorithm",
        description: "Does something useful",
        version: "1.0.0"
  """
  defmacro __using__(opts) do
    # Compile-time validation of required options
    if !Keyword.has_key?(opts, :name) do
      raise ArgumentError, """
      Missing required :name option for Jido.AI.Algorithms.Base.

      Usage:
          use Jido.AI.Algorithms.Base,
            name: "my_algorithm",
            description: "What this algorithm does"
      """
    end

    if !Keyword.has_key?(opts, :description) do
      raise ArgumentError, """
      Missing required :description option for Jido.AI.Algorithms.Base.

      Usage:
          use Jido.AI.Algorithms.Base,
            name: "my_algorithm",
            description: "What this algorithm does"
      """
    end

    quote location: :keep do
      @behaviour Jido.AI.Algorithms.Algorithm

      @_algorithm_opts unquote(opts)

      # ========================================================================
      # Default Metadata Implementation
      # ========================================================================

      @doc false
      @impl true
      def metadata do
        opts = @_algorithm_opts

        base = %{
          name: Keyword.fetch!(opts, :name),
          description: Keyword.fetch!(opts, :description)
        }

        # Merge any additional options into metadata
        opts
        |> Keyword.drop([:name, :description])
        |> Enum.into(base)
      end

      # ========================================================================
      # Default Optional Callback Implementations
      # ========================================================================

      @doc false
      @impl true
      def can_execute?(_input, _context), do: true

      @doc false
      @impl true
      def before_execute(input, _context), do: {:ok, input}

      @doc false
      @impl true
      def after_execute(result, _context), do: {:ok, result}

      @doc false
      @impl true
      def on_error(error, _context), do: {:fail, error}

      # Allow overriding defaults
      defoverridable can_execute?: 2, before_execute: 2, after_execute: 2, on_error: 2, metadata: 0

      # ========================================================================
      # Helper Functions
      # ========================================================================

      @doc """
      Executes the algorithm with before and after hooks.

      This function orchestrates the full execution flow:
      1. Calls `before_execute/2` to preprocess input
      2. Calls `execute/2` with the preprocessed input
      3. Calls `after_execute/2` to postprocess the result

      If any step returns an error, execution stops and the error is returned.

      ## Arguments

        * `input` - The input map for the algorithm
        * `context` - The execution context

      ## Returns

        * `{:ok, result}` - Successful execution with final result
        * `{:error, reason}` - Execution failed at some step

      ## Example

          result = MyAlgorithm.run_with_hooks(%{value: 10}, %{})
      """
      @spec run_with_hooks(map(), map()) :: {:ok, map()} | {:error, term()}
      def run_with_hooks(input, context) do
        with {:ok, processed_input} <- before_execute(input, context),
             {:ok, result} <- execute(processed_input, context) do
          after_execute(result, context)
        end
      end

      @doc """
      Handles errors using the on_error callback if implemented.

      This function checks if the module implements the `on_error/2` callback
      and delegates to it. If not implemented, it returns `{:fail, error}`.

      ## Arguments

        * `error` - The error term from a failed execution
        * `context` - The execution context

      ## Returns

        * `{:retry, opts}` - Retry execution with the given options
        * `{:fail, reason}` - Fail with the given reason

      ## Example

          case MyAlgorithm.execute(input, context) do
            {:ok, result} -> {:ok, result}
            {:error, error} -> MyAlgorithm.handle_error(error, context)
          end
      """
      @spec handle_error(term(), map()) ::
              {:retry, keyword()} | {:fail, term()}
      def handle_error(error, context) do
        on_error(error, context)
      end

      @doc """
      Merges additional context into the existing context.

      This is a convenience function for updating the context map
      during algorithm execution.

      ## Arguments

        * `context` - The existing context map
        * `additions` - Map or keyword list of additions to merge

      ## Returns

        The merged context map.

      ## Example

          new_context = merge_context(context, %{step: 1, started_at: DateTime.utc_now()})
      """
      @spec merge_context(map(), map() | keyword()) :: map()
      def merge_context(context, additions) when is_map(additions) do
        Map.merge(context, additions)
      end

      def merge_context(context, additions) when is_list(additions) do
        Enum.into(additions, context)
      end
    end
  end
end
