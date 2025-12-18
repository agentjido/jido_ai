defmodule Jido.AI.Runner.ProgramOfThought.ProblemClassifier do
  @moduledoc """
  Classifies computational problems to determine if Program-of-Thought is appropriate.

  Analyzes problems to identify:
  - Computational components (math, calculations, data processing)
  - Domain classification (mathematical, financial, scientific)
  - Complexity estimation
  - Routing decisions (PoT vs regular CoT)

  ## Classification Criteria

  **Mathematical Domain**:
  - Arithmetic operations
  - Algebraic equations
  - Calculus and derivatives
  - Number theory

  **Financial Domain**:
  - Interest calculations
  - Investment returns
  - Currency conversions
  - Risk analysis

  **Scientific Domain**:
  - Unit conversions
  - Physics calculations
  - Statistical analysis
  - Data transformations

  ## Examples

      iex> ProblemClassifier.classify("What is 15% of 240?")
      {:ok, %{
        domain: :mathematical,
        computational: true,
        complexity: :low,
        confidence: 0.95,
        should_use_pot: true
      }}

      iex> ProblemClassifier.classify("Calculate compound interest on $5000")
      {:ok, %{
        domain: :financial,
        computational: true,
        complexity: :medium,
        confidence: 0.90,
        should_use_pot: true
      }}
  """

  require Logger

  # Domain keywords for classification
  @mathematical_keywords ~w(
    calculate compute solve equation formula
    sum product difference quotient
    multiply divide add subtract
    percentage fraction decimal
    square root power exponent
    derivative integral
  )

  @financial_keywords ~w(
    interest rate return investment
    profit loss revenue expense
    compound simple annual
    price cost value worth
    dollar euro currency exchange
    loan mortgage payment
  )

  @scientific_keywords ~w(
    velocity acceleration force mass
    energy temperature pressure volume
    density concentration
    conversion unit meter kilogram
    statistics average median mode
    probability distribution
  )

  @doc """
  Classifies a problem to determine domain and computational nature.

  Returns analysis with domain, complexity, and routing recommendation.
  """
  @spec classify(String.t()) :: {:ok, map()} | {:error, term()}
  def classify(problem) when is_binary(problem) do
    analysis = %{
      domain: detect_domain(problem),
      computational: computational?(problem),
      complexity: estimate_complexity(problem),
      confidence: calculate_confidence(problem),
      operations: detect_operations(problem),
      should_use_pot: false
    }

    # Determine if PoT should be used
    should_use_pot = should_route_to_pot?(analysis)
    final_analysis = Map.put(analysis, :should_use_pot, should_use_pot)

    Logger.debug("Problem classification: #{inspect(final_analysis)}")

    {:ok, final_analysis}
  end

  @doc """
  Analyzes a problem with a specified domain.

  Skips domain detection and uses the provided domain.
  """
  @spec analyze_with_domain(String.t(), atom()) :: {:ok, map()} | {:error, term()}
  def analyze_with_domain(problem, domain)
      when is_binary(problem) and is_atom(domain) do
    analysis = %{
      domain: domain,
      computational: computational?(problem),
      complexity: estimate_complexity(problem),
      confidence: 1.0,
      # User-specified domain
      operations: detect_operations(problem),
      should_use_pot: true
      # Trust user's domain choice
    }

    {:ok, analysis}
  end

  # Private functions

  defp detect_domain(problem) do
    problem_lower = String.downcase(problem)

    scores = %{
      mathematical: score_keywords(problem_lower, @mathematical_keywords),
      financial: score_keywords(problem_lower, @financial_keywords),
      scientific: score_keywords(problem_lower, @scientific_keywords)
    }

    # Get domain with highest score
    {domain, score} = Enum.max_by(scores, fn {_domain, score} -> score end)

    # If no strong domain match, default to mathematical for computational problems
    if score > 0 do
      domain
    else
      :mathematical
    end
  end

  defp score_keywords(text, keywords) do
    Enum.count(keywords, fn keyword ->
      String.contains?(text, keyword)
    end)
  end

  defp computational?(problem) do
    problem_lower = String.downcase(problem)

    # Check for computational indicators
    computational_indicators = [
      ~r/\d+/,
      # Numbers
      ~r/calculate|compute|solve|find/,
      # Action verbs
      ~r/[\+\-\*\/=]/,
      # Operators (math symbols)
      ~r/percent|%/,
      # Percentage
      ~r/\$/,
      # Currency
      ~r/how (much|many)/
      # Quantity questions
    ]

    Enum.any?(computational_indicators, fn regex ->
      Regex.match?(regex, problem_lower)
    end)
  end

  defp estimate_complexity(problem) do
    problem_lower = String.downcase(problem)

    # Count complexity indicators
    complexity_indicators = %{
      # Multiple steps needed
      multi_step:
        Enum.count(["and then", "after that", "next"], fn phrase ->
          String.contains?(problem_lower, phrase)
        end),
      # Number of numbers
      numbers: length(Regex.scan(~r/\d+/, problem)),
      # Complex operations
      complex_ops:
        Enum.count(["compound", "exponential", "logarithm", "derivative", "integral"], fn term ->
          String.contains?(problem_lower, term)
        end),
      # Word count
      length: String.split(problem) |> length()
    }

    # Calculate complexity score
    score =
      complexity_indicators.multi_step * 3 +
        complexity_indicators.complex_ops * 2 +
        (complexity_indicators.numbers - 1) +
        div(complexity_indicators.length, 10)

    cond do
      score <= 2 -> :low
      score <= 5 -> :medium
      true -> :high
    end
  end

  defp calculate_confidence(problem) do
    # Confidence based on clarity of computational intent
    indicators = %{
      has_numbers: Regex.match?(~r/\d+/, problem),
      has_math_verbs: Regex.match?(~r/calculate|compute|solve|find/, String.downcase(problem)),
      has_operators: Regex.match?(~r/[\+\-\*\/=]/, problem),
      has_units: Regex.match?(~r/\$|%|meter|kg|second/, problem)
    }

    # Count true indicators
    true_count = Enum.count(indicators, fn {_key, value} -> value end)

    # Convert to confidence score
    case true_count do
      4 -> 0.95
      3 -> 0.80
      2 -> 0.65
      1 -> 0.50
      0 -> 0.30
    end
  end

  defp detect_operations(problem) do
    problem_lower = String.downcase(problem)

    operations = []

    operations =
      if Regex.match?(~r/add|sum|plus|\+/, problem_lower) do
        [:addition | operations]
      else
        operations
      end

    operations =
      if Regex.match?(~r/subtract|minus|difference|\-/, problem_lower) do
        [:subtraction | operations]
      else
        operations
      end

    operations =
      if Regex.match?(~r/multiply|times|product|\*/, problem_lower) do
        [:multiplication | operations]
      else
        operations
      end

    operations =
      if Regex.match?(~r/divide|quotient|\//, problem_lower) do
        [:division | operations]
      else
        operations
      end

    operations =
      if Regex.match?(~r/percent|%/, problem_lower) do
        [:percentage | operations]
      else
        operations
      end

    operations =
      if Regex.match?(~r/power|exponent|\^|squared|cubed/, problem_lower) do
        [:exponentiation | operations]
      else
        operations
      end

    operations =
      if Regex.match?(~r/square root|sqrt/, problem_lower) do
        [:square_root | operations]
      else
        operations
      end

    operations =
      if Regex.match?(~r/average|mean/, problem_lower) do
        [:average | operations]
      else
        operations
      end

    Enum.reverse(operations)
  end

  defp should_route_to_pot?(analysis) do
    # Route to PoT if:
    # 1. Problem is computational
    # 2. Confidence is above threshold
    # 3. Complexity is not too high (high complexity might need hybrid approach)

    analysis.computational and
      analysis.confidence >= 0.5 and
      analysis.complexity in [:low, :medium]
  end
end
