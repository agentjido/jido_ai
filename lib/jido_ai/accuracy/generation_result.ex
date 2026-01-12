defmodule Jido.AI.Accuracy.GenerationResult do
  @moduledoc """
  Represents the result of multi-candidate generation.

  A GenerationResult contains multiple candidates from a generation process
  along with aggregated metadata like total token usage and the best candidate.

  ## Fields

  - `:candidates` - List of Candidate structs
  - `:total_tokens` - Total tokens used across all candidates
  - `:best_candidate` - The highest-scoring candidate (or nil if empty)
  - `:aggregation_method` - How candidates were aggregated (`:none`, `:best_of_n`, `:majority_vote`, etc.)
  - `:metadata` - Additional generation metadata

  ## Usage

      # Create from list of candidates
      candidates = [
        Candidate.new!(%{content: "Answer A", score: 0.7}),
        Candidate.new!(%{content: "Answer B", score: 0.9})
      ]
      result = GenerationResult.new!(candidates, aggregation_method: :best_of_n)

      # Get the best candidate
      best = GenerationResult.best_candidate(result)

      # Select by specific strategy
      selected = GenerationResult.select_by_strategy(result, :best)

      # Add a new candidate
      updated = GenerationResult.add_candidate(result, new_candidate)
  """

  alias Jido.AI.Accuracy.Candidate

  @type t :: %__MODULE__{
          candidates: [Candidate.t()],
          total_tokens: non_neg_integer(),
          best_candidate: Candidate.t() | nil,
          aggregation_method: atom(),
          metadata: map()
        }

  defstruct [
    :candidates,
    :total_tokens,
    :best_candidate,
    :aggregation_method,
    metadata: %{}
  ]

  @doc """
  Creates a new GenerationResult from a list of candidates.

  Automatically computes:
  - `:total_tokens` - Sum of all candidate token usage
  - `:best_candidate` - The candidate with the highest score

  ## Parameters

  - `candidates` - List of Candidate structs
  - `opts` - Optional keyword arguments:
    - `:aggregation_method` - Method used for aggregation (default: `:none`)
    - `:metadata` - Additional metadata (default: `%{}`)

  ## Returns

  `{:ok, generation_result}` on success, `{:error, reason}` on failure.

  ## Examples

      iex> candidates = [Candidate.new!(%{content: "A", score: 0.5})]
      iex> {:ok, result} = GenerationResult.new(candidates)
      iex> result.total_tokens >= 0
      true
  """
  @spec new([Candidate.t()], keyword()) :: {:ok, t()} | {:error, term()}
  def new(candidates, opts \\ []) when is_list(candidates) do
    if valid_candidate_list?(candidates) do
      # Reverse for O(1) prepend performance in add_candidate/2
      reversed_candidates = Enum.reverse(candidates)

      result = %__MODULE__{
        candidates: reversed_candidates,
        total_tokens: compute_total_tokens(reversed_candidates),
        best_candidate: find_best_candidate(reversed_candidates),
        aggregation_method: Keyword.get(opts, :aggregation_method, :none),
        metadata: Keyword.get(opts, :metadata, %{})
      }

      {:ok, result}
    else
      {:error, :invalid_candidates}
    end
  end

  @doc """
  Creates a new GenerationResult, raising on error.

  Like `new/2` but always returns a result. Raises `ArgumentError`
  if candidates is invalid.
  """
  @spec new!([Candidate.t()], keyword()) :: t()
  def new!(candidates, opts \\ []) when is_list(candidates) do
    case new(candidates, opts) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid generation result: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the best (highest-scoring) candidate from the result.

  Returns `nil` if the result has no candidates or all candidates have nil scores.

  ## Parameters

  - `result` - The GenerationResult

  ## Returns

  The highest-scoring Candidate or `nil`.

  ## Examples

      iex> c1 = Candidate.new!(%{content: "A", score: 0.5})
      iex> c2 = Candidate.new!(%{content: "B", score: 0.9})
      iex> result = GenerationResult.new!([c1, c2])
      iex> GenerationResult.best_candidate(result).content
      "B"
  """
  @spec best_candidate(t()) :: Candidate.t() | nil
  def best_candidate(%__MODULE__{candidates: []}) do
    nil
  end

  def best_candidate(%__MODULE__{best_candidate: best}) do
    best
  end

  @doc """
  Returns the total tokens used across all candidates.

  ## Parameters

  - `result` - The GenerationResult

  ## Returns

  Total token count as a non-negative integer.

  ## Examples

      iex> c1 = Candidate.new!(%{tokens_used: 100})
      iex> c2 = Candidate.new!(%{tokens_used: 50})
      iex> result = GenerationResult.new!([c1, c2])
      iex> GenerationResult.total_tokens(result)
      150
  """
  @spec total_tokens(t()) :: non_neg_integer()
  def total_tokens(%__MODULE__{total_tokens: total}) do
    total
  end


  @doc """
  Selects a candidate using the specified strategy.

  Supported strategies:
  - `:best` - Select the highest-scoring candidate
  - `:vote` - Select by majority voting (simple implementation for now)
  - `:first` - Select the first candidate
  - `:last` - Select the last candidate

  ## Parameters

  - `result` - The GenerationResult
  - `strategy` - Selection strategy atom

  ## Returns

  The selected Candidate or `nil` if no candidates.

  ## Examples

      iex> c1 = Candidate.new!(%{content: "A", score: 0.5})
      iex> c2 = Candidate.new!(%{content: "B", score: 0.9})
      iex> result = GenerationResult.new!([c1, c2])
      iex> GenerationResult.select_by_strategy(result, :best).content
      "B"
  """
  @spec select_by_strategy(t(), atom()) :: Candidate.t() | nil
  def select_by_strategy(%__MODULE__{candidates: []}, _strategy) do
    nil
  end

  def select_by_strategy(%__MODULE__{} = result, :best) do
    best_candidate(result)
  end

  def select_by_strategy(%__MODULE__{candidates: candidates}, :first) do
    # Get first candidate (which is last in our internal reversed list)
    List.last(candidates)
  end

  def select_by_strategy(%__MODULE__{candidates: candidates}, :last) do
    # Get last candidate (which is first in our internal reversed list)
    List.first(candidates)
  end

  def select_by_strategy(%__MODULE__{} = result, :vote) do
    # Simple majority vote implementation
    # Full implementation in Phase 1.3 with answer extraction
    select_by_majority_content(candidates(result))
  end

  def select_by_strategy(%__MODULE__{candidates: candidates}, strategy) do
    # Unknown strategy - fall back to best
    select_by_strategy(
      %__MODULE__{candidates: candidates, best_candidate: find_best_candidate(candidates)},
      :best
    )
  end

  @doc """
  Adds a new candidate to the generation result.

  Recomputes total_tokens and best_candidate after adding.

  ## Parameters

  - `result` - The GenerationResult
  - `candidate` - The Candidate to add

  ## Returns

  An updated GenerationResult with the new candidate.

  ## Examples

      iex> result = GenerationResult.new!([Candidate.new!(%{content: "A"})])
      iex> new_candidate = Candidate.new!(%{content: "B", tokens_used: 50})
      iex> updated = GenerationResult.add_candidate(result, new_candidate)
      iex> length(updated.candidates)
      2
  """
  @spec add_candidate(t(), Candidate.t()) :: t() | {:error, term()}
  def add_candidate(%__MODULE__{} = result, %Candidate{} = candidate) do
    # Prepend for O(1) performance instead of append (O(n))
    # Order is preserved by reversing in candidates/1 when accessed
    new_candidates = [candidate | result.candidates]

    %{result | candidates: new_candidates, total_tokens: compute_total_tokens(new_candidates)}
    |> recompute_best_candidate()
  end

  @doc """
  Returns the list of candidates from the result.

  Candidates are returned in the order they were added (oldest first).

  ## Parameters

  - `result` - The GenerationResult

  ## Returns

  List of Candidate structs.

  ## Examples

      iex> candidates = [Candidate.new!(%{content: "A"})]
      iex> result = GenerationResult.new!(candidates)
      iex> length(GenerationResult.candidates(result))
      1
  """
  @spec candidates(t()) :: [Candidate.t()]
  def candidates(%__MODULE__{candidates: candidates}) do
    # Reverse to maintain original order since we prepend in add_candidate/2
    Enum.reverse(candidates)
  end

  @doc """
  Serializes a generation result to a map.

  The map can be deserialized back using `from_map/1`.

  ## Parameters

  - `result` - The GenerationResult

  ## Returns

  A map with generation result data.

  ## Examples

      iex> candidates = [Candidate.new!(%{content: "A", score: 0.5})]
      iex> result = GenerationResult.new!(candidates, aggregation_method: :best_of_n)
      iex> map = GenerationResult.to_map(result)
      iex> map["aggregation_method"]
      "best_of_n"
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    %{
      "candidates" => Enum.map(candidates(result), &Candidate.to_map/1),
      "total_tokens" => result.total_tokens,
      "best_candidate" => if(result.best_candidate, do: Candidate.to_map(result.best_candidate), else: nil),
      "aggregation_method" => result.aggregation_method,
      "metadata" => result.metadata
    }
  end

  @doc """
  Deserializes a map to a generation result.

  Reconstructs a result from a map created by `to_map/1`.

  ## Parameters

  - `map` - A map with generation result data

  ## Returns

  `{:ok, generation_result}` on success, `{:error, reason}` on failure.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    with {:ok, candidates} <- deserialize_candidates(Map.get(map, "candidates", [])),
         {:ok, best_candidate} <- deserialize_best_candidate(Map.get(map, "best_candidate")) do
      opts = [
        aggregation_method: parse_aggregation_method(Map.get(map, "aggregation_method") || Map.get(map, :aggregation_method)),
        metadata: Map.get(map, "metadata", %{}) || Map.get(map, :metadata, %{})
      ]

      # Rebuild with new to compute best_candidate properly
      new(candidates, opts)
    else
      _ -> {:error, :invalid_map}
    end
  end

  def from_map(_invalid) do
    {:error, :invalid_map}
  end

  @doc """
  Deserializes a map to a generation result, raising on error.
  """
  @spec from_map!(map()) :: t()
  def from_map!(map) when is_map(map) do
    case from_map(map) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid generation result map: #{inspect(reason)}"
    end
  end

  def from_map!(invalid) do
    raise ArgumentError, "Invalid generation result map: expected a map, got #{inspect(invalid)}"
  end

  # Private functions

  defp valid_candidate_list?(candidates) do
    Enum.all?(candidates, fn
      %Candidate{} -> true
      _ -> false
    end)
  end

  defp compute_total_tokens(candidates) do
    Enum.reduce(candidates, 0, fn candidate, acc ->
      acc + (candidate.tokens_used || 0)
    end)
  end

  defp find_best_candidate([]), do: nil

  defp find_best_candidate(candidates) do
    candidates
    |> Enum.reject(fn c -> is_nil(c.score) end)
    |> Enum.max_by(fn c -> c.score end, fn -> nil end)
  end

  defp recompute_best_candidate(%__MODULE__{} = result) do
    %{result | best_candidate: find_best_candidate(result.candidates)}
  end

  defp select_by_majority_content(candidates) do
    # Group candidates by content (simple string comparison)
    # Full implementation with answer extraction in Phase 1.3
    candidates
    |> Enum.group_by(fn c -> c.content end)
    |> Enum.max_by(fn {_content, group} -> length(group) end, fn -> nil end)
    |> case do
      {_content, [candidate | _]} -> candidate
      _ -> nil
    end
  end

  defp deserialize_candidates(nil), do: {:ok, []}
  defp deserialize_candidates([]), do: {:ok, []}

  defp deserialize_candidates(candidates) when is_list(candidates) do
    candidates
    |> Enum.reduce({:ok, []}, fn candidate_map, acc ->
      case {acc, Candidate.from_map(candidate_map)} do
        {{:ok, list}, {:ok, candidate}} -> {:ok, list ++ [candidate]}
        {{:ok, _list}, {:error, _reason}} -> {:error, :invalid_candidate}
        {{:error, _reason}, _} -> acc
      end
    end)
  end

  defp deserialize_candidates(_), do: {:error, :invalid_candidates}

  defp deserialize_best_candidate(nil), do: {:ok, nil}
  defp deserialize_best_candidate(%{} = map), do: Candidate.from_map(map)
  defp deserialize_best_candidate(_), do: {:ok, nil}

  defp parse_aggregation_method(nil), do: :none
  defp parse_aggregation_method(method) when is_atom(method), do: method
  defp parse_aggregation_method(method) when is_binary(method), do: String.to_existing_atom(method)
  defp parse_aggregation_method(_), do: :none
end
