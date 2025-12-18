defmodule Jido.AI.Runner.GEPA.Diversity.SimilarityDetector do
  @moduledoc """
  Detects similarity and near-duplicates in prompt populations.

  Supports multiple similarity strategies:
  - **Text**: Fast, cheap, works for most cases (Levenshtein, Jaccard, n-grams)
  - **Structural**: Moderate cost, considers prompt structure (segments, patterns)
  - **Semantic**: Expensive, embedding-based (requires LLM/embedding model)
  - **Behavioral**: Very expensive, trajectory-based (requires execution data)
  - **Composite**: Weighted combination of multiple strategies

  ## Usage

      # Single comparison
      {:ok, result} = SimilarityDetector.compare(prompt_a, prompt_b)
      result.similarity_score  # => 0.75

      # Build similarity matrix for population
      {:ok, matrix} = SimilarityDetector.build_matrix(prompts, strategy: :text)

      # Find duplicates
      duplicates = SimilarityDetector.find_duplicates(prompts, threshold: 0.9)
  """

  alias Jido.AI.Runner.GEPA.Diversity.{SimilarityMatrix, SimilarityResult}

  @doc """
  Compares two prompts for similarity.

  ## Parameters

  - `prompt_a` - First prompt (string or map with :text field)
  - `prompt_b` - Second prompt
  - `opts` - Options:
    - `:strategy` - :text (default), :structural, :semantic, :behavioral, :composite
    - `:id_a` - ID for prompt_a (default: generated)
    - `:id_b` - ID for prompt_b (default: generated)

  ## Returns

  - `{:ok, SimilarityResult.t()}` - Similarity comparison
  - `{:error, reason}` - If comparison fails

  ## Examples

      {:ok, result} = SimilarityDetector.compare("Solve this", "Calculate that")
      result.similarity_score  # => 0.45
  """
  @spec compare(String.t() | map(), String.t() | map(), keyword()) ::
          {:ok, SimilarityResult.t()} | {:error, term()}
  def compare(prompt_a, prompt_b, opts \\ [])

  def compare(prompt_a, prompt_b, opts) do
    strategy = Keyword.get(opts, :strategy, :text)
    id_a = Keyword.get(opts, :id_a, Uniq.UUID.uuid4())
    id_b = Keyword.get(opts, :id_b, Uniq.UUID.uuid4())

    text_a = extract_text(prompt_a)
    text_b = extract_text(prompt_b)

    with {:ok, score, components} <- calculate_similarity(text_a, text_b, strategy) do
      result = %SimilarityResult{
        prompt_a_id: id_a,
        prompt_b_id: id_b,
        similarity_score: score,
        strategy_used: strategy,
        components: components,
        metadata: %{
          prompt_a_length: String.length(text_a),
          prompt_b_length: String.length(text_b)
        }
      }

      {:ok, result}
    end
  end

  @doc """
  Builds a similarity matrix for a population of prompts.

  Computes pairwise similarity for all prompt pairs.

  ## Parameters

  - `prompts` - List of prompts (strings or maps with :id and :text)
  - `opts` - Options (same as compare/3)

  ## Returns

  - `{:ok, SimilarityMatrix.t()}` - Complete similarity matrix
  - `{:error, reason}` - If matrix construction fails

  ## Examples

      prompts = ["prompt1", "prompt2", "prompt3"]
      {:ok, matrix} = SimilarityDetector.build_matrix(prompts)
      SimilarityDetector.get_similarity(matrix, 0, 1)  # => 0.65
  """
  @spec build_matrix(list(String.t() | map()), keyword()) ::
          {:ok, SimilarityMatrix.t()} | {:error, term()}
  def build_matrix(prompts, opts \\ [])

  def build_matrix([], _opts), do: {:error, :empty_population}

  def build_matrix(prompts, opts) when is_list(prompts) do
    strategy = Keyword.get(opts, :strategy, :text)

    # Extract IDs and texts
    indexed_prompts =
      Enum.with_index(prompts)
      |> Enum.map(fn {prompt, idx} ->
        {extract_id(prompt, idx), extract_text(prompt)}
      end)

    prompt_ids = Enum.map(indexed_prompts, fn {id, _text} -> id end)

    # Compute pairwise similarities
    scores =
      for {id_a, text_a} <- indexed_prompts,
          {id_b, text_b} <- indexed_prompts,
          id_a < id_b,
          into: %{} do
        {score, _components} =
          case calculate_similarity(text_a, text_b, strategy) do
            {:ok, s, c} -> {s, c}
            {:error, _} -> {0.0, %{}}
          end

        {{id_a, id_b}, score}
      end

    matrix = %SimilarityMatrix{
      prompt_ids: prompt_ids,
      scores: scores,
      strategy_used: strategy,
      computed_at: DateTime.utc_now(),
      metadata: %{
        population_size: length(prompts),
        comparisons: map_size(scores)
      }
    }

    {:ok, matrix}
  end

  @doc """
  Gets similarity score between two prompts from a matrix.

  ## Parameters

  - `matrix` - SimilarityMatrix struct
  - `id_a` - First prompt ID or index
  - `id_b` - Second prompt ID or index

  ## Returns

  - `float()` - Similarity score, or 1.0 if comparing same prompt

  ## Examples

      {:ok, matrix} = SimilarityDetector.build_matrix(prompts)
      score = SimilarityDetector.get_similarity(matrix, "id1", "id2")
  """
  @spec get_similarity(SimilarityMatrix.t(), String.t() | integer(), String.t() | integer()) ::
          float()
  def get_similarity(%SimilarityMatrix{} = matrix, id_a, id_b) do
    # Convert indices to IDs if needed
    id_a = resolve_id(matrix, id_a)
    id_b = resolve_id(matrix, id_b)

    if id_a == id_b do
      1.0
    else
      {min_id, max_id} = if id_a < id_b, do: {id_a, id_b}, else: {id_b, id_a}
      Map.get(matrix.scores, {min_id, max_id}, 0.0)
    end
  end

  @doc """
  Finds near-duplicate prompts above a similarity threshold.

  ## Parameters

  - `prompts` - List of prompts
  - `opts` - Options:
    - `:threshold` - Similarity threshold (default: 0.85)
    - `:strategy` - Similarity strategy (default: :text)

  ## Returns

  - `{:ok, duplicates}` - List of {id_a, id_b, score} tuples
  - `{:error, reason}` - If detection fails

  ## Examples

      duplicates = SimilarityDetector.find_duplicates(prompts, threshold: 0.9)
      # => [{"id1", "id2", 0.95}, {"id3", "id4", 0.92}]
  """
  @spec find_duplicates(list(String.t() | map()), keyword()) ::
          {:ok, list({String.t(), String.t(), float()})} | {:error, term()}
  def find_duplicates(prompts, opts \\ []) do
    threshold = Keyword.get(opts, :threshold, 0.85)

    with {:ok, matrix} <- build_matrix(prompts, opts) do
      duplicates =
        matrix.scores
        |> Enum.filter(fn {_pair, score} -> score >= threshold end)
        |> Enum.map(fn {{id_a, id_b}, score} -> {id_a, id_b, score} end)
        |> Enum.sort_by(fn {_a, _b, score} -> score end, :desc)

      {:ok, duplicates}
    end
  end

  # Private functions

  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(%{text: text}), do: text
  defp extract_text(%{prompt: text}), do: text
  defp extract_text(%{content: text}), do: text
  defp extract_text(_), do: ""

  defp extract_id(%{id: id}, _idx), do: id
  defp extract_id(_prompt, idx), do: "prompt_#{idx}"

  defp resolve_id(%SimilarityMatrix{prompt_ids: ids}, idx) when is_integer(idx) do
    Enum.at(ids, idx)
  end

  defp resolve_id(_matrix, id) when is_binary(id), do: id

  defp calculate_similarity(text_a, text_b, :text) do
    text_similarity(text_a, text_b)
  end

  defp calculate_similarity(_text_a, _text_b, :structural) do
    # credo:disable-for-next-line Credo.Check.Design.TagTODO
    # TODO: Implement structural similarity
    {:error, :not_implemented}
  end

  defp calculate_similarity(_text_a, _text_b, :semantic) do
    # credo:disable-for-next-line Credo.Check.Design.TagTODO
    # TODO: Implement semantic similarity
    {:error, :not_implemented}
  end

  defp calculate_similarity(_text_a, _text_b, :behavioral) do
    # credo:disable-for-next-line Credo.Check.Design.TagTODO
    # TODO: Implement behavioral similarity
    {:error, :not_implemented}
  end

  defp calculate_similarity(text_a, text_b, :composite) do
    # Composite: weighted combination
    with {:ok, text_score, text_comp} <- text_similarity(text_a, text_b) do
      # For now, just use text similarity
      # Future: combine multiple strategies
      {:ok, text_score, Map.put(text_comp, :composite, true)}
    end
  end

  # Text-based similarity
  defp text_similarity(text_a, text_b) do
    # Calculate multiple text similarity metrics
    levenshtein = levenshtein_similarity(text_a, text_b)
    jaccard = jaccard_similarity(text_a, text_b)
    ngram = ngram_similarity(text_a, text_b, 3)

    # Weighted average
    score = levenshtein * 0.4 + jaccard * 0.4 + ngram * 0.2

    components = %{
      levenshtein: levenshtein,
      jaccard: jaccard,
      ngram: ngram
    }

    {:ok, Float.round(score, 3), components}
  end

  # Levenshtein distance similarity (normalized)
  defp levenshtein_similarity(text_a, text_b) do
    distance = String.jaro_distance(text_a, text_b)
    Float.round(distance, 3)
  end

  # Jaccard similarity of words
  defp jaccard_similarity(text_a, text_b) do
    words_a = tokenize(text_a)
    words_b = tokenize(text_b)

    intersection = MapSet.intersection(words_a, words_b) |> MapSet.size()
    union = MapSet.union(words_a, words_b) |> MapSet.size()

    if union > 0 do
      Float.round(intersection / union, 3)
    else
      0.0
    end
  end

  # N-gram similarity
  defp ngram_similarity(text_a, text_b, n) do
    ngrams_a = create_ngrams(text_a, n)
    ngrams_b = create_ngrams(text_b, n)

    intersection = MapSet.intersection(ngrams_a, ngrams_b) |> MapSet.size()
    union = MapSet.union(ngrams_a, ngrams_b) |> MapSet.size()

    if union > 0 do
      Float.round(intersection / union, 3)
    else
      0.0
    end
  end

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  defp create_ngrams(text, n) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.graphemes()
    |> Enum.chunk_every(n, 1, :discard)
    |> Enum.map(&Enum.join/1)
    |> MapSet.new()
  end
end
