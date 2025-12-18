defmodule Jido.AI.Runner.SelfConsistency do
  @moduledoc """
  Self-Consistency Chain-of-Thought reasoning implementation.

  Generates multiple independent reasoning paths and selects the most reliable answer
  through voting. Research shows +17.9% accuracy improvement on GSM8K at 5-10x cost.

  The implementation:
  - Generates k diverse reasoning paths in parallel (default: 5-10)
  - Encourages diversity through temperature and prompt variation
  - Extracts and normalizes answers from each path
  - Uses voting mechanisms to select the most common/reliable answer
  - Filters low-quality paths before voting

  ## Usage

      {:ok, result} = SelfConsistency.run(
        problem: "What is 15% of 80?",
        sample_count: 5,
        temperature: 0.7
      )

      # => %{
      #   answer: "12",
      #   confidence: 0.8,
      #   paths: [...],
      #   votes: %{"12" => 4, "11.5" => 1}
      # }

  ## Research

  Self-consistency dramatically improves accuracy on reasoning tasks:
  - GSM8K: +17.9% accuracy improvement
  - Cost: 5-10x (k=5-10 samples)
  - Best for: Mission-critical decisions, mathematical reasoning, logic problems
  """

  require Logger

  alias Jido.AI.Runner.SelfConsistency.{
    AnswerExtractor,
    PathQualityAnalyzer,
    VotingMechanism
  }

  @default_sample_count 5
  @default_temperature 0.7
  @default_diversity_threshold 0.3
  @default_quality_threshold 0.5

  @type reasoning_path :: %{
          reasoning: String.t(),
          answer: term(),
          confidence: float(),
          quality_score: float()
        }

  @type result :: %{
          answer: term(),
          confidence: float(),
          consensus: float(),
          paths: list(reasoning_path()),
          votes: map(),
          metadata: map()
        }

  @doc """
  Runs self-consistency CoT reasoning.

  ## Parameters

  - `problem` - The problem/question to solve
  - `opts` - Options:
    - `:sample_count` - Number of reasoning paths to generate (default: 5)
    - `:temperature` - Temperature for diversity (default: 0.7)
    - `:diversity_threshold` - Minimum diversity between paths (default: 0.3)
    - `:quality_threshold` - Minimum quality score to include path (default: 0.5)
    - `:voting_strategy` - :majority | :confidence_weighted (default: :majority)
    - `:min_consensus` - Minimum agreement required (default: 0.4)
    - `:reasoning_fn` - Function to generate reasoning (for testing)
    - `:parallel` - Use parallel execution (default: true)

  ## Returns

  - `{:ok, result}` - Successful consensus reached
  - `{:error, reason}` - Failed to reach consensus or generate paths
  """
  @spec run(keyword()) :: {:ok, result()} | {:error, term()}
  def run(opts \\ []) do
    problem = Keyword.get(opts, :problem)
    sample_count = Keyword.get(opts, :sample_count, @default_sample_count)
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    diversity_threshold = Keyword.get(opts, :diversity_threshold, @default_diversity_threshold)
    quality_threshold = Keyword.get(opts, :quality_threshold, @default_quality_threshold)
    voting_strategy = Keyword.get(opts, :voting_strategy, :majority)
    min_consensus = Keyword.get(opts, :min_consensus, 0.4)
    reasoning_fn = Keyword.get(opts, :reasoning_fn)
    parallel = Keyword.get(opts, :parallel, true)

    with {:ok, paths} <-
           generate_reasoning_paths(problem, sample_count, temperature, reasoning_fn, parallel),
         {:ok, paths_with_answers} <- extract_answers(paths),
         {:ok, quality_paths} <-
           analyze_and_filter_quality(paths_with_answers, quality_threshold),
         {:ok, diverse_paths} <- ensure_diversity(quality_paths, diversity_threshold),
         {:ok, result} <- vote_and_select(diverse_paths, voting_strategy, min_consensus) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Generates multiple independent reasoning paths in parallel.

  ## Parameters

  - `problem` - The problem to solve
  - `sample_count` - Number of paths to generate
  - `temperature` - Temperature for diversity
  - `reasoning_fn` - Optional custom reasoning function
  - `parallel` - Whether to use parallel execution

  ## Returns

  - `{:ok, paths}` - List of generated reasoning paths
  - `{:error, reason}` - Generation failed
  """
  @spec generate_reasoning_paths(String.t(), pos_integer(), float(), fun() | nil, boolean()) ::
          {:ok, list(String.t())} | {:error, term()}
  def generate_reasoning_paths(problem, sample_count, temperature, reasoning_fn, parallel \\ true) do
    Logger.info("Generating #{sample_count} reasoning paths for self-consistency")

    generator =
      if reasoning_fn do
        reasoning_fn
      else
        fn i ->
          generate_single_path(problem, temperature, i)
        end
      end

    paths =
      if parallel do
        # Generate paths in parallel using Tasks
        1..sample_count
        |> Enum.map(fn i ->
          Task.async(fn -> generator.(i) end)
        end)
        |> Task.await_many(30_000)
      else
        # Generate paths sequentially
        Enum.map(1..sample_count, generator)
      end

    # Filter out any errors and log failures for observability
    {valid_paths, errors} =
      paths
      |> Enum.with_index(1)
      |> Enum.reduce({[], []}, fn {path, index}, {valid, errs} ->
        if is_binary(path) do
          {[path | valid], errs}
        else
          Logger.warning("Path generation #{index}/#{sample_count} failed: #{inspect(path)}")
          {valid, [path | errs]}
        end
      end)

    valid_paths = Enum.reverse(valid_paths)
    errors = Enum.reverse(errors)

    if length(valid_paths) >= div(sample_count, 2) do
      if length(errors) > 0 do
        Logger.info(
          "Self-consistency completed with partial failures: #{length(valid_paths)}/#{sample_count} paths succeeded"
        )
      end

      {:ok, valid_paths}
    else
      Logger.error(
        "Self-consistency failed: insufficient valid paths (#{length(valid_paths)}/#{sample_count}, needed #{div(sample_count, 2)})"
      )

      {:error, :insufficient_valid_paths}
    end
  end

  @doc """
  Ensures diversity among reasoning paths.

  Filters paths to maintain minimum diversity threshold, preventing
  near-duplicate paths from dominating voting.

  ## Parameters

  - `paths` - Reasoning paths with answers
  - `diversity_threshold` - Minimum diversity score (0.0-1.0)

  ## Returns

  - `{:ok, diverse_paths}` - Filtered diverse paths
  """
  @spec ensure_diversity(list(reasoning_path()), float()) ::
          {:ok, list(reasoning_path())} | {:error, term()}
  def ensure_diversity(paths, diversity_threshold) do
    diverse_paths =
      Enum.reduce(paths, [], fn path, acc ->
        if Enum.empty?(acc) do
          [path | acc]
        else
          # Check if path is sufficiently different from existing paths
          min_diversity =
            Enum.map(acc, fn existing ->
              calculate_diversity(path, existing)
            end)
            |> Enum.min()

          if min_diversity >= diversity_threshold do
            [path | acc]
          else
            acc
          end
        end
      end)
      |> Enum.reverse()

    {:ok, diverse_paths}
  end

  # Private functions

  defp generate_single_path(problem, temperature, seed) do
    # This would call an LLM in production
    # For now, return a simulated reasoning path
    "Reasoning path #{seed} for: #{problem}. Temperature: #{temperature}. Answer: #{simulate_answer(seed)}"
  end

  defp simulate_answer(seed) do
    # Simulate different answers based on seed
    rem(seed, 3) + 10
  end

  defp extract_answers(paths) do
    paths_with_answers =
      Enum.map(paths, fn reasoning ->
        case AnswerExtractor.extract(reasoning) do
          {:ok, answer} ->
            %{
              reasoning: reasoning,
              answer: answer,
              confidence: 0.7,
              # Default confidence
              quality_score: nil
            }

          {:error, _} ->
            %{
              reasoning: reasoning,
              answer: nil,
              confidence: 0.0,
              quality_score: 0.0
            }
        end
      end)

    # Filter out paths without answers
    valid_paths = Enum.filter(paths_with_answers, fn path -> path.answer != nil end)

    if Enum.empty?(valid_paths) do
      {:error, :no_valid_answers_extracted}
    else
      {:ok, valid_paths}
    end
  end

  defp analyze_and_filter_quality(paths, quality_threshold) do
    # Analyze quality of each path
    paths_with_quality =
      Enum.map(paths, fn path ->
        quality_score = PathQualityAnalyzer.analyze(path)
        %{path | quality_score: quality_score}
      end)

    # Filter by quality threshold
    quality_paths = Enum.filter(paths_with_quality, &(&1.quality_score >= quality_threshold))

    if Enum.empty?(quality_paths) do
      Logger.warning("No paths meet quality threshold, using all paths")
      {:ok, paths_with_quality}
    else
      {:ok, quality_paths}
    end
  end

  defp vote_and_select(paths, voting_strategy, min_consensus) do
    case VotingMechanism.vote(paths, strategy: voting_strategy) do
      {:ok, result} ->
        # Check if consensus meets minimum threshold
        if result.consensus >= min_consensus do
          {:ok, result}
        else
          {:error, {:insufficient_consensus, result.consensus}}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_diversity(path1, path2) do
    # Simple diversity calculation based on answer and reasoning differences
    answer_diversity = if path1.answer == path2.answer, do: 0.0, else: 1.0

    reasoning_diversity =
      String.jaro_distance(
        path1.reasoning || "",
        path2.reasoning || ""
      )

    # Combine (jaro distance is similarity, so 1.0 - similarity = diversity)
    answer_diversity * 0.5 + (1.0 - reasoning_diversity) * 0.5
  end
end
