defmodule Jido.AI.Accuracy.Prms.LLMPrm do
  @moduledoc """
  LLM-based Process Reward Model for scoring reasoning steps.

  This PRM uses a language model to evaluate individual reasoning steps
  and classify them as correct, incorrect, or neutral. It enables
  step-level verification for guided search and reflection.

  ## Configuration

  - `:model` - Model to use for PRM scoring (default: from Config)
  - `:prompt_template` - Custom EEx template for step evaluation
  - `:score_range` - {min, max} range for step scores (default: {0.0, 1.0})
  - `:temperature` - Temperature for LLM calls (default: 0.2, lower for consistent classification)
  - `:timeout` - Timeout for LLM calls in ms (default: 30_000)
  - `:max_retries` - Maximum retry attempts (default: 2)
  - `:parallel` - Whether to score steps in parallel (default: false)

  ## Usage

      # Create PRM with defaults
      prm = LLMPrm.new!([])

      # Score a single reasoning step
      {:ok, score} = LLMPrm.score_step(prm,
        "First, I'll add 15 and 23 to get 38.",
        %{question: "What is 15 * 23?"},
        []
      )
      # => {:ok, 0.3} (low score because this step is on the wrong track)

      # Score a full reasoning trace
      {:ok, scores} = LLMPrm.score_trace(prm, [
        "Let me calculate 15 * 23.",
        "15 * 23 = 15 * 20 + 15 * 3 = 300 + 45 = 345",
        "Therefore, 15 * 23 = 345."
      ], %{question: "What is 15 * 23?"}, [])
      # => {:ok, [1.0, 1.0, 1.0]}

      # Classify a step
      {:ok, classification} = LLMPrm.classify_step(prm,
        "2 + 2 = 5",
        %{question: "What is 2 + 2?"},
        []
      )
      # => {:ok, :incorrect}

  ## Prompt Template

  The default prompt template uses EEx interpolation with these variables:
  - `@question` - The original question/prompt
  - `@step` - The reasoning step being evaluated
  - `@min_score` - Minimum score in range
  - `@max_score` - Maximum score in range
  - `@previous_steps` - Previous steps in the trace (for context)

  You can provide a custom template:

      prm = LLMPrm.new!(%{
        prompt_template: \"""
        Question: <%= @question %>
        Reasoning Step: <%= @step %>

        Rate this step from 0 to 100:
        Score: [0-100]
        Classification: [correct|incorrect|neutral]
        \"""
      })

  ## Score Classification Mapping

  Scores are mapped to classifications:
  - Score >= 0.7 (or 70% of range): `:correct`
  - Score <= 0.3 (or 30% of range): `:incorrect`
  - Otherwise: `:neutral`

  """

  @behaviour Jido.AI.Accuracy.Prm

  alias Jido.AI.Accuracy.{Config, Prm}
  alias Jido.AI.Helpers
  alias Jido.AI.Helpers.Text

  @type t :: %__MODULE__{
          model: String.t() | nil,
          prompt_template: String.t() | nil,
          score_range: {number(), number()},
          temperature: number(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          parallel: boolean()
        }

  defstruct model: nil,
            prompt_template: nil,
            score_range: {0.0, 1.0},
            temperature: 0.2,
            timeout: 30_000,
            max_retries: 2,
            parallel: false

  @default_step_prompt """
  You are an expert evaluator assessing reasoning steps.

  Original Question: <%= @question %>

  Reasoning Step to Evaluate:
  <%= @step %>

  <%= if length(@previous_steps) > 0 do %>
  Previous Steps (for context):
  <%= Enum.join(@previous_steps, "\\n") %>
  <% end %>

  Evaluate this reasoning step on a scale from <%= @min_score %> to <%= @max_score %>:
  - <%= @max_score %>: Correct and sound reasoning - logically valid, no errors
  - <%= @mid_score %>: Partially correct - on the right track but has issues
  - <%= @min_score %>: Incorrect - contains errors or flawed logic

  Also classify the step as:
  - correct: The step is logically sound and error-free
  - incorrect: The step contains errors or flawed reasoning
  - neutral: The step is ambiguous or cannot be determined

  Provide your response in the following format:
  Score: [numeric score]
  Classification: [correct|incorrect|neutral]
  """

  @default_trace_prompt """
  You are an expert evaluator assessing reasoning steps.

  Original Question: <%= @question %>

  Evaluate each of the following <%= @step_count %> reasoning steps on a scale from <%= @min_score %> to <%= @max_score %>:
  - <%= @max_score %>: Correct and sound reasoning - logically valid, no errors
  - <%= @mid_score %>: Partially correct - on the right track but has issues
  - <%= @min_score %>: Incorrect - contains errors or flawed logic

  Also classify each step as:
  - correct: The step is logically sound and error-free
  - incorrect: The step contains errors or flawed reasoning
  - neutral: The step is ambiguous or cannot be determined

  Reasoning Steps:
  <%= @formatted_steps %>

  For each step, provide:
  Step N: Score: [numeric score], Classification: [correct|incorrect|neutral]
  """

  @doc """
  Creates a new LLM PRM from the given attributes.

  ## Options

  - `:model` - Model to use (defaults to Config.default_model())
  - `:prompt_template` - Custom EEx template (uses default)
  - `:score_range` - {min, max} range for scores (default: {0.0, 1.0})
  - `:temperature` - Temperature for LLM (default: 0.2)
  - `:timeout` - Timeout in ms (default: 30_000)
  - `:max_retries` - Max retry attempts (default: 2)
  - `:parallel` - Score steps in parallel (default: false)

  ## Returns

  - `{:ok, prm}` - Success
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> LLMPrm.new([])
      {:ok, %LLMPrm{model: nil, score_range: {0.0, 1.0}}}

      iex> LLMPrm.new(%{score_range: {-1, 1}})
      {:ok, %LLMPrm{score_range: {-1, 1}}}

      iex> LLMPrm.new(%{score_range: {1, 0}})
      {:error, :invalid_score_range}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    prm = struct(__MODULE__, opts)

    with :ok <- validate_score_range(prm.score_range),
         :ok <- validate_temperature(prm.temperature),
         :ok <- validate_timeout(prm.timeout) do
      {:ok, prm}
    end
  end

  @doc """
  Creates a new LLM PRM, raising on error.

  ## Examples

      iex> LLMPrm.new!([])
      %LLMPrm{score_range: {0.0, 1.0}}

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, prm} -> prm
      {:error, reason} -> raise ArgumentError, "Invalid LLM PRM: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Scores a single reasoning step using an LLM.

  ## Examples

      prm = LLMPrm.new!([])
      {:ok, score} = LLMPrm.score_step(prm,
        "2 + 2 = 4",
        %{question: "What is 2 + 2?"},
        []
      )

  """
  @spec score_step(t(), String.t(), map(), keyword()) :: {:ok, number()} | {:error, term()}
  def score_step(%__MODULE__{} = prm, step, context, _opts) when is_binary(step) do
    question = Map.get(context, :question) || Map.get(context, :prompt) || ""
    previous_steps = Map.get(context, :previous_steps, [])

    template = prm.prompt_template || @default_step_prompt

    assigns = [
      question: question,
      step: step,
      previous_steps: previous_steps,
      min_score: elem(prm.score_range, 0),
      max_score: elem(prm.score_range, 1),
      mid_score: midpoint(prm.score_range)
    ]

    case render_template(template, assigns) do
      {:ok, prompt} ->
        case call_llm_with_retry(prm, prompt) do
          {:ok, response} ->
            score = extract_score(response.content, prm.score_range)
            {:ok, score}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @doc """
  Scores a full reasoning trace using an LLM.

  For efficiency, all steps are evaluated in a single LLM call when
  parallel is false. When parallel is true, each step is scored separately.

  ## Examples

      prm = LLMPrm.new!([])
      {:ok, scores} = LLMPrm.score_trace(prm, [
        "Step 1",
        "Step 2"
      ], %{question: "What is...?"}, [])

  """
  @spec score_trace(t(), [String.t()], map(), keyword()) :: {:ok, [number()]} | {:error, term()}
  def score_trace(%__MODULE__{} = prm, trace, context, opts) when is_list(trace) do
    if Enum.empty?(trace) do
      {:ok, []}
    else
      question = Map.get(context, :question) || Map.get(context, :prompt) || ""

      if prm.parallel do
        score_trace_parallel(prm, trace, context, opts)
      else
        score_trace_batch(prm, trace, question)
      end
    end
  end

  @impl true
  @doc """
  Classifies a reasoning step as correct, incorrect, or neutral.

  Classification is based on the step's score:
  - Score >= 70% of range: `:correct`
  - Score <= 30% of range: `:incorrect`
  - Otherwise: `:neutral`

  ## Examples

      prm = LLMPrm.new!([])
      {:ok, :correct} = LLMPrm.classify_step(prm, "Valid step", %{question: "?"}, [])

      {:ok, :incorrect} = LLMPrm.classify_step(prm, "Invalid step", %{question: "?"}, [])

  """
  @spec classify_step(t(), String.t(), map(), keyword()) ::
          {:ok, Prm.step_classification()} | {:error, term()}
  def classify_step(%__MODULE__{} = prm, step, context, opts) when is_binary(step) do
    case score_step(prm, step, context, opts) do
      {:ok, score} ->
        classification = score_to_classification(score, prm.score_range)
        {:ok, classification}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @doc """
  LLM PRM supports streaming for incremental evaluation.

  """
  @spec supports_streaming?() :: true
  def supports_streaming?, do: true

  # Private functions

  defp score_trace_batch(prm, trace, question) do
    template = prm.prompt_template || @default_trace_prompt

    # Pre-format steps for the template
    formatted_steps =
      trace
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {step, i} -> "#{i}. #{step}" end)

    assigns = [
      question: question,
      steps: trace,
      formatted_steps: formatted_steps,
      step_count: length(trace),
      min_score: elem(prm.score_range, 0),
      max_score: elem(prm.score_range, 1),
      mid_score: midpoint(prm.score_range)
    ]

    case render_template(template, assigns) do
      {:ok, prompt} ->
        case call_llm_with_retry(prm, prompt) do
          {:ok, response} ->
            scores = extract_trace_scores(response.content, length(trace), prm.score_range)
            {:ok, scores}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp score_trace_parallel(prm, trace, context, opts) do
    # Score each step independently with context from previous steps
    trace
    |> Enum.with_index()
    |> Task.async_stream(
      fn {step, index} ->
        previous_steps = Enum.slice(trace, 0, index)
        context_with_prev = Map.put(context, :previous_steps, previous_steps)

        case score_step(prm, step, context_with_prev, opts) do
          {:ok, score} -> score
          # Default to middle score on error
          {:error, _} -> midpoint(prm.score_range)
        end
      end,
      max_concurrency: 10,
      timeout: prm.timeout
    )
    |> Enum.map(fn
      {:ok, score} -> score
      {:exit, _} -> midpoint(prm.score_range)
    end)
    |> then(&{:ok, &1})
  end

  defp call_llm_with_retry(prm, prompt) do
    call_llm_with_retry(prm, prompt, prm.max_retries)
  end

  defp call_llm_with_retry(_prm, _prompt, 0) do
    {:error, :max_retries_exceeded}
  end

  defp call_llm_with_retry(prm, prompt, retries) do
    model = prm.model || Config.default_model()

    context =
      ReqLLM.Context.new()
      |> ReqLLM.Context.append(ReqLLM.Context.text(:user, prompt))

    reqllm_opts = [
      temperature: prm.temperature,
      receive_timeout: prm.timeout
    ]

    case ReqLLM.Generation.generate_text(model, context, reqllm_opts) do
      {:ok, response} ->
        content = extract_content(response)
        {:ok, %{content: content}}

      {:error, error} when retries > 0 ->
        case Helpers.classify_error(error) do
          :timeout ->
            call_llm_with_retry(prm, prompt, retries - 1)

          :rate_limit ->
            backoff = trunc(:math.pow(2, prm.max_retries - retries + 1) * 1000)
            Process.sleep(backoff)
            call_llm_with_retry(prm, prompt, retries - 1)

          :network ->
            Process.sleep(1000)
            call_llm_with_retry(prm, prompt, retries - 1)

          _ ->
            {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_content(response) do
    Text.extract_text(response)
  end

  defp extract_score(content, score_range) do
    patterns = [
      ~r/Score:\s*(-?\d+\.?\d*)/i,
      ~r/score:\s*(-?\d+\.?\d*)/i,
      ~r/Step Score:\s*(-?\d+\.?\d*)/i,
      ~r/step score:\s*(-?\d+\.?\d*)/i,
      ~r/Rating:\s*(-?\d+\.?\d*)/i
    ]

    score =
      Enum.find_value(patterns, fn pattern ->
        case Regex.run(pattern, content) do
          [_, score_str] ->
            parse_score_value(score_str)

          _ ->
            nil
        end
      end)

    {min_score, max_score} = score_range
    default_score = midpoint(score_range)

    cond do
      score == nil -> default_score
      score < min_score -> min_score
      score > max_score -> max_score
      true -> score
    end
  end

  defp extract_trace_scores(content, step_count, score_range) do
    # Try to extract scores in format "Step N: Score: X"
    pattern = ~r/Step\s*(\d+):\s*(?:.*?\s*)?Score:\s*(-?\d+\.?\d*)/i

    captures = Regex.scan(pattern, content)

    if Enum.empty?(captures) do
      # Try alternative format: just scores in order
      extract_scores_simple(content, step_count, score_range)
    else
      # Build map of step index to score
      scores_map =
        Map.new(captures, fn [_, index_str, score_str] ->
          {String.to_integer(index_str) - 1, parse_score_value(score_str)}
        end)

      # Convert to list in order
      0..(step_count - 1)
      |> Enum.map(fn index ->
        Map.get(scores_map, index, midpoint(score_range))
      end)
    end
  end

  defp extract_scores_simple(content, step_count, score_range) do
    # Extract all numeric scores from content
    pattern = ~r/(?:Score|Rating):\s*(-?\d+\.?\d*)/i

    scores =
      Regex.scan(pattern, content)
      |> Enum.map(fn [_, score_str] -> parse_score_value(score_str) end)

    # Pad or truncate to match step_count
    case length(scores) do
      n when n < step_count ->
        scores ++ List.duplicate(midpoint(score_range), step_count - n)

      n when n > step_count ->
        Enum.take(scores, step_count)

      _ ->
        scores
    end
  end

  defp parse_score_value(str) do
    case Float.parse(str) do
      {score, ""} ->
        score

      {score, _rest} ->
        score

      :error ->
        case Integer.parse(str) do
          {score, ""} -> score * 1.0
          {score, _rest} -> score * 1.0
          :error -> nil
        end
    end
  end

  defp score_to_classification(score, {min_score, max_score}) do
    range = max_score - min_score
    normalized = (score - min_score) / range

    cond do
      normalized >= 0.7 -> :correct
      normalized <= 0.3 -> :incorrect
      true -> :neutral
    end
  end

  defp midpoint({min, max}), do: (min + max) / 2

  defp render_template(template, assigns) do
    rendered = Jido.AI.Accuracy.Helpers.eval_eex_quiet(template, assigns: assigns)
    {:ok, rendered}
  rescue
    e in [SyntaxError, TokenMissingError, ArgumentError] ->
      {:error, {:template_error, Exception.message(e)}}
  end

  # Validation

  defp validate_score_range({min, max}) when is_number(min) and is_number(max) and min < max, do: :ok

  defp validate_score_range(_), do: {:error, :invalid_score_range}

  defp validate_temperature(temp) when is_number(temp) and temp >= 0 and temp <= 2, do: :ok
  defp validate_temperature(_), do: {:error, :invalid_temperature}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}
  defp format_error(atom) when is_atom(atom), do: atom
end
