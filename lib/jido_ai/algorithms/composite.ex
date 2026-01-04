defmodule Jido.AI.Algorithms.Composite do
  @moduledoc """
  Provides composition operators for building complex algorithms from simpler ones.

  The Composite module offers operators that create new algorithm modules from
  existing ones, enabling sequential chaining, parallel execution, conditional
  selection, and repetition patterns.

  ## Composition Operators

  ### `sequence/1` - Sequential Composition

  Creates an algorithm that executes multiple algorithms in sequence:

      algo = Composite.sequence([ValidateInput, ProcessData, SaveResult])
      {:ok, result} = Composite.execute_composite(algo, input, context)

  ### `parallel/1` - Parallel Composition

  Creates an algorithm that executes multiple algorithms concurrently:

      algo = Composite.parallel([FetchA, FetchB, FetchC], merge_strategy: :merge_maps)
      {:ok, result} = Composite.execute_composite(algo, input, context)

  ### `choice/3` - Conditional Selection

  Creates an algorithm that selects between two algorithms based on a predicate:

      algo = Composite.choice(
        fn input -> input.premium? end,
        PremiumHandler,
        StandardHandler
      )
      {:ok, result} = Composite.execute_composite(algo, input, context)

  ### `repeat/2` - Repeated Execution

  Creates an algorithm that executes another algorithm multiple times:

      # Fixed number of times
      algo = Composite.repeat(RetryableOperation, times: 3)

      # While condition holds
      algo = Composite.repeat(IncrementStep, while: fn result -> result.value < 100 end)

  ## Dynamic Composition

  ### `compose/2` - Runtime Composition

  Combines two algorithms into a sequential chain:

      algo1 = Composite.sequence([A, B])
      algo2 = Composite.parallel([C, D])
      combined = Composite.compose(algo1, algo2)

  ### Nested Compositions

  Composition operators can be nested arbitrarily:

      workflow = Composite.sequence([
        ValidateInput,
        Composite.parallel([FetchA, FetchB]),
        Composite.choice(
          fn input -> input.fast_path? end,
          FastProcess,
          StandardProcess
        ),
        SaveResult
      ])

  ## Conditional Execution

  ### `when_cond/2` - Conditional Guard

  Creates an algorithm that only executes when a condition is met:

      algo = Composite.when_cond(fn input -> input.valid? end, ProcessData)
      {:ok, result} = Composite.execute_composite(algo, input, context)

  If the condition is false, returns the input unchanged.

  Pattern matching variant:

      algo = Composite.when_cond(%{type: :premium}, PremiumHandler)

  ## Executing Composites

  All composition operators return structs that can be executed via:

      {:ok, result} = Composite.execute_composite(composite, input, context)

  Or the composite can be used in a context with the `:composite` key:

      {:ok, result} = Composite.execute(input, %{composite: composite})

  ## Telemetry

  The following telemetry events are emitted:

    * `[:jido, :ai, :algorithm, :composite, :start]`
      - Measurements: `%{system_time: integer}`
      - Metadata: `%{type: atom}` - The composition type

    * `[:jido, :ai, :algorithm, :composite, :stop]`
      - Measurements: `%{duration: integer}`
      - Metadata: `%{type: type}`

  ## Example

      defmodule MyWorkflow do
        alias Jido.AI.Algorithms.Composite

        def build do
          Composite.sequence([
            # Stage 1: Validate
            ValidateSchema,

            # Stage 2: Fetch in parallel
            Composite.parallel([FetchUserData, FetchSettings]),

            # Stage 3: Conditional processing
            Composite.choice(
              fn input -> input.premium? end,
              PremiumPipeline,
              StandardPipeline
            ),

            # Stage 4: Retry-able save
            Composite.repeat(SaveWithRetry, times: 3)
          ])
        end
      end

      # Usage
      algo = MyWorkflow.build()
      {:ok, result} = Composite.execute_composite(algo, input, %{})

  ## Security Considerations

  Several composition operators accept user-provided functions:

    * `choice/3` - predicate function
    * `when_cond/2` - condition function
    * `repeat/2` - while predicate function
    * `parallel/2` - custom merge_strategy function

  **WARNING**: These functions are executed without sandboxing. Never pass
  functions from untrusted sources (e.g., deserialized data, user input).
  Functions should only come from compile-time definitions or trusted
  runtime sources.

  ### Repeat Safety

  The `repeat/2` operator has a built-in safety limit of 10,000 iterations
  (configurable via `:max_iterations` option) to prevent infinite loops
  from buggy predicates.
  """

  use Jido.AI.Algorithms.Base,
    name: "composite",
    description: "Composition operators for building complex algorithms"

  alias Jido.AI.Algorithms.Helpers

  # Maximum iterations for repeat to prevent infinite loops
  @max_iterations 10_000

  # ============================================================================
  # Composition Types (Structs for holding composition data)
  # ============================================================================

  defmodule SequenceComposite do
    @moduledoc false
    @type t :: %__MODULE__{algorithms: list(module() | struct())}
    defstruct [:algorithms]
  end

  defmodule ParallelComposite do
    @moduledoc false
    @type t :: %__MODULE__{algorithms: list(module() | struct()), options: map()}
    defstruct [:algorithms, :options]
  end

  defmodule ChoiceComposite do
    @moduledoc false
    @type t :: %__MODULE__{
            predicate: (map() -> boolean()),
            if_true: module() | struct(),
            if_false: module() | struct()
          }
    defstruct [:predicate, :if_true, :if_false]
  end

  defmodule RepeatComposite do
    @moduledoc false
    @type t :: %__MODULE__{algorithm: module() | struct(), options: map()}
    defstruct [:algorithm, :options]
  end

  defmodule WhenComposite do
    @moduledoc false
    @type t :: %__MODULE__{
            condition: (map() -> boolean()) | map(),
            algorithm: module() | struct()
          }
    defstruct [:condition, :algorithm]
  end

  defmodule ComposeComposite do
    @moduledoc false
    @type t :: %__MODULE__{first: module() | struct(), second: module() | struct()}
    defstruct [:first, :second]
  end

  # ============================================================================
  # Composition Operators (Public API)
  # ============================================================================

  @doc """
  Creates a sequential composition of algorithms.

  The algorithms are executed in order, with each algorithm's output
  becoming the next algorithm's input.

  ## Examples

      algo = Composite.sequence([ValidateInput, ProcessData, SaveResult])
      {:ok, result} = Composite.execute_composite(algo, input, context)
  """
  @spec sequence(list(module() | struct())) :: SequenceComposite.t()
  def sequence(algorithms) when is_list(algorithms) do
    %SequenceComposite{algorithms: algorithms}
  end

  @doc """
  Creates a parallel composition of algorithms.

  All algorithms receive the same input and execute concurrently.
  Results are merged according to the merge strategy.

  ## Options

    * `:merge_strategy` - How to merge results (default: `:merge_maps`)
    * `:error_mode` - How to handle errors (default: `:fail_fast`)
    * `:max_concurrency` - Max parallel tasks
    * `:timeout` - Timeout per task in ms

  ## Examples

      algo = Composite.parallel([FetchA, FetchB], merge_strategy: :collect)
      {:ok, results} = Composite.execute_composite(algo, input, context)
  """
  @spec parallel(list(module() | struct()), keyword()) :: ParallelComposite.t()
  def parallel(algorithms, opts \\ []) when is_list(algorithms) do
    %ParallelComposite{algorithms: algorithms, options: Map.new(opts)}
  end

  @doc """
  Creates a choice composition that selects between two algorithms.

  The predicate function receives the input and returns a boolean.
  If true, `if_true` algorithm is executed; otherwise `if_false`.

  ## Examples

      algo = Composite.choice(
        fn input -> input.premium? end,
        PremiumHandler,
        StandardHandler
      )
  """
  @spec choice((map() -> boolean()), module() | struct(), module() | struct()) ::
          ChoiceComposite.t()
  def choice(predicate, if_true, if_false) when is_function(predicate, 1) do
    %ChoiceComposite{predicate: predicate, if_true: if_true, if_false: if_false}
  end

  @doc """
  Creates a repeated execution of an algorithm.

  ## Options

    * `:times` - Number of times to execute (default: 1)
    * `:while` - Predicate function that receives result, continues while true
    * `:max_iterations` - Safety limit to prevent infinite loops (default: 10,000)

  If both `:times` and `:while` are specified, execution stops when either
  condition is met (times exhausted or while returns false).

  The `:max_iterations` option provides a safety cap that cannot be exceeded
  regardless of `:times` or `:while` settings. This prevents runaway loops
  from buggy predicates.

  ## Examples

      # Fixed repetition
      algo = Composite.repeat(IncrementStep, times: 5)

      # Conditional repetition
      algo = Composite.repeat(IncrementStep, while: fn result -> result.value < 100 end)

      # With custom safety limit
      algo = Composite.repeat(Step, times: 1_000_000, max_iterations: 1000)
  """
  @spec repeat(module() | struct(), keyword()) :: RepeatComposite.t()
  def repeat(algorithm, opts \\ []) do
    %RepeatComposite{algorithm: algorithm, options: Map.new(opts)}
  end

  @doc """
  Creates a conditional execution guard.

  The algorithm only executes if the condition is true.
  If false, returns the input unchanged.

  The condition can be:
  - A function receiving input: `fn input -> input.valid? end`
  - A pattern map for matching: `%{type: :premium}`

  ## Examples

      # Function predicate
      algo = Composite.when_cond(fn input -> input.valid? end, ProcessData)

      # Pattern matching
      algo = Composite.when_cond(%{type: :premium}, PremiumHandler)
  """
  @spec when_cond((map() -> boolean()) | map(), module() | struct()) :: WhenComposite.t()
  def when_cond(condition, algorithm) do
    %WhenComposite{condition: condition, algorithm: algorithm}
  end

  @doc """
  Composes two algorithms into a sequential chain.

  This is useful for combining already-composed algorithms at runtime.

  ## Examples

      algo1 = Composite.sequence([A, B])
      algo2 = Composite.parallel([C, D])
      combined = Composite.compose(algo1, algo2)
  """
  @spec compose(module() | struct(), module() | struct()) :: ComposeComposite.t()
  def compose(first, second) do
    %ComposeComposite{first: first, second: second}
  end

  # ============================================================================
  # Composite Execution (Public API)
  # ============================================================================

  @doc """
  Executes a composite algorithm structure.

  This is the main entry point for executing composites created with the
  composition operators.

  ## Examples

      algo = Composite.sequence([A, B, C])
      {:ok, result} = Composite.execute_composite(algo, input, context)
  """
  @spec execute_composite(struct(), map(), map()) :: {:ok, map()} | {:error, term()}
  def execute_composite(%SequenceComposite{} = c, input, context) do
    execute_sequence(c.algorithms, input, context)
  end

  def execute_composite(%ParallelComposite{} = c, input, context) do
    execute_parallel(c.algorithms, input, context, c.options)
  end

  def execute_composite(%ChoiceComposite{} = c, input, context) do
    execute_choice(c.predicate, c.if_true, c.if_false, input, context)
  end

  def execute_composite(%RepeatComposite{} = c, input, context) do
    execute_repeat(c.algorithm, input, context, c.options)
  end

  def execute_composite(%WhenComposite{} = c, input, context) do
    execute_when(c.condition, c.algorithm, input, context)
  end

  def execute_composite(%ComposeComposite{} = c, input, context) do
    execute_compose(c.first, c.second, input, context)
  end

  @doc """
  Checks if a composite can execute with the given input and context.
  """
  @spec can_execute_composite?(struct(), map(), map()) :: boolean()
  def can_execute_composite?(%SequenceComposite{algorithms: algorithms}, input, context) do
    Enum.all?(algorithms, &check_can_execute(&1, input, context))
  end

  def can_execute_composite?(%ParallelComposite{algorithms: algorithms}, input, context) do
    Enum.all?(algorithms, &check_can_execute(&1, input, context))
  end

  def can_execute_composite?(%ChoiceComposite{}, _input, _context) do
    # For choice, we can always execute - the predicate determines which branch
    true
  end

  def can_execute_composite?(%RepeatComposite{algorithm: algorithm}, input, context) do
    check_can_execute(algorithm, input, context)
  end

  def can_execute_composite?(%WhenComposite{algorithm: algorithm}, input, context) do
    check_can_execute(algorithm, input, context)
  end

  def can_execute_composite?(%ComposeComposite{first: first, second: second}, input, context) do
    check_can_execute(first, input, context) && check_can_execute(second, input, context)
  end

  # ============================================================================
  # Algorithm Implementation (for when Composite itself is used as an algorithm)
  # ============================================================================

  @impl true
  def execute(input, context) do
    # When Composite is used directly, look for :composite in context
    composite = Map.get(context, :composite)

    case composite do
      nil ->
        {:ok, input}

      %SequenceComposite{} ->
        execute_composite(composite, input, context)

      %ParallelComposite{} ->
        execute_composite(composite, input, context)

      %ChoiceComposite{} ->
        execute_composite(composite, input, context)

      %RepeatComposite{} ->
        execute_composite(composite, input, context)

      %WhenComposite{} ->
        execute_composite(composite, input, context)

      %ComposeComposite{} ->
        execute_composite(composite, input, context)
    end
  end

  @impl true
  def can_execute?(input, context) do
    composite = Map.get(context, :composite)

    case composite do
      nil -> true
      _ -> can_execute_composite?(composite, input, context)
    end
  end

  # ============================================================================
  # Execution Functions
  # ============================================================================

  defp execute_sequence(algorithms, input, context) do
    emit_start(:sequence)
    start_time = System.monotonic_time()

    # Execute algorithms in sequence, handling both modules and composite structs
    result = do_execute_sequence(algorithms, input, context)

    emit_stop(:sequence, start_time)
    result
  end

  defp do_execute_sequence([], input, _context) do
    {:ok, input}
  end

  defp do_execute_sequence(algorithms, input, context) do
    algorithms
    |> Enum.reduce_while({:ok, input}, fn algorithm, {:ok, current_input} ->
      case execute_algorithm(algorithm, current_input, context) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp execute_parallel(algorithms, input, context, options) do
    emit_start(:parallel)
    start_time = System.monotonic_time()

    # Execute algorithms in parallel, handling both modules and composite structs
    result = do_execute_parallel(algorithms, input, context, options)

    emit_stop(:parallel, start_time)
    result
  end

  defp do_execute_parallel([], input, _context, _options) do
    {:ok, input}
  end

  defp do_execute_parallel(algorithms, input, context, options) do
    merge_strategy = Map.get(options, :merge_strategy, :merge_maps)
    error_mode = Map.get(options, :error_mode, :fail_fast)
    max_concurrency = Map.get(options, :max_concurrency, System.schedulers_online() * 2)
    timeout = Map.get(options, :timeout, 5_000)

    results =
      algorithms
      |> Task.async_stream(
        fn algorithm ->
          execute_algorithm(algorithm, input, context)
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task,
        ordered: true
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, :timeout} -> {:error, :timeout}
        {:exit, reason} -> {:error, {:exit, reason}}
      end)

    Helpers.handle_results(results, merge_strategy, error_mode)
  end

  defp execute_choice(predicate, if_true, if_false, input, context) do
    emit_start(:choice)
    start_time = System.monotonic_time()

    selected =
      if predicate.(input) do
        if_true
      else
        if_false
      end

    result = execute_algorithm(selected, input, context)

    emit_stop(:choice, start_time)
    result
  end

  defp execute_repeat(algorithm, input, context, options) do
    emit_start(:repeat)
    start_time = System.monotonic_time()

    times = Map.get(options, :times, 1)
    while_fn = Map.get(options, :while)
    max_iter = Map.get(options, :max_iterations, @max_iterations)

    # Enforce max iterations to prevent infinite loops
    effective_times = min(times, max_iter)

    result = do_repeat(algorithm, input, context, effective_times, while_fn, 0, max_iter)

    emit_stop(:repeat, start_time)
    result
  end

  defp execute_when(condition, algorithm, input, context) do
    emit_start(:when)
    start_time = System.monotonic_time()

    should_execute = evaluate_condition(condition, input)

    result =
      if should_execute do
        execute_algorithm(algorithm, input, context)
      else
        {:ok, input}
      end

    emit_stop(:when, start_time)
    result
  end

  defp execute_compose(first, second, input, context) do
    emit_start(:compose)
    start_time = System.monotonic_time()

    result =
      with {:ok, intermediate} <- execute_algorithm(first, input, context) do
        execute_algorithm(second, intermediate, context)
      end

    emit_stop(:compose, start_time)
    result
  end

  # ============================================================================
  # Private Functions - Algorithm Dispatch
  # ============================================================================

  # Pattern matching for composite structs
  defp execute_algorithm(%SequenceComposite{} = c, input, context),
    do: execute_composite(c, input, context)

  defp execute_algorithm(%ParallelComposite{} = c, input, context),
    do: execute_composite(c, input, context)

  defp execute_algorithm(%ChoiceComposite{} = c, input, context),
    do: execute_composite(c, input, context)

  defp execute_algorithm(%RepeatComposite{} = c, input, context),
    do: execute_composite(c, input, context)

  defp execute_algorithm(%WhenComposite{} = c, input, context),
    do: execute_composite(c, input, context)

  defp execute_algorithm(%ComposeComposite{} = c, input, context),
    do: execute_composite(c, input, context)

  # Module-based algorithms
  defp execute_algorithm(algorithm, input, context) when is_atom(algorithm) do
    if Helpers.valid_algorithm?(algorithm) do
      algorithm.execute(input, context)
    else
      {:error, {:invalid_algorithm, algorithm}}
    end
  end

  defp execute_algorithm(algorithm, _input, _context) do
    {:error, {:invalid_algorithm, algorithm}}
  end

  # Pattern matching for composite structs
  defp check_can_execute(%SequenceComposite{} = c, input, context),
    do: can_execute_composite?(c, input, context)

  defp check_can_execute(%ParallelComposite{} = c, input, context),
    do: can_execute_composite?(c, input, context)

  defp check_can_execute(%ChoiceComposite{} = c, input, context),
    do: can_execute_composite?(c, input, context)

  defp check_can_execute(%RepeatComposite{} = c, input, context),
    do: can_execute_composite?(c, input, context)

  defp check_can_execute(%WhenComposite{} = c, input, context),
    do: can_execute_composite?(c, input, context)

  defp check_can_execute(%ComposeComposite{} = c, input, context),
    do: can_execute_composite?(c, input, context)

  # Module-based algorithms
  defp check_can_execute(algorithm, input, context) when is_atom(algorithm) do
    if function_exported?(algorithm, :can_execute?, 2) do
      algorithm.can_execute?(input, context)
    else
      true
    end
  end

  defp check_can_execute(_algorithm, _input, _context), do: true

  # ============================================================================
  # Private Functions - Repeat Logic
  # ============================================================================

  defp do_repeat(_algorithm, result, _context, times, _while_fn, iteration, _max_iter)
       when iteration >= times do
    {:ok, result}
  end

  defp do_repeat(_algorithm, result, _context, _times, _while_fn, iteration, max_iter)
       when iteration >= max_iter do
    # Max iterations reached - return current result to prevent infinite loop
    {:ok, result}
  end

  defp do_repeat(algorithm, input, context, times, while_fn, iteration, max_iter) do
    case execute_algorithm(algorithm, input, context) do
      {:ok, result} ->
        should_continue =
          cond do
            while_fn != nil -> while_fn.(result)
            true -> true
          end

        if should_continue do
          do_repeat(algorithm, result, context, times, while_fn, iteration + 1, max_iter)
        else
          {:ok, result}
        end

      {:error, _} = error ->
        error
    end
  end

  defp evaluate_condition(condition, input) when is_function(condition, 1) do
    condition.(input)
  end

  defp evaluate_condition(pattern, input) when is_map(pattern) do
    Enum.all?(pattern, fn {key, value} ->
      Map.get(input, key) == value
    end)
  end

  # ============================================================================
  # Telemetry
  # ============================================================================

  defp emit_start(type) do
    :telemetry.execute(
      [:jido, :ai, :algorithm, :composite, :start],
      %{system_time: System.system_time()},
      %{type: type}
    )
  end

  defp emit_stop(type, start_time) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:jido, :ai, :algorithm, :composite, :stop],
      %{duration: duration},
      %{type: type}
    )
  end
end
