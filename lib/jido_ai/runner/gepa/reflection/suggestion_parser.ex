defmodule Jido.AI.Runner.GEPA.Reflection.SuggestionParser do
  @moduledoc """
  Parses LLM reflection responses into structured suggestions (Task 1.3.2.3).

  This module extracts actionable insights from LLM responses, handling both
  JSON and natural language formats. It validates suggestions, categorizes them,
  and ensures they're actionable for mutation operators.

  ## Features

  - JSON response parsing with schema validation
  - Fallback natural language parsing
  - Suggestion validation and sanitization
  - Confidence scoring based on response quality
  - Clarification need detection

  ## Usage

      response = %ReflectionResponse{content: json_string, format: :json}
      {:ok, parsed} = SuggestionParser.parse(response)

      parsed.suggestions
      |> Enum.filter(&(&1.priority == :high))
      |> Enum.each(&apply_suggestion/1)
  """

  require Logger
  alias Jido.AI.Runner.GEPA.Reflector

  @doc """
  Parses a reflection response into structured format.

  Attempts JSON parsing first, falls back to natural language extraction
  if JSON parsing fails. Validates and sanitizes all extracted suggestions.

  ## Parameters

  - `response` - `ReflectionResponse` from LLM
  - `opts` - Options:
    - `:strict` - Fail if response doesn't match expected format (default: false)
    - `:min_suggestions` - Minimum suggestions required (default: 1)

  ## Returns

  - `{:ok, ParsedReflection.t()}` - Successfully parsed reflection
  - `{:error, reason}` - If parsing fails

  ## Examples

      {:ok, parsed} = SuggestionParser.parse(response)
      high_priority = Enum.filter(parsed.suggestions, &(&1.priority == :high))
  """
  @spec parse(Reflector.ReflectionResponse.t(), keyword()) ::
          {:ok, Reflector.ParsedReflection.t()} | {:error, term()}
  def parse(%Reflector.ReflectionResponse{} = response, opts \\ []) do
    case response.format do
      :json -> parse_json_response(response, opts)
      :text -> parse_text_response(response, opts)
    end
  end

  @doc """
  Validates a parsed reflection meets quality standards.

  Checks that suggestions are actionable, properly categorized, and
  sufficient in number.

  ## Parameters

  - `parsed` - `ParsedReflection` to validate

  ## Returns

  - `{:ok, ParsedReflection.t()}` - If validation passes
  - `{:error, reason}` - If validation fails

  ## Examples

      {:ok, validated} = SuggestionParser.validate(parsed)
  """
  @spec validate(Reflector.ParsedReflection.t()) ::
          {:ok, Reflector.ParsedReflection.t()} | {:error, term()}
  def validate(%Reflector.ParsedReflection{} = parsed) do
    cond do
      parsed.analysis == "" ->
        {:error, :missing_analysis}

      Enum.empty?(parsed.suggestions) ->
        {:error, :no_suggestions}

      not all_suggestions_valid?(parsed.suggestions) ->
        {:error, :invalid_suggestions}

      true ->
        {:ok, parsed}
    end
  end

  @doc """
  Scores a parsed reflection's quality and completeness.

  Returns a confidence level based on:
  - Number and quality of suggestions
  - Presence of rationale and specific text
  - Analysis clarity
  - Root cause identification

  ## Parameters

  - `parsed` - `ParsedReflection` to score

  ## Returns

  `:high | :medium | :low` confidence level

  ## Examples

      confidence = SuggestionParser.score_confidence(parsed)
  """
  @spec score_confidence(Reflector.ParsedReflection.t()) :: Reflector.confidence()
  def score_confidence(%Reflector.ParsedReflection{} = parsed) do
    score = calculate_confidence_score(parsed)

    cond do
      score >= 0.75 -> :high
      score >= 0.45 -> :medium
      true -> :low
    end
  end

  @doc """
  Determines if clarification is needed based on response quality.

  Returns true if:
  - Confidence is low
  - Suggestions are vague or generic
  - Analysis lacks specificity
  - Root causes unclear

  ## Parameters

  - `parsed` - `ParsedReflection` to check

  ## Returns

  Boolean indicating if clarification needed.

  ## Examples

      if SuggestionParser.needs_clarification?(parsed) do
        # Ask follow-up questions
      end
  """
  @spec needs_clarification?(Reflector.ParsedReflection.t()) :: boolean()
  def needs_clarification?(%Reflector.ParsedReflection{} = parsed) do
    parsed.confidence == :low or
      length(parsed.root_causes) < 2 or
      suggestions_too_generic?(parsed.suggestions)
  end

  # Private functions

  defp parse_json_response(response, opts) do
    case Jason.decode(response.content) do
      {:ok, data} ->
        build_parsed_reflection(data, opts)

      {:error, reason} ->
        Logger.warning("JSON parsing failed, attempting text fallback", reason: reason)

        if opts[:strict] do
          {:error, {:json_parse_error, reason}}
        else
          parse_text_response(response, opts)
        end
    end
  end

  defp parse_text_response(response, opts) do
    # Extract structured information from natural language response
    parsed = %Reflector.ParsedReflection{
      analysis: extract_analysis(response.content),
      root_causes: extract_root_causes(response.content),
      suggestions: extract_suggestions_from_text(response.content),
      expected_improvement: extract_expected_improvement(response.content),
      confidence: :low,
      # Natural language fallback has lower confidence
      needs_clarification: true
    }

    min_suggestions = opts[:min_suggestions] || 1

    if length(parsed.suggestions) >= min_suggestions do
      scored = %{parsed | confidence: score_confidence(parsed)}
      {:ok, scored}
    else
      {:error, :insufficient_suggestions}
    end
  end

  defp build_parsed_reflection(data, _opts) do
    suggestions = parse_suggestions(data["suggestions"] || [])

    parsed = %Reflector.ParsedReflection{
      analysis: data["analysis"] || "",
      root_causes: data["root_causes"] || [],
      suggestions: suggestions,
      expected_improvement: data["expected_improvement"] || "",
      confidence: :medium,
      # Will be scored
      needs_clarification: false,
      metadata: %{
        raw_data: data
      }
    }

    # Score confidence based on parsed content
    scored = %{parsed | confidence: score_confidence(parsed)}
    needs_clarification = needs_clarification?(scored)
    final = %{scored | needs_clarification: needs_clarification}

    {:ok, final}
  end

  defp parse_suggestions(suggestions_data) when is_list(suggestions_data) do
    suggestions_data
    |> Enum.map(&parse_suggestion/1)
    |> Enum.filter(&(&1 != nil))
  end

  defp parse_suggestion(data) when is_map(data) do
    with {:ok, type} <- parse_suggestion_type(data["type"]),
         {:ok, category} <- parse_suggestion_category(data["category"]),
         {:ok, priority} <- parse_priority(data["priority"]) do
      %Reflector.Suggestion{
        type: type,
        category: category,
        description: data["description"] || "",
        rationale: data["rationale"] || "",
        priority: priority,
        specific_text: data["specific_text"],
        target_section: data["target_section"]
      }
    else
      _ ->
        Logger.debug("Failed to parse suggestion (data: #{inspect(data)})")
        nil
    end
  end

  defp parse_suggestion(data) when is_binary(data) do
    # Try to extract from string description
    %Reflector.Suggestion{
      type: :modify,
      category: :clarity,
      description: data,
      rationale: "Extracted from text response",
      priority: :medium,
      specific_text: nil,
      target_section: nil
    }
  end

  defp parse_suggestion(_), do: nil

  defp parse_suggestion_type(type) when is_binary(type) do
    case String.downcase(type) do
      "add" -> {:ok, :add}
      "modify" -> {:ok, :modify}
      "remove" -> {:ok, :remove}
      "restructure" -> {:ok, :restructure}
      _ -> {:error, :invalid_type}
    end
  end

  defp parse_suggestion_type(_), do: {:error, :invalid_type}

  defp parse_suggestion_category(category) when is_binary(category) do
    case String.downcase(category) do
      "clarity" -> {:ok, :clarity}
      "constraint" -> {:ok, :constraint}
      "example" -> {:ok, :example}
      "structure" -> {:ok, :structure}
      "reasoning" -> {:ok, :reasoning}
      _ -> {:error, :invalid_category}
    end
  end

  defp parse_suggestion_category(_), do: {:error, :invalid_category}

  defp parse_priority(priority) when is_binary(priority) do
    case String.downcase(priority) do
      "high" -> {:ok, :high}
      "medium" -> {:ok, :medium}
      "low" -> {:ok, :low}
      _ -> {:error, :invalid_priority}
    end
  end

  defp parse_priority(_), do: {:error, :invalid_priority}

  # Text extraction fallbacks

  defp extract_analysis(text) do
    # Extract first paragraph or up to 500 characters
    text
    |> String.split("\n\n")
    |> List.first()
    |> then(&String.slice(&1 || "", 0..500))
  end

  defp extract_root_causes(text) do
    # Look for bulleted lists or numbered lists mentioning causes
    text
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, ["cause", "issue", "problem", "failure"]))
    |> Enum.take(3)
    |> Enum.map(&String.trim/1)
  end

  defp extract_suggestions_from_text(text) do
    # Extract sentences that look like suggestions
    text
    |> String.split(~r/[.!?]+/)
    |> Enum.filter(&suggestion_like?/1)
    |> Enum.take(5)
    |> Enum.map(&text_to_suggestion/1)
  end

  defp extract_expected_improvement(text) do
    # Extract last paragraph or sentences mentioning improvement
    text
    |> String.split("\n\n")
    |> Enum.reverse()
    |> Enum.find("", &String.contains?(&1, ["improve", "better", "should", "will"]))
    |> String.slice(0..300)
  end

  defp suggestion_like?(sentence) do
    keywords = ["should", "add", "remove", "change", "modify", "include", "clarify", "specify"]
    String.contains?(String.downcase(sentence), keywords)
  end

  defp text_to_suggestion(text) do
    %Reflector.Suggestion{
      type: infer_type(text),
      category: infer_category(text),
      description: String.trim(text),
      rationale: "Extracted from text response",
      priority: :medium,
      specific_text: nil,
      target_section: nil
    }
  end

  defp infer_type(text) do
    cond do
      String.contains?(text, ["add", "include"]) -> :add
      String.contains?(text, ["remove", "delete"]) -> :remove
      String.contains?(text, ["restructure", "reorganize"]) -> :restructure
      true -> :modify
    end
  end

  defp infer_category(text) do
    cond do
      String.contains?(text, ["clear", "clarify", "specific"]) -> :clarity
      String.contains?(text, ["constraint", "limit", "boundary"]) -> :constraint
      String.contains?(text, ["example", "instance", "case"]) -> :example
      String.contains?(text, ["reason", "logic", "think"]) -> :reasoning
      true -> :structure
    end
  end

  # Validation

  defp all_suggestions_valid?(suggestions) do
    Enum.all?(suggestions, &suggestion_valid?/1)
  end

  defp suggestion_valid?(%Reflector.Suggestion{} = suggestion) do
    suggestion.description != "" and
      suggestion.rationale != ""
  end

  defp suggestions_too_generic?(suggestions) do
    generic_count =
      Enum.count(suggestions, fn s ->
        word_count = String.split(s.description) |> length()
        word_count < 5 or is_nil(s.specific_text)
      end)

    generic_count / max(length(suggestions), 1) > 0.6
  end

  # Confidence scoring

  defp calculate_confidence_score(parsed) do
    suggestion_score = min(length(parsed.suggestions) / 5, 1.0) * 0.3

    specificity_score =
      parsed.suggestions
      |> Enum.count(&(not is_nil(&1.specific_text)))
      |> then(&(&1 / max(length(parsed.suggestions), 1)))
      |> Kernel.*(0.25)

    high_priority_score =
      parsed.suggestions
      |> Enum.count(&(&1.priority == :high))
      |> then(&(&1 / max(length(parsed.suggestions), 1)))
      |> Kernel.*(0.20)

    analysis_score = if String.length(parsed.analysis) > 50, do: 0.15, else: 0.05

    root_cause_score = min(length(parsed.root_causes) / 3, 1.0) * 0.10

    suggestion_score + specificity_score + high_priority_score + analysis_score + root_cause_score
  end
end
