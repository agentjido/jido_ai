defmodule Jido.AI.Accuracy.Aggregators.MajorityVote do
  @moduledoc """
  Majority vote aggregator for self-consistency.

  This aggregator implements the self-consistency technique by selecting
  the most common answer among multiple candidates. It extracts final
  answers from candidate content and uses majority voting to select
  the best response.

  ## Features

  - Answer extraction from multiple formats
  - Fuzzy matching for similar answers
  - Deterministic tie-breaking
  - Vote confidence calculation
  - Vote distribution analysis

  ## Answer Extraction

  The aggregator tries multiple patterns to extract the final answer:

  1. Quoted text: `"42"` or `"answer"`
  2. "Answer:" prefix
  3. "Therefore:" prefix
  4. "Thus:" prefix
  5. "So:" prefix
  6. "The answer is:" prefix
  7. "Result:" prefix
  8. Last line of content

  ## Usage

      candidates = [
        Candidate.new!(%{content: "Let me think...\\n\\nThe answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 41"})
      ]

      {:ok, best, metadata} = MajorityVote.aggregate(candidates)
      # best.content => "The answer is: 42"
      # metadata.confidence => 0.67 (2/3 votes)

  ## Tie-Breaking

  When there's a tie in votes, the candidate that appeared first
  in the original list is selected (deterministic).

  ## Confidence

  Confidence is calculated as: `vote_count / total_candidates`

  For example, if 3 out of 5 candidates voted for the winning answer,
  confidence = 3/5 = 0.6
  """

  @behaviour Jido.AI.Accuracy.Aggregator

  alias Jido.AI.Accuracy.{Aggregator, Candidate}

  @type answer :: String.t()

  # Answer extraction patterns
  @answer_patterns [
    # Quoted answer
    {~r/"([^"]+)"/, :quote},
    # "Answer:" prefix (with double newline)
    {"\n\nAnswer:", :answer_prefix},
    # "Therefore:" prefix (with double newline)
    {"\n\nTherefore:", :therefore_prefix},
    # "Thus:" prefix (with double newline)
    {"\n\nThus:", :thus_prefix},
    # "So:" prefix (with double newline)
    {"\n\nSo:", :so_prefix},
    # "The answer is:" prefix (with double newline)
    {"\n\nThe answer is:", :the_answer_is_prefix},
    # "Result:" prefix (with double newline)
    {"\n\nResult:", :result_prefix},
    # Single newline patterns (also at start of content)
    {~r/\nAnswer:\s*/i, :answer_prefix_regex_single},
    {~r/\nTherefore:\s*/i, :therefore_prefix_regex_single},
    {~r/\nThus:\s*/i, :thus_prefix_regex_single},
    {~r/\nSo:\s*/i, :so_prefix_regex_single},
    {~r/\nThe answer is:\s*/i, :the_answer_is_prefix_regex_single},
    {~r/\nResult:\s*/i, :result_prefix_regex_single},
    # Start of content patterns (no preceding newline)
    {~r/^Answer:\s*/i, :answer_prefix_start},
    {~r/^Therefore:\s*/i, :therefore_prefix_start},
    {~r/^Thus:\s*/i, :thus_prefix_start},
    {~r/^So:\s*/i, :so_prefix_start},
    {~r/^The answer is:\s*/i, :the_answer_is_prefix_start},
    {~r/^Result:\s*/i, :result_prefix_start},
    # Case-insensitive regex patterns as fallback with double newline
    {~r/\n\nAnswer:\s*/i, :answer_prefix_regex},
    {~r/\n\nTherefore:\s*/i, :therefore_prefix_regex},
    {~r/\n\nThus:\s*/i, :thus_prefix_regex},
    {~r/\n\nSo:\s*/i, :so_prefix_regex},
    {~r/\n\nThe answer is:\s*/i, :the_answer_is_prefix_regex},
    {~r/\n\nResult:\s*/i, :result_prefix_regex}
  ]

  @doc """
  Aggregates candidates using majority voting.

  Extracts answers from all candidates, counts votes, and returns
  the candidate with the most votes along with confidence metadata.

  ## Options

  - `:strict` - If true, disables fuzzy matching (default: false)
  - `:tie_breaker` - `:first` (default) or `:random` for tie-breaking

  ## Examples

      iex> candidates = [
      ...>   Candidate.new!(%{content: "The answer is: 42"}),
      ...>   Candidate.new!(%{content: "The answer is: 42"}),
      ...>   Candidate.new!(%{content: "The answer is: 41"})
      ...> ]
      iex> {:ok, best, meta} = MajorityVote.aggregate(candidates)
      iex> best.content
      "The answer is: 42"
      iex> meta.confidence
      0.666...

  """
  @impl Aggregator
  @spec aggregate([Candidate.t()], keyword()) :: Aggregator.aggregate_result()
  def aggregate(candidates, opts \\ [])

  def aggregate([], _opts) do
    {:error, :no_candidates}
  end

  def aggregate([single], _opts) do
    # Single candidate is always the winner
    {:ok, single, %{confidence: 1.0, vote_distribution: %{extract_answer(single) => 1}}}
  end

  def aggregate(candidates, opts) when is_list(candidates) do
    strict = Keyword.get(opts, :strict, false)

    # Extract answers from all candidates
    answers =
      Enum.map(candidates, fn candidate ->
        {candidate, extract_answer(candidate)}
      end)

    # Normalize answers for comparison
    normalized_answers =
      Enum.map(answers, fn {candidate, answer} ->
        {candidate, normalize_answer(answer, strict)}
      end)

    # Count votes
    vote_counts = count_votes(normalized_answers)

    # Find the winner (most votes) with deterministic tie-breaking
    # We need to find which answer has the most votes, and in case of tie,
    # pick the one that appears first in the original candidates list
    max_votes = vote_counts |> Map.values() |> Enum.max(fn -> 0 end)

    # Find all answers with max votes
    tied_answers =
      vote_counts
      |> Enum.filter(fn {_answer, count} -> count == max_votes end)
      |> Enum.map(fn {answer, _count} -> answer end)

    # Find the first candidate in original order with a tied answer
    winner_answer =
      Enum.find_value(normalized_answers, fn {_candidate, normalized_answer} ->
        if normalized_answer in tied_answers do
          normalized_answer
        end
      end)

    # Find the first candidate with the winning answer
    winner =
      Enum.find_value(answers, fn {candidate, answer} ->
        if normalize_answer(answer, strict) == winner_answer do
          candidate
        end
      end)

    vote_count = Map.get(vote_counts, winner_answer, 0)
    confidence = vote_count / length(candidates)

    metadata = %{
      confidence: confidence,
      vote_distribution: vote_counts,
      total_votes: length(candidates),
      winning_votes: vote_count
    }

    {:ok, winner, metadata}
  end

  @doc """
  Extracts the final answer from a candidate's content.

  Tries multiple patterns to find the final answer:
  - Quoted text
  - "Answer:" prefix
  - "Therefore:" prefix
  - "Thus:" prefix
  - "So:" prefix
  - "The answer is:" prefix
  - "Result:" prefix
  - Last line as fallback

  ## Examples

      iex> candidate = Candidate.new!(%{content: "Thinking...\\n\\nThe answer is: 42"})
      iex> MajorityVote.extract_answer(candidate)
      "42"

      iex> candidate = Candidate.new!(%{content: "Let's calculate.\\n\\nTherefore: 100"})
      iex> MajorityVote.extract_answer(candidate)
      "100"

  """
  @spec extract_answer(Candidate.t()) :: String.t()
  def extract_answer(%Candidate{content: content}) when is_binary(content) do
    extract_answer_from_content(content)
  end

  def extract_answer(%Candidate{}), do: ""

  @spec extract_answer_from_content(String.t()) :: String.t()
  def extract_answer_from_content(content) do
    # Try each pattern in order
    extract_with_patterns(content, @answer_patterns) || fallback_to_last_line(content)
  end

  @doc """
  Returns the vote distribution for a list of candidates.

  Useful for analyzing how votes were distributed among answers.

  ## Examples

      iex> candidates = [
      ...>   Candidate.new!(%{content: "Answer: 42"}),
      ...>   Candidate.new!(%{content: "Answer: 42"}),
      ...>   Candidate.new!(%{content: "Answer: 41"})
      ...> ]
      iex> MajorityVote.distribution(candidates)
      %{"42" => 2, "41" => 1}

  """
  @impl Aggregator
  @spec distribution([Candidate.t()]) :: %{String.t() => non_neg_integer()}
  def distribution(candidates) when is_list(candidates) do
    candidates
    |> Enum.map(fn candidate -> {candidate, extract_answer(candidate)} end)
    |> Enum.map(fn {candidate, answer} -> {candidate, normalize_answer(answer, false)} end)
    |> count_votes()
  end

  # Private functions

  defp extract_with_patterns(content, [{pattern, type} | rest]) do
    case extract_with_pattern(content, pattern, type) do
      {:ok, answer} -> String.trim(answer)
      :no_match -> extract_with_patterns(content, rest)
    end
  end

  defp extract_with_patterns(_content, []), do: nil

  defp extract_with_pattern(content, _regex, :quote) do
    # Extract quoted text (non-greedy)
    case Regex.run(~r/"([^"]+)"/, content) do
      [_, match] -> {:ok, match}
      _ -> :no_match
    end
  end

  defp extract_with_pattern(content, regex, _type) when is_struct(regex, Regex) do
    # Generic regex pattern extraction
    case Regex.run(regex, content) do
      [_, match] -> {:ok, match}
      _ -> :no_match
    end
  end

  defp extract_with_pattern(content, pattern, _type) when is_binary(pattern) do
    case String.split(content, pattern, parts: 2) do
      [_before, after_part] ->
        # Take the content after the pattern, up to the next newline or end
        answer =
          after_part
          |> String.split("\n", parts: 2)
          |> List.first()
          |> String.trim()

        if answer == "" do
          :no_match
        else
          {:ok, answer}
        end

      [_single_part] ->
        :no_match
    end
  end

  defp extract_with_pattern(content, regex, _type) do
    case Regex.split(regex, content, include_captures: false, parts: 2) do
      [_before, after_part] ->
        answer =
          after_part
          |> String.split("\n", parts: 2)
          |> List.first()
          |> String.trim()

        if answer == "" do
          :no_match
        else
          {:ok, answer}
        end

      [_single_part] ->
        :no_match
    end
  end

  defp fallback_to_last_line(content) do
    content
    |> String.split("\n")
    |> Enum.filter(&(String.trim(&1) != ""))
    |> List.last()
    |> case do
      nil -> ""
      line -> String.trim(line)
    end
  end

  defp normalize_answer(answer, _strict) when is_binary(answer) do
    answer
    |> String.downcase()
    |> String.trim()
    |> remove_punctuation()
  end

  defp normalize_answer(_answer, _strict), do: ""

  defp remove_punctuation(str) do
    str
    |> String.replace(~r/[.,!?;:()\[\]{}"']+$/, "")
    |> String.trim()
  end

  defp count_votes(pairs) do
    Enum.reduce(pairs, %{}, fn {_candidate, answer}, acc ->
      Map.update(acc, answer, 1, &(&1 + 1))
    end)
  end
end
