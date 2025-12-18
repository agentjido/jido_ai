defmodule Jido.AI.Runner.ReAct.ObservationProcessor do
  @moduledoc """
  Processes action results into observations for the next reasoning step.

  The ObservationProcessor:
  - Converts action results into textual observations
  - Summarizes long results to fit context windows
  - Formats observations for inclusion in thought prompts
  - Preserves important metadata while reducing noise
  - Handles errors and edge cases gracefully

  ## Design Principles

  1. **Conciseness**: Observations should be informative but concise
  2. **Relevance**: Focus on information relevant to answering the question
  3. **Readability**: Format for easy consumption by LLM reasoning
  4. **Safety**: Sanitize potentially harmful content

  ## Examples

      ObservationProcessor.process("The Eiffel Tower is in Paris, France")
      # => {:ok, "The Eiffel Tower is in Paris, France"}

      ObservationProcessor.process(very_long_text)
      # => {:ok, "Summary of the key points: ..."}

      ObservationProcessor.process(%{results: [...]})
      # => {:ok, "Found 3 results: result1, result2, result3"}
  """

  @default_max_length 500
  @default_summary_length 300

  @doc """
  Processes an action result into an observation string.

  ## Parameters

  - `result` - The action result (string, map, list, etc.)
  - `opts` - Processing options:
    - `:max_length` - Maximum observation length (default: 500)
    - `:summarize` - Whether to summarize long content (default: true)
    - `:format` - Output format (:text, :json, :markdown)
    - `:preserve_metadata` - Whether to include metadata (default: false)

  ## Returns

  - `{:ok, observation}` - Processed observation string
  - `{:error, reason}` - Processing failed
  """
  @spec process(term(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def process(result, opts \\ []) do
    max_length = Keyword.get(opts, :max_length, @default_max_length)
    summarize? = Keyword.get(opts, :summarize, true)
    format = Keyword.get(opts, :format, :text)
    preserve_metadata = Keyword.get(opts, :preserve_metadata, false)

    try do
      # Convert result to string
      observation = to_observation_string(result, format, preserve_metadata)

      # Truncate or summarize if needed
      final_observation =
        if summarize? and String.length(observation) > max_length do
          summarize_observation(observation, max_length)
        else
          String.slice(observation, 0, max_length)
        end

      {:ok, final_observation}
    rescue
      error ->
        {:error, {:processing_failed, error}}
    end
  end

  @doc """
  Summarizes a long observation into a concise form.

  Uses various strategies:
  - Extract key sentences
  - Preserve numbers and entities
  - Focus on factual information
  - Remove redundancy

  ## Parameters

  - `text` - The text to summarize
  - `target_length` - Target summary length (default: 300)

  ## Returns

  - Summarized text
  """
  @spec summarize_observation(String.t(), pos_integer()) :: String.t()
  def summarize_observation(text, target_length \\ @default_summary_length) do
    # Simple summarization strategy:
    # 1. Split into sentences
    # 2. Score sentences by information content
    # 3. Select top sentences until target length

    sentences = split_into_sentences(text)

    # Score each sentence
    scored_sentences =
      sentences
      |> Enum.with_index()
      |> Enum.map(fn {sentence, index} ->
        score = score_sentence(sentence, index, length(sentences))
        {sentence, score}
      end)
      |> Enum.sort_by(fn {_sentence, score} -> score end, :desc)

    # Build summary by selecting top sentences
    build_summary(scored_sentences, target_length)
  end

  @doc """
  Formats an observation for display in the reasoning trajectory.

  Adds context and structure to make observations more useful
  for subsequent reasoning steps.

  ## Parameters

  - `observation` - The observation text
  - `action_name` - The action that produced this observation
  - `opts` - Formatting options

  ## Returns

  - Formatted observation string
  """
  @spec format_for_reasoning(String.t(), String.t(), keyword()) :: String.t()
  def format_for_reasoning(observation, action_name, opts \\ []) do
    include_action = Keyword.get(opts, :include_action, true)
    add_context = Keyword.get(opts, :add_context, false)

    parts = []

    parts =
      if include_action do
        parts ++ ["[#{action_name}]"]
      else
        parts
      end

    parts = parts ++ [observation]

    parts =
      if add_context do
        parts ++ ["(This information may help answer the question)"]
      else
        parts
      end

    Enum.join(parts, " ")
  end

  # Private functions

  defp to_observation_string(result, format, preserve_metadata) do
    case result do
      s when is_binary(s) ->
        s

      m when is_map(m) ->
        map_to_observation(m, format, preserve_metadata)

      l when is_list(l) ->
        list_to_observation(l, format)

      {:ok, value} ->
        to_observation_string(value, format, preserve_metadata)

      {:error, reason} ->
        "Error: #{inspect(reason)}"

      other ->
        inspect(other)
    end
  end

  defp map_to_observation(map, format, preserve_metadata) do
    case format do
      :json ->
        # Try to encode as JSON, fall back to inspect if encoding fails
        # This handles non-JSON-encodable data like PIDs, refs, functions
        try do
          Jason.encode!(map)
        rescue
          e ->
            require Logger

            Logger.warning(
              "Failed to JSON encode observation (#{inspect(e)}). Falling back to inspect/1."
            )

            inspect(map)
        end

      :text ->
        map_to_text(map, preserve_metadata)

      :markdown ->
        map_to_markdown(map)
    end
  end

  defp map_to_text(map, preserve_metadata) do
    # Extract key fields
    important_keys = ["result", "answer", "content", "text", "value", "data", "message"]

    # Try to find main content
    main_content =
      Enum.find_value(important_keys, fn key ->
        Map.get(map, key) || Map.get(map, String.to_atom(key))
      end)

    if main_content do
      to_observation_string(main_content, :text, preserve_metadata)
    else
      # No obvious main content, format entire map
      map
      |> Enum.reject(fn {k, _v} ->
        # Filter out metadata unless requested
        !preserve_metadata && k in [:metadata, :__meta__, :__struct__]
      end)
      |> Enum.map_join(", ", fn {k, v} -> "#{k}: #{inspect(v)}" end)
    end
  end

  defp map_to_markdown(map) do
    map
    |> Enum.map_join("\n", fn {k, v} -> "**#{k}**: #{inspect(v)}" end)
  end

  defp list_to_observation([], _format) do
    "No results found"
  end

  defp list_to_observation(list, _format) when length(list) <= 3 do
    # Small list, show all items
    items = Enum.map(list, &inspect/1)
    "Found #{length(list)} results: #{Enum.join(items, ", ")}"
  end

  defp list_to_observation(list, _format) do
    # Large list, show count and first few
    items =
      list
      |> Enum.take(3)
      |> Enum.map(&inspect/1)

    "Found #{length(list)} results. First 3: #{Enum.join(items, ", ")}"
  end

  defp split_into_sentences(text) do
    text
    |> String.split(~r/[.!?]+\s+/)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp score_sentence(sentence, index, total) do
    # Simple scoring heuristic
    score = 0.0

    # First and last sentences often more important
    score =
      cond do
        index == 0 -> score + 1.0
        index == total - 1 -> score + 0.5
        true -> score
      end

    # Sentences with numbers often more important
    score = if Regex.match?(~r/\d+/, sentence), do: score + 0.5, else: score

    # Sentences with entities (capitalized words) often more important
    score =
      if Regex.match?(~r/\b[A-Z][a-z]+/, sentence), do: score + 0.3, else: score

    # Shorter sentences preferred for conciseness
    length_score = max(0.0, 1.0 - String.length(sentence) / 200.0)
    score = score + length_score * 0.2

    score
  end

  defp build_summary(scored_sentences, target_length) do
    # Select sentences until we reach target length
    {summary, _length} =
      Enum.reduce_while(scored_sentences, {[], 0}, fn {sentence, _score}, {acc, current_length} ->
        new_length = current_length + String.length(sentence) + 2

        # +2 for punctuation and space
        if new_length <= target_length do
          {:cont, {[sentence | acc], new_length}}
        else
          {:halt, {acc, current_length}}
        end
      end)

    if Enum.empty?(summary) do
      # If no sentences fit, just truncate the first sentence
      {first_sentence, _} = List.first(scored_sentences)
      String.slice(first_sentence, 0, target_length)
    else
      # Reassemble in original order by sorting by index
      summary
      |> Enum.reverse()
      |> Enum.join(". ")
      |> Kernel.<>(".")
    end
  end
end
