defmodule Jido.AI.Accuracy.Search.DiverseDecoding do
  @moduledoc """
  Diverse Decoding search controller using MMR (Maximal Marginal Relevance).

  This search algorithm generates diverse candidates by balancing:
  - **Relevance**: How good the candidate is (from verifier scores)
  - **Diversity**: How different the candidate is from already selected ones

  ## Algorithm

  1. Generate N candidates with varied temperatures
  2. Score all candidates with verifier
  3. Apply MMR to select diverse top-K:
     ```
     mmr_score = lambda * relevance - (1 - lambda) * max_similarity_to_selected
     ```
  4. Return best candidate from selected set

  ## Configuration

  - `:num_candidates` - Number of candidates to generate (default: 10)
  - `:diversity_threshold` - Min similarity to be considered "too similar" (default: 0.7)
  - `:temperature_range` - Temperature range for generation (default: {0.0, 1.0})
  - `:lambda` - MMR relevance/diversity tradeoff (default: 0.5)
    - Higher lambda = prioritize relevance over diversity
    - Lower lambda = prioritize diversity over relevance

  ## Usage

      # Balanced search (default)
      {:ok, best} = DiverseDecoding.search(
        "What is 15 * 23?",
        LLMGenerator,
        DeterministicVerifier,
        num_candidates: 10
      )

      # Diversity-focused search
      {:ok, best} = DiverseDecoding.search(
        "Explain quantum computing",
        LLMGenerator,
        LLMOutcomeVerifier,
        num_candidates: 20,
        lambda: 0.3  # Prioritize diversity
      )

      # Relevance-focused search
      {:ok, best} = DiverseDecoding.search(
        "Solve: x^2 + 5x + 6 = 0",
        LLMGenerator,
        DeterministicVerifier,
        num_candidates: 15,
        lambda: 0.7  # Prioritize relevance
      )

  ## MMR Algorithm

  The Maximal Marginal Relevance algorithm selects candidates that optimize
  the tradeoff between relevance and diversity:

      mmr_score(candidate, selected) =
        lambda * relevance(candidate) -
        (1 - lambda) * max_similarity(candidate, s for s in selected)

  Where:
  - `relevance` is the verifier score (0.0 to 1.0)
  - `similarity` is the text similarity between candidates (0.0 to 1.0)
  - `lambda` controls the relevance/diversity tradeoff

  """

  @behaviour Jido.AI.Accuracy.SearchController

  alias Jido.AI.Accuracy.{
    Candidate,
    SearchController,
    Similarity,
    VerificationResult
  }

  @type t :: %__MODULE__{
          num_candidates: pos_integer(),
          diversity_threshold: float(),
          temperature_range: {float(), float()},
          lambda: float()
        }

  defstruct num_candidates: 10,
            diversity_threshold: 0.7,
            temperature_range: {0.0, 1.0},
            lambda: 0.5

  # Client API

  @doc """
  Creates a new DiverseDecoding configuration.

  ## Options

  - `:num_candidates` - Number of candidates to generate (1-100, default: 10)
  - `:diversity_threshold` - Min similarity threshold (0.0-1.0, default: 0.7)
  - `:temperature_range` - {min, max} temperature (default: {0.0, 1.0})
  - `:lambda` - MMR relevance/diversity tradeoff (0.0-1.0, default: 0.5)

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts \\ []) when is_list(opts) do
    config = struct(__MODULE__, opts)

    with :ok <- validate_num_candidates(config.num_candidates),
         :ok <- validate_diversity_threshold(config.diversity_threshold),
         :ok <- validate_temperature_range(config.temperature_range),
         :ok <- validate_lambda(config.lambda) do
      {:ok, config}
    end
  end

  @doc """
  Creates a new DiverseDecoding configuration, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts \\ []) when is_list(opts) do
    case new(opts) do
      {:ok, config} -> config
      {:error, reason} -> raise ArgumentError, "Invalid DiverseDecoding config: #{format_error(reason)}"
    end
  end

  @impl true
  @spec search(String.t(), module(), module(), keyword()) :: {:ok, Candidate.t()} | {:error, term()}
  def search(prompt, generator, verifier, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)
    timeout = SearchController.get_timeout(opts, 30_000)

    with {:ok, config} <- new(opts),
         :ok <-
           SearchController.validate_opts(
             Keyword.drop(opts, [:num_candidates, :diversity_threshold, :temperature_range, :lambda, :timeout]),
             []
           ) do
      do_search(prompt, generator, verifier, config, start_time, timeout)
    end
  end

  # Private functions

  defp do_search(prompt, generator, verifier, config, start_time, timeout) do
    # Step 1: Generate candidates with varied temperatures
    with {:ok, candidates} <-
           generate_diverse_candidates(prompt, generator, config, start_time, timeout),
         {:ok, scored_candidates} <-
           score_candidates(candidates, verifier, prompt, start_time, timeout) do
      # Step 2: Apply MMR to select diverse set
      selected = mmr_select(scored_candidates, config.lambda, config.diversity_threshold)

      # Step 3: Return best candidate from selected set
      case selected do
        [] -> {:error, :no_valid_candidate}
        [best | _] -> {:ok, best}
      end
    end
  end

  defp generate_diverse_candidates(prompt, generator, config, start_time, timeout) do
    num = config.num_candidates
    {min_temp, max_temp} = config.temperature_range

    # Calculate temperature step
    temp_step =
      if num > 1 do
        (max_temp - min_temp) / (num - 1)
      else
        0
      end

    # Generate candidates with varied temperatures
    candidates =
      Enum.map(0..(num - 1), fn i ->
        temp = min_temp + temp_step * i
        generate_candidate(prompt, generator, temp, start_time, timeout)
      end)

    # Filter out errors
    successful =
      Enum.filter(candidates, fn
        {:ok, _} -> true
        _ -> false
      end)

    if Enum.empty?(successful) do
      {:error, :no_candidates}
    else
      {:ok, Enum.map(successful, fn {:ok, c} -> c end)}
    end
  end

  defp generate_candidate(prompt, generator, temperature, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      {:error, :timeout}
    else
      try do
        case Code.ensure_loaded?(generator) and function_exported?(generator, :generate_candidates, 3) do
          true ->
            case generator.generate_candidates(prompt,
                   num_candidates: 1,
                   temperature: temperature,
                   timeout: remaining
                 ) do
              {:ok, [candidate | _]} -> {:ok, candidate}
              {:ok, []} -> {:error, :no_candidates}
              {:error, _} = error -> error
            end

          false ->
            # Fallback: create simple candidate
            candidate =
              Candidate.new!(%{
                id: "#{System.unique_integer([:positive, :monotonic])}",
                content: "#{prompt} (temp=#{:erlang.float_to_binary(temperature, decimals: 2)})",
                metadata: %{fallback: true, temperature: temperature}
              })

            {:ok, candidate}
        end
      rescue
        _ -> {:error, :generator_failed}
      end
    end
  end

  defp score_candidates(candidates, verifier, prompt, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      {:error, :timeout}
    else
      scored =
        Enum.map(candidates, fn candidate ->
          score = score_candidate(candidate, verifier, prompt, start_time, timeout)
          %{candidate | score: score}
        end)

      {:ok, scored}
    end
  end

  defp score_candidate(candidate, verifier, prompt, start_time, timeout) do
    remaining = timeout - (System.monotonic_time(:millisecond) - start_time)

    if remaining <= 0 do
      0.5
    else
      context = %{prompt: prompt, timeout: remaining}

      try do
        case verifier.verify(candidate, context) do
          {:ok, %VerificationResult{score: score}} when is_number(score) ->
            score

          {:ok, %VerificationResult{}} ->
            0.5

          _ ->
            0.5
        end
      rescue
        _ -> 0.5
      end
    end
  end

  @doc """
  Applies MMR (Maximal Marginal Relevance) to select diverse candidates.

  ## Parameters

  - `candidates` - List of scored candidates
  - `lambda` - Relevance/diversity tradeoff (0.0 to 1.0)
  - `threshold` - Diversity threshold (candidates above this similarity are penalized)

  ## Returns

  List of candidates sorted by MMR score (highest first)

  """
  @spec mmr_select([Candidate.t()], float(), float()) :: [Candidate.t()]
  def mmr_select(candidates, lambda, threshold \\ 0.7) do
    if Enum.empty?(candidates) do
      []
    else
      # Start with highest relevance candidate
      [best | rest] = Enum.sort_by(candidates, & &1.score, :desc)

      # Iteratively select candidates using MMR
      mmr_iterate([best], rest, lambda, threshold)
    end
  end

  defp mmr_iterate(selected, [], _lambda, _threshold), do: Enum.reverse(selected)

  defp mmr_iterate(selected, remaining, lambda, threshold) do
    # Calculate MMR score for each remaining candidate
    scored_remaining =
      Enum.map(remaining, fn candidate ->
        mmr_score = calculate_mmr_score(candidate, selected, lambda, threshold)
        {mmr_score, candidate}
      end)

    # Select candidate with highest MMR score
    {_best_score, best_candidate} = Enum.max_by(scored_remaining, fn {score, _} -> score end, fn -> {0.0, nil} end)

    if best_candidate == nil do
      Enum.reverse(selected)
    else
      # Move best candidate from remaining to selected
      new_remaining = Enum.reject(remaining, fn c -> c.id == best_candidate.id end)
      new_selected = [best_candidate | selected]
      mmr_iterate(new_selected, new_remaining, lambda, threshold)
    end
  end

  defp calculate_mmr_score(candidate, selected, lambda, threshold) do
    relevance = candidate.score || 0.5

    # Find max similarity to any selected candidate
    max_sim =
      Enum.reduce(selected, 0.0, fn selected_candidate, acc ->
        sim = compute_similarity(candidate, selected_candidate)
        max(acc, sim)
      end)

    # Apply threshold - penalize heavily if similarity exceeds threshold
    diversity_penalty =
      if max_sim > threshold do
        max_sim
      else
        # Reduced penalty if below threshold
        max_sim * 0.5
      end

    # MMR score: lambda * relevance - (1 - lambda) * diversity_penalty
    lambda * relevance - (1 - lambda) * diversity_penalty
  end

  @doc """
  Computes similarity between two candidates.

  Uses combined Jaccard and edit distance similarity.

  """
  @spec compute_similarity(Candidate.t(), Candidate.t()) :: float()
  def compute_similarity(%Candidate{} = c1, %Candidate{} = c2) do
    Similarity.combined_similarity(c1.content, c2.content, 0.5, 0.5)
  end

  # Validation

  defp validate_num_candidates(n) when is_integer(n) and n >= 1 and n <= 100, do: :ok
  defp validate_num_candidates(_), do: {:error, :invalid_num_candidates}

  defp validate_diversity_threshold(t) when is_number(t) and t >= 0.0 and t <= 1.0, do: :ok
  defp validate_diversity_threshold(_), do: {:error, :invalid_diversity_threshold}

  defp validate_temperature_range({min, max})
       when is_number(min) and is_number(max) and min >= 0.0 and max <= 2.0 and min <= max, do: :ok

  defp validate_temperature_range(_), do: {:error, :invalid_temperature_range}

  defp validate_lambda(l) when is_number(l) and l >= 0.0 and l <= 1.0, do: :ok
  defp validate_lambda(_), do: {:error, :invalid_lambda}
  defp format_error(atom) when is_atom(atom), do: atom
end
