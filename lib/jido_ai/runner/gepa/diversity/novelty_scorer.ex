defmodule Jido.AI.Runner.GEPA.Diversity.NoveltyScorer do
  @moduledoc """
  Assigns novelty scores to prompts based on behavioral uniqueness.

  Implements novelty search using k-nearest neighbor distance in
  behavioral space. Prompts that produce novel behaviors (execution
  trajectories, outputs, strategies) receive higher scores.

  ## Behavioral Characterization

  A prompt's behavior is characterized by:
  - Execution trajectory patterns
  - Output characteristics (length, structure, format)
  - Reasoning strategy (step-by-step, direct, analytical)
  - Success/failure patterns

  ## K-NN Novelty Scoring

  Novelty score = average distance to k nearest neighbors in behavioral space.

  Higher score = more novel behavior = greater exploration value.

  ## Usage

      # Score a single prompt
      {:ok, score} = NoveltyScorer.score_prompt(prompt, archive)

      # Score entire population
      {:ok, scores} = NoveltyScorer.score_population(prompts, archive)

      # Update archive with new prompts
      {:ok, updated_archive} = NoveltyScorer.update_archive(archive, new_prompts)
  """

  alias Jido.AI.Runner.GEPA.Diversity.NoveltyScore

  @default_k 5
  @max_archive_size 50

  @doc """
  Scores a prompt's novelty based on behavioral distance from archive.

  ## Parameters

  - `prompt` - Prompt to score (string or map with behavioral features)
  - `archive` - List of historical prompts with features
  - `opts` - Options:
    - `:k` - Number of nearest neighbors (default: 5)
    - `:features` - Behavioral features for prompt (default: extract from prompt)

  ## Returns

  - `{:ok, NoveltyScore.t()}` - Novelty score struct
  - `{:error, reason}` - If scoring fails

  ## Examples

      {:ok, score} = NoveltyScorer.score_prompt(prompt, archive)
      score.novelty_score  # => 0.75 (fairly novel)
  """
  @spec score_prompt(String.t() | map(), list(map()), keyword()) ::
          {:ok, NoveltyScore.t()} | {:error, term()}
  def score_prompt(prompt, archive, opts \\ [])

  def score_prompt(prompt, [], _opts) do
    # Empty archive = everything is novel
    score = %NoveltyScore{
      prompt_id: extract_id(prompt),
      novelty_score: 1.0,
      k_nearest_distance: 1.0,
      behavioral_features: extract_features(prompt),
      metadata: %{archive_size: 0}
    }

    {:ok, score}
  end

  def score_prompt(prompt, archive, opts) do
    k = Keyword.get(opts, :k, @default_k)
    features = Keyword.get(opts, :features) || extract_features(prompt)

    # Calculate distances to all archive members
    distances =
      Enum.map(archive, fn archived ->
        archived_features = extract_features(archived)
        distance = euclidean_distance(features, archived_features)
        {archived, distance}
      end)
      |> Enum.sort_by(fn {_archived, dist} -> dist end)

    # Get k nearest neighbors
    k_nearest = Enum.take(distances, min(k, length(distances)))
    k_distances = Enum.map(k_nearest, fn {_archived, dist} -> dist end)

    # Novelty score = average distance to k nearest
    avg_distance =
      if length(k_distances) > 0 do
        Enum.sum(k_distances) / length(k_distances)
      else
        1.0
      end

    score = %NoveltyScore{
      prompt_id: extract_id(prompt),
      novelty_score: Float.round(min(1.0, avg_distance), 3),
      k_nearest_distance: Float.round(avg_distance, 3),
      behavioral_features: features,
      metadata: %{
        archive_size: length(archive),
        k_used: k,
        nearest_distances: k_distances
      }
    }

    {:ok, score}
  end

  @doc """
  Scores an entire population for novelty.

  ## Parameters

  - `prompts` - List of prompts to score
  - `archive` - Behavioral archive
  - `opts` - Options (same as score_prompt/3)

  ## Returns

  - `{:ok, scores}` - List of NoveltyScore structs
  - `{:error, reason}` - If scoring fails

  ## Examples

      {:ok, scores} = NoveltyScorer.score_population(prompts, archive)
      # scores => [%NoveltyScore{novelty_score: 0.75, ...}, ...]
  """
  @spec score_population(list(String.t() | map()), list(map()), keyword()) ::
          {:ok, list(NoveltyScore.t())} | {:error, term()}
  def score_population(prompts, archive, opts \\ []) do
    scores =
      Enum.map(prompts, fn prompt ->
        {:ok, score} = score_prompt(prompt, archive, opts)
        score
      end)

    {:ok, scores}
  end

  @doc """
  Updates behavioral archive with new prompts.

  Maintains archive at maximum size by keeping most diverse behaviors.

  ## Parameters

  - `archive` - Current archive
  - `new_prompts` - New prompts to add
  - `opts` - Options:
    - `:max_size` - Maximum archive size (default: 50)
    - `:selection_strategy` - :random | :diverse | :recent (default: :diverse)

  ## Returns

  - `{:ok, updated_archive}` - Updated archive
  - `{:error, reason}` - If update fails

  ## Examples

      {:ok, archive} = NoveltyScorer.update_archive(archive, new_evaluated_prompts)
  """
  @spec update_archive(list(map()), list(String.t() | map()), keyword()) ::
          {:ok, list(map())} | {:error, term()}
  def update_archive(archive, new_prompts, opts \\ []) do
    max_size = Keyword.get(opts, :max_size, @max_archive_size)
    strategy = Keyword.get(opts, :selection_strategy, :diverse)

    # Convert new prompts to archive entries
    new_entries =
      Enum.map(new_prompts, fn prompt ->
        %{
          id: extract_id(prompt),
          text: extract_text(prompt),
          features: extract_features(prompt),
          added_at: DateTime.utc_now()
        }
      end)

    # Combine with existing archive
    combined = archive ++ new_entries

    # Select best entries based on strategy
    selected =
      case strategy do
        :random ->
          Enum.take_random(combined, min(max_size, length(combined)))

        :recent ->
          combined
          |> Enum.sort_by(& &1.added_at, {:desc, DateTime})
          |> Enum.take(max_size)

        :diverse ->
          select_diverse_entries(combined, max_size)
      end

    {:ok, selected}
  end

  @doc """
  Creates a combined fitness-novelty score.

  ## Parameters

  - `fitness` - Fitness score (0.0-1.0)
  - `novelty` - Novelty score (0.0-1.0)
  - `novelty_weight` - Weight for novelty (default: 0.2)

  ## Returns

  - `float()` - Combined score

  ## Examples

      combined = NoveltyScorer.combine_fitness_novelty(0.8, 0.6, 0.2)
      # => 0.76 (80% fitness, 20% novelty)
  """
  @spec combine_fitness_novelty(float(), float(), float()) :: float()
  def combine_fitness_novelty(fitness, novelty, novelty_weight \\ 0.2) do
    fitness_weight = 1.0 - novelty_weight
    combined = fitness * fitness_weight + novelty * novelty_weight
    Float.round(combined, 3)
  end

  # Private functions

  defp extract_id(%{id: id}), do: id
  defp extract_id(prompt) when is_binary(prompt), do: Uniq.UUID.uuid4()
  defp extract_id(_), do: Uniq.UUID.uuid4()

  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(%{text: text}), do: text
  defp extract_text(%{prompt: text}), do: text
  defp extract_text(_), do: ""

  defp extract_features(prompt) do
    # Extract simple behavioral features from prompt
    # In a full implementation, this would use trajectory data
    text = extract_text(prompt)

    has_example = if String.contains?(String.downcase(text), "example"), do: 1.0, else: 0.0
    has_step = if String.contains?(String.downcase(text), "step"), do: 1.0, else: 0.0

    has_constraints =
      if String.contains?(String.downcase(text), ["must", "should", "don't"]), do: 1.0, else: 0.0

    [
      # Length feature
      String.length(text) / 1000.0,
      # Word count feature
      length(String.split(text)) / 100.0,
      # Has examples
      has_example,
      # Has step-by-step
      has_step,
      # Has constraints
      has_constraints
    ]
  end

  defp euclidean_distance(features_a, features_b) do
    # Ensure same length
    len = min(length(features_a), length(features_b))
    feat_a = Enum.take(features_a, len)
    feat_b = Enum.take(features_b, len)

    # Calculate Euclidean distance
    squared_diffs =
      Enum.zip(feat_a, feat_b)
      |> Enum.map(fn {a, b} -> :math.pow(a - b, 2) end)
      |> Enum.sum()

    :math.sqrt(squared_diffs)
  end

  defp select_diverse_entries(entries, max_size) do
    if length(entries) <= max_size do
      entries
    else
      # Select entries with maximum pairwise distance
      # Simple greedy approach: start with random, add most distant
      [first | rest] = Enum.shuffle(entries)
      selected = [first]

      select_diverse_greedy(rest, selected, max_size - 1)
    end
  end

  defp select_diverse_greedy(_candidates, selected, remaining) when remaining <= 0 do
    selected
  end

  defp select_diverse_greedy([], selected, _remaining) do
    selected
  end

  defp select_diverse_greedy(candidates, selected, remaining) do
    # Find candidate most distant from current selection
    {most_distant, _distance} =
      Enum.map(candidates, fn candidate ->
        min_distance =
          Enum.map(selected, fn sel ->
            euclidean_distance(candidate.features, sel.features)
          end)
          |> Enum.min()

        {candidate, min_distance}
      end)
      |> Enum.max_by(fn {_candidate, dist} -> dist end)

    new_selected = [most_distant | selected]
    new_candidates = List.delete(candidates, most_distant)

    select_diverse_greedy(new_candidates, new_selected, remaining - 1)
  end
end
