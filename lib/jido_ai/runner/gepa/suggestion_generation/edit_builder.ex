defmodule Jido.AI.Runner.GEPA.SuggestionGeneration.EditBuilder do
  @moduledoc """
  Converts abstract LLM suggestions into concrete edit operations.

  Takes a Suggestion from the Reflector (Task 1.3.2) and generates specific
  PromptEdit operations with exact text and locations that can be applied
  by mutation operators.

  ## Strategy

  - **Add suggestions**: Generate insertion edits with content and location
  - **Modify suggestions**: Generate replacement edits identifying target text
  - **Remove suggestions**: Generate deletion edits identifying what to remove
  - **Restructure suggestions**: Generate multiple coordinated edits

  ## Usage

      {:ok, edits} = EditBuilder.build_edits(suggestion, prompt_structure)

      Enum.each(edits, fn e ->
        IO.puts("\#{e.operation} at \#{inspect(e.location)}")
      end)
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Reflector.Suggestion
  alias Jido.AI.Runner.GEPA.SuggestionGeneration.{PromptEdit, PromptLocation, PromptStructure}

  @doc """
  Builds concrete edits from an abstract suggestion.

  ## Parameters

  - `suggestion` - Abstract suggestion from LLM reflection
  - `prompt_structure` - Analyzed prompt structure
  - `opts` - Options:
    - `:max_edits_per_suggestion` - Limit edits generated (default: 3)
    - `:fallback_to_append` - Append if location unclear (default: true)

  ## Returns

  - `{:ok, [PromptEdit.t()]}` - List of concrete edits
  - `{:error, reason}` - If edit generation fails

  ## Examples

      suggestion = %Suggestion{
        type: :add,
        category: :clarity,
        description: "Add step-by-step instruction",
        specific_text: "Let's solve this step by step:",
        priority: :high
      }

      {:ok, edits} = EditBuilder.build_edits(suggestion, structure)
  """
  @spec build_edits(Suggestion.t(), PromptStructure.t(), keyword()) ::
          {:ok, list(PromptEdit.t())} | {:error, term()}
  def build_edits(%Suggestion{} = suggestion, %PromptStructure{} = structure, opts \\ []) do
    Logger.debug(
      "Building edits for suggestion (type: #{suggestion.type}, category: #{suggestion.category})"
    )

    case suggestion.type do
      :add -> build_addition_edits(suggestion, structure, opts)
      :modify -> build_modification_edits(suggestion, structure, opts)
      :remove -> build_deletion_edits(suggestion, structure, opts)
      :restructure -> build_restructure_edits(suggestion, structure, opts)
    end
  end

  # Private functions

  defp build_addition_edits(suggestion, structure, opts) do
    location = determine_addition_location(suggestion, structure, opts)
    content = get_addition_content(suggestion, structure)

    if content && String.trim(content) != "" do
      edit = %PromptEdit{
        id: generate_edit_id(),
        operation: :insert,
        location: location,
        content: content,
        source_suggestion: suggestion,
        rationale: suggestion.rationale,
        priority: suggestion.priority,
        metadata: %{
          category: suggestion.category,
          target_section: suggestion.target_section
        }
      }

      {:ok, [edit]}
    else
      {:error, :no_content_generated}
    end
  end

  defp build_modification_edits(suggestion, structure, opts) do
    # Try to identify what text to modify
    target_text = identify_modification_target(suggestion, structure)

    if target_text do
      replacement = get_replacement_content(suggestion, structure, target_text)

      edit = %PromptEdit{
        id: generate_edit_id(),
        operation: :replace,
        location: %PromptLocation{
          type: :within,
          pattern: target_text,
          scope: :phrase
        },
        content: replacement,
        target_text: target_text,
        source_suggestion: suggestion,
        rationale: suggestion.rationale,
        priority: suggestion.priority
      }

      {:ok, [edit]}
    else
      # Fallback: convert to addition if we can't identify target
      Logger.debug("Could not identify modification target, falling back to addition")
      build_addition_edits(suggestion, structure, opts)
    end
  end

  defp build_deletion_edits(suggestion, structure, _opts) do
    target_text = identify_deletion_target(suggestion, structure)

    if target_text do
      edit = %PromptEdit{
        id: generate_edit_id(),
        operation: :delete,
        location: %PromptLocation{
          type: :within,
          pattern: target_text,
          scope: :phrase
        },
        content: nil,
        target_text: target_text,
        source_suggestion: suggestion,
        rationale: suggestion.rationale,
        priority: suggestion.priority
      }

      {:ok, [edit]}
    else
      {:error, :cannot_identify_deletion_target}
    end
  end

  defp build_restructure_edits(suggestion, structure, opts) do
    # Restructure is complex - for now, treat as multiple modifications
    # In a full implementation, this would analyze the prompt and generate
    # coordinated edits to reorganize sections
    Logger.debug("Restructure suggestions not fully implemented, treating as modification")
    build_modification_edits(suggestion, structure, opts)
  end

  defp determine_addition_location(suggestion, structure, _opts) do
    cond do
      # If target_section specified, try to add there
      suggestion.target_section && suggestion.target_section != "" ->
        find_section_location(suggestion.target_section, structure)

      # If adding constraints, add after main instructions
      suggestion.category == :constraint ->
        %PromptLocation{type: :end, scope: :prompt}

      # If adding examples, add at end
      suggestion.category == :example ->
        %PromptLocation{type: :end, scope: :prompt}

      # Default: append to end
      true ->
        %PromptLocation{type: :end, scope: :prompt}
    end
  end

  defp find_section_location(section_name, structure) do
    section =
      Enum.find(structure.sections, fn s ->
        String.downcase(s.name) == String.downcase(section_name)
      end)

    if section do
      %PromptLocation{
        type: :within,
        section_name: section.name,
        absolute_position: section.start,
        scope: :section
      }
    else
      # Fallback to end if section not found
      %PromptLocation{type: :end, scope: :prompt}
    end
  end

  defp get_addition_content(suggestion, _structure) do
    cond do
      # If LLM provided specific text, use it
      suggestion.specific_text && String.trim(suggestion.specific_text) != "" ->
        ensure_proper_spacing(suggestion.specific_text)

      # Generate from description for common patterns
      suggestion.category == :clarity && String.contains?(suggestion.description, "step") ->
        "\n\nLet's approach this step by step."

      suggestion.category == :constraint ->
        generate_constraint_text(suggestion.description)

      suggestion.category == :example ->
        "\n\nFor example: #{suggestion.description}"

      # Fallback: use description as-is
      true ->
        "\n\n#{suggestion.description}"
    end
  end

  defp generate_constraint_text(description) do
    # Extract constraint from description
    desc_lower = String.downcase(description)

    cond do
      String.contains?(desc_lower, "show") ->
        "\n\nIMPORTANT: Show all your work and intermediate steps."

      String.contains?(desc_lower, "format") ->
        "\n\nIMPORTANT: Format your response clearly and consistently."

      String.contains?(desc_lower, "explain") ->
        "\n\nIMPORTANT: Explain your reasoning at each step."

      true ->
        "\n\nIMPORTANT: #{description}"
    end
  end

  defp ensure_proper_spacing(text) do
    # Ensure text starts with newline if adding to prompt
    if String.starts_with?(text, "\n") do
      text
    else
      "\n\n#{text}"
    end
  end

  defp identify_modification_target(suggestion, structure) do
    cond do
      # If specific text provided, use it as target
      suggestion.specific_text && String.trim(suggestion.specific_text) != "" ->
        suggestion.specific_text

      # Try to extract from description
      suggestion.description =~ ~r/modify ["'](.+?)["']/i ->
        case Regex.run(~r/modify ["'](.+?)["']/i, suggestion.description) do
          [_, target] -> target
          _ -> nil
        end

      # Look for phrases in prompt that match description keywords
      true ->
        find_phrase_matching_description(suggestion.description, structure.raw_text)
    end
  end

  defp find_phrase_matching_description(description, prompt_text) do
    # Extract key words from description
    keywords =
      description
      |> String.downcase()
      |> String.split()
      |> Enum.filter(&(String.length(&1) > 4))
      |> Enum.take(3)

    # Find sentences containing these keywords
    prompt_text
    |> String.split(~r/[.!?]+/)
    |> Enum.find(fn sentence ->
      sentence_lower = String.downcase(sentence)
      Enum.any?(keywords, &String.contains?(sentence_lower, &1))
    end)
    |> case do
      nil -> nil
      sentence -> String.trim(sentence)
    end
  end

  defp get_replacement_content(suggestion, _structure, target_text) do
    if suggestion.specific_text && String.trim(suggestion.specific_text) != "" do
      suggestion.specific_text
    else
      # Generate improved version of target text
      improve_text(target_text, suggestion.category)
    end
  end

  defp improve_text(text, category) do
    case category do
      :clarity ->
        text <> " (be specific and show your work)"

      :reasoning ->
        "Think through: #{text}"

      :constraint ->
        "#{text} - ensure you follow this carefully"

      _ ->
        text
    end
  end

  defp identify_deletion_target(suggestion, structure) do
    cond do
      # If specific text provided, delete that
      suggestion.specific_text && String.trim(suggestion.specific_text) != "" ->
        suggestion.specific_text

      # Try to extract from description
      suggestion.description =~ ~r/remove ["'](.+?)["']/i ->
        case Regex.run(~r/remove ["'](.+?)["']/i, suggestion.description) do
          [_, target] -> target
          _ -> nil
        end

      # Look for redundant phrases
      String.contains?(String.downcase(suggestion.description), "redundant") ->
        find_redundant_text(structure.raw_text)

      true ->
        nil
    end
  end

  defp find_redundant_text(prompt_text) do
    # Look for common redundant patterns
    redundant_patterns = [
      ~r/please note that/i,
      ~r/it (is important|should be noted) that/i,
      ~r/as (mentioned|stated|noted) (before|above|previously)/i
    ]

    Enum.find_value(redundant_patterns, fn pattern ->
      case Regex.run(pattern, prompt_text) do
        [match | _] -> match
        nil -> nil
      end
    end)
  end

  defp generate_edit_id do
    "edit_#{:erlang.unique_integer([:positive])}"
  end
end
