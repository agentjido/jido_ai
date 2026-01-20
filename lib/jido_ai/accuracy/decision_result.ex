defmodule Jido.AI.Accuracy.DecisionResult do
  @moduledoc """
  Represents the result of a selective generation decision.

  A DecisionResult contains information about whether to answer or abstain,
  along with the expected value calculations that informed the decision.

  ## Fields

  - `:decision` - The decision made (:answer or :abstain)
  - `:candidate` - The (possibly modified) candidate
  - `:confidence` - The original confidence score
  - `:ev_answer` - Expected value of answering
  - `:ev_abstain` - Expected value of abstaining (always 0)
  - `:reasoning` - Human-readable explanation for the decision
  - `:metadata` - Additional metadata

  ## Decisions

  - `:answer` - Return the candidate (positive expected value)
  - `:abstain` - Abstain from answering (non-positive expected value)

  ## Usage

      # Create a decision result
      {:ok, result} = DecisionResult.new(%{
        decision: :answer,
        candidate: candidate,
        confidence: 0.8,
        ev_answer: 0.6,
        ev_abstain: 0.0,
        reasoning: "Positive expected value"
      })

      # Check decision type
      DecisionResult.answered?(result)
      # => true

      DecisionResult.abstained?(result)
      # => false

  """

  alias Jido.AI.Accuracy.{Candidate, Helpers}

  import Helpers, only: [get_attr: 2, get_attr: 3]

  @type t :: %__MODULE__{
          decision: decision(),
          candidate: Candidate.t() | nil,
          confidence: float(),
          ev_answer: float(),
          ev_abstain: float(),
          reasoning: String.t() | nil,
          metadata: map()
        }

  @type decision :: :answer | :abstain

  @decisions [:answer, :abstain]

  defstruct [
    :decision,
    :candidate,
    :confidence,
    :ev_answer,
    :ev_abstain,
    :reasoning,
    metadata: %{}
  ]

  @doc """
  Creates a new DecisionResult from the given attributes.

  ## Parameters

  - `attrs` - Map with decision result attributes:
    - `:decision` (required) - The decision made
    - `:candidate` (optional) - The candidate
    - `:confidence` (optional) - Confidence score
    - `:ev_answer` (optional) - Expected value of answering
    - `:ev_abstain` (optional) - Expected value of abstaining
    - `:reasoning` (optional) - Explanation for decision
    - `:metadata` (optional) - Additional metadata

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> DecisionResult.new(%{decision: :answer, confidence: 0.8})
      {:ok, %DecisionResult{decision: :answer, ...}}

      iex> DecisionResult.new(%{decision: :invalid})
      {:error, :invalid_decision}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    decision = get_attr(attrs, :decision)

    with :ok <- validate_decision(decision) do
      result = %__MODULE__{
        decision: decision,
        candidate: get_attr(attrs, :candidate),
        confidence: get_attr(attrs, :confidence),
        ev_answer: get_attr(attrs, :ev_answer, 0.0),
        ev_abstain: get_attr(attrs, :ev_abstain, 0.0),
        reasoning: get_attr(attrs, :reasoning),
        metadata: get_attr(attrs, :metadata, %{})
      }

      {:ok, result}
    end
  end

  @doc """
  Creates a new DecisionResult, raising on error.

  ## Examples

      iex> DecisionResult.new!(%{decision: :answer})
      %DecisionResult{decision: :answer}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid DecisionResult: #{format_error(reason)}"
    end
  end

  @doc """
  Returns true if the decision was to answer.

  ## Examples

      iex> result = DecisionResult.new!(%{decision: :answer})
      iex> DecisionResult.answered?(result)
      true

  """
  @spec answered?(t()) :: boolean()
  def answered?(%__MODULE__{decision: :answer}), do: true
  def answered?(%__MODULE__{}), do: false

  @doc """
  Returns true if the decision was to abstain.

  ## Examples

      iex> result = DecisionResult.new!(%{decision: :abstain})
      iex> DecisionResult.abstained?(result)
      true

  """
  @spec abstained?(t()) :: boolean()
  def abstained?(%__MODULE__{decision: :abstain}), do: true
  def abstained?(%__MODULE__{}), do: false

  @doc """
  Converts the result to a map for serialization.

  ## Examples

      iex> result = DecisionResult.new!(%{decision: :answer, confidence: 0.8})
      iex> map = DecisionResult.to_map(result)
      iex> Map.has_key?(map, "decision")
      true

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Enum.reject(fn {k, v} -> k == :__struct__ or is_nil(v) or v == %{} end)
    |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
  end

  @doc """
  Creates a result from a map (inverse of `to_map/1`).

  ## Examples

      iex> map = %{"decision" => "answer", "confidence" => 0.8}
      iex> {:ok, result} = DecisionResult.from_map(map)
      iex> result.decision
      :answer

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    attrs =
      map
      |> Map.new(fn {k, v} -> {String.to_atom(k), convert_value(k, v)} end)

    new(attrs)
  end

  # Private functions

  defp validate_decision(decision) when decision in @decisions, do: :ok
  defp validate_decision(_), do: {:error, :invalid_decision}

  # Convert values from string representation back to atoms
  # Note: When atom conversion fails (unknown atom), we keep the string value.
  # This allows partial deserialization and prevents data loss. The caller
  # should validate the result's decision field after deserialization.
  defp convert_value("decision", value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp convert_value(_, value), do: value
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
