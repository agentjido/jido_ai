defmodule Jido.AI.Runner.ChainOfThought.ZeroShot do
  @moduledoc """
  Zero-shot Chain-of-Thought reasoning implementation.

  This module implements the foundational zero-shot CoT pattern using the
  "Let's think step by step" prompting technique. Zero-shot CoT provides
  8-15% accuracy improvement with 3-4x token overhead compared to standard
  prompting, without requiring examples or task-specific structure.

  ## Features

  - Simple step-by-step prompting with "Let's think step by step" trigger
  - Structured reasoning extraction parsing LLM responses
  - Temperature control (0.2-0.3) for consistent reasoning
  - Support for multiple model backends (GPT-4, Claude, etc.)
  - Automatic step detection and parsing

  ## Usage

      # Generate zero-shot reasoning
      {:ok, reasoning} = ZeroShot.generate(
        problem: "What is 15 * 24?",
        model: "gpt-4o",
        temperature: 0.3
      )

      # Reasoning structure:
      %{
        problem: "What is 15 * 24?",
        reasoning_text: "Let's think step by step...",
        steps: ["Step 1: ...", "Step 2: ..."],
        answer: "360",
        confidence: 0.95
      }

  ## Temperature Guidelines

  - 0.2-0.3: Consistent, focused reasoning (recommended for most tasks)
  - 0.4-0.5: Balanced creativity and consistency
  - 0.6-0.7: More creative reasoning paths

  ## Supported Models

  - OpenAI: gpt-4o, gpt-4-turbo, gpt-3.5-turbo
  - Anthropic: claude-3-5-sonnet, claude-3-opus, claude-3-sonnet
  - Google: gemini-pro, gemini-1.5-pro
  """

  require Logger
  alias Jido.AI.Actions.TextCompletion
  alias Jido.AI.{Model, Prompt}

  @default_temperature 0.3
  @default_max_tokens 2000

  @doc """
  Generates zero-shot Chain-of-Thought reasoning for a problem.

  Uses the "Let's think step by step" prompt technique to elicit
  step-by-step reasoning from the LLM without providing examples.

  ## Parameters

  - `opts` - Keyword list with options:
    - `:problem` (required) - The problem or question to reason about
    - `:model` - Model string (default: "gpt-4o")
    - `:temperature` - Temperature for generation (default: 0.3)
    - `:max_tokens` - Maximum tokens in response (default: 2000)
    - `:context` - Additional context (default: %{})

  ## Returns

  - `{:ok, reasoning}` - Structured reasoning map
  - `{:error, reason}` - Generation failed

  ## Examples

      {:ok, reasoning} = ZeroShot.generate(
        problem: "If a train travels 60 miles in 1 hour, how far does it travel in 2.5 hours?",
        temperature: 0.2
      )

      reasoning.steps
      # => ["Step 1: Identify the speed: 60 miles per hour",
      #     "Step 2: Calculate distance: speed × time",
      #     "Step 3: 60 × 2.5 = 150 miles"]
  """
  @spec generate(keyword()) :: {:ok, map()} | {:error, term()}
  def generate(opts) do
    with {:ok, problem} <- validate_problem(opts),
         {:ok, prompt} <- build_zero_shot_prompt(problem, opts),
         {:ok, model} <- build_model(opts),
         {:ok, response} <- generate_reasoning(prompt, model, opts),
         {:ok, parsed} <- parse_reasoning(response, problem) do
      {:ok, parsed}
    else
      {:error, reason} = error ->
        Logger.error("Zero-shot reasoning generation failed: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Builds a zero-shot prompt with "Let's think step by step" trigger.

  ## Parameters

  - `problem` - The problem statement
  - `opts` - Additional options for prompt customization

  ## Returns

  - `{:ok, prompt}` - Jido.AI.Prompt struct
  - `{:error, reason}` - Prompt building failed
  """
  @spec build_zero_shot_prompt(String.t(), keyword()) :: {:ok, Prompt.t()} | {:error, term()}
  def build_zero_shot_prompt(problem, opts \\ []) do
    context = Keyword.get(opts, :context, %{})

    template = """
    #{format_context(context)}Problem: #{problem}

    Let's think step by step to solve this problem.
    """

    prompt = Prompt.new(:user, String.trim(template))
    {:ok, prompt}
  end

  @doc """
  Parses LLM response into structured reasoning.

  Extracts step-by-step reasoning, identifies the answer, and
  structures the result for downstream use.

  ## Parameters

  - `response_text` - Raw LLM response text
  - `problem` - Original problem statement

  ## Returns

  - `{:ok, reasoning}` - Structured reasoning map
  - `{:error, reason}` - Parsing failed
  """
  @spec parse_reasoning(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def parse_reasoning(response_text, problem) do
    steps = extract_steps(response_text)
    answer = extract_answer(response_text, steps)
    confidence = estimate_confidence(response_text, steps)

    reasoning = %{
      problem: problem,
      reasoning_text: response_text,
      steps: steps,
      answer: answer,
      confidence: confidence,
      timestamp: DateTime.utc_now()
    }

    {:ok, reasoning}
  end

  @doc """
  Extracts step-by-step reasoning from LLM response.

  Identifies lines that represent reasoning steps, such as:
  - "Step 1: ..."
  - "First, ..."
  - "1. ..."
  - Lines starting with numbers or bullets

  ## Parameters

  - `text` - LLM response text

  ## Returns

  List of extracted step strings
  """
  @spec extract_steps(String.t()) :: list(String.t())
  def extract_steps(text) do
    text
    |> String.split("\n")
    |> Enum.filter(&step?/1)
    |> Enum.map(&clean_step/1)
    |> Enum.reject(&(&1 == ""))
  end

  @doc """
  Extracts the final answer from reasoning.

  Looks for answer indicators like:
  - "Therefore, ..."
  - "So the answer is ..."
  - "The final answer is ..."
  - Last step content

  ## Parameters

  - `text` - LLM response text
  - `steps` - Extracted reasoning steps

  ## Returns

  Answer string or nil if not found
  """
  @spec extract_answer(String.t(), list(String.t())) :: String.t() | nil
  def extract_answer(text, steps) do
    # Try to find explicit answer statements
    answer_patterns = [
      ~r/\b(?:the )?(?:final )?answer is:?\s+([^,\n]+?)\.?$/im,
      ~r/\bso,?\s+(?:the )?answer is\s+([^,\n]+?)\.?$/im,
      ~r/(?:result|solution):\s*([^,\n]+?)\.?$/im,
      ~r/\b(?:therefore|thus),?\s+(?:the answer is\s+)?.*?(\d+)\.?$/im,
      ~r/\b(?:therefore|thus),?\s+([^,\n]+?)\.?$/im
    ]

    # Find all matches with their positions and return the earliest one
    answer =
      answer_patterns
      |> Enum.flat_map(fn pattern ->
        case Regex.run(pattern, text, return: :index) do
          [match | _] ->
            {pos, _len} = match

            captured_text =
              case Regex.run(pattern, text) do
                [_, captured] -> String.trim(captured)
                _ -> nil
              end

            if captured_text, do: [{pos, captured_text}], else: []

          _ ->
            []
        end
      end)
      |> Enum.sort_by(fn {pos, _text} -> pos end)
      |> case do
        [{_pos, text} | _] -> text
        [] -> nil
      end

    # Fall back to last step if no explicit answer found
    answer || List.last(steps)
  end

  @doc """
  Estimates confidence in the reasoning.

  Uses heuristics based on:
  - Number of steps (more steps may indicate thoroughness)
  - Presence of explicit answer
  - Use of definitive language
  - Logical flow indicators

  ## Parameters

  - `text` - LLM response text
  - `steps` - Extracted reasoning steps

  ## Returns

  Confidence score between 0.0 and 1.0
  """
  @spec estimate_confidence(String.t(), list(String.t())) :: float()
  def estimate_confidence(text, steps) do
    base_confidence = 0.6

    # More steps generally indicate more thorough reasoning
    step_bonus = min(length(steps) * 0.05, 0.2)

    # Explicit answer indicators
    answer_bonus =
      if String.match?(text, ~r/\b(therefore|thus|so)\b|\banswer is\b/i), do: 0.1, else: 0.0

    # Definitive language
    definitive_bonus =
      if String.match?(text, ~r/\b(clearly|obviously|certainly|definitely)\b/i),
        do: 0.05,
        else: 0.0

    # Logical flow indicators
    flow_bonus =
      if String.match?(text, ~r/\b(because|since|consequently)\b|\bas a result\b/i),
        do: 0.05,
        else: 0.0

    confidence = base_confidence + step_bonus + answer_bonus + definitive_bonus + flow_bonus
    min(confidence, 1.0)
  end

  # Private helper functions

  @spec validate_problem(keyword()) :: {:ok, String.t()} | {:error, term()}
  defp validate_problem(opts) do
    case Keyword.get(opts, :problem) do
      nil -> {:error, "Problem is required"}
      problem when is_binary(problem) and byte_size(problem) > 0 -> {:ok, problem}
      _ -> {:error, "Problem must be a non-empty string"}
    end
  end

  @spec format_context(map()) :: String.t()
  defp format_context(context) when context == %{}, do: ""

  defp format_context(context) do
    context
    |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{inspect(v)}" end)
    |> then(&"Context:\n#{&1}\n\n")
  end

  @spec build_model(keyword()) :: {:ok, Model.t()} | {:error, term()}
  defp build_model(opts) do
    model_string = Keyword.get(opts, :model, "gpt-4o")
    temperature = Keyword.get(opts, :temperature, @default_temperature)
    max_tokens = Keyword.get(opts, :max_tokens, @default_max_tokens)

    # Validate temperature is in recommended range
    validated_temperature =
      if temperature < 0.2 or temperature > 0.7 do
        Logger.warning(
          "Temperature #{temperature} outside recommended range (0.2-0.7), using #{@default_temperature}"
        )

        @default_temperature
      else
        temperature
      end

    # Parse model string to extract provider and model name
    {provider, model_name} = infer_provider(model_string)

    model = %Model{
      provider: provider,
      model: model_name,
      temperature: validated_temperature,
      max_tokens: max_tokens
    }

    {:ok, model}
  rescue
    error ->
      {:error, "Failed to build model: #{inspect(error)}"}
  end

  @spec infer_provider(String.t()) :: {atom(), String.t()}
  defp infer_provider("gpt-" <> _ = model), do: {:openai, model}
  defp infer_provider("claude-" <> _ = model), do: {:anthropic, model}
  defp infer_provider("gemini-" <> _ = model), do: {:google, model}

  defp infer_provider(model) do
    # Handle provider/model format
    case String.split(model, "/", parts: 2) do
      [provider_str, model_str] -> {String.to_atom(provider_str), model_str}
      [single_part] -> {:openai, single_part}
    end
  end

  @spec generate_reasoning(Prompt.t(), Model.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  defp generate_reasoning(prompt, model, _opts) do
    completion_params = %{
      model: model,
      prompt: prompt,
      temperature: model.temperature,
      max_tokens: model.max_tokens
    }

    case TextCompletion.run(completion_params, %{}) do
      {:ok, %{content: content}} ->
        {:ok, content}

      {:ok, %{content: content}, _meta} ->
        {:ok, content}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec step?(String.t()) :: boolean()
  defp step?(line) do
    trimmed = String.trim(line)

    # Check various step patterns
    String.match?(trimmed, ~r/^(?:step\s+\d+|first|second|third|next|then|finally|\d+\.|\*|-)/i) and
      String.length(trimmed) > 5
  end

  @spec clean_step(String.t()) :: String.t()
  defp clean_step(line) do
    line
    |> String.trim()
    |> String.replace(~r/^(?:step\s+\d+:?\s*|\d+\.\s*|\*\s*|-\s*)/i, "")
    |> String.trim()
  end
end
