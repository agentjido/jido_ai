defmodule Sparq do
  @moduledoc """
  Sparq is a simple, extensible interpreter for a custom programming language.
  It provides lexical scoping, first-class functions, modules, and basic arithmetic operations.

  ## Key Features
  - Lexical scoping and variable binding
  - First-class functions and modules
  - Rich debugging and tracing capabilities
  - Pattern matching and type checking
  - Standard library of common operations
  """

  @doc """
  Executes a Sparq script or expression.

  ## Options
    * `:debug` - Enable debug output (default: false)
    * `:step` - Enable step-by-step execution (default: false)
    * `:max_trace_size` - Maximum number of trace entries to keep (default: 1000)
    * `:event_mask` - Debug event types to capture (default: none)

  ## Examples
      iex> Sparq.eval([{:add, [], [1, 2]}])
      {:ok, 3}

      iex> Sparq.eval([
      ...>   {:bind, [], [:x, 42, :let]},
      ...>   {:var, [], :x}
      ...> ])
      {:ok, 42}

      iex> Sparq.eval([{:unknown, [], []}])
      {:error, :unknown_operation}
  """
  def eval(code, opts \\ []) do
    Sparq.Core.execute(code, opts)
  end

  @doc """
  Executes a Sparq script or expression with debug output enabled.
  This is equivalent to calling `eval(code, debug: true)`.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.

  ## Examples
      iex> Sparq.debug([{:add, [], [1, 2]}])
      # [DEBUG] Evaluating built-in: {:add, [1, 2]}
      {:ok, 3}
  """
  def debug(code, opts \\ []) do
    eval(code, Keyword.put(opts, :debug, true))
  end

  @doc """
  Executes a Sparq script or expression with step-by-step execution.
  Pauses after each step and waits for user input to continue.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.

  ## Examples
      iex> Sparq.step([{:add, [], [1, 2]}])
      # Step 1
      # ----------------------------------------
      # Action: Built-in operation: add
      # Line: unknown
      # Current scope: ...
      # ----------------------------------------
      # Press Enter to continue...
  """
  def step(code, opts \\ []) do
    eval(code, Keyword.put(opts, :step, true))
  end

  @doc """
  Creates a new execution context with optional configuration.

  ## Options
    * `:event_mask` - Debug event types to capture
    * `:max_trace_size` - Maximum trace entries to keep
    * `:debug` - Enable debug output
    * `:step` - Enable step-by-step execution

  ## Examples
      iex> ctx = Sparq.new_context(debug: true)
      iex> Sparq.eval([{:add, [], [1, 2]}], context: ctx)
  """
  def new_context(opts \\ []) do
    Sparq.Context.new(opts)
  end

  @doc """
  Returns the execution trace from the last evaluation.
  The trace includes all operations performed, variable accesses, function calls, etc.

  ## Examples
      iex> {:ok, result, ctx} = Sparq.eval([{:add, [], [1, 2]}])
      iex> Sparq.trace(ctx)
      [{:frame_entry, ...}, {:variable_write, ...}, {:frame_exit, ...}]
  """
  def trace(%Sparq.Context{} = ctx) do
    Sparq.Context.get_trace(ctx)
  end

  @doc """
  Returns the execution time of the last evaluation in microseconds.

  ## Examples
      iex> {:ok, result, ctx} = Sparq.eval([{:add, [], [1, 2]}])
      iex> Sparq.timing(ctx)
      42.3
  """
  def timing(%Sparq.Context{} = ctx) do
    Sparq.Context.get_timing(ctx)
  end
end
