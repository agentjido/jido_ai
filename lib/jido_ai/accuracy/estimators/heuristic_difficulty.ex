defmodule Jido.AI.Accuracy.Estimators.HeuristicDifficulty do
  @moduledoc """
  Fast difficulty estimation using heuristics and rule-based analysis.

  This estimator analyzes query features to determine difficulty without
  requiring an LLM call, making it fast and cost-effective.

  ## Features Analyzed

  | Feature | Weight | Indicators |
  |---------|--------|------------|
  | Length | 0.25 | Character/word count |
  | Complexity | 0.30 | Long words, special characters, punctuation |
  | Domain | 0.25 | Math, code, reasoning indicators |
  | Question Type | 0.20 | Why/how vs what/when |

  ## Scoring

  Features are combined into a score [0.0 - 1.0]:
  - Score < 0.35 → Easy
  - Score 0.35 - 0.65 → Medium
  - Score > 0.65 → Hard

  ## Usage

      # Create estimator with default settings
      estimator = HeuristicDifficulty.new!(%{})

      # Estimate difficulty
      {:ok, estimate} = HeuristicDifficulty.estimate(estimator, "What is 2+2?", %{})
      # => %DifficultyEstimate{level: :easy, score: 0.15, ...}

      {:ok, estimate} = HeuristicDifficulty.estimate(
        estimator,
        "Explain the quantum mechanical principles behind entanglement",
        %{}
      )
      # => %DifficultyEstimate{level: :hard, score: 0.8, ...}

  ## Domain Detection

  The estimator detects the following domains:

  - **Math**: $\sum$, $\int$, equations, numbers, operations
  - **Code**: `function`, `class`, `def`, indentation-like patterns
  - **Reasoning**: "explain", "why", "how", "analyze", "compare"
  - **Creative**: "write", "create", "generate", "story"

  ## Configuration

  - `:length_weight` - Weight for query length feature (default: 0.25)
  - `:complexity_weight` - Weight for complexity feature (default: 0.30)
  - `:domain_weight` - Weight for domain feature (default: 0.25)
  - `:question_weight` - Weight for question type feature (default: 0.20)
  - `:custom_indicators` - Map of custom domain indicators

  ## Examples

      # Custom weights
      estimator = HeuristicDifficulty.new!(%{
        length_weight: 0.3,
        complexity_weight: 0.4
      })

      # Custom domain indicators
      estimator = HeuristicDifficulty.new!(%{
        custom_indicators: %{
          physics: ["quantum", "entanglement", "particle"]
        }
      })

  """

  @behaviour Jido.AI.Accuracy.DifficultyEstimator

  import Jido.AI.Accuracy.Helpers, only: [get_attr: 3]

  alias Jido.AI.Accuracy.DifficultyEstimate

  @type t :: %__MODULE__{
          length_weight: float(),
          complexity_weight: float(),
          domain_weight: float(),
          question_weight: float(),
          custom_indicators: map(),
          timeout: pos_integer()
        }

  # Default feature weights
  @default_length_weight 0.25
  @default_complexity_weight 0.30
  @default_domain_weight 0.25
  @default_question_weight 0.20

  # SECURITY: Maximum query length to prevent DoS
  @max_query_length 50_000

  # SECURITY: Default timeout for regex operations (5 seconds)
  @default_timeout 5000
  # SECURITY: Maximum allowed timeout (30 seconds)
  @max_timeout 30_000

  defstruct length_weight: @default_length_weight,
            complexity_weight: @default_complexity_weight,
            domain_weight: @default_domain_weight,
            question_weight: @default_question_weight,
            custom_indicators: %{},
            timeout: @default_timeout

  # Domain indicators
  @math_indicators [
    # Math symbols and operations
    "~",
    "sum",
    "integral",
    "derivative",
    "equation",
    "formula",
    "+",
    "-",
    "*",
    "/",
    "^",
    "=",
    "<",
    ">",
    "≤",
    "≥",
    # Math terms
    "calculate",
    "compute",
    "solve",
    "probability",
    "statistic",
    "algebra",
    "geometry",
    "trigonometry",
    "calculus"
  ]

  @code_indicators [
    # Programming keywords
    "function",
    "class",
    "def ",
    "import",
    "return",
    "if ",
    "else",
    "for ",
    "while",
    "const",
    "let",
    "var",
    "print",
    "array",
    # Code-like patterns
    "()",
    "{}",
    "[]",
    "=>",
    "==",
    "!=",
    "&&",
    "||",
    # Programming terms
    "algorithm",
    "data structure",
    "recursion",
    "iteration",
    "compile",
    "execute",
    "debug"
  ]

  @reasoning_indicators [
    "explain",
    "why",
    "how",
    "analyze",
    "compare",
    "contrast",
    "evaluate",
    "assess",
    "justify",
    "reasoning",
    "logic",
    "relationship",
    "difference",
    "similarity",
    "cause"
  ]

  @creative_indicators [
    "write",
    "create",
    "generate",
    "story",
    "poem",
    "creative",
    "imagine",
    "invent",
    "design",
    "compose",
    "narrative"
  ]

  @simple_question_words [
    "what",
    "when",
    "where",
    "who",
    "which",
    "is",
    "are",
    "do",
    "does",
    "list",
    "name",
    "identify",
    "define",
    "state"
  ]

  @doc """
  Creates a new HeuristicDifficulty estimator from the given attributes.

  ## Options

  - `:length_weight` - Weight for query length feature (default: 0.25)
  - `:complexity_weight` - Weight for complexity feature (default: 0.30)
  - `:domain_weight` - Weight for domain feature (default: 0.25)
  - `:question_weight` - Weight for question type feature (default: 0.20)
  - `:custom_indicators` - Map of custom domain indicators
  - `:timeout` - Timeout for regex operations in ms (default: 5000, max: 30000)

  ## Returns

  `{:ok, estimator}` on success, `{:error, reason}` on validation failure.

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    length_weight = get_attr(attrs, :length_weight, @default_length_weight)
    complexity_weight = get_attr(attrs, :complexity_weight, @default_complexity_weight)
    domain_weight = get_attr(attrs, :domain_weight, @default_domain_weight)
    question_weight = get_attr(attrs, :question_weight, @default_question_weight)
    custom_indicators = get_attr(attrs, :custom_indicators, %{})
    timeout = get_attr(attrs, :timeout, @default_timeout)

    with :ok <- validate_weights(length_weight, complexity_weight, domain_weight, question_weight),
         :ok <- validate_timeout(timeout) do
      estimator = %__MODULE__{
        length_weight: length_weight,
        complexity_weight: complexity_weight,
        domain_weight: domain_weight,
        question_weight: question_weight,
        custom_indicators: custom_indicators,
        timeout: timeout
      }

      {:ok, estimator}
    end
  end

  @doc """
  Creates a new HeuristicDifficulty estimator, raising on error.

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, estimator} -> estimator
      {:error, reason} -> raise ArgumentError, "Invalid HeuristicDifficulty: #{format_error(reason)}"
    end
  end

  @doc """
  Estimates difficulty for the given query using heuristic analysis.

  ## Parameters

  - `estimator` - The estimator struct
  - `query` - The query string to analyze
  - `context` - Additional context (not currently used)

  ## Returns

  - `{:ok, DifficultyEstimate.t()}` on success
  - `{:error, reason}` on failure
  - `{:error, :timeout}` if feature extraction exceeds timeout

  """
  @impl true
  @spec estimate(t(), String.t(), map()) :: {:ok, DifficultyEstimate.t()} | {:error, term()}
  def estimate(%__MODULE__{} = estimator, query, _context) when is_binary(query) do
    query = String.trim(query)

    cond do
      query == "" ->
        {:error, :invalid_query}

      byte_size(query) > @max_query_length ->
        {:error, :query_too_long}

      true ->
        # Wrap feature extraction in timeout-protected task
        task = Task.async(fn -> extract_features(query, estimator) end)

        case Task.yield(task, estimator.timeout) do
          {:ok, features} ->
            score = calculate_score(features, estimator)
            level = DifficultyEstimate.to_level(score)
            confidence = calculate_confidence(features, score)

            reasoning = generate_reasoning(features, score, level)

            estimate = %DifficultyEstimate{
              level: level,
              score: score,
              confidence: confidence,
              reasoning: reasoning,
              features: features,
              metadata: %{
                method: :heuristic,
                estimator: __MODULE__
              }
            }

            {:ok, estimate}

          {:exit, _reason} ->
            {:error, :feature_extraction_failed}

          nil ->
            # Timeout - kill the task
            Task.shutdown(task, :brutal_kill)
            {:error, :timeout}
        end
    end
  end

  def estimate(_estimator, _query, _context) do
    {:error, :invalid_query}
  end

  # Feature extraction

  defp extract_features(query, estimator) do
    %{
      length: extract_length_feature(query),
      complexity: extract_complexity_feature(query),
      domain: extract_domain_feature(query, estimator.custom_indicators),
      question_type: extract_question_type_feature(query)
    }
  end

  # Length feature: normalized by typical query lengths
  # Very short = easy, very long = hard
  defp extract_length_feature(query) do
    char_count = String.length(query)
    words = String.split(query)
    word_count = length(words)

    # Normalize: 0 for short queries (< 50 chars), 1 for very long (> 300 chars)
    length_score =
      cond do
        char_count < 50 -> 0.0
        char_count < 100 -> 0.2
        char_count < 200 -> 0.5
        char_count < 300 -> 0.7
        true -> 1.0
      end

    %{
      score: length_score,
      char_count: char_count,
      word_count: word_count
    }
  end

  # Complexity feature: average word length, special chars, punctuation density
  defp extract_complexity_feature(query) do
    words = String.split(query)
    _word_count = length(words)
    avg_word_len = calculate_avg_word_length(words)

    special_count = count_pattern(query, ~r/[^\w\s]/)
    number_count = count_pattern(query, ~r/\b\d+\b/)

    complexity_score = calculate_complexity_score(avg_word_len, special_count)

    %{
      score: complexity_score,
      avg_word_length: Float.round(avg_word_len, 2),
      special_char_count: special_count,
      number_count: number_count
    }
  end

  defp calculate_avg_word_length([]), do: 0

  defp calculate_avg_word_length(words) do
    total_chars = words |> Enum.map(&String.length/1) |> Enum.sum()
    total_chars / length(words)
  end

  defp count_pattern(text, pattern), do: Regex.scan(pattern, text) |> length()

  defp calculate_complexity_score(avg_word_len, special_count) do
    complexity_category(avg_word_len, special_count)
    |> score_for_category()
  end

  defp complexity_category(w, s) when w < 4 and s < 2, do: :very_low
  defp complexity_category(w, s) when w < 5 and s < 5, do: :low
  defp complexity_category(w, s) when w < 6 and s < 10, do: :medium
  defp complexity_category(w, s) when w < 7 or s < 15, do: :high
  defp complexity_category(_, _), do: :very_high

  defp score_for_category(:very_low), do: 0.0
  defp score_for_category(:low), do: 0.3
  defp score_for_category(:medium), do: 0.5
  defp score_for_category(:high), do: 0.7
  defp score_for_category(:very_high), do: 1.0

  # Domain feature: detect math, code, reasoning, creative domains
  defp extract_domain_feature(query, custom_indicators) do
    query_lower = String.downcase(query)

    # Check each domain
    math_score = count_indicators(query_lower, @math_indicators)
    code_score = count_indicators(query_lower, @code_indicators)
    reasoning_score = count_indicators(query_lower, @reasoning_indicators)
    creative_score = count_indicators(query_lower, @creative_indicators)

    # Check custom indicators
    custom_scores =
      Enum.map(custom_indicators, fn {domain, indicators} ->
        {domain, count_indicators(query_lower, indicators)}
      end)

    # Domain score: max of detected domains, normalized
    max_score =
      [math_score, code_score, reasoning_score, creative_score]
      |> Enum.max(fn -> 0 end)

    domain_score =
      cond do
        max_score >= 3 -> 1.0
        max_score >= 2 -> 0.7
        max_score >= 1 -> 0.4
        true -> 0.0
      end

    detected_domains = []
    detected_domains = if math_score > 0, do: [:math | detected_domains], else: detected_domains
    detected_domains = if code_score > 0, do: [:code | detected_domains], else: detected_domains
    detected_domains = if reasoning_score > 0, do: [:reasoning | detected_domains], else: detected_domains
    detected_domains = if creative_score > 0, do: [:creative | detected_domains], else: detected_domains

    %{
      score: domain_score,
      domains: Enum.reverse(detected_domains),
      custom: Map.new(custom_scores)
    }
  end

  # Question type feature: simple vs complex questions
  defp extract_question_type_feature(query) do
    query_lower = String.downcase(query)

    # Check for simple question words
    simple_count =
      @simple_question_words
      |> Enum.count(fn word -> String.contains?(query_lower, word) end)

    # Check for reasoning question words
    reasoning_count =
      @reasoning_indicators
      |> Enum.count(fn word -> String.contains?(query_lower, word) end)

    # Complex questions have reasoning indicators or are statements
    question_score =
      cond do
        reasoning_count >= 2 -> 1.0
        reasoning_count >= 1 -> 0.6
        simple_count >= 2 -> 0.2
        String.ends_with?(query, "?") -> 0.3
        true -> 0.5
      end

    %{
      score: question_score,
      has_question_mark: String.ends_with?(query, "?"),
      simple_indicator_count: simple_count,
      reasoning_indicator_count: reasoning_count
    }
  end

  defp count_indicators(query, indicators) do
    Enum.count(indicators, fn indicator ->
      String.contains?(query, indicator)
    end)
  end

  # Score calculation

  defp calculate_score(features, estimator) do
    length_score = features.length.score * estimator.length_weight
    complexity_score = features.complexity.score * estimator.complexity_weight
    domain_score = features.domain.score * estimator.domain_weight
    question_score = features.question_type.score * estimator.question_weight

    total_score = length_score + complexity_score + domain_score + question_score

    # Normalize to [0, 1]
    min(max(total_score, 0.0), 1.0)
  end

  # Confidence calculation based on feature agreement
  defp calculate_confidence(features, _score) do
    # High confidence when features agree (all low or all high)
    # Low confidence when features disagree (mixed signals)

    scores = [
      features.length.score,
      features.complexity.score,
      features.domain.score,
      features.question_type.score
    ]

    avg_score = Enum.sum(scores) / length(scores)

    # Variance from mean indicates disagreement
    variance =
      Enum.reduce(scores, 0.0, fn s, acc ->
        acc + :math.pow(s - avg_score, 2)
      end) / length(scores)

    # Low variance = high confidence
    confidence =
      cond do
        variance < 0.05 -> 0.95
        variance < 0.1 -> 0.85
        variance < 0.2 -> 0.7
        true -> 0.6
      end

    confidence
  end

  # Generate reasoning explanation

  defp generate_reasoning(features, _score, level) do
    base = build_reasoning_base(features)
    format_reasoning_by_level(base, level)
  end

  defp build_reasoning_base(features) do
    domain_part = describe_domain(features.domain.domains)
    length_part = describe_length(features.length.score)
    question_part = describe_question_type(features.question_type.score)

    "#{domain_part}, #{length_part}, #{question_part}"
  end

  defp describe_domain([]), do: "general domain"
  defp describe_domain(domains), do: "#{Enum.join(domains, "/")} domain"

  defp describe_length(score) when score < 0.3, do: "short query"
  defp describe_length(score) when score < 0.7, do: "medium-length query"
  defp describe_length(_score), do: "long query"

  defp describe_question_type(score) when score < 0.3, do: "simple question"
  defp describe_question_type(score) when score < 0.7, do: "moderate question"
  defp describe_question_type(_score), do: "complex question"

  defp format_reasoning_by_level(base, :easy), do: "Simple: #{base}"
  defp format_reasoning_by_level(base, :medium), do: "Moderate difficulty: #{base}"
  defp format_reasoning_by_level(base, :hard), do: "Complex: #{base} with multiple factors"

  # Validation

  defp validate_weights(lw, cw, dw, qw) do
    weights = [lw, cw, dw, qw]

    cond do
      not Enum.all?(weights, &is_number/1) ->
        {:error, :invalid_weights}

      not Enum.all?(weights, &(&1 >= 0.0 and &1 <= 1.0)) ->
        {:error, :invalid_weights}

      abs(Enum.sum(weights) - 1.0) > 0.01 ->
        {:error, :weights_dont_sum_to_1}

      true ->
        :ok
    end
  end

  defp validate_timeout(timeout) when is_integer(timeout) and timeout >= 1000 and timeout <= @max_timeout, do: :ok

  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp format_error(atom) when is_atom(atom), do: atom
end
