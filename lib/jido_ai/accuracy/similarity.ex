defmodule Jido.AI.Accuracy.Similarity do
  @moduledoc """
  Text similarity metrics for diverse decoding.

  Provides various similarity measures used to ensure diversity
  among candidates in search algorithms.

  ## Metrics

  - **Jaccard Similarity**: Token-based similarity using Jaccard index
  - **Edit Distance Similarity**: Character-based similarity using Levenshtein distance
  - **Combined Similarity**: Weighted combination of multiple metrics

  ## Examples

      iex> Similarity.jaccard_similarity("hello world", "hello there")
      0.5

      iex> Similarity.edit_distance_similarity("kitten", "sitting")
      0.571...

      iex> Similarity.combined_similarity("a", "b", 0.5, 0.5)
      0.25

  ## Jaccard Similarity

  Jaccard similarity measures the overlap between two token sets:

      jaccard(A, B) = |A ∩ B| / |A ∪ B|

  Returns a value between 0.0 (no overlap) and 1.0 (identical).

  ## Edit Distance Similarity

  Based on Levenshtein distance (minimum edit operations):

      similarity = 1 - (edit_distance / max_length)

  Returns a value between 0.0 (completely different) and 1.0 (identical).

  """

  @type similarity_value :: float()

  @doc """
  Calculates Jaccard similarity between two strings.

  Jaccard similarity measures the overlap between token sets:
  |intersection| / |union|

  ## Parameters

  - `text1` - First text string
  - `text2` - Second text string

  ## Returns

  A float between 0.0 (no overlap) and 1.0 (identical tokens).

  ## Examples

      iex> Similarity.jaccard_similarity("hello world", "hello world")
      1.0

      iex> Similarity.jaccard_similarity("hello world", "foo bar")
      0.0

      iex> Similarity.jaccard_similarity("hello world", "hello there")
      0.333...

  """
  @spec jaccard_similarity(String.t(), String.t()) :: similarity_value()
  def jaccard_similarity(text1, text2) when is_binary(text1) and is_binary(text2) do
    tokens1 = tokenize(text1)
    tokens2 = tokenize(text2)

    size1 = MapSet.size(tokens1)
    size2 = MapSet.size(tokens2)

    cond do
      size1 == 0 and size2 == 0 ->
        1.0

      size1 == 0 or size2 == 0 ->
        0.0

      true ->
        intersection = MapSet.intersection(tokens1, tokens2) |> MapSet.size()
        union = MapSet.union(tokens1, tokens2) |> MapSet.size()
        intersection / union
    end
  end

  @doc """
  Calculates similarity based on Levenshtein edit distance.

  Edit distance similarity is defined as:
  1 - (edit_distance / max_length)

  ## Parameters

  - `text1` - First text string
  - `text2` - Second text string

  ## Returns

  A float between 0.0 (completely different) and 1.0 (identical).

  ## Examples

      iex> Similarity.edit_distance_similarity("hello", "hello")
      1.0

      iex> Similarity.edit_distance_similarity("kitten", "sitting")
      0.428...

  """
  @spec edit_distance_similarity(String.t(), String.t()) :: similarity_value()
  def edit_distance_similarity(text1, text2) when is_binary(text1) and is_binary(text2) do
    len1 = String.length(text1)
    len2 = String.length(text2)

    cond do
      len1 == 0 and len2 == 0 ->
        1.0

      len1 == 0 or len2 == 0 ->
        0.0

      true ->
        distance = levenshtein_distance(text1, text2)
        max_len = max(len1, len2)
        1.0 - distance / max_len
    end
  end

  @doc """
  Calculates combined similarity using weighted average.

  Combines Jaccard and edit distance similarities with specified weights.

  ## Parameters

  - `text1` - First text string
  - `text2` - Second text string
  - `jaccard_weight` - Weight for Jaccard similarity (0.0 to 1.0)
  - `edit_weight` - Weight for edit distance similarity (0.0 to 1.0)

  ## Returns

  A weighted similarity score between 0.0 and 1.0.

  ## Examples

      iex> Similarity.combined_similarity("hello", "hello", 0.5, 0.5)
      1.0

      iex> Similarity.combined_similarity("hello world", "hello there", 0.7, 0.3)
      0.3...

  """
  @spec combined_similarity(String.t(), String.t(), float(), float()) :: similarity_value()
  def combined_similarity(text1, text2, jaccard_weight, edit_weight)
      when is_binary(text1) and is_binary(text2) and is_number(jaccard_weight) and is_number(edit_weight) do
    jaccard = jaccard_similarity(text1, text2)
    edit = edit_distance_similarity(text1, text2)

    total_weight = jaccard_weight + edit_weight

    if total_weight > 0 do
      (jaccard * jaccard_weight + edit * edit_weight) / total_weight
    else
      0.0
    end
  end

  # Tokenization helper

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.split(~r/[\s\p{P}]+/, trim: true)
    |> MapSet.new()
  end

  # Levenshtein distance calculation using dynamic programming

  defp levenshtein_distance(text1, text2) do
    chars1 = String.graphemes(text1)
    chars2 = String.graphemes(text2)

    len1 = length(chars1)
    len2 = length(chars2)

    # Initialize DP matrix
    matrix = init_matrix(len1 + 1, len2 + 1)

    # Fill the matrix
    Enum.reduce(1..len1, matrix, fn i, acc ->
      Enum.reduce(1..len2, acc, fn j, inner_acc ->
        cost = if Enum.at(chars1, i - 1) == Enum.at(chars2, j - 1), do: 0, else: 1
        del = get_matrix(inner_acc, i - 1, j) + 1
        ins = get_matrix(inner_acc, i, j - 1) + 1
        sub = get_matrix(inner_acc, i - 1, j - 1) + cost
        put_matrix(inner_acc, i, j, min(del, min(ins, sub)))
      end)
    end)
    |> get_matrix(len1, len2)
  end

  defp init_matrix(rows, cols) do
    for i <- 0..(rows - 1), j <- 0..(cols - 1), into: %{} do
      cond do
        i == 0 -> {{i, j}, j}
        j == 0 -> {{i, j}, i}
        true -> {{i, j}, 0}
      end
    end
  end

  defp get_matrix(matrix, i, j), do: Map.get(matrix, {i, j}, 0)
  defp put_matrix(matrix, i, j, val), do: Map.put(matrix, {i, j}, val)
end
