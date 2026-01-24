defmodule Jido.AI.Algorithms.Helpers do
  @moduledoc """
  Shared helper functions for algorithm implementations.

  This module provides common utility functions used across multiple algorithm
  implementations, including result handling, merging, and error processing.

  ## Security Considerations

  Several functions in this module accept user-provided functions (e.g., custom
  merge strategies). These functions are executed without sandboxing.

  **WARNING**: Never pass functions from untrusted sources to these helpers.
  Functions should only come from compile-time definitions or trusted runtime
  sources.

  ## Functions

    * `deep_merge/2` - Deep merges two maps with depth limiting
    * `deep_merge/3` - Deep merges with explicit depth limit
    * `partition_results/1` - Splits results into successes and errors
    * `handle_results/3` - Processes results according to error mode
    * `merge_successes/2` - Merges successful results by strategy
  """

  @default_max_depth 100

  # ============================================================================
  # Deep Merge
  # ============================================================================

  @doc """
  Deep merges two maps, with nested maps being recursively merged.

  Uses a default maximum depth of #{@default_max_depth} to prevent stack overflow
  from deeply nested structures.

  ## Examples

      iex> Helpers.deep_merge(%{a: %{b: 1}}, %{a: %{c: 2}})
      %{a: %{b: 1, c: 2}}

      iex> Helpers.deep_merge(%{a: 1}, %{a: 2})
      %{a: 2}
  """
  @spec deep_merge(map(), map()) :: map()
  def deep_merge(left, right) do
    deep_merge(left, right, @default_max_depth)
  end

  @doc """
  Deep merges two maps with an explicit depth limit.

  When the depth limit is reached, the right value overwrites the left
  without further recursion.

  ## Arguments

    * `left` - The base map
    * `right` - The map to merge into left
    * `max_depth` - Maximum recursion depth (prevents stack overflow)

  ## Examples

      iex> Helpers.deep_merge(%{a: %{b: 1}}, %{a: %{c: 2}}, 10)
      %{a: %{b: 1, c: 2}}
  """
  @spec deep_merge(map(), map(), non_neg_integer()) :: map()
  def deep_merge(left, right, max_depth)

  def deep_merge(left, right, 0) when is_map(left) and is_map(right) do
    # Depth limit reached, just use right value
    right
  end

  def deep_merge(left, right, max_depth) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val, max_depth - 1)

      _key, _left_val, right_val ->
        right_val
    end)
  end

  def deep_merge(_left, right, _max_depth), do: right

  # ============================================================================
  # Result Partitioning
  # ============================================================================

  @doc """
  Partitions a list of results into successes and errors.

  ## Arguments

    * `results` - List of `{:ok, value}` or `{:error, reason}` tuples

  ## Returns

    A tuple of `{successes, errors}` where each is a list of the original tuples.

  ## Examples

      iex> Helpers.partition_results([{:ok, 1}, {:error, :fail}, {:ok, 2}])
      {[{:ok, 1}, {:ok, 2}], [{:error, :fail}]}
  """
  @spec partition_results([{:ok, term()} | {:error, term()}]) ::
          {[{:ok, term()}], [{:error, term()}]}
  def partition_results(results) do
    Enum.split_with(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)
  end

  # ============================================================================
  # Result Handling
  # ============================================================================

  @doc """
  Handles parallel execution results according to the specified error mode.

  ## Arguments

    * `results` - List of `{:ok, value}` or `{:error, reason}` tuples
    * `merge_strategy` - How to merge successful results
    * `error_mode` - How to handle errors

  ## Error Modes

    * `:fail_fast` - Return first error encountered
    * `:collect_errors` - Return all errors with successful results
    * `:ignore_errors` - Return only successful results

  ## Returns

    * `{:ok, merged}` - When all succeed or errors are ignored
    * `{:error, reason}` - When fail_fast encounters error
    * `{:error, %{errors: [...], successful: [...]}}` - When collecting errors
  """
  @spec handle_results(
          [{:ok, term()} | {:error, term()}],
          :merge_maps | :collect | (list() -> term()),
          :fail_fast | :collect_errors | :ignore_errors
        ) :: {:ok, term()} | {:error, term()}
  def handle_results(results, merge_strategy, error_mode) do
    {successes, errors} = partition_results(results)

    case error_mode do
      :fail_fast ->
        handle_fail_fast(successes, errors, merge_strategy)

      :collect_errors ->
        handle_collect_errors(successes, errors, merge_strategy)

      :ignore_errors ->
        handle_ignore_errors(successes, merge_strategy)
    end
  end

  defp handle_fail_fast(successes, errors, merge_strategy) do
    case errors do
      [] ->
        merge_successes(successes, merge_strategy)

      [{:error, reason} | _] ->
        {:error, reason}
    end
  end

  defp handle_collect_errors(successes, errors, merge_strategy) do
    case {successes, errors} do
      {_, []} ->
        merge_successes(successes, merge_strategy)

      {[], _} ->
        error_reasons = Enum.map(errors, fn {:error, reason} -> reason end)
        {:error, %{errors: error_reasons, successful: []}}

      {_, _} ->
        success_results = Enum.map(successes, fn {:ok, result} -> result end)
        error_reasons = Enum.map(errors, fn {:error, reason} -> reason end)
        {:error, %{errors: error_reasons, successful: success_results}}
    end
  end

  defp handle_ignore_errors(successes, merge_strategy) do
    case successes do
      [] ->
        {:error, :all_failed}

      _ ->
        merge_successes(successes, merge_strategy)
    end
  end

  # ============================================================================
  # Result Merging
  # ============================================================================

  @doc """
  Merges successful results according to the specified strategy.

  ## Arguments

    * `successes` - List of `{:ok, value}` tuples
    * `merge_strategy` - How to merge the values

  ## Merge Strategies

    * `:merge_maps` - Deep merge all result maps
    * `:collect` - Return list of results
    * `fun/1` - Custom function receiving list of results

  ## Security Warning

  Custom merge functions are executed without sandboxing. Only pass functions
  from trusted sources.

  ## Examples

      iex> Helpers.merge_successes([{:ok, %{a: 1}}, {:ok, %{b: 2}}], :merge_maps)
      {:ok, %{a: 1, b: 2}}

      iex> Helpers.merge_successes([{:ok, 1}, {:ok, 2}], :collect)
      {:ok, [1, 2]}
  """
  @spec merge_successes(
          [{:ok, term()}],
          :merge_maps | :collect | (list() -> term())
        ) :: {:ok, term()}
  def merge_successes(successes, merge_strategy) do
    results = Enum.map(successes, fn {:ok, result} -> result end)
    merged = merge_results(results, merge_strategy)
    {:ok, merged}
  end

  defp merge_results(results, :merge_maps) do
    Enum.reduce(results, %{}, &deep_merge(&2, &1))
  end

  defp merge_results(results, :collect) do
    results
  end

  defp merge_results(results, merge_fn) when is_function(merge_fn, 1) do
    merge_fn.(results)
  end

  # ============================================================================
  # Algorithm Validation
  # ============================================================================

  @doc """
  Validates that a module is a valid algorithm with required callbacks.

  ## Arguments

    * `module` - The module to validate

  ## Returns

    * `true` if the module exports `execute/2`
    * `false` otherwise
  """
  @spec valid_algorithm?(module()) :: boolean()
  def valid_algorithm?(module) when is_atom(module) do
    function_exported?(module, :execute, 2)
  end

  def valid_algorithm?(_), do: false
end
