defmodule Jido.AI.Runner.GEPA.SuggestionGeneration.PromptStructureAnalyzer do
  @moduledoc """
  Analyzes prompt structure to identify sections, patterns, and organization.

  This module examines a prompt text to understand its structure, which
  informs where and how edits can be applied. Identifies:

  - Sections (instructions, constraints, examples, etc.)
  - Organizational patterns (lists, step-by-step triggers)
  - Complexity level
  - Key features (has examples, has constraints, etc.)

  ## Usage

      {:ok, structure} = PromptStructureAnalyzer.analyze("Solve this problem step by step")

      structure.has_cot_trigger  # => true
      structure.complexity       # => :simple
      structure.sections         # => [%{name: "instructions", ...}]
  """

  alias Jido.AI.Runner.GEPA.SuggestionGeneration.PromptStructure

  # Chain-of-thought trigger phrases
  @cot_triggers [
    "step by step",
    "think through",
    "reason about",
    "let's think",
    "work through",
    "break down",
    "analyze",
    "consider"
  ]

  # Constraint indicators
  @constraint_indicators [
    "must",
    "should",
    "required",
    "ensure",
    "make sure",
    "don't",
    "do not",
    "avoid",
    "always",
    "never"
  ]

  # Example indicators
  @example_indicators [
    "for example",
    "e.g.",
    "such as",
    "like this",
    "example:",
    "instance:"
  ]

  @doc """
  Analyzes a prompt to extract its structure.

  ## Parameters

  - `prompt` - The prompt text to analyze

  ## Returns

  - `{:ok, PromptStructure.t()}` - Analyzed structure
  - `{:error, reason}` - If analysis fails

  ## Examples

      {:ok, structure} = PromptStructureAnalyzer.analyze("Solve this step by step")
      structure.has_cot_trigger  # => true
  """
  @spec analyze(String.t()) :: {:ok, PromptStructure.t()} | {:error, term()}
  def analyze(prompt) when is_binary(prompt) do
    structure = %PromptStructure{
      raw_text: prompt,
      length: String.length(prompt),
      has_examples: has_examples?(prompt),
      has_constraints: has_constraints?(prompt),
      has_cot_trigger: has_cot_trigger?(prompt),
      complexity: assess_complexity(prompt),
      sections: identify_sections(prompt),
      patterns: identify_patterns(prompt)
    }

    {:ok, structure}
  end

  def analyze(_), do: {:error, :invalid_prompt}

  # Private functions

  defp has_examples?(prompt) do
    prompt_lower = String.downcase(prompt)
    Enum.any?(@example_indicators, &String.contains?(prompt_lower, &1))
  end

  defp has_constraints?(prompt) do
    prompt_lower = String.downcase(prompt)
    Enum.any?(@constraint_indicators, &String.contains?(prompt_lower, &1))
  end

  defp has_cot_trigger?(prompt) do
    prompt_lower = String.downcase(prompt)
    Enum.any?(@cot_triggers, &String.contains?(prompt_lower, &1))
  end

  defp assess_complexity(prompt) do
    length = String.length(prompt)
    sentence_count = count_sentences(prompt)
    has_sections = length(identify_sections(prompt)) > 1

    cond do
      length < 100 and sentence_count <= 2 -> :simple
      length > 500 or sentence_count > 10 or has_sections -> :complex
      true -> :moderate
    end
  end

  defp count_sentences(text) do
    text
    |> String.split(~r/[.!?]+/)
    |> Enum.reject(&(String.trim(&1) == ""))
    |> length()
  end

  defp identify_sections(prompt) do
    sections = []

    # Try to identify common section patterns
    sections = sections ++ identify_instruction_section(prompt)
    sections = sections ++ identify_constraint_section(prompt)
    sections = sections ++ identify_example_section(prompt)

    if sections == [] do
      # Default: treat entire prompt as single section
      [
        %{
          name: "main",
          start: 0,
          end: String.length(prompt),
          content: prompt
        }
      ]
    else
      sections
    end
  end

  defp identify_instruction_section(prompt) do
    # Look for instruction markers at the start
    if String.length(prompt) < 200 and
         not String.contains?(String.downcase(prompt), ["example:", "for example"]) do
      [
        %{
          name: "instructions",
          start: 0,
          end: String.length(prompt),
          content: prompt
        }
      ]
    else
      []
    end
  end

  defp identify_constraint_section(prompt) do
    # Look for constraint indicators
    if has_constraints?(prompt) do
      # Simple heuristic: constraints often come after main instruction
      parts = String.split(prompt, ~r/\n\n+/)

      if length(parts) > 1 do
        Enum.with_index(parts)
        |> Enum.filter(fn {part, _idx} ->
          String.downcase(part) |> String.contains?(["must", "should", "ensure"])
        end)
        |> Enum.map(fn {part, idx} ->
          # Calculate approximate position
          start = Enum.take(parts, idx) |> Enum.join("\n\n") |> String.length()

          %{
            name: "constraints",
            start: start,
            end: start + String.length(part),
            content: part
          }
        end)
      else
        []
      end
    else
      []
    end
  end

  defp identify_example_section(prompt) do
    if has_examples?(prompt) do
      # Find example markers
      example_regex = ~r/(for example|e\.g\.|example:|such as).*/i

      case Regex.run(example_regex, prompt, return: :index) do
        [{start, length} | _] ->
          [
            %{
              name: "examples",
              start: start,
              end: start + length,
              content: String.slice(prompt, start, length)
            }
          ]

        nil ->
          []
      end
    else
      []
    end
  end

  defp identify_patterns(prompt) do
    prompt_lower = String.downcase(prompt)

    %{
      has_numbered_list: Regex.match?(~r/\d+\./, prompt),
      has_bullet_list: Regex.match?(~r/[\-\*•]/, prompt),
      has_cot_trigger: has_cot_trigger?(prompt),
      has_imperative: String.contains?(prompt_lower, ["solve", "calculate", "determine", "find"]),
      has_question: String.contains?(prompt, "?"),
      multiline: String.contains?(prompt, "\n")
    }
  end
end
