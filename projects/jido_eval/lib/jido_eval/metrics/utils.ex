defmodule Jido.Eval.Metrics.Utils do
  @moduledoc """
  Utility functions for implementing evaluation metrics.

  Provides common patterns and helpers used across LLM-based metrics including
  prompt building, score normalization, and error handling.

  ## Examples

      # Build a prompt with context
      prompt = Utils.build_prompt(template, %{response: "Hello", contexts: ["World"]})
      
      # Normalize score to range
      normalized = Utils.normalize_score(0.85, {0.0, 1.0})
      
      # Extract numeric score from LLM response
      {:ok, 0.8} = Utils.extract_score("The score is 0.8 out of 1.0")
  """

  require Logger

  @doc """
  Build a prompt from a template with variable substitution.

  Supports simple variable substitution using `{{variable}}` syntax.

  ## Parameters

  - `template` - Prompt template string with `{{variable}}` placeholders
  - `variables` - Map of variable names to values

  ## Returns

  - `String.t()` - Rendered prompt

  ## Examples

      iex> template = "Rate this response: {{response}} given context: {{context}}"
      iex> variables = %{response: "Hello", context: "greeting"}
      iex> Jido.Eval.Metrics.Utils.build_prompt(template, variables)
      "Rate this response: Hello given context: greeting"
  """
  @spec build_prompt(String.t(), map()) :: String.t()
  def build_prompt(template, variables) when is_binary(template) and is_map(variables) do
    Enum.reduce(variables, template, fn {key, value}, acc ->
      placeholder = "{{#{key}}}"
      String.replace(acc, placeholder, to_string(value))
    end)
  end

  @doc """
  Normalize a score to fit within a specified range.

  ## Parameters

  - `score` - Raw score value
  - `range` - Target range as `{min, max}` tuple

  ## Returns

  - `float()` - Normalized score

  ## Examples

      iex> Jido.Eval.Metrics.Utils.normalize_score(0.85, {0.0, 1.0})
      0.85
      
      iex> Jido.Eval.Metrics.Utils.normalize_score(85, {0.0, 1.0})
      0.85
  """
  @spec normalize_score(number(), {number(), number()}) :: float()
  def normalize_score(score, {min_val, max_val}) when is_number(score) do
    cond do
      score >= min_val and score <= max_val ->
        score / 1.0

      score > max_val ->
        # Assume score is on a different scale, normalize by dividing by likely base
        cond do
          score <= 10 -> score / 10.0
          score <= 100 -> score / 100.0
          true -> max_val / 1.0
        end

      score < min_val ->
        min_val / 1.0
    end
  end

  @doc """
  Extract a numeric score from LLM response text.

  Looks for common score patterns in text responses including:
  - "Score: 0.8"
  - "0.8/1.0" 
  - "Rating: 4/5"
  - Standalone numbers

  ## Parameters

  - `text` - LLM response text

  ## Returns

  - `{:ok, float()}` - Extracted score
  - `{:error, :no_score_found}` - No valid score found

  ## Examples

      iex> Jido.Eval.Metrics.Utils.extract_score("The score is 0.8")
      {:ok, 0.8}
      
      iex> Jido.Eval.Metrics.Utils.extract_score("Rating: 4/5")
      {:ok, 0.8}
  """
  @spec extract_score(String.t()) :: {:ok, float()} | {:error, :no_score_found}
  def extract_score(text) when is_binary(text) do
    patterns = [
      # "Score: 0.8" or "score: 0.8"
      ~r/score:\s*([0-9]*\.?[0-9]+)/i,
      # "0.8/1.0" or "4/5"
      ~r/([0-9]*\.?[0-9]+)\s*\/\s*([0-9]*\.?[0-9]+)/,
      # "Rating: 0.8" or "rating: 0.8"
      ~r/rating:\s*([0-9]*\.?[0-9]+)/i,
      # Standalone decimal numbers
      ~r/\b([0-9]*\.[0-9]+)\b/,
      # Standalone integers (when no decimals found)
      ~r/\b([0-9]+)\b/
    ]

    case extract_with_patterns(text, patterns) do
      {:ok, score} -> {:ok, score}
      :not_found -> {:error, :no_score_found}
    end
  end

  @doc """
  Format contexts for LLM prompts.

  Takes a list of contexts and formats them with numbering for clear presentation.

  ## Parameters

  - `contexts` - List of context strings

  ## Returns

  - `String.t()` - Formatted contexts

  ## Examples

      iex> contexts = ["First context", "Second context"]
      iex> Jido.Eval.Metrics.Utils.format_contexts(contexts)
      "Context 1: First context\\nContext 2: Second context"
  """
  @spec format_contexts([String.t()]) :: String.t()
  def format_contexts(contexts) when is_list(contexts) do
    contexts
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {context, idx} -> "Context #{idx}: #{context}" end)
  end

  @doc """
  Execute an LLM-based metric evaluation with error handling.

  Wraps LLM calls with consistent error handling and logging for metrics.

  ## Parameters

  - `metric_name` - Name of the metric for logging
  - `model_spec` - Model specification (string, tuple, or struct)
  - `prompt` - Prompt to send to LLM
  - `opts` - Additional options

  ## Returns

  - `{:ok, String.t()}` - LLM response
  - `{:error, term()}` - Error with metric context
  """
  @spec execute_llm_metric(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def execute_llm_metric(metric_name, model_spec, prompt, opts) do
    Logger.debug("Executing #{metric_name} metric with LLM")

    case Jido.Eval.LLM.generate_text(model_spec, prompt, opts) do
      {:ok, response} ->
        Logger.debug("#{metric_name} metric LLM call successful")
        {:ok, response}

      {:error, reason} ->
        Logger.warning("#{metric_name} metric LLM call failed: #{inspect(reason)}")
        {:error, {:llm_error, reason}}
    end
  end

  @doc """
  Parse a boolean response from LLM text.

  Extracts yes/no, true/false, or similar boolean responses from text.

  ## Parameters

  - `text` - LLM response text

  ## Returns

  - `{:ok, boolean()}` - Parsed boolean
  - `{:error, :no_boolean_found}` - No clear boolean found

  ## Examples

      iex> Jido.Eval.Metrics.Utils.parse_boolean("Yes, this is correct")
      {:ok, true}
      
      iex> Jido.Eval.Metrics.Utils.parse_boolean("No, this is wrong")
      {:ok, false}
  """
  @spec parse_boolean(String.t()) :: {:ok, boolean()} | {:error, :no_boolean_found}
  def parse_boolean(text) when is_binary(text) do
    normalized = String.downcase(String.trim(text))

    cond do
      String.contains?(normalized, "yes") or String.contains?(normalized, "true") ->
        {:ok, true}

      String.contains?(normalized, "no") or String.contains?(normalized, "false") ->
        {:ok, false}

      String.starts_with?(normalized, "1") ->
        {:ok, true}

      String.starts_with?(normalized, "0") ->
        {:ok, false}

      true ->
        {:error, :no_boolean_found}
    end
  end

  # Private helper functions

  defp extract_with_patterns(_text, []), do: :not_found

  defp extract_with_patterns(text, [pattern | rest]) do
    case Regex.run(pattern, text) do
      nil ->
        extract_with_patterns(text, rest)

      [_, score_str] ->
        case Float.parse(score_str) do
          {score, _} -> {:ok, score}
          :error -> extract_with_patterns(text, rest)
        end

      [_, numerator_str, denominator_str] ->
        # Handle fractions like "4/5"
        with {num, _} <- Float.parse(numerator_str),
             {den, _} <- Float.parse(denominator_str),
             true <- den > 0 do
          {:ok, num / den}
        else
          _ -> extract_with_patterns(text, rest)
        end
    end
  end
end
