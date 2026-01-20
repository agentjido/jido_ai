defmodule Jido.AI.Accuracy.RoutingResult do
  @moduledoc """
  Represents the result of routing a candidate through a calibration gate.

  A RoutingResult contains information about what action was taken,
  the (possibly modified) candidate, and metadata about the routing decision.

  ## Fields

  - `:action` - The action taken (:direct, :with_verification, :with_citations, :abstain, :escalate)
  - `:candidate` - The (possibly modified) candidate
  - `:original_score` - The original confidence score
  - `:confidence_level` - The confidence level (:high, :medium, :low)
  - `:reasoning` - Human-readable explanation for the routing decision
  - `:metadata` - Additional metadata

  ## Actions

  - `:direct` - Return candidate unchanged (high confidence)
  - `:with_verification` - Add verification suggestions (medium confidence)
  - `:with_citations` - Add source citations (medium confidence)
  - `:abstain` - Return abstention message (low confidence)
  - `:escalate` - Escalate to human review (low confidence)

  ## Usage

      # Create a routing result
      {:ok, result} = RoutingResult.new(%{
        action: :direct,
        candidate: candidate,
        original_score: 0.85,
        confidence_level: :high,
        reasoning: "High confidence, returning answer directly"
      })

      # Check action type
      RoutingResult.direct?(result)
      # => true

      RoutingResult.abstained?(result)
      # => false

  """

  alias Jido.AI.Accuracy.{Candidate, Helpers}

  import Helpers, only: [get_attr: 2, get_attr: 3]

  @type t :: %__MODULE__{
          action: action(),
          candidate: Candidate.t() | nil,
          original_score: float(),
          confidence_level: confidence_level(),
          reasoning: String.t() | nil,
          metadata: map()
        }

  @type action :: :direct | :with_verification | :with_citations | :abstain | :escalate
  @type confidence_level :: :high | :medium | :low

  @actions [:direct, :with_verification, :with_citations, :abstain, :escalate]

  defstruct [
    :action,
    :candidate,
    :original_score,
    :confidence_level,
    :reasoning,
    metadata: %{}
  ]

  @doc """
  Creates a new RoutingResult from the given attributes.

  ## Parameters

  - `attrs` - Map with routing result attributes:
    - `:action` (required) - The action taken
    - `:candidate` (optional) - The candidate
    - `:original_score` (optional) - Original confidence score
    - `:confidence_level` (optional) - Confidence level
    - `:reasoning` (optional) - Explanation for routing
    - `:metadata` (optional) - Additional metadata

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> RoutingResult.new(%{action: :direct, original_score: 0.8, confidence_level: :high})
      {:ok, %RoutingResult{action: :direct, ...}}

      iex> RoutingResult.new(%{action: :invalid})
      {:error, :invalid_action}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    action = get_attr(attrs, :action)
    original_score = get_attr(attrs, :original_score)
    confidence_level = get_attr(attrs, :confidence_level)

    with :ok <- validate_action(action),
         :ok <- validate_score(original_score),
         :ok <- validate_confidence_level(confidence_level) do
      result = %__MODULE__{
        action: action,
        candidate: get_attr(attrs, :candidate),
        original_score: original_score,
        confidence_level: confidence_level,
        reasoning: get_attr(attrs, :reasoning),
        metadata: get_attr(attrs, :metadata, %{})
      }

      {:ok, result}
    end
  end

  @doc """
  Creates a new RoutingResult, raising on error.

  ## Examples

      iex> RoutingResult.new!(%{action: :direct, original_score: 0.8})
      %RoutingResult{action: :direct, ...}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, result} -> result
      {:error, reason} -> raise ArgumentError, "Invalid RoutingResult: #{format_error(reason)}"
    end
  end

  @doc """
  Returns true if the action was :direct.

  ## Examples

      iex> result = RoutingResult.new!(%{action: :direct})
      iex> RoutingResult.direct?(result)
      true

  """
  @spec direct?(t()) :: boolean()
  def direct?(%__MODULE__{action: :direct}), do: true
  def direct?(%__MODULE__{}), do: false

  @doc """
  Returns true if the action was :with_verification.

  ## Examples

      iex> result = RoutingResult.new!(%{action: :with_verification})
      iex> RoutingResult.with_verification?(result)
      true

  """
  @spec with_verification?(t()) :: boolean()
  def with_verification?(%__MODULE__{action: :with_verification}), do: true
  def with_verification?(%__MODULE__{}), do: false

  @doc """
  Returns true if the action was :with_citations.

  ## Examples

      iex> result = RoutingResult.new!(%{action: :with_citations})
      iex> RoutingResult.with_citations?(result)
      true

  """
  @spec with_citations?(t()) :: boolean()
  def with_citations?(%__MODULE__{action: :with_citations}), do: true
  def with_citations?(%__MODULE__{}), do: false

  @doc """
  Returns true if the action was :abstain.

  ## Examples

      iex> result = RoutingResult.new!(%{action: :abstain})
      iex> RoutingResult.abstained?(result)
      true

  """
  @spec abstained?(t()) :: boolean()
  def abstained?(%__MODULE__{action: :abstain}), do: true
  def abstained?(%__MODULE__{}), do: false

  @doc """
  Returns true if the action was :escalate.

  ## Examples

      iex> result = RoutingResult.new!(%{action: :escalate})
      iex> RoutingResult.escalated?(result)
      true

  """
  @spec escalated?(t()) :: boolean()
  def escalated?(%__MODULE__{action: :escalate}), do: true
  def escalated?(%__MODULE__{}), do: false

  @doc """
  Returns true if the candidate was returned as-is (direct action).

  ## Examples

      iex> result = RoutingResult.new!(%{action: :direct})
      iex> RoutingResult.unmodified?(result)
      true

      iex> result = RoutingResult.new!(%{action: :abstain})
      iex> RoutingResult.unmodified?(result)
      false

  """
  @spec unmodified?(t()) :: boolean()
  def unmodified?(%__MODULE__{action: :direct}), do: true
  def unmodified?(%__MODULE__{}), do: false

  @doc """
  Returns true if the candidate was modified from its original form.

  ## Examples

      iex> result = RoutingResult.new!(%{action: :with_verification})
      iex> RoutingResult.modified?(result)
      true

  """
  @spec modified?(t()) :: boolean()
  def modified?(%__MODULE__{} = result), do: !unmodified?(result)

  @doc """
  Converts the result to a map for serialization.

  ## Examples

      iex> result = RoutingResult.new!(%{action: :direct, original_score: 0.8})
      iex> map = RoutingResult.to_map(result)
      iex> Map.has_key?(map, "action")
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

      iex> map = %{"action" => "direct", "original_score" => 0.8}
      iex> {:ok, result} = RoutingResult.from_map(map)
      iex> result.action
      :direct

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    attrs =
      map
      |> Map.new(fn {k, v} -> {String.to_atom(k), convert_value(k, v)} end)

    new(attrs)
  end

  # Convert values from string representation back to atoms
  # Note: When atom conversion fails (unknown atom), we keep the string value.
  # This allows partial deserialization and prevents data loss. The caller
  # should validate the result's action/confidence_level fields after deserialization.
  defp convert_value("action", value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp convert_value("confidence_level", value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> value
  end

  defp convert_value(_, value), do: value

  # Private functions

  defp validate_action(action) when action in @actions, do: :ok
  defp validate_action(_), do: {:error, :invalid_action}

  defp validate_score(nil), do: :ok
  defp validate_score(score) when is_number(score) and score >= 0.0 and score <= 1.0, do: :ok
  defp validate_score(_), do: {:error, :invalid_score}

  defp validate_confidence_level(nil), do: :ok
  defp validate_confidence_level(level) when level in [:high, :medium, :low], do: :ok
  defp validate_confidence_level(_), do: {:error, :invalid_confidence_level}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
