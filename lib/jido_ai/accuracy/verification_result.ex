defmodule Jido.AI.Accuracy.VerificationResult do
  @moduledoc """
  Represents the result of verifying a candidate response.

  A VerificationResult contains the verification score, confidence,
  optional reasoning text, and step-level scores for process reward models (PRMs).

  ## Fields

  - `:candidate_id` - ID of the verified candidate
  - `:score` - Numeric score (higher is better, scale depends on verifier)
  - `:confidence` - Confidence in the score [0.0, 1.0]
  - `:reasoning` - Text explanation for the score (from LLM verifiers)
  - `:step_scores` - Map of step identifiers to scores (for PRMs)
  - `:metadata` - Additional verifier-specific data

  ## Usage

      # Create a verification result
      {:ok, result} = VerificationResult.new(%{
        candidate_id: "candidate_1",
        score: 0.95,
        confidence: 0.9,
        reasoning: "The answer is correct and well-reasoned."
      })

      # Check if result passes threshold
      VerificationResult.pass?(result, 0.7)
      # => true

      # Merge step scores for PRM aggregation
      result = VerificationResult.merge_step_scores(result, %{"step_1" => 0.8})

      # Serialize for storage/transmission
      map = VerificationResult.to_map(result)
      {:ok, restored} = VerificationResult.from_map(map)

  ## Score Scales

  Different verifiers may use different score scales:
  - Binary verifiers: 0.0 (fail) or 1.0 (pass)
  - LLM verifiers: 0.0 to 1.0 (normalized)
  - PRMs: Sum of step scores (variable range)
  - Custom verifiers: Any numeric range (documented in verifier)

  ## Process Reward Models

  For step-level verification, use `step_scores` to store individual
  step scores. The `merge_step_scores/2` function combines multiple
  step score maps.

      result = VerificationResult.new(%{
        score: 2.4,
        step_scores: %{
          "step_1" => 0.8,
          "step_2" => 0.9,
          "step_3" => 0.7
        }
      })

  """

  @type t :: %__MODULE__{
          candidate_id: String.t() | nil,
          score: number() | nil,
          confidence: number() | nil,
          reasoning: String.t() | nil,
          step_scores: %{String.t() => number()} | nil,
          metadata: map()
        }

  defstruct [
    :candidate_id,
    :score,
    :confidence,
    :reasoning,
    :step_scores,
    metadata: %{}
  ]

  @doc """
  Creates a new VerificationResult from the given attributes.

  ## Parameters

  - `attrs` - Map with verification result attributes:
    - `:candidate_id` (optional) - ID of the verified candidate
    - `:score` (optional) - Numeric verification score
    - `:confidence` (optional) - Confidence in the score [0.0, 1.0]
    - `:reasoning` (optional) - Text explanation for the score
    - `:step_scores` (optional) - Map of step scores for PRMs
    - `:metadata` (optional) - Additional metadata, defaults to `%{}`

  ## Returns

  - `{:ok, result}` - Success
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> VerificationResult.new(%{score: 0.8, confidence: 0.9})
      {:ok, %VerificationResult{score: 0.8, confidence: 0.9}}

      iex> VerificationResult.new(%{score: 0.8, confidence: 1.5})
      {:error, :invalid_confidence}

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    result = struct(__MODULE__, attrs)

    with :ok <- validate_score(result.score),
         :ok <- validate_confidence(result.confidence),
         :ok <- validate_step_scores(result.step_scores) do
      {:ok, result}
    end
  end

  @doc """
  Creates a new VerificationResult, raising on error.

  ## Examples

      iex> VerificationResult.new!(%{score: 0.8})
      %VerificationResult{score: 0.8}

      iex> VerificationResult.new!(%{confidence: 1.5})
      ** (ArgumentError) Invalid confidence: must be in [0.0, 1.0]

  """
  @spec new!(map()) :: t()
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid verification result: #{format_error(reason)}"
    end
  end

  @doc """
  Checks if a verification result passes a given threshold.

  Returns `true` if the result's score is greater than or equal to
  the threshold. Returns `false` if score is nil.

  ## Parameters

  - `result` - The verification result to check
  - `threshold` - The minimum passing score (default: 0.5)

  ## Returns

  - `true` - Score >= threshold
  - `false` - Score < threshold or score is nil

  ## Examples

      iex> result = VerificationResult.new!(%{score: 0.8})
      iex> VerificationResult.pass?(result, 0.7)
      true

      iex> result = VerificationResult.new!(%{score: 0.3})
      iex> VerificationResult.pass?(result, 0.5)
      false

  """
  @spec pass?(t(), number()) :: boolean()
  def pass?(result, threshold \\ 0.5)
  def pass?(%__MODULE__{score: nil}, _threshold), do: false

  def pass?(%__MODULE__{score: score}, threshold) when is_number(score) do
    score >= threshold
  end

  @doc """
  Merges step score maps into the verification result.

  Combines the existing `step_scores` with a new map of step scores.
  If keys conflict, the new values overwrite the old values.

  ## Parameters

  - `result` - The verification result to update
  - `new_scores` - Map of step identifiers to scores to merge

  ## Returns

  Updated verification result with merged step scores

  ## Examples

      iex> result = VerificationResult.new!(%{step_scores: %{"step_1" => 0.8}})
      iex> updated = VerificationResult.merge_step_scores(result, %{"step_2" => 0.9})
      iex> updated.step_scores
      %{"step_1" => 0.8, "step_2" => 0.9}

      iex> result = VerificationResult.new!(%{})
      iex> updated = VerificationResult.merge_step_scores(result, %{"step_1" => 0.8})
      iex> updated.step_scores
      %{"step_1" => 0.8}

  """
  @spec merge_step_scores(t(), %{String.t() => number()}) :: t()
  def merge_step_scores(%__MODULE__{} = result, new_scores) when is_map(new_scores) do
    current_step_scores = Map.get(result, :step_scores) || %{}

    %{result | step_scores: Map.merge(current_step_scores, new_scores)}
  end

  @doc """
  Serializes a verification result to a map.

  All struct fields are converted to a map with string keys
  for JSON encoding and storage.

  ## Examples

      iex> result = VerificationResult.new!(%{score: 0.8, reasoning: "Good"})
      iex> map = VerificationResult.to_map(result)
      iex> map["score"]
      0.8

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  @doc """
  Deserializes a verification result from a map.

  Accepts maps with either string or atom keys.

  ## Returns

  - `{:ok, result}` - Success
  - `{:error, reason}` - Invalid input

  ## Examples

      iex> map = %{"score" => 0.8, "confidence" => 0.9}
      iex> {:ok, result} = VerificationResult.from_map(map)
      iex> result.score
      0.8

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    # Convert string keys to atoms if necessary
    attrs =
      Enum.reduce(map, %{}, fn {k, v}, acc ->
        key = if is_binary(k), do: String.to_existing_atom(k), else: k
        Map.put(acc, key, v)
      end)

    new(attrs)
  end

  @doc """
  Deserializes a verification result from a map, raising on error.

  ## Examples

      iex> map = %{"score" => 0.8, "confidence" => 0.9}
      iex> result = VerificationResult.from_map!(map)
      iex> result.score
      0.8

  """
  @spec from_map!(map()) :: t()
  def from_map!(map) when is_map(map) do
    case from_map(map) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid verification result map: #{format_error(reason)}"
    end
  end

  # Validation functions

  defp validate_score(nil), do: :ok
  defp validate_score(score) when is_number(score), do: :ok
  defp validate_score(_), do: {:error, :invalid_score}

  defp validate_confidence(nil), do: :ok
  defp validate_confidence(conf) when is_number(conf) and conf >= 0.0 and conf <= 1.0, do: :ok
  defp validate_confidence(_), do: {:error, :invalid_confidence}

  defp validate_step_scores(nil), do: :ok

  defp validate_step_scores(scores) when is_map(scores) do
    if Enum.all?(scores, fn {k, v} -> is_binary(k) and is_number(v) end) do
      :ok
    else
      {:error, :invalid_step_scores}
    end
  end

  defp validate_step_scores(_), do: {:error, :invalid_step_scores}
  defp format_error(atom) when is_atom(atom), do: atom
end
