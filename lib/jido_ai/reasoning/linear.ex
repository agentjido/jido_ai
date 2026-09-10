defmodule Jido.AI.Reasoning.Linear do
  @moduledoc "Shared CoT and CoD prompt and result rules. Core Flow owns execution."
  @type step :: %{number: pos_integer(), content: String.t()}

  def linear?(method), do: method in [:chain_of_thought, :chain_of_draft]
  defdelegate label(method), to: Jido.AI.Reasoning

  def instructions(method, value)
      when method in [:chain_of_thought, :chain_of_draft] and value in [nil, ""],
      do: default_prompt(method)

  def instructions(_, value), do: value

  def project(method, result, raw) when method in [:chain_of_thought, :chain_of_draft] do
    {steps, conclusion} =
      if is_binary(result), do: extract_steps_and_conclusion(result), else: {[], nil}

    {conclusion || result,
     %{
       termination_reason: :success,
       reasoning: %{
         method: method,
         steps: steps,
         steps_count: length(steps),
         conclusion: conclusion,
         raw_response: raw
       }
     }}
  end

  def project(_, result, _), do: {result, %{}}

  @doc false
  def stored_record(%Jido.Agent{state: state}, method, request_id) when is_map(state) do
    records = Map.get(state, :requests, %{})

    record =
      if request_id do
        Map.get(records, request_id)
      else
        records
        |> Map.values()
        |> Enum.filter(&(&1.method == method))
        |> Enum.max_by(&{&1.inserted_at, &1.id}, fn -> nil end)
      end

    case record do
      %{method: ^method} -> record
      _ -> nil
    end
  end

  def stored_record(%Jido.Agent{}, _, _), do: nil

  def stored_reasoning(agent, method, request_id) do
    case stored_record(agent, method, request_id) do
      %{meta: %{reasoning: reasoning}} when is_map(reasoning) -> reasoning
      _ -> %{}
    end
  end

  def default_prompt(:chain_of_thought) do
    """
    You are a helpful AI assistant that thinks through problems step by step.

    When solving problems:
    1. Break down the problem into clear, logical steps
    2. Show your reasoning for each step
    3. Number your steps (Step 1:, Step 2:, etc.)
    4. After all steps, provide your final answer clearly marked as "Conclusion:" or "Answer:"

    Think carefully and explain your reasoning at each step.
    """
  end

  def default_prompt(:chain_of_draft) do
    """
    You are a helpful AI assistant using Chain-of-Draft reasoning.

    Think step by step, but keep each intermediate draft extremely concise:
    - Use minimal draft steps with at most 5 words when possible.
    - Keep only the essential information needed to progress.
    - Avoid verbose explanations during reasoning.

    At the end of your response, provide the final answer after the separator ####.
    """
  end

  def extract_steps_and_conclusion(text) when is_binary(text) do
    case extract_hash_conclusion(text) do
      {content_text, conclusion} ->
        {extract_steps(content_text), conclusion}

      :none ->
        lines = String.split(text, ~r/\r?\n/, trim: false)
        {content_lines, conclusion} = extract_conclusion(lines)
        steps = extract_steps(Enum.join(content_lines, "\n"))
        {steps, conclusion}
    end
  end

  def extract_steps_and_conclusion(_), do: {[], nil}

  defp extract_hash_conclusion(text) when is_binary(text) do
    case String.split(text, "####", parts: 2) do
      [content, conclusion] ->
        conclusion = String.trim(conclusion)

        if conclusion == "" do
          :none
        else
          {String.trim(content), conclusion}
        end

      _ ->
        :none
    end
  end

  # Extract conclusion from lines
  defp extract_conclusion(lines) do
    conclusion_patterns = [
      ~r/^(?:conclusion|answer|therefore|final answer|in conclusion|thus|hence|so)(?=\s|:|-|$)\s*[:\-]?\s*/i
    ]

    # Find the index of conclusion marker
    conclusion_idx =
      Enum.find_index(lines, fn line ->
        trimmed = String.trim(line)
        Enum.any?(conclusion_patterns, &Regex.match?(&1, trimmed))
      end)

    case conclusion_idx do
      nil ->
        {lines, nil}

      idx ->
        content_lines = Enum.take(lines, idx)
        conclusion_lines = Enum.drop(lines, idx)

        conclusion =
          conclusion_lines
          |> Enum.join("\n")
          |> String.trim()
          |> String.replace(
            ~r/^(?:conclusion|answer|therefore|final answer|in conclusion|thus|hence|so)(?=\s|:|-|$)\s*[:\-]?\s*/i,
            ""
          )
          |> String.trim()

        conclusion = if conclusion != "", do: conclusion

        {content_lines, conclusion}
    end
  end

  # Extract steps from text
  defp extract_steps(text) do
    # Pattern for numbered steps at the beginning of a line:
    # "Step 1:", "Step 1.", "1.", "1)", "1:"
    # Must be at line start or after newline
    step_pattern = ~r/(?:^|\n)\s*(?:step\s+)?(\d+)[.:\)]\s*/i

    # Find all matches with their positions
    matches = Regex.scan(step_pattern, text, return: :index)

    if matches == [] do
      # Try bullet points if no numbered steps
      extract_bullet_steps(text)
    else
      # Extract step content between markers
      extract_steps_from_matches(text, matches)
    end
  end

  defp extract_steps_from_matches(text, matches) do
    matches
    |> Enum.with_index()
    |> Enum.map(fn {[{start, len}, {number_start, number_len}], index} ->
      end_pos =
        case Enum.at(matches, index + 1) do
          [{next_start, _} | _] -> next_start
          nil -> byte_size(text)
        end

      # Regex positions are byte offsets, including for non-ASCII text.
      content = binary_part(text, start + len, end_pos - start - len) |> String.trim()
      number = binary_part(text, number_start, number_len) |> String.to_integer()
      %{number: number, content: content}
    end)
    |> Enum.reject(&(&1.content == ""))
  end

  # Extract bullet point steps
  defp extract_bullet_steps(text) do
    bullet_pattern = ~r/^[\-\*•]\s+/mu

    # Only extract if there are actual bullet points in the text
    if Regex.match?(bullet_pattern, text) do
      parts =
        text
        |> String.split(bullet_pattern, trim: true)
        |> Enum.filter(&(String.trim(&1) != ""))

      parts
      |> Enum.with_index(1)
      |> Enum.map(fn {content, idx} ->
        %{
          number: idx,
          content: String.trim(content)
        }
      end)
    else
      []
    end
  end
end
