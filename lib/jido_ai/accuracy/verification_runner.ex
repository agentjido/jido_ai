defmodule Jido.AI.Accuracy.VerificationRunner do
  @moduledoc """
  Orchestrates verification across multiple verifiers.

  The VerificationRunner coordinates multiple verifiers to evaluate candidates,
  aggregate their scores, and handle errors gracefully. This enables ensemble
  verification where different verification methods are combined for robustness.

  ## Configuration

  Verifiers are configured as a list of tuples containing:
  - The verifier module
  - Configuration options for the verifier
  - Weight for score aggregation

      runner = VerificationRunner.new!(%{
        verifiers: [
          {Jido.AI.Accuracy.Verifiers.DeterministicVerifier,
           %{ground_truth: "42", comparison_type: :exact},
           1.0},
          {Jido.AI.Accuracy.Verifiers.LLMOutcomeVerifier,
           %{model: "anthropic:claude-3-haiku-20250307"},
           0.5}
        ],
        parallel: true,
        aggregation: :weighted_avg,
        on_error: :continue
      })

  ## Execution Modes

  ### Sequential Execution

  Verifiers run one after another. Slower but more predictable:

      VerificationRunner.verify_candidate(runner, candidate, %{})

  ### Parallel Execution

  Verifiers run concurrently using Task.Supervisor. Faster but requires
  stateless verifiers:

      VerificationRunner.verify_candidate(runner, candidate, %{
        mode: :parallel
      })

  ## Aggregation Strategies

  - `:weighted_avg` - Weighted average of all scores (default)
  - `:max` - Maximum score (optimistic)
  - `:min` - Minimum score (pessimistic/bottleneck)
  - `:sum` - Sum of all scores
  - `:product` - Product of all scores (probability-style)

  ## Error Handling

  - `:continue` - Continue with other verifiers on error (default)
  - `:halt` - Stop verification immediately on error

  ## Telemetry

  The following telemetry events are emitted:

  - `[:verification, :start]` - Verification started
  - `[:verification, :stop]` - Verification completed
  - `[:verification, :error]` - Verification failed

  ## Usage

      # Create runner with multiple verifiers
      runner = VerificationRunner.new!(%{
        verifiers: [
          {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
          {LLMOutcomeVerifier, %{model: model}, 0.5}
        ],
        aggregation: :weighted_avg
      })

      # Verify a candidate
      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Verify multiple candidates
      {:ok, results} = VerificationRunner.verify_all_candidates(runner, candidates, %{})

  """

  alias Jido.AI.Accuracy.{Candidate, VerificationResult}

  require Logger

  @type verifier_config :: {module(), map(), number()}
  @type aggregation_strategy :: :weighted_avg | :max | :min | :sum | :product
  @type error_strategy :: :continue | :halt
  @type execution_mode :: :sequential | :parallel

  @type t :: %__MODULE__{
          verifiers: [verifier_config()],
          parallel: boolean(),
          aggregation: aggregation_strategy(),
          on_error: error_strategy(),
          timeout: pos_integer() | nil
        }

  defstruct verifiers: [],
            parallel: false,
            aggregation: :weighted_avg,
            on_error: :continue,
            timeout: 30_000

  @doc """
  Creates a new verification runner from the given attributes.

  ## Options

  - `:verifiers` - List of {verifier_module, config, weight} tuples
  - `:parallel` - Whether to run verifiers in parallel (default: false)
  - `:aggregation` - Score aggregation strategy (default: :weighted_avg)
  - `:on_error` - Error handling strategy (:continue or :halt, default: :continue)
  - `:timeout` - Timeout for verification in ms (default: 30000)

  ## Returns

  - `{:ok, runner}` - Success
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> VerificationRunner.new(%{verifiers: []})
      {:ok, %VerificationRunner{verifiers: []}}

      iex> VerificationRunner.new(%{
      ...>   verifiers: [{DeterministicVerifier, %{ground_truth: "42"}, 1.0}],
      ...>   aggregation: :max
      ...> })
      {:ok, %VerificationRunner{aggregation: :max}}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) or is_map(opts) do
    runner = struct(__MODULE__, opts)

    with :ok <- validate_verifiers(runner.verifiers),
         :ok <- validate_aggregation(runner.aggregation),
         :ok <- validate_error_strategy(runner.on_error),
         :ok <- validate_timeout(runner.timeout) do
      {:ok, runner}
    end
  end

  @doc """
  Creates a new verification runner, raising on error.

  ## Examples

      iex> VerificationRunner.new!(%{verifiers: []})
      %VerificationRunner{verifiers: []}

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) or is_map(opts) do
    case new(opts) do
      {:ok, runner} -> runner
      {:error, reason} -> raise ArgumentError, "Invalid verification runner: #{inspect(reason)}"
    end
  end

  @doc """
  Verifies a single candidate using all configured verifiers.

  Runs each verifier in the configuration and aggregates the results
  according to the aggregation strategy.

  ## Parameters

  - `runner` - The verification runner
  - `candidate` - The candidate to verify
  - `context` - Additional verification context
  - `opts` - Options:
    - `:mode` - Override execution mode (:sequential or :parallel)
    - `:timeout` - Override timeout

  ## Returns

  - `{:ok, result}` - Aggregated verification result
  - `{:error, reason}` - Verification failed

  ## Examples

      iex> runner = VerificationRunner.new!(%{
      ...>   verifiers: [{DeterministicVerifier, %{ground_truth: "42"}, 1.0}]
      ...> })
      iex> candidate = Candidate.new!(%{content: "42"})
      iex> {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})
      iex> result.score >= 0.0
      true

  """
  @spec verify_candidate(t(), Candidate.t(), map(), keyword()) ::
          {:ok, VerificationResult.t()} | {:error, term()}
  def verify_candidate(%__MODULE__{} = runner, %Candidate{} = candidate, context, opts \\ []) do
    mode = Keyword.get(opts, :mode, if(runner.parallel, do: :parallel, else: :sequential))
    timeout = Keyword.get(opts, :timeout, runner.timeout)

    start_time = System.monotonic_time(:millisecond)
    :telemetry.execute([:verification, :start], %{candidate_id: candidate.id}, %{})

    results =
      case mode do
        :parallel -> verify_parallel(runner, candidate, context, timeout)
        :sequential -> verify_sequential(runner, candidate, context, timeout)
      end

    duration = System.monotonic_time(:millisecond) - start_time

    case results do
      {:ok, verifier_results} ->
        aggregated = aggregate_results(runner, verifier_results, candidate)

        :telemetry.execute(
          [:verification, :stop],
          %{candidate_id: candidate.id, count: length(verifier_results)},
          %{duration: duration, score: aggregated.score}
        )

        {:ok, aggregated}

      {:error, _reason} = error ->
        :telemetry.execute([:verification, :error], %{candidate_id: candidate.id}, %{duration: duration})
        error
    end
  end

  @doc """
  Verifies multiple candidates using all configured verifiers.

  Each candidate is verified independently using the same verification
  configuration.

  ## Parameters

  - `runner` - The verification runner
  - `candidates` - List of candidates to verify
  - `context` - Additional verification context
  - `opts` - Options passed through to verify_candidate/4

  ## Returns

  - `{:ok, results}` - List of aggregated verification results
  - `{:error, reason}` - Batch verification failed

  ## Examples

      iex> runner = VerificationRunner.new!(%{
      ...>   verifiers: [{DeterministicVerifier, %{ground_truth: "42"}, 1.0}]
      ...> })
      iex> candidates = [
      ...>   Candidate.new!(%{id: "1", content: "42"}),
      ...>   Candidate.new!(%{id: "2", content: "43"})
      ...> ]
      iex> {:ok, results} = VerificationRunner.verify_all_candidates(runner, candidates, %{})
      iex> length(results)
      2

  """
  @spec verify_all_candidates(t(), [Candidate.t()], map(), keyword()) ::
          {:ok, [VerificationResult.t()]} | {:error, term()}
  def verify_all_candidates(%__MODULE__{} = runner, candidates, context, opts \\ []) when is_list(candidates) do
    results =
      Enum.map(candidates, fn candidate ->
        case verify_candidate(runner, candidate, context, opts) do
          {:ok, result} -> result
          {:error, _reason} -> error_result(candidate, :verification_failed)
        end
      end)

    {:ok, results}
  end

  @doc """
  Aggregates verification results using the specified strategy.

  ## Parameters

  - `results` - List of verification results
  - `weights` - List of weights corresponding to each result
  - `strategy` - Aggregation strategy to use

  ## Returns

  - Aggregated score

  ## Examples

      iex> results = [
      ...>   VerificationResult.new!(%{score: 0.8}),
      ...>   VerificationResult.new!(%{score: 0.6})
      ...> ]
      iex> VerificationRunner.aggregate_scores(results, [1.0, 1.0], :weighted_avg)
      0.7

      iex> VerificationRunner.aggregate_scores(results, [1.0, 1.0], :max)
      0.8

  """
  @spec aggregate_scores([VerificationResult.t()], [number()], aggregation_strategy()) :: number()
  def aggregate_scores(results, weights, strategy \\ :weighted_avg) when is_list(results) and is_list(weights) do
    scores = Enum.map(results, & &1.score)

    case strategy do
      :weighted_avg -> weighted_average(scores, weights)
      :max -> max_score(scores)
      :min -> min_score(scores)
      :sum -> sum_scores(scores)
      :product -> product_scores(scores)
    end
  end

  # Private functions

  defp verify_sequential(%__MODULE__{verifiers: verifiers, on_error: on_error}, candidate, context, timeout) do
    start_time = System.monotonic_time(:millisecond)

    results =
      Enum.reduce_while(verifiers, [], fn {verifier_mod, config, _weight}, acc ->
        remaining_time = timeout - (System.monotonic_time(:millisecond) - start_time)

        if remaining_time <= 0 do
          {:halt, {:error, :timeout}}
        else
          handle_verifier_result(
            run_verifier(verifier_mod, config, candidate, context, remaining_time),
            verifier_mod,
            acc,
            on_error
          )
        end
      end)

    case results do
      {:error, _} = error -> error
      results -> {:ok, Enum.reverse(results)}
    end
  end

  defp handle_verifier_result({:ok, result}, _verifier_mod, acc, _on_error) do
    {:cont, [result | acc]}
  end

  defp handle_verifier_result({:error, reason}, verifier_mod, acc, :continue) do
    Logger.warning("Verifier #{inspect(verifier_mod)} failed: #{inspect(reason)}")
    {:cont, acc}
  end

  defp handle_verifier_result({:error, reason}, verifier_mod, _acc, _halt) do
    {:halt, {:error, {:verifier_failed, {verifier_mod, reason}}}}
  end

  defp verify_parallel(%__MODULE__{verifiers: verifiers, on_error: on_error}, candidate, context, timeout) do
    # Use Task.Supervisor for parallel execution
    # Store verifier modules alongside tasks for error reporting
    task_verifier_pairs =
      Enum.map(verifiers, fn {verifier_mod, config, _weight} ->
        task =
          Task.async(fn ->
            run_verifier(verifier_mod, config, candidate, context, timeout)
          end)

        {task, verifier_mod}
      end)

    # Wait for all tasks with timeout
    start_time = System.monotonic_time(:millisecond)
    results = collect_parallel_results(task_verifier_pairs, start_time, timeout, on_error)

    # Separate successes and failures
    {oks, errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    if on_error == :halt and errors != [] do
      [first_error | _] = errors
      first_error
    else
      successful_results = Enum.map(oks, fn {:ok, result} -> result end)
      {:ok, successful_results}
    end
  end

  defp collect_parallel_results(task_verifier_pairs, start_time, timeout, on_error) do
    Enum.map(task_verifier_pairs, fn {task, verifier_mod} ->
      remaining = timeout - (System.monotonic_time(:millisecond) - start_time)
      actual_timeout = max(remaining, 1)

      handle_task_result(Task.yield(task, actual_timeout), verifier_mod, on_error)
    end)
  end

  defp handle_task_result({:ok, {:ok, result}}, _verifier_mod, _on_error) do
    {:ok, result}
  end

  defp handle_task_result({:ok, {:error, reason}}, verifier_mod, :continue) do
    Logger.warning("Verifier #{inspect(verifier_mod)} failed: #{inspect(reason)}")
    {:error, reason}
  end

  defp handle_task_result({:ok, {:error, reason}}, verifier_mod, _halt) do
    {:error, {:verifier_failed, {verifier_mod, reason}}}
  end

  defp handle_task_result({:exit, _reason}, _verifier_mod, _on_error) do
    Logger.warning("Verifier task exited unexpectedly")
    {:error, :task_exited}
  end

  defp handle_task_result(nil, _verifier_mod, _on_error) do
    {:error, :timeout}
  end

  defp run_verifier(verifier_mod, config, candidate, context, _timeout) do
    # Initialize verifier if it has new/1
    with {:ok, verifier} <- init_verifier(verifier_mod, config) do
      # Call verify with appropriate arity
      verify_with_verifier(verifier_mod, verifier, candidate, context)
    end
  end

  # Try to call new/1, handling the case where the module might not be fully loaded
  defp init_verifier(verifier_mod, config) do
    # Ensure module is loaded by accessing exports
    _ = verifier_mod.module_info(:exports)
    exports = verifier_mod.module_info(:exports)

    init_verifier_with_exports(verifier_mod, config, exports)
  rescue
    error ->
      # Module doesn't exist or can't be loaded
      {:error, {:module_not_found, {verifier_mod, error}}}
  end

  defp init_verifier_with_exports(verifier_mod, config, exports) do
    if Keyword.get(exports, :new) == 1 do
      call_verifier_new(verifier_mod, config)
    else
      # No new/1, try to create struct directly
      try_create_struct(verifier_mod, config)
    end
  end

  defp call_verifier_new(verifier_mod, config) when is_map(config) do
    case verifier_mod.new(Map.to_list(config)) do
      {:ok, v} -> {:ok, v}
      {:error, reason} -> {:error, {:init_failed, reason}}
    end
  end

  defp call_verifier_new(verifier_mod, config) do
    case verifier_mod.new(config) do
      {:ok, v} -> {:ok, v}
      {:error, reason} -> {:error, {:init_failed, reason}}
    end
  end

  defp try_create_struct(verifier_mod, config) do
    # Check if module has verify/3, which suggests it needs a struct
    exports = verifier_mod.module_info(:exports)

    if Keyword.get(exports, :verify) == 3 do
      create_verifier_struct(verifier_mod, config)
    else
      # Use module directly for verify/2
      {:ok, verifier_mod}
    end
  end

  defp create_verifier_struct(verifier_mod, config) do
    {:ok, struct!(verifier_mod, config)}
  rescue
    _ -> {:ok, verifier_mod}
  end

  defp verify_with_verifier(_verifier_mod, verifier, candidate, context) when is_struct(verifier) do
    struct_module = verifier.__struct__

    if function_exported?(struct_module, :verify, 3) do
      struct_module.verify(verifier, candidate, context)
    else
      require Logger

      Logger.warning("Verifier #{inspect(struct_module)} does not have verify/3")
      {:error, :verify_not_implemented}
    end
  end

  defp verify_with_verifier(verifier_mod, verifier, candidate, context) when is_atom(verifier) do
    if function_exported?(verifier, :verify, 2) do
      verifier.verify(candidate, context)
    else
      log_verify_error(verifier_mod, verifier)
    end
  end

  defp verify_with_verifier(verifier_mod, verifier, _candidate, _context) do
    log_verify_error(verifier_mod, verifier)
  end

  defp log_verify_error(verifier_mod, verifier) do
    require Logger

    Logger.warning(
      "verify_with_verifier failed: verifier_mod=#{inspect(verifier_mod)}, verifier=#{inspect(verifier)}, is_struct=#{is_struct(verifier)}"
    )

    {:error, :verify_not_implemented}
  end

  defp aggregate_results(runner, results, candidate) do
    if results == [] do
      empty_result(candidate)
    else
      weights = Enum.map(runner.verifiers, fn {_mod, _config, weight} -> weight end)

      score = aggregate_scores(results, weights, runner.aggregation)

      # Combine reasoning from all results
      combined_reasoning = build_combined_reasoning(results)

      # Combine confidence (average)
      confidences = Enum.map(results, &confidence_value/1)
      avg_confidence = if confidences == [], do: 0.0, else: Enum.sum(confidences) / length(confidences)

      # Merge all metadata
      combined_metadata = combine_metadata(results)

      # Merge step scores if present (for PRMs)
      combined_step_scores = merge_all_step_scores(results)

      %VerificationResult{
        candidate_id: candidate.id,
        score: score,
        confidence: avg_confidence,
        reasoning: combined_reasoning,
        step_scores: combined_step_scores,
        metadata: Map.put(combined_metadata, :verifier_count, length(results))
      }
    end
  end

  defp confidence_value(%{confidence: nil}), do: 0.5
  defp confidence_value(%{confidence: c}) when is_number(c), do: c
  defp confidence_value(_), do: 0.5

  defp build_combined_reasoning(results) do
    reasonings =
      Enum.map(results, fn
        %{reasoning: nil} -> ""
        %{reasoning: ""} -> ""
        %{reasoning: r} -> r
      end)
      |> Enum.reject(&(&1 == ""))

    if reasonings == [] do
      "Verification completed"
    else
      "Combined verification: " <> Enum.join(reasonings, "; ")
    end
  end

  defp combine_metadata(results) do
    Enum.reduce(results, %{}, fn result, acc ->
      Map.merge(acc, Map.get(result, :metadata, %{}))
    end)
  end

  defp merge_all_step_scores(results) do
    Enum.reduce(results, %{}, fn result, acc ->
      step_scores = Map.get(result, :step_scores) || %{}
      Map.merge(acc, step_scores)
    end)
  end

  defp empty_result(candidate) do
    %VerificationResult{
      candidate_id: candidate.id,
      score: 0.0,
      confidence: 0.0,
      reasoning: "No verification results",
      metadata: %{verifier_count: 0}
    }
  end

  defp error_result(candidate, reason) do
    %VerificationResult{
      candidate_id: candidate.id,
      score: 0.0,
      confidence: 0.0,
      reasoning: "Verification failed: #{inspect(reason)}",
      metadata: %{error: reason}
    }
  end

  # Score aggregation functions

  defp weighted_average(scores, weights) do
    {weighted_sum, weight_total} =
      Enum.zip(scores, weights)
      |> Enum.reduce({0.0, 0.0}, fn {score, weight}, {sum_acc, weight_acc} ->
        normalized_score = if is_number(score), do: score, else: 0.0
        {sum_acc + normalized_score * weight, weight_acc + weight}
      end)

    if weight_total > 0 do
      weighted_sum / weight_total
    else
      0.0
    end
  end

  defp max_score([]), do: 0.0

  defp max_score(scores) do
    scores
    |> Enum.filter(&is_number/1)
    |> Enum.max(fn -> 0.0 end)
  end

  defp min_score([]), do: 0.0

  defp min_score(scores) do
    scores
    |> Enum.filter(&is_number/1)
    |> Enum.min(fn -> 0.0 end)
  end

  defp sum_scores(scores) do
    scores
    |> Enum.filter(&is_number/1)
    |> Enum.sum()
  end

  defp product_scores([]), do: 0.0

  defp product_scores(scores) do
    scores
    |> Enum.filter(&is_number/1)
    |> Enum.product()
  end

  defp on_error?(:continue), do: true
  defp on_error?(:halt), do: false
  # default
  defp on_error?(_), do: true

  # Validation

  defp validate_verifiers(verifiers) when is_list(verifiers) do
    if Enum.all?(verifiers, &valid_verifier_config?/1) do
      :ok
    else
      {:error, :invalid_verifiers_config}
    end
  end

  defp validate_verifiers(_), do: {:error, :verifiers_must_be_list}

  defp valid_verifier_config?({mod, config, weight}) when is_atom(mod) and is_map(config) and is_number(weight) do
    weight >= 0
  end

  defp valid_verifier_config?({mod, config}) when is_atom(mod) and is_map(config) do
    true
  end

  defp valid_verifier_config?(_), do: false

  defp validate_aggregation(strategy) when strategy in [:weighted_avg, :max, :min, :sum, :product], do: :ok
  defp validate_aggregation(_), do: {:error, :invalid_aggregation_strategy}

  defp validate_error_strategy(strategy) when strategy in [:continue, :halt], do: :ok
  defp validate_error_strategy(_), do: {:error, :invalid_error_strategy}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(nil), do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}
end
