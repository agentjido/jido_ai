defmodule Jido.AI.Accuracy.SelfConsistency do
  @moduledoc """
  Self-consistency runner for test-time compute scaling.

  This module orchestrates the complete self-consistency workflow:
  generating multiple candidate responses and selecting the best answer
  through aggregation strategies like majority voting.

  Self-consistency improves accuracy by sampling multiple diverse
  responses and selecting the most common or highest-quality answer.

  ## Features

  - Unified interface for generation and aggregation
  - Multiple aggregation strategies (majority vote, best-of-N, weighted)
  - Chain-of-Thought reasoning support
  - Telemetry events for monitoring
  - Configurable candidate count and temperature range
  - Custom generator and aggregator support

  ## Usage

  Basic usage with defaults:

      {:ok, best, metadata} = SelfConsistency.run("What is 15 * 23?")
      # best.content => "345"
      # metadata.confidence => 0.6 (3/5 votes)

  With options:

      {:ok, best, metadata} = SelfConsistency.run("What is 15 * 23?",
        num_candidates: 7,
        aggregator: :weighted
      )

  With Chain-of-Thought reasoning:

      {:ok, best, metadata} = SelfConsistency.run_with_reasoning(
        "Solve step by step: 15 * 23 + 7"
      )
      # best.reasoning => "Let me calculate..."
      # best.content => "352"

  ## Configuration

  Options passed to `run/2` or `run_with_reasoning/2`:

  - `:num_candidates` - Number of candidates to generate (default: 5)
  - `:aggregator` - Aggregation strategy (default: `:majority_vote`)
  - `:temperature_range` - Temperature range for sampling (default: `{0.0, 1.0}`)
  - `:model` - Model to use (default: `"anthropic:claude-haiku-4-5"`)
  - `:timeout` - Per-candidate timeout in ms (default: 30000)
  - `:max_concurrency` - Max parallel generations (default: 3)
  - `:generator` - Custom generator module or struct (default: `LLMGenerator`)
  - `:system_prompt` - Optional system prompt

  ## Aggregation Strategies

  - `:majority_vote` - Select most common answer (self-consistency)
  - `:best_of_n` - Select candidate with highest score
  - `:weighted` - Combine multiple strategies with weights
  - Custom module - Any module implementing `Aggregator` behavior

  ## Telemetry

  Emits events under `[:jido, :accuracy, :self_consistency, *]`:

  - `[:start]` - Execution started
  - `[:stop]` - Execution completed
  - `[:exception]` - Execution failed

  ## Examples

      # Generate with high temperature for diversity
      {:ok, best, meta} = SelfConsistency.run("What is the capital of Australia?",
        num_candidates: 10,
        temperature_range: {0.7, 1.0}
      )

      # Use custom generator
      gen = MyGenerator.new!(%{model: :fast})
      {:ok, best, meta} = SelfConsistency.run("What is 2+2?",
        generator: gen
      )

      # Use custom aggregator
      {:ok, best, meta} = SelfConsistency.run("What is 2+2?",
        aggregator: MyCustomAggregator
      )

  """

  alias Jido.AI.Accuracy.Candidate
  alias Jido.AI.Accuracy.Generators.LLMGenerator
  alias Jido.AI.Accuracy.Aggregators.MajorityVote
  alias Jido.AI.Accuracy.Aggregators.BestOfN
  alias Jido.AI.Accuracy.Aggregators.Weighted

  @type result :: {:ok, Candidate.t(), metadata()} | {:error, term()}

  @type metadata :: %{
    confidence: number(),
    num_candidates: non_neg_integer(),
    aggregator: atom() | module(),
    total_tokens: non_neg_integer() | nil,
    aggregation_metadata: map()
  }

  @type opts :: keyword()

  # Default configuration
  @default_num_candidates 5
  @default_aggregator :majority_vote
  @default_temperature_range {0.0, 1.0}
  @default_model "anthropic:claude-haiku-4-5"
  @default_timeout 30_000
  @default_max_concurrency 3

  # Aggregator name to module mapping
  @aggregators %{
    majority_vote: MajorityVote,
    best_of_n: BestOfN,
    weighted: Weighted
  }

  @doc """
  Runs self-consistency on a prompt.

  Generates multiple candidates and selects the best one using
  the configured aggregation strategy.

  ## Parameters

  - `prompt` - The input prompt
  - `opts` - Configuration options (see module documentation)

  ## Returns

  - `{:ok, candidate, metadata}` - Success with best candidate and metadata
  - `{:error, reason}` - Generation or aggregation failed

  ## Examples

      {:ok, best, metadata} = SelfConsistency.run("What is 15 * 23?")

      {:ok, best, metadata} = SelfConsistency.run("What is 15 * 23?",
        num_candidates: 7,
        aggregator: :best_of_n
      )

  """
  @spec run(String.t(), opts()) :: result()
  def run(prompt, opts \\ []) when is_binary(prompt) do
    start_time = System.monotonic_time(:millisecond)
    start_metadata = build_start_metadata(prompt, opts)
    :telemetry.execute([:jido, :accuracy, :self_consistency, :start], %{system_time: start_time}, start_metadata)

    aggregator = resolve_aggregator(Keyword.get(opts, :aggregator, @default_aggregator))

    case validate_aggregator(aggregator) do
      :ok ->
        do_run(prompt, aggregator, opts, start_time)

      {:error, _reason} = error ->
        emit_exception(start_time, error)
        error
    end
  end

  @doc """
  Runs self-consistency with Chain-of-Thought reasoning.

  Generates candidates with reasoning traces preserved separately
  from the final answer.

  ## Parameters

  - `prompt` - The input prompt
  - `opts` - Configuration options

  ## Returns

  - `{:ok, candidate, metadata}` - Success with best candidate (with reasoning field)
  - `{:error, reason}` - Generation or aggregation failed

  ## Examples

      {:ok, best, metadata} = SelfConsistency.run_with_reasoning(
        "Solve step by step: 15 * 23 + 7"
      )
      # best.reasoning => "Let me calculate..."
      # best.content => "352"

  """
  @spec run_with_reasoning(String.t(), opts()) :: result()
  def run_with_reasoning(prompt, opts \\ []) when is_binary(prompt) do
    start_time = System.monotonic_time(:millisecond)
    start_metadata = build_start_metadata(prompt, opts)
    :telemetry.execute([:jido, :accuracy, :self_consistency, :start], %{system_time: start_time}, start_metadata)

    aggregator = resolve_aggregator(Keyword.get(opts, :aggregator, @default_aggregator))

    case validate_aggregator(aggregator) do
      :ok ->
        do_run_with_reasoning(prompt, aggregator, opts, start_time)

      {:error, _reason} = error ->
        emit_exception(start_time, error)
        error
    end
  end

  # Private functions

  defp do_run(prompt, aggregator, opts, start_time) do
    generator = get_generator(opts)

    gen_opts = build_generator_opts(opts)

    generator_module = get_generator_module(generator)

    case apply_generator_generate(generator_module, :generate_candidates, [generator, prompt, gen_opts]) do
      {:ok, candidates} ->
        aggregate_and_build_result(candidates, aggregator, start_time, opts)

      {:error, _reason} = error ->
        emit_exception(start_time, error)
        error
    end
  rescue
    e ->
      error = {:exception, Exception.message(e), __struct__: e.__struct__}
      emit_exception(start_time, error)
      error
  end

  defp do_run_with_reasoning(prompt, aggregator, opts, start_time) do
    generator = get_generator(opts)

    gen_opts = build_generator_opts(opts)

    generator_module = get_generator_module(generator)

    case apply_generator_generate(generator_module, :generate_with_reasoning, [generator, prompt, gen_opts]) do
      {:ok, candidates} ->
        aggregate_and_build_result(candidates, aggregator, start_time, opts)

      {:error, _reason} = error ->
        emit_exception(start_time, error)
        error
    end
  rescue
    e ->
      error = {:exception, Exception.message(e), __struct__: e.__struct__}
      emit_exception(start_time, error)
      error
  end

  defp aggregate_and_build_result(candidates, aggregator, start_time, opts) do
    case apply(aggregator, :aggregate, [candidates, opts]) do
      {:ok, best, agg_metadata} ->
        metadata = build_metadata(candidates, agg_metadata, aggregator, opts)
        emit_stop(start_time, candidates, metadata)
        {:ok, best, metadata}

      {:error, _reason} = error ->
        emit_exception(start_time, error)
        error
    end
  end

  defp get_generator(opts) do
    case Keyword.get(opts, :generator) do
      nil -> LLMGenerator.new!([])
      module when is_atom(module) -> module
      struct when is_struct(struct) -> struct
    end
  end

  defp get_generator_module(%_struct{}), do: LLMGenerator
  defp get_generator_module(module) when is_atom(module), do: module

  defp apply_generator_generate(LLMGenerator, func, args) do
    apply(LLMGenerator, func, args)
  end

  defp apply_generator_generate(module, func, args) do
    apply(module, func, args)
  end

  defp build_generator_opts(opts) do
    []
    |> Keyword.put(:num_candidates, Keyword.get(opts, :num_candidates, @default_num_candidates))
    |> Keyword.put(:temperature_range, Keyword.get(opts, :temperature_range, @default_temperature_range))
    |> Keyword.put(:timeout, Keyword.get(opts, :timeout, @default_timeout))
    |> Keyword.put(:max_concurrency, Keyword.get(opts, :max_concurrency, @default_max_concurrency))
    |> Keyword.put(:model, Keyword.get(opts, :model, @default_model))
    |> maybe_put_system_prompt(opts)
  end

  defp maybe_put_system_prompt(acc, opts) do
    case Keyword.get(opts, :system_prompt) do
      nil -> acc
      prompt -> Keyword.put(acc, :system_prompt, prompt)
    end
  end

  defp resolve_aggregator(aggregator) when is_atom(aggregator) do
    Map.get(@aggregators, aggregator, aggregator)
  end

  defp resolve_aggregator(aggregator), do: aggregator

  defp validate_aggregator(module) when is_atom(module) do
    # Ensure the module is loaded
    Code.ensure_loaded?(module)

    cond do
      function_exported?(module, :aggregate, 2) ->
        :ok

      function_exported?(module, :aggregate, 1) ->
        # aggregate/1 might be for default args
        :ok

      true ->
        {:error, :invalid_aggregator}
    end
  end

  defp validate_aggregator(_), do: {:error, :invalid_aggregator}

  defp build_metadata(candidates, agg_metadata, aggregator, _opts) do
    %{
      confidence: Map.get(agg_metadata, :confidence, 0.0),
      num_candidates: length(candidates),
      aggregator: aggregator,
      total_tokens: calculate_total_tokens(candidates),
      aggregation_metadata: agg_metadata
    }
  end

  defp calculate_total_tokens(candidates) do
    candidates
    |> Enum.map(fn %Candidate{tokens_used: tokens} -> tokens || 0 end)
    |> Enum.sum()
    |> case do
      0 -> nil
      sum -> sum
    end
  end

  defp build_start_metadata(prompt, opts) do
    %{
      prompt: truncate_prompt(prompt),
      num_candidates: Keyword.get(opts, :num_candidates, @default_num_candidates),
      aggregator: Keyword.get(opts, :aggregator, @default_aggregator),
      temperature_range: Keyword.get(opts, :temperature_range, @default_temperature_range)
    }
  end

  defp truncate_prompt(prompt) when byte_size(prompt) > 100 do
    String.slice(prompt, 0, 97) <> "..."
  end

  defp truncate_prompt(prompt), do: prompt

  defp emit_stop(start_time, candidates, metadata) do
    duration = System.monotonic_time(:millisecond) - start_time

    stop_metadata = %{
      num_candidates: length(candidates),
      aggregator: metadata.aggregator,
      confidence: metadata.confidence,
      total_tokens: metadata.total_tokens
    }

    :telemetry.execute([:jido, :accuracy, :self_consistency, :stop], %{duration: duration}, stop_metadata)
  end

  defp emit_exception(start_time, error) do
    duration = System.monotonic_time(:millisecond) - start_time

    exception_metadata = case error do
      {kind, reason, _} when is_atom(kind) ->
        %{kind: kind, reason: reason}
      {kind, reason} when is_atom(kind) ->
        %{kind: kind, reason: reason}
      reason when is_atom(reason) ->
        %{kind: :error, reason: reason}
      _ ->
        %{kind: :error, reason: :unknown}
    end

    :telemetry.execute([:jido, :accuracy, :self_consistency, :exception], %{duration: duration}, exception_metadata)
  end
end
