defmodule Jido.AI.Accuracy.ConfidenceEstimate do
  @moduledoc """
  Represents a confidence estimate for a candidate response.

  A ConfidenceEstimate contains the confidence score along with metadata
  about how the confidence was estimated and additional context.

  ## Fields

  - `:score` - Confidence score in range [0.0, 1.0]
  - `:calibration` - How well-calibrated this estimate is (optional)
  - `:method` - The method used for estimation (e.g., `:attention`, `:ensemble`)
  - `:reasoning` - Human-readable explanation for the confidence level
  - `:token_level_confidence` - Per-token confidence scores if available
  - `:metadata` - Additional metadata

  ## Confidence Levels

  - **High confidence**: score ≥ 0.7 - Answer can be returned directly
  - **Medium confidence**: 0.4 ≤ score < 0.7 - Answer should include verification
  - **Low confidence**: score < 0.4 - System should abstain or escalate

  ## Usage

      # Create a basic confidence estimate
      {:ok, estimate} = ConfidenceEstimate.new(%{
        score: 0.85,
        method: :attention
      })

      # Check confidence level
      ConfidenceEstimate.high_confidence?(estimate)
      # => true

      ConfidenceEstimate.confidence_level(estimate)
      # => :high

      # Create with token-level detail
      {:ok, estimate} = ConfidenceEstimate.new(%{
        score: 0.75,
        method: :attention,
        token_level_confidence: [0.9, 0.8, 0.7, 0.6],
        reasoning: "Most tokens have high probability"
      })

  """

  @type t :: %__MODULE__{
          score: float(),
          calibration: float() | nil,
          method: atom() | String.t(),
          reasoning: String.t() | nil,
          token_level_confidence: [float()] | nil,
          metadata: map()
        }

  defstruct [
    :score,
    :calibration,
    :method,
    :reasoning,
    :token_level_confidence,
    metadata: %{}
  ]

  @type confidence_level :: :high | :medium | :low

  @doc """
  Creates a new ConfidenceEstimate from the given attributes.

  ## Parameters

  - `attrs` - Map with confidence estimate attributes:
    - `:score` (required) - Confidence score [0-1]
    - `:method` (required) - Estimation method
    - `:calibration` (optional) - Calibration metric
    - `:reasoning` (optional) - Explanation for confidence
    - `:token_level_confidence` (optional) - Per-token scores
    - `:metadata` (optional) - Additional metadata

  ## Returns

  `{:ok, estimate}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> ConfidenceEstimate.new(%{score: 0.8, method: :attention})
      {:ok, %ConfidenceEstimate{score: 0.8, method: :attention, ...}}

      iex> ConfidenceEstimate.new(%{score: 1.5, method: :bad})
      {:error, :invalid_score}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    score = get_attr(attrs, :score)
    method = get_attr(attrs, :method)

    with :ok <- validate_score(score),
         :ok <- validate_method(method) do
      estimate = %__MODULE__{
        score: score,
        method: method,
        calibration: get_attr(attrs, :calibration),
        reasoning: get_attr(attrs, :reasoning),
        token_level_confidence: get_attr(attrs, :token_level_confidence),
        metadata: get_attr(attrs, :metadata, %{})
      }

      {:ok, estimate}
    end
  end

  @doc """
  Creates a new ConfidenceEstimate, raising on error.

  ## Examples

      iex> ConfidenceEstimate.new!(%{score: 0.8, method: :attention})
      %ConfidenceEstimate{score: 0.8, method: :attention, ...}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, estimate} -> estimate
      {:error, reason} -> raise ArgumentError, "Invalid ConfidenceEstimate: #{format_error(reason)}"
    end
  end

  @doc """
  Returns true if the confidence score is high (≥ 0.7).

  ## Examples

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})
      iex> ConfidenceEstimate.high_confidence?(estimate)
      true

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})
      iex> ConfidenceEstimate.high_confidence?(estimate)
      false

  """
  @spec high_confidence?(t()) :: boolean()
  def high_confidence?(%__MODULE__{score: score}) when is_number(score) do
    score >= 0.7
  end

  @doc """
  Returns true if the confidence score is low (< 0.4).

  ## Examples

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.3, method: :test})
      iex> ConfidenceEstimate.low_confidence?(estimate)
      true

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.6, method: :test})
      iex> ConfidenceEstimate.low_confidence?(estimate)
      false

  """
  @spec low_confidence?(t()) :: boolean()
  def low_confidence?(%__MODULE__{score: score}) when is_number(score) do
    score < 0.4
  end

  @doc """
  Returns true if the confidence score is medium (0.4 ≤ score < 0.7).

  ## Examples

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})
      iex> ConfidenceEstimate.medium_confidence?(estimate)
      true

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})
      iex> ConfidenceEstimate.medium_confidence?(estimate)
      false

  """
  @spec medium_confidence?(t()) :: boolean()
  def medium_confidence?(%__MODULE__{score: score}) when is_number(score) do
    score >= 0.4 and score < 0.7
  end

  @doc """
  Returns the confidence level as an atom.

  ## Returns

  - `:high` - if score ≥ 0.7
  - `:medium` - if 0.4 ≤ score < 0.7
  - `:low` - if score < 0.4

  ## Examples

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})
      iex> ConfidenceEstimate.confidence_level(estimate)
      :high

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})
      iex> ConfidenceEstimate.confidence_level(estimate)
      :medium

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.3, method: :test})
      iex> ConfidenceEstimate.confidence_level(estimate)
      :low

  """
  @spec confidence_level(t()) :: confidence_level()
  def confidence_level(%__MODULE__{score: score}) when is_number(score) do
    cond do
      score >= 0.7 -> :high
      score >= 0.4 -> :medium
      true -> :low
    end
  end

  @doc """
  Converts the estimate to a map for serialization.

  ## Examples

      iex> estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :attention})
      iex> map = ConfidenceEstimate.to_map(estimate)
      iex> Map.has_key?(map, "score")
      true

  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = estimate) do
    estimate
    |> Map.from_struct()
    |> Enum.reject(fn {k, v} -> k == :__struct__ or is_nil(v) or v == %{} end)
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
    |> Map.new()
  end

  @doc """
  Creates an estimate from a map (inverse of `to_map/1`).

  ## Examples

      iex> map = %{"score" => 0.8, "method" => "attention"}
      iex> {:ok, estimate} = ConfidenceEstimate.from_map(map)
      iex> estimate.score
      0.8

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    attrs =
      map
      |> Enum.map(fn {k, v} -> {String.to_atom(k), v} end)
      |> Map.new()

    new(attrs)
  end

  # Private functions

  defp get_attr(attrs, key) when is_list(attrs) do
    Keyword.get(attrs, key)
  end

  defp get_attr(attrs, key) when is_map(attrs) do
    Map.get(attrs, key)
  end

  defp get_attr(attrs, key, default) when is_list(attrs) do
    Keyword.get(attrs, key, default)
  end

  defp get_attr(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, default)
  end

  defp validate_score(score) when is_number(score) do
    if score >= 0.0 and score <= 1.0 do
      :ok
    else
      {:error, :invalid_score}
    end
  end

  defp validate_score(_), do: {:error, :invalid_score}

  defp validate_method(nil), do: {:error, :invalid_method}
  defp validate_method(method) when is_atom(method) or is_binary(method), do: :ok
  defp validate_method(_), do: {:error, :invalid_method}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
