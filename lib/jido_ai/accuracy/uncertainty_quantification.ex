defmodule Jido.AI.Accuracy.UncertaintyQuantification do
  @moduledoc """
  Quantifies and classifies uncertainty in queries and responses.

  Uncertainty quantification distinguishes between two types of uncertainty:

  1. **Aleatoric uncertainty** - Inherent uncertainty that cannot be reduced
     - Subjective questions ("What's the best movie?")
     - Ambiguous queries ("How should I proceed?")
     - Multiple valid interpretations ("What's the meaning of life?")

  2. **Epistemic uncertainty** - Uncertainty due to lack of knowledge
     - Out-of-domain queries ("Who is the king of Mars in 2050?")
     - Missing factual information
     - Insufficient training data

  ## Fields

  - `:aleatoric_patterns` - Regex patterns for aleatoric uncertainty
  - `:epistemic_patterns` - Regex patterns for epistemic uncertainty
  - `:domain_keywords` - Domain-specific keywords (for epistemic detection)

  ## Usage

      # Create with default patterns
      {:ok, uq} = UncertaintyQuantification.new(%{})

      # Classify a query
      {:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "What's the best movie?")
      # => %UncertaintyResult{uncertainty_type: :aleatoric, ...}

      # Create with custom patterns
      {:ok, uq} = UncertaintyQuantification.new(%{
        aleatoric_patterns: [
          ~r/better|best|worst/i,
          ~r/favorite|prefer/i
        ]
      })

  ## Default Aleatoric Patterns

  - Subjective adjectives: best, better, worst, favorite, prefer
  - Ambiguity markers: maybe, possibly, depends, could be
  - Opinion words: think, believe, feel, opinion
  - Open-ended: how should, what way, in your opinion

  ## Default Epistemic Patterns

  - Future speculation: will happen, predict, forecast
  - Out-of-domain: recent very specific dates, obscure technical details
  - Unknown entities: names that don't match common knowledge

  ## Action Recommendations

  ### Aleatoric Actions
  - `:provide_options` - List multiple valid approaches
  - `:acknowledge_subjectivity` - State that the answer is subjective
  - `:ask_clarification` - Request more specific details

  ### Epistemic Actions
  - `:abstain` - Admit lack of knowledge
  - `:suggest_source` - Recommend where to find the answer
  - `:escalate` - Request human assistance

  ### Certain Actions
  - `:answer_directly` - Provide the factual answer
  - `:provide_citation` - Include source references

  """

  alias Jido.AI.Accuracy.{Candidate, UncertaintyResult, Helpers}

  import Helpers, only: [get_attr: 3]

  @type t :: %__MODULE__{
          aleatoric_patterns: [Regex.t()],
          epistemic_patterns: [Regex.t()],
          domain_keywords: [String.t()],
          min_matches: integer()
        }

  @default_aleatoric_patterns [
    # Subjective adjectives
    ~r/\b(best|better|worst|favorite|prefer|greatest)\b/i,
    # Ambiguity markers
    ~r/\b(maybe|possibly|perhaps|depends|could be|might be)\b/i,
    # Opinion words
    ~r/\b(think|believe|feel|opinion|view|perspective)\b/i,
    # Open-ended questions
    ~r/\b(how should|what way|in your opinion|what do you think)\b/i,
    # Preference words
    ~r/\b(like|love|enjoy|prefer|would rather)\b/i,
    # Subjective nouns
    ~r/\b(beautiful|ugly|good|bad|right|wrong|fair|unfair)\b/i,
    # Comparative
    ~r/\b(more|less|rather|than|compared to)\b/i
  ]

  @default_epistemic_patterns [
    # Future speculation
    ~r/\b(will happen|predict|forecast|future of|going to be)\b/i,
    # Future tense questions
    ~r/\bwho will|what will|when will|where will\b/i,
    # Unanswerable factual questions
    ~r/\b(what is the population of|who is the CEO of)\b/i,
    # Prediction language
    ~r/\b(will win|will happen|predict the)\b/i
  ]

  # Maximum pattern source length to prevent ReDoS attacks
  @max_pattern_length 500
  # Maximum number of patterns to prevent resource exhaustion
  @max_patterns_count 50

  defstruct aleatoric_patterns: nil,
            epistemic_patterns: nil,
            domain_keywords: [],
            min_matches: 1

  @doc """
  Creates a new UncertaintyQuantification from the given attributes.

  ## Parameters

  - `attrs` - Map with uncertainty quantification attributes:
    - `:aleatoric_patterns` (optional) - Custom aleatoric patterns (default: built-in)
    - `:epistemic_patterns` (optional) - Custom epistemic patterns (default: built-in)
    - `:domain_keywords` (optional) - Domain-specific keywords
    - `:min_matches` (optional) - Minimum pattern matches (default: 1)

  ## Returns

  `{:ok, uq}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> UncertaintyQuantification.new(%{})
      {:ok, %UncertaintyQuantification{...}}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    aleatoric_patterns = get_attr(attrs, :aleatoric_patterns, @default_aleatoric_patterns)
    epistemic_patterns = get_attr(attrs, :epistemic_patterns, @default_epistemic_patterns)
    domain_keywords = get_attr(attrs, :domain_keywords, [])
    min_matches = get_attr(attrs, :min_matches, 1)

    with :ok <- validate_patterns(aleatoric_patterns),
         :ok <- validate_patterns(epistemic_patterns) do
      uq = %__MODULE__{
        aleatoric_patterns: aleatoric_patterns,
        epistemic_patterns: epistemic_patterns,
        domain_keywords: domain_keywords,
        min_matches: min_matches
      }

      {:ok, uq}
    end
  end

  @doc """
  Creates a new UncertaintyQuantification, raising on error.

  ## Examples

      iex> UncertaintyQuantification.new!(%{})
      %UncertaintyQuantification{...}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, uq} -> uq
      {:error, reason} -> raise ArgumentError, "Invalid UncertaintyQuantification: #{format_error(reason)}"
    end
  end

  @doc """
  Classifies the uncertainty type of a query or candidate.

  ## Parameters

  - `uq` - The uncertainty quantification configuration
  - `query_or_candidate` - String query or Candidate struct

  ## Returns

  `{:ok, result}` where result contains the uncertainty type and reasoning.

  ## Examples

      uq = UncertaintyQuantification.new!(%{})

      {:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "What's the best movie?")
      # => %UncertaintyResult{uncertainty_type: :aleatoric, ...}

      {:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "What is the capital of France?")
      # => %UncertaintyResult{uncertainty_type: :none, ...}

  """
  @spec classify_uncertainty(t(), String.t() | Candidate.t()) :: {:ok, UncertaintyResult.t()}
  def classify_uncertainty(%__MODULE__{} = uq, query_or_candidate) do
    query = extract_query(query_or_candidate)

    aleatoric_score = detect_aleatoric(uq, query)
    epistemic_score = detect_epistemic(uq, query)

    {uncertainty_type, confidence, reasoning} =
      determine_uncertainty_type(aleatoric_score, epistemic_score, query)

    action = recommend_action(uncertainty_type, confidence)

    result = %UncertaintyResult{
      uncertainty_type: uncertainty_type,
      confidence: confidence,
      reasoning: reasoning,
      suggested_action: action,
      metadata: %{
        aleatoric_score: aleatoric_score,
        epistemic_score: epistemic_score
      }
    }

    {:ok, result}
  end

  @doc """
  Detects aleatoric uncertainty in a query.

  Returns a score [0-1] indicating the likelihood of aleatoric uncertainty.

  ## Examples

      uq = UncertaintyQuantification.new!(%{})

      UncertaintyQuantification.detect_aleatoric(uq, "What's the best movie?")
      # => 0.8 (high aleatoric uncertainty)

  """
  @spec detect_aleatoric(t(), String.t()) :: float()
  def detect_aleatoric(%__MODULE__{} = uq, query) when is_binary(query) do
    matches =
      Enum.count(uq.aleatoric_patterns, fn pattern ->
        Regex.match?(pattern, query)
      end)

    if matches > 0 do
      # Scale based on number of matches
      base_score = matches / length(uq.aleatoric_patterns)
      # Boost to ensure detection is more sensitive
      min(base_score * 3.0, 1.0)
    else
      0.0
    end
  end

  @doc """
  Detects epistemic uncertainty in a query.

  Returns a score [0-1] indicating the likelihood of epistemic uncertainty.

  ## Examples

      uq = UncertaintyQuantification.new!(%{})

      UncertaintyQuantification.detect_epistemic(uq, "Who will be president in 2030?")
      # => 0.7 (high epistemic uncertainty)

  """
  @spec detect_epistemic(t(), String.t()) :: float()
  def detect_epistemic(%__MODULE__{} = uq, query) when is_binary(query) do
    matches =
      Enum.count(uq.epistemic_patterns, fn pattern ->
        Regex.match?(pattern, query)
      end)

    if matches > 0 do
      # Scale based on number of matches
      base_score = matches / length(uq.epistemic_patterns)
      # Boost to ensure detection is more sensitive
      min(base_score * 4.0, 1.0)
    else
      0.0
    end
  end

  @doc """
  Recommends an action based on uncertainty type.

  ## Examples

      UncertaintyQuantification.recommend_action(:aleatoric, 0.8)
      # => :provide_options

      UncertaintyQuantification.recommend_action(:epistemic, 0.7)
      # => :abstain

  """
  @spec recommend_action(UncertaintyResult.uncertainty_type(), float()) :: atom()
  def recommend_action(:aleatoric, _confidence) do
    # For aleatoric uncertainty, provide options or acknowledge subjectivity
    :provide_options
  end

  def recommend_action(:epistemic, confidence) when confidence >= 0.5 do
    # For high epistemic uncertainty, abstain
    :abstain
  end

  def recommend_action(:epistemic, _confidence) do
    # For lower epistemic uncertainty, suggest sources
    :suggest_source
  end

  def recommend_action(:none, _confidence) do
    :answer_directly
  end

  # Private functions

  defp extract_query(%Candidate{content: content}) when is_binary(content), do: content
  defp extract_query(%Candidate{reasoning: reasoning}) when is_binary(reasoning), do: reasoning
  defp extract_query(%Candidate{}), do: ""
  defp extract_query(query) when is_binary(query), do: query

  defp determine_uncertainty_type(aleatoric_score, epistemic_score, _query) do
    cond do
      # No significant uncertainty
      aleatoric_score < 0.3 and epistemic_score < 0.3 ->
        {:none, 1.0 - Kernel.max(aleatoric_score, epistemic_score), "Query appears factual and straightforward"}

      # Aleatoric dominates
      aleatoric_score > epistemic_score * 1.5 ->
        {:aleatoric, aleatoric_score, "Query contains subjective or ambiguous elements requiring interpretation"}

      # Epistemic dominates
      epistemic_score > aleatoric_score * 1.5 ->
        {:epistemic, epistemic_score, "Query requires knowledge that may not be available"}

      # Mixed uncertainty - default to aleatoric as it's more common
      true ->
        {:aleatoric, Kernel.max(aleatoric_score, epistemic_score), "Query has elements of inherent uncertainty"}
    end
  end

  defp validate_patterns(patterns) when is_list(patterns) do
    cond do
      length(patterns) > @max_patterns_count ->
        {:error, :too_many_patterns}

      not Enum.all?(patterns, &is_valid_regex/1) ->
        {:error, :invalid_patterns}

      Enum.any?(patterns, fn pattern ->
        pattern_size = :erlang.term_to_binary(pattern) |> byte_size()
        pattern_size > @max_pattern_length
      end) ->
        {:error, :pattern_too_long}

      true ->
        :ok
    end
  end

  defp validate_patterns(_), do: {:error, :invalid_patterns}

  defp is_valid_regex(%Regex{}), do: true
  defp is_valid_regex(_), do: false
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
