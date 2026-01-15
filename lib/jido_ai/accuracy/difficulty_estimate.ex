defmodule Jido.AI.Accuracy.DifficultyEstimate do
  @moduledoc """
  Represents a difficulty estimate for a query.

  A DifficultyEstimate contains the difficulty classification along with metadata
  about how the difficulty was determined and additional context.

  ## Fields

  - `:level` - The difficulty level (:easy, :medium, or :hard)
  - `:score` - Numeric difficulty score in range [0.0, 1.0]
  - `:confidence` - Confidence in the difficulty estimate [0.0, 1.0]
  - `:reasoning` - Human-readable explanation for the difficulty assessment
  - `:features` - Map of contributing features (length, complexity, domain, etc.)
  - `:metadata` - Additional metadata

  ## Difficulty Levels

  - **Easy** (score < 0.35): Simple factual questions, direct lookup, basic arithmetic
  - **Medium** (0.35 ≤ score ≤ 0.65): Some reasoning required, multi-step, synthesis
  - **Hard** (score > 0.65): Complex reasoning, creative tasks, deep analysis

  ## Usage

      # Create a basic difficulty estimate
      {:ok, estimate} = DifficultyEstimate.new(%{
        level: :easy,
        score: 0.2,
        confidence: 0.9
      })

      # Check difficulty level
      DifficultyEstimate.easy?(estimate)
      # => true

      DifficultyEstimate.level(estimate)
      # => :easy

      # Create with features and reasoning
      {:ok, estimate} = DifficultyEstimate.new(%{
        level: :hard,
        score: 0.8,
        confidence: 0.7,
        reasoning: "Multi-step math problem with complex operations",
        features: %{
          length: 150,
          complexity: 0.9,
          domain: :math
        }
      })

  ## Compute Budget Mapping

  Difficulty levels map to compute budgets for adaptive allocation:

  | Level | Candidates | PRM | Search | Budget |
  |-------|-----------|-----|--------|--------|
  | Easy  | 3         | No  | No     | Low    |
  | Medium| 5         | Yes | No     | Medium |
  | Hard  | 10        | Yes | Yes    | High   |

  """

  alias Jido.AI.Accuracy.Helpers

  import Helpers, only: [get_attr: 2, get_attr: 3]

  @type t :: %__MODULE__{
          level: level(),
          score: float(),
          confidence: float(),
          reasoning: String.t() | nil,
          features: map(),
          metadata: map()
        }

  @type level :: :easy | :medium | :hard

  @levels [:easy, :medium, :hard]

  # Score thresholds for level classification
  @easy_threshold 0.35
  @hard_threshold 0.65

  defstruct [
    :level,
    :score,
    :confidence,
    :reasoning,
    features: %{},
    metadata: %{}
  ]

  @doc """
  Creates a new DifficultyEstimate from the given attributes.

  ## Parameters

  - `attrs` - Map with difficulty estimate attributes:
    - `:level` (optional) - Difficulty level (:easy, :medium, :hard)
    - `:score` (optional) - Numeric difficulty score [0-1]
    - `:confidence` (optional) - Confidence in estimate [0-1]
    - `:reasoning` (optional) - Explanation for difficulty
    - `:features` (optional) - Contributing features map
    - `:metadata` (optional) - Additional metadata

  If `:level` is not provided, it will be derived from `:score`.

  ## Returns

  `{:ok, estimate}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> DifficultyEstimate.new(%{level: :easy, score: 0.2})
      {:ok, %DifficultyEstimate{level: :easy, score: 0.2, ...}}

      iex> DifficultyEstimate.new(%{score: 0.8})
      {:ok, %DifficultyEstimate{level: :hard, score: 0.8, ...}}

      iex> DifficultyEstimate.new(%{level: :invalid})
      {:error, :invalid_level}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    level = get_attr(attrs, :level)
    score = get_attr(attrs, :score)
    confidence = get_attr(attrs, :confidence)

    with :ok <- validate_score(score),
         :ok <- validate_confidence(confidence),
         {:ok, final_level} <- compute_or_validate_level(level, score) do
      estimate = %__MODULE__{
        level: final_level,
        score: score,
        confidence: confidence,
        reasoning: get_attr(attrs, :reasoning),
        features: get_attr(attrs, :features, %{}),
        metadata: get_attr(attrs, :metadata, %{})
      }

      {:ok, estimate}
    end
  end

  @doc """
  Creates a new DifficultyEstimate, raising on error.

  ## Examples

      iex> DifficultyEstimate.new!(%{level: :easy, score: 0.2})
      %DifficultyEstimate{level: :easy, score: 0.2, ...}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, estimate} -> estimate
      {:error, reason} -> raise ArgumentError, "Invalid DifficultyEstimate: #{format_error(reason)}"
    end
  end

  @doc """
  Returns true if the difficulty level is :easy.

  ## Examples

      iex> estimate = DifficultyEstimate.new!(%{level: :easy, score: 0.2})
      iex> DifficultyEstimate.easy?(estimate)
      true

      iex> estimate = DifficultyEstimate.new!(%{level: :hard, score: 0.8})
      iex> DifficultyEstimate.easy?(estimate)
      false

  """
  @spec easy?(t()) :: boolean()
  def easy?(%__MODULE__{level: :easy}), do: true
  def easy?(%__MODULE__{}), do: false

  @doc """
  Returns true if the difficulty level is :medium.

  ## Examples

      iex> estimate = DifficultyEstimate.new!(%{level: :medium, score: 0.5})
      iex> DifficultyEstimate.medium?(estimate)
      true

  """
  @spec medium?(t()) :: boolean()
  def medium?(%__MODULE__{level: :medium}), do: true
  def medium?(%__MODULE__{}), do: false

  @doc """
  Returns true if the difficulty level is :hard.

  ## Examples

      iex> estimate = DifficultyEstimate.new!(%{level: :hard, score: 0.8})
      iex> DifficultyEstimate.hard?(estimate)
      true

  """
  @spec hard?(t()) :: boolean()
  def hard?(%__MODULE__{level: :hard}), do: true
  def hard?(%__MODULE__{}), do: false

  @doc """
  Returns the difficulty level.

  Alias for accessing the level field directly.

  ## Examples

      iex> estimate = DifficultyEstimate.new!(%{level: :easy, score: 0.2})
      iex> DifficultyEstimate.level(estimate)
      :easy

  """
  @spec level(t()) :: level()
  def level(%__MODULE__{level: level}), do: level

  @doc """
  Converts a numeric score to a difficulty level.

  ## Parameters

  - `score` - Numeric difficulty score [0-1]

  ## Returns

  - `:easy` - if score < 0.35
  - `:medium` - if 0.35 ≤ score ≤ 0.65
  - `:hard` - if score > 0.65

  ## Examples

      iex> DifficultyEstimate.to_level(0.2)
      :easy

      iex> DifficultyEstimate.to_level(0.5)
      :medium

      iex> DifficultyEstimate.to_level(0.8)
      :hard

  """
  @spec to_level(float()) :: level()
  def to_level(score) when is_number(score) do
    cond do
      score < @easy_threshold -> :easy
      score <= @hard_threshold -> :medium
      true -> :hard
    end
  end

  def to_level(_), do: :medium

  @doc """
  Gets the easy threshold.

  """
  @spec easy_threshold() :: float()
  def easy_threshold, do: @easy_threshold

  @doc """
  Gets the hard threshold.

  """
  @spec hard_threshold() :: float()
  def hard_threshold, do: @hard_threshold

  @doc """
  Converts the estimate to a map for serialization.

  ## Examples

      iex> estimate = DifficultyEstimate.new!(%{level: :easy, score: 0.2})
      iex> map = DifficultyEstimate.to_map(estimate)
      iex> Map.has_key?(map, "level")
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

      iex> map = %{"level" => "easy", "score" => 0.2, "confidence" => 0.9}
      iex> {:ok, estimate} = DifficultyEstimate.from_map(map)
      iex> estimate.level
      :easy

  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(map) when is_map(map) do
    # SECURITY: Check for invalid level strings before converting
    # to prevent atom exhaustion attacks
    with {:ok, level} <- convert_level_from_map(Map.get(map, "level")),
         attrs <- map
           |> Enum.map(fn {k, v} -> {String.to_atom(k), convert_value(k, v)} end)
           |> Map.new()
           |> Map.put(:level, level) do
      new(attrs)
    end
  end

  # Private functions

  defp validate_score(nil), do: :ok
  defp validate_score(score) when is_number(score) and score >= 0.0 and score <= 1.0, do: :ok
  defp validate_score(_), do: {:error, :invalid_score}

  defp validate_confidence(nil), do: :ok
  defp validate_confidence(confidence) when is_number(confidence) and confidence >= 0.0 and confidence <= 1.0, do: :ok
  defp validate_confidence(_), do: {:error, :invalid_confidence}

  defp compute_or_validate_level(nil, nil), do: {:ok, :medium}
  defp compute_or_validate_level(nil, score) when is_number(score), do: {:ok, to_level(score)}
  defp compute_or_validate_level(level, _) when level in @levels, do: {:ok, level}
  defp compute_or_validate_level(_, _), do: {:error, :invalid_level}

  # SECURITY: Safe level conversion from map to prevent atom exhaustion
  defp convert_level_from_map(nil), do: {:ok, nil}
  defp convert_level_from_map(level) when is_atom(level) and level in @levels, do: {:ok, level}
  defp convert_level_from_map(level) when is_binary(level) do
    case level do
      "easy" -> {:ok, :easy}
      "medium" -> {:ok, :medium}
      "hard" -> {:ok, :hard}
      _ -> {:error, :invalid_level}
    end
  end
  defp convert_level_from_map(_), do: {:error, :invalid_level}

  # Convert values from string representation back to atoms
  # SECURITY: Use explicit case statement instead of to_existing_atom
  # to prevent atom exhaustion attacks and invalid atom injection
  defp convert_value("level", _value), do: nil  # Level handled separately in convert_level_from_map
  defp convert_value(_, value), do: value
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
