defmodule Jido.AI.Runner.GEPA.SuggestionGeneration.EditValidator do
  @moduledoc """
  Validates that proposed edits are applicable and safe to apply.

  Checks that:
  - Edit locations are valid
  - Edit operations make sense for the prompt structure
  - Target text exists for replacements/deletions
  - Content is appropriate for insertions

  ## Usage

      {:ok, validated_edit} = EditValidator.validate(edit, prompt_structure)

      if validated_edit.validated do
        # Safe to apply
      end
  """

  require Logger

  alias Jido.AI.Runner.GEPA.SuggestionGeneration.{PromptEdit, PromptStructure}

  @doc """
  Validates an edit against a prompt structure.

  ##Parameters

  - `edit` - The edit to validate
  - `prompt_structure` - The prompt structure to validate against

  ## Returns

  - `{:ok, PromptEdit.t()}` - Validated edit (with validated=true if valid)
  - `{:error, reason}` - If validation fails critically

  ## Examples

      {:ok, validated} = EditValidator.validate(edit, structure)
      validated.validated  # => true or false
  """
  @spec validate(PromptEdit.t(), PromptStructure.t()) ::
          {:ok, PromptEdit.t()} | {:error, term()}
  def validate(%PromptEdit{} = edit, %PromptStructure{} = structure) do
    validations = [
      &validate_operation/2,
      &validate_location/2,
      &validate_content/2,
      &validate_target_text/2
    ]

    result =
      Enum.reduce_while(validations, {:ok, edit}, fn validator, {:ok, current_edit} ->
        case validator.(current_edit, structure) do
          {:ok, updated_edit} -> {:cont, {:ok, updated_edit}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, validated_edit} ->
        # Mark as validated
        {:ok, %{validated_edit | validated: true}}

      error ->
        error
    end
  end

  # Validation functions

  defp validate_operation(edit, _structure) do
    case edit.operation do
      op when op in [:insert, :replace, :delete, :move] ->
        {:ok, edit}

      _ ->
        {:error, :invalid_operation}
    end
  end

  defp validate_location(edit, structure) do
    location = edit.location

    case location.type do
      :start ->
        {:ok, edit}

      :end ->
        {:ok, edit}

      :before ->
        if location.relative_marker do
          if String.contains?(structure.raw_text, location.relative_marker) do
            {:ok, edit}
          else
            Logger.warning(
              "Relative marker not found in prompt (marker: #{location.relative_marker})"
            )

            # Fallback to end
            {:ok, %{edit | location: %{location | type: :end}}}
          end
        else
          {:error, :missing_relative_marker}
        end

      :after ->
        if location.relative_marker do
          if String.contains?(structure.raw_text, location.relative_marker) do
            {:ok, edit}
          else
            Logger.warning("Relative marker not found in prompt")
            {:ok, %{edit | location: %{location | type: :end}}}
          end
        else
          {:error, :missing_relative_marker}
        end

      :within ->
        # Check if pattern exists in prompt
        if location.pattern do
          pattern_str =
            if is_struct(location.pattern, Regex),
              do: inspect(location.pattern),
              else: location.pattern

          if contains_pattern?(structure.raw_text, location.pattern) do
            {:ok, edit}
          else
            Logger.warning("Pattern not found in prompt (pattern: #{pattern_str})")
            # Cannot fall back for within - this is an error
            {:ok,
             %{
               edit
               | validated: false,
                 metadata: Map.put(edit.metadata, :validation_warning, :pattern_not_found)
             }}
          end
        else
          {:error, :missing_pattern}
        end

      :replace_all ->
        {:ok, edit}

      _ ->
        {:error, :invalid_location_type}
    end
  end

  defp validate_content(edit, _structure) do
    case edit.operation do
      :insert ->
        if edit.content && String.trim(edit.content) != "" do
          {:ok, edit}
        else
          {:error, :missing_insert_content}
        end

      :replace ->
        if edit.content && String.trim(edit.content) != "" do
          {:ok, edit}
        else
          {:error, :missing_replacement_content}
        end

      :delete ->
        # Deletes don't need content
        {:ok, edit}

      :move ->
        {:ok, edit}
    end
  end

  defp validate_target_text(edit, structure) do
    case edit.operation do
      :replace ->
        if edit.target_text do
          if String.contains?(structure.raw_text, edit.target_text) do
            {:ok, edit}
          else
            Logger.warning("Target text not found in prompt (target: #{edit.target_text})")

            {:ok,
             %{
               edit
               | validated: false,
                 metadata: Map.put(edit.metadata, :validation_warning, :target_not_found)
             }}
          end
        else
          {:error, :missing_target_text}
        end

      :delete ->
        if edit.target_text do
          if String.contains?(structure.raw_text, edit.target_text) do
            {:ok, edit}
          else
            Logger.warning("Deletion target not found (target: #{edit.target_text})")

            {:ok,
             %{
               edit
               | validated: false,
                 metadata: Map.put(edit.metadata, :validation_warning, :target_not_found)
             }}
          end
        else
          {:error, :missing_deletion_target}
        end

      _ ->
        {:ok, edit}
    end
  end

  defp contains_pattern?(text, pattern) when is_binary(pattern) do
    String.contains?(text, pattern)
  end

  defp contains_pattern?(text, %Regex{} = pattern) do
    Regex.match?(pattern, text)
  end

  defp contains_pattern?(_text, _pattern), do: false
end
