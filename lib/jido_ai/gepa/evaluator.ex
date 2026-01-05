defmodule Jido.AI.GEPA.Evaluator do
  @moduledoc """
  Evaluates prompt variants against a set of tasks.

  The Evaluator runs a `PromptVariant`'s template against a collection of
  `Task` structs, collecting metrics (accuracy, token usage, latency) that
  are used for Pareto-optimal selection in GEPA.

  ## Usage

      # Create tasks and a variant
      tasks = [
        Task.new!(%{input: "What is 2+2?", expected: "4"}),
        Task.new!(%{input: "What is 3+3?", expected: "6"})
      ]
      variant = PromptVariant.new!(%{template: "Answer concisely: {{input}}"})

      # Evaluate the variant
      {:ok, result} = Evaluator.evaluate_variant(variant, tasks, runner: my_runner)

      # Result contains metrics
      result.accuracy   # => 0.75
      result.token_cost # => 150
      result.results    # => [%{task: task1, success: true, ...}, ...]

  ## Runner Function

  The evaluator requires a `:runner` function that executes the actual LLM call.
  This allows flexibility in how tasks are run (e.g., using different strategies,
  models, or mock implementations for testing).

  The runner function signature:
      (template :: String.t(), input :: String.t(), opts :: keyword()) ->
        {:ok, %{output: String.t(), tokens: integer()}} | {:error, term()}
  """

  alias Jido.AI.GEPA.PromptVariant
  alias Jido.AI.GEPA.Task, as: GEPATask
  alias Jido.AI.GEPA.Helpers

  @type run_result :: %{
          task: GEPATask.t(),
          success: boolean(),
          output: String.t() | nil,
          tokens: non_neg_integer(),
          latency_ms: non_neg_integer(),
          error: term() | nil
        }

  @type eval_result :: %{
          accuracy: float(),
          token_cost: non_neg_integer(),
          latency_ms: non_neg_integer(),
          results: [run_result()]
        }

  @type runner_fn :: (String.t(), String.t(), keyword() -> {:ok, map()} | {:error, term()})

  @doc """
  Evaluates a prompt variant against a set of tasks.

  ## Parameters

  - `variant` - The `PromptVariant` to evaluate
  - `tasks` - List of `GEPATask` structs to run
  - `opts` - Options:
    - `:runner` (required) - Function to execute LLM calls
    - `:parallel` - Run tasks in parallel (default: false)
    - `:timeout` - Timeout per task in ms (default: 30_000)
    - `:runner_opts` - Additional options passed to runner

  ## Returns

  `{:ok, eval_result}` with aggregated metrics, or `{:error, reason}`.

  ## Example

      {:ok, result} = Evaluator.evaluate_variant(variant, tasks,
        runner: &MyRunner.run/3,
        parallel: true
      )
  """
  @spec evaluate_variant(PromptVariant.t(), [GEPATask.t()], keyword()) ::
          {:ok, eval_result()} | {:error, atom()}
  def evaluate_variant(%PromptVariant{} = variant, tasks, opts) when is_list(tasks) do
    case validate_opts(opts) do
      :ok ->
        results = run_all_tasks(variant, tasks, opts)
        {:ok, aggregate_results(results)}

      {:error, _} = error ->
        error
    end
  end

  def evaluate_variant(_, _, _), do: {:error, :invalid_args}

  @doc """
  Runs a single task with a prompt variant.

  ## Parameters

  - `variant` - The `PromptVariant` containing the template
  - `task` - The `GEPATask` to run
  - `opts` - Options:
    - `:runner` (required) - Function to execute LLM calls
    - `:timeout` - Timeout in ms (default: 30_000)
    - `:runner_opts` - Additional options passed to runner

  ## Returns

  A `run_result` map with:
  - `:task` - The original task
  - `:success` - Whether the output passed the task's success criteria
  - `:output` - The LLM output (nil on error)
  - `:tokens` - Token count used
  - `:latency_ms` - Time taken in milliseconds
  - `:error` - Error term if failed, nil otherwise

  ## Example

      result = Evaluator.run_single_task(variant, task, runner: &MyRunner.run/3)
      result.success  # => true
      result.output   # => "The answer is 4"
  """
  @spec run_single_task(PromptVariant.t(), GEPATask.t(), keyword()) :: run_result()
  def run_single_task(%PromptVariant{} = variant, %GEPATask{} = task, opts) do
    runner = Keyword.fetch!(opts, :runner)
    timeout = Keyword.get(opts, :timeout, 30_000)
    runner_opts = Keyword.get(opts, :runner_opts, [])

    start_time = System.monotonic_time(:millisecond)

    # Render the template with task input
    prompt = render_template(variant.template, task.input)

    # Execute with timeout protection
    # Wrap runner in try/rescue inside the task to catch exceptions
    safe_runner = fn ->
      try do
        runner.(prompt, task.input, runner_opts)
      rescue
        e -> {:error, {:exception, Exception.message(e)}}
      catch
        kind, reason -> {:error, {kind, reason}}
      end
    end

    result =
      try do
        async_task = Elixir.Task.async(safe_runner)

        case Elixir.Task.yield(async_task, timeout) || Elixir.Task.shutdown(async_task) do
          {:ok, runner_result} -> runner_result
          nil -> {:error, :timeout}
        end
      rescue
        e -> {:error, {:exception, Exception.message(e)}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end

    end_time = System.monotonic_time(:millisecond)
    latency_ms = max(0, end_time - start_time)

    build_run_result(task, result, latency_ms)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp validate_opts(opts) do
    Helpers.validate_runner_opts(opts)
  end

  defp run_all_tasks(variant, tasks, opts) do
    parallel = Keyword.get(opts, :parallel, false)

    if parallel do
      run_tasks_parallel(variant, tasks, opts)
    else
      run_tasks_sequential(variant, tasks, opts)
    end
  end

  defp run_tasks_sequential(variant, tasks, opts) do
    Enum.map(tasks, fn task ->
      run_single_task(variant, task, opts)
    end)
  end

  defp run_tasks_parallel(variant, tasks, opts) do
    # Calculate bounded timeout: individual timeout * task count + buffer
    per_task_timeout = Keyword.get(opts, :timeout, 30_000)
    total_timeout = per_task_timeout * length(tasks) + 5_000

    tasks
    |> Enum.map(fn task ->
      Elixir.Task.async(fn -> run_single_task(variant, task, opts) end)
    end)
    |> Enum.map(&Elixir.Task.await(&1, total_timeout))
  end

  defp render_template(template, input) when is_binary(template) do
    # Simple template substitution - replace {{input}} with actual input
    template
    |> String.replace("{{input}}", input)
    |> String.replace("{{ input }}", input)
  end

  defp render_template(template, input) when is_map(template) do
    # For map templates, render each string value
    template
    |> Enum.map(fn {k, v} ->
      if is_binary(v) do
        {k, render_template(v, input)}
      else
        {k, v}
      end
    end)
    |> Map.new()
  end

  defp render_template(template, _input), do: template

  defp build_run_result(task, {:ok, %{output: output, tokens: tokens}}, latency_ms) do
    success = Jido.AI.GEPA.Task.success?(task, output || "")

    %{
      task: task,
      success: success,
      output: output,
      tokens: tokens || 0,
      latency_ms: latency_ms,
      error: nil
    }
  end

  defp build_run_result(task, {:ok, %{output: output}}, latency_ms) do
    # Handle case where tokens is not provided
    build_run_result(task, {:ok, %{output: output, tokens: 0}}, latency_ms)
  end

  defp build_run_result(task, {:error, reason}, latency_ms) do
    %{
      task: task,
      success: false,
      output: nil,
      tokens: 0,
      latency_ms: latency_ms,
      error: reason
    }
  end

  defp aggregate_results(results) do
    total = length(results)
    successes = Enum.count(results, & &1.success)

    accuracy =
      if total > 0 do
        Float.round(successes / total, 4)
      else
        0.0
      end

    token_cost = Enum.sum(Enum.map(results, & &1.tokens))
    total_latency = Enum.sum(Enum.map(results, & &1.latency_ms))

    avg_latency =
      if total > 0 do
        div(total_latency, total)
      else
        0
      end

    %{
      accuracy: accuracy,
      token_cost: token_cost,
      latency_ms: avg_latency,
      results: results
    }
  end
end
