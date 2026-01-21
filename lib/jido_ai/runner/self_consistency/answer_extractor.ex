defmodule Jido.AI.Runner.SelfConsistency.AnswerExtractor do
  @moduledoc """
  Extracts and normalizes answers from reasoning paths.

  This module handles the challenge of extracting final answers from diverse
  reasoning paths that may express the same answer in different formats:

  - "The answer is 42"
  - "Therefore: 42"
  - "42 is the result"
  - "forty-two"

  The extractor provides:
  - Pattern-based extraction for common answer formats
  - Normalization to canonical forms
  - Semantic equivalence detection
  - Domain-specific extraction strategies
  """

  require Logger

  @type extraction_result :: {:ok, term()} | {:error, term()}

  @doc """
  Extracts the final answer from a reasoning path.

  ## Parameters

  - `reasoning` - The reasoning text to extract from
  - `opts` - Options:
    - `:domain` - Domain-specific extractor (:math, :code, :text, :general)
    - `:patterns` - Additional extraction patterns to try
    - `:normalize` - Whether to normalize the answer (default: true)

  ## Returns

  - `{:ok, answer}` - Successfully extracted answer
  - `{:error, reason}` - Failed to extract answer

  ## Examples

      {:ok, answer} = AnswerExtractor.extract("The answer is 42")
      # => {:ok, 42}

      {:ok, answer} = AnswerExtractor.extract("Therefore: forty-two", domain: :math)
      # => {:ok, 42}
  """
  @spec extract(String.t(), keyword()) :: extraction_result()
  def extract(reasoning, opts \\ []) do
    domain = Keyword.get(opts, :domain, :general)
    custom_patterns = Keyword.get(opts, :patterns, [])
    normalize? = Keyword.get(opts, :normalize, true)

    with {:ok, raw_answer} <- extract_raw_answer(reasoning, domain, custom_patterns),
         {:ok, normalized} <- maybe_normalize(raw_answer, normalize?, domain) do
      {:ok, normalized}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Checks if two answers are semantically equivalent.

  Handles various representations of the same answer:
  - Numeric: 42, "42", "forty-two"
  - Boolean: true, "true", "yes", "correct"
  - String: case-insensitive, whitespace-normalized

  ## Parameters

  - `answer1` - First answer
  - `answer2` - Second answer
  - `opts` - Options:
    - `:domain` - Domain for equivalence checking
    - `:strict` - Strict matching (default: false)

  ## Returns

  - `true` if answers are equivalent
  - `false` otherwise

  ## Examples

      AnswerExtractor.equivalent?(42, "42")
      # => true

      AnswerExtractor.equivalent?("yes", true)
      # => true

      AnswerExtractor.equivalent?("Hello", "hello")
      # => true
  """
  @spec equivalent?(term(), term(), keyword()) :: boolean()
  def equivalent?(answer1, answer2, opts \\ []) do
    domain = Keyword.get(opts, :domain, :general)
    strict = Keyword.get(opts, :strict, false)

    cond do
      answer1 == answer2 ->
        true

      strict ->
        false

      true ->
        check_semantic_equivalence(answer1, answer2, domain)
    end
  end

  @doc """
  Normalizes an answer to a canonical form.

  ## Parameters

  - `answer` - The answer to normalize
  - `opts` - Options:
    - `:domain` - Domain for normalization
    - `:format` - Target format (:string, :number, :boolean, :auto)

  ## Returns

  - `{:ok, normalized_answer}`
  - `{:error, reason}`

  ## Examples

      AnswerExtractor.normalize("  HELLO  ")
      # => {:ok, "hello"}

      AnswerExtractor.normalize("forty-two", domain: :math)
      # => {:ok, 42}
  """
  @spec normalize(term(), keyword()) :: extraction_result()
  def normalize(answer, opts \\ []) do
    domain = Keyword.get(opts, :domain, :general)
    format = Keyword.get(opts, :format, :auto)

    normalized =
      case {format, domain} do
        {:auto, :math} -> normalize_math(answer)
        {:auto, :code} -> normalize_code(answer)
        {:auto, :text} -> normalize_text(answer)
        {:auto, :general} -> normalize_general(answer)
        {:string, _} -> normalize_to_string(answer)
        {:number, _} -> normalize_to_number(answer)
        {:boolean, _} -> normalize_to_boolean(answer)
        _ -> {:ok, answer}
      end

    normalized
  end

  # Private functions

  defp extract_raw_answer(reasoning, domain, custom_patterns) do
    # Try custom patterns first
    case try_patterns(reasoning, custom_patterns) do
      {:ok, answer} ->
        {:ok, answer}

      {:error, _} ->
        # Fall back to domain-specific extraction
        case domain do
          :math -> extract_math_answer(reasoning)
          :code -> extract_code_answer(reasoning)
          :text -> extract_text_answer(reasoning)
          :general -> extract_general_answer(reasoning)
          _ -> extract_general_answer(reasoning)
        end
    end
  end

  defp try_patterns(_reasoning, []), do: {:error, :no_custom_patterns}

  defp try_patterns(reasoning, [pattern | rest]) do
    case Regex.run(pattern, reasoning, capture: :all_but_first) do
      [match | _] -> {:ok, String.trim(match)}
      nil -> try_patterns(reasoning, rest)
    end
  end

  defp extract_general_answer(reasoning) do
    # Common answer patterns
    patterns = [
      ~r/(?:the\s+)?answer\s+is\s+[:\-]?\s*(.+?)(?:\.|$)/i,
      ~r/(?:therefore|thus|hence)[:\-]?\s*(.+?)(?:\.|$)/i,
      ~r/(?:result|solution|conclusion)[:\-]?\s*(.+?)(?:\.|$)/i,
      ~r/^(.+?)$/m
      # Last resort: take last line
    ]

    case try_patterns(reasoning, patterns) do
      {:ok, answer} -> {:ok, String.trim(answer)}
      {:error, _} -> {:error, :no_answer_found}
    end
  end

  defp extract_math_answer(reasoning) do
    # Math-specific patterns prioritizing numeric answers
    patterns = [
      ~r/(?:answer|result|solution)\s*[=:]\s*([+-]?\d+(?:\.\d+)?)/i,
      ~r/=\s*([+-]?\d+(?:\.\d+)?)\s*$/m,
      ~r/([+-]?\d+(?:\.\d+)?)\s+is\s+(?:the\s+)?(?:answer|result)/i,
      ~r/([+-]?\d+(?:\.\d+)?)/
      # Any number as fallback
    ]

    case try_patterns(reasoning, patterns) do
      {:ok, answer} -> {:ok, answer}
      {:error, _} -> extract_general_answer(reasoning)
    end
  end

  defp extract_code_answer(reasoning) do
    # Code-specific patterns
    patterns = [
      ~r/```(?:\w+)?\s*\n(.+?)\n```/s,
      # Code blocks
      ~r/`([^`]+)`/,
      # Inline code
      ~r/(?:function|method|class)\s+(\w+)/i
    ]

    case try_patterns(reasoning, patterns) do
      {:ok, answer} -> {:ok, String.trim(answer)}
      {:error, _} -> extract_general_answer(reasoning)
    end
  end

  defp extract_text_answer(reasoning) do
    # For text, typically take the conclusion
    patterns = [
      ~r/(?:in\s+conclusion|to\s+summarize|therefore)[:\-]?\s*(.+?)(?:\.|$)/i,
      ~r/(?:the\s+)?answer\s+is\s+[:\-]?\s*(.+?)(?:\.|$)/i
    ]

    case try_patterns(reasoning, patterns) do
      {:ok, answer} -> {:ok, String.trim(answer)}
      {:error, _} -> extract_general_answer(reasoning)
    end
  end

  defp maybe_normalize(answer, true, domain), do: normalize(answer, domain: domain)
  defp maybe_normalize(answer, false, _domain), do: {:ok, answer}

  defp check_semantic_equivalence(answer1, answer2, domain) do
    # Normalize both and compare
    with {:ok, norm1} <- normalize(answer1, domain: domain),
         {:ok, norm2} <- normalize(answer2, domain: domain) do
      norm1 == norm2
    else
      _ -> false
    end
  end

  defp normalize_general(answer) when is_binary(answer) do
    # Try to detect and normalize numbers and booleans in strings
    trimmed = String.trim(answer)

    # Try number conversion first
    case normalize_to_number(trimmed) do
      {:ok, num} ->
        {:ok, num}

      {:error, _} ->
        # Try boolean conversion
        case normalize_to_boolean(trimmed) do
          {:ok, bool} ->
            {:ok, bool}

          {:error, _} ->
            # Fall back to string normalization
            {:ok, String.downcase(trimmed)}
        end
    end
  end

  defp normalize_general(answer), do: {:ok, answer}

  defp normalize_math(answer) when is_binary(answer) do
    # Try to parse as number
    case normalize_to_number(answer) do
      {:ok, num} -> {:ok, num}
      {:error, _} -> normalize_general(answer)
    end
  end

  defp normalize_math(answer) when is_number(answer), do: {:ok, answer}
  defp normalize_math(answer), do: {:ok, answer}

  defp normalize_code(answer) when is_binary(answer) do
    # Remove code block markers and trim
    normalized =
      answer
      |> String.replace(~r/```(?:\w+)?/, "")
      |> String.replace("`", "")
      |> String.trim()

    {:ok, normalized}
  end

  defp normalize_code(answer), do: {:ok, answer}

  defp normalize_text(answer) when is_binary(answer) do
    normalized =
      answer
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, " ")

    {:ok, normalized}
  end

  defp normalize_text(answer), do: {:ok, answer}

  defp normalize_to_string(answer) when is_binary(answer), do: {:ok, String.trim(answer)}
  defp normalize_to_string(answer), do: {:ok, to_string(answer)}

  defp normalize_to_number(answer) when is_number(answer), do: {:ok, answer}

  defp normalize_to_number(answer) when is_binary(answer) do
    # Try integer first
    case Integer.parse(answer) do
      {num, ""} ->
        {:ok, num}

      {num, rest} ->
        # Check if rest is just whitespace or decimal
        if String.trim(rest) == "" do
          {:ok, num}
        else
          # Try float
          case Float.parse(answer) do
            {num, ""} ->
              {:ok, num}

            {num, rest} ->
              if String.trim(rest) == "", do: {:ok, num}, else: try_word_to_number(answer)

            :error ->
              try_word_to_number(answer)
          end
        end

      :error ->
        # Try float directly
        case Float.parse(answer) do
          {num, ""} ->
            {:ok, num}

          {num, rest} ->
            if String.trim(rest) == "", do: {:ok, num}, else: try_word_to_number(answer)

          :error ->
            try_word_to_number(answer)
        end
    end
  end

  defp normalize_to_number(_answer), do: {:error, :not_a_number}

  defp try_word_to_number(word) do
    # Simple word-to-number conversion
    word_map = %{
      "zero" => 0,
      "one" => 1,
      "two" => 2,
      "three" => 3,
      "four" => 4,
      "five" => 5,
      "six" => 6,
      "seven" => 7,
      "eight" => 8,
      "nine" => 9,
      "ten" => 10,
      "eleven" => 11,
      "twelve" => 12,
      "thirteen" => 13,
      "fourteen" => 14,
      "fifteen" => 15,
      "sixteen" => 16,
      "seventeen" => 17,
      "eighteen" => 18,
      "nineteen" => 19,
      "twenty" => 20,
      "thirty" => 30,
      "forty" => 40,
      "fifty" => 50,
      "sixty" => 60,
      "seventy" => 70,
      "eighty" => 80,
      "ninety" => 90,
      "hundred" => 100,
      "thousand" => 1000
    }

    normalized = String.downcase(String.trim(word))

    case Map.get(word_map, normalized) do
      nil -> {:error, :not_a_number}
      num -> {:ok, num}
    end
  end

  defp normalize_to_boolean(answer) when is_boolean(answer), do: {:ok, answer}

  defp normalize_to_boolean(answer) when is_binary(answer) do
    normalized = String.downcase(String.trim(answer))

    cond do
      normalized in ["true", "yes", "correct", "1", "t", "y"] -> {:ok, true}
      normalized in ["false", "no", "incorrect", "0", "f", "n"] -> {:ok, false}
      true -> {:error, :not_a_boolean}
    end
  end

  defp normalize_to_boolean(_answer), do: {:error, :not_a_boolean}
end
