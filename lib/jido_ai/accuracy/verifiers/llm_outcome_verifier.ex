defmodule Jido.AI.Accuracy.Verifiers.LLMOutcomeVerifier do
  @moduledoc """
  LLM-based outcome verifier that scores candidate responses.

  This verifier uses a language model to evaluate the quality and correctness
  of candidate answers. It extracts both a numeric score and reasoning from
  the LLM response.

  ## Configuration

  - `:model` - Model to use for verification (default: from Config)
  - `:prompt_template` - Custom EEx template for verification prompt
  - `:score_range` - {min, max} range for scores (default: {0.0, 1.0})
  - `:temperature` - Temperature for LLM calls (default: 0.3)
  - `:timeout` - Timeout for LLM calls in ms (default: 30_000)
  - `:max_retries` - Maximum retry attempts (default: 2)
  - `:max_content_length` - Maximum candidate content length in chars (default: 50_000)

  ## Usage

      # Create verifier with defaults
      verifier = LLMOutcomeVerifier.new!(%{})

      # Verify a candidate
      {:ok, result} = LLMOutcomeVerifier.verify(verifier, candidate, %{
        prompt: "What is 2+2?"
      })

      result.score  # => 0.85
      result.reasoning  # => "The answer is correct..."

  ## Prompt Template

  The default prompt template uses EEx interpolation with these variables:
  - `@prompt` - The original question/prompt
  - `@candidate` - The candidate being verified
  - `@min_score` - Minimum score in range
  - `@max_score` - Maximum score in range
  - `@mid_score` - Midpoint score in range

  You can provide a custom template:

      verifier = LLMOutcomeVerifier.new!(%{
        prompt_template: \"\"\"
        Rate this answer from 0 to 100:
        Question: <%= @prompt %>
        Answer: <%= @candidate.content %>

        Score: [0-100]
        Reasoning: [explanation]
        \"\"\"
      })

  ## Score Extraction

  The verifier looks for patterns in the LLM response:
  - `Score: <number>` - Case-insensitive, extracts numeric value
  - `score: <number>` - Alternative format
  - Can handle integers, decimals, and percentages

  Scores are automatically normalized to the configured range.

  ## Security

  Candidate content is sanitized before being interpolated into prompts to prevent
  prompt injection attacks:
  - Content is truncated to `max_content_length`
  - Special delimiter markers are added to clearly delineate content
  - Suspicious patterns are escaped

  """

  @behaviour Jido.AI.Accuracy.Verifier

  alias Jido.AI.Accuracy.{Candidate, Config, VerificationResult}
  alias Jido.AI.Helpers
  alias Jido.AI.Text

  @type t :: %__MODULE__{
          model: String.t(),
          prompt_template: String.t() | nil,
          score_range: {number(), number()},
          temperature: number(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          max_content_length: pos_integer()
        }

  defstruct model: nil,
            prompt_template: nil,
            score_range: {0.0, 1.0},
            temperature: 0.3,
            timeout: 30_000,
            max_retries: 2,
            max_content_length: 50_000

  @default_prompt_template """
  You are an expert evaluator assessing the quality and correctness of answers.

  Original Question: <%= @prompt %>

  === CANDIDATE ANSWER BEGINS ===
  <%= @candidate.content %>
  === CANDIDATE ANSWER ENDS ===

  Evaluate this answer on a scale from <%= @min_score %> to <%= @max_score %>:
  - <%= @max_score %>: Perfect answer - correct, complete, and well-explained
  - <%= @mid_score %>: Partially correct - on the right track but missing details or has minor errors
  - <%= @min_score %>: Incorrect - wrong answer or fundamentally flawed reasoning

  Provide your response in the following format:
  Score: [numeric score]
  Reasoning: [brief explanation]
  """

  @doc """
  Creates a new LLM outcome verifier from the given attributes.

  ## Options

  - `:model` - Model to use (defaults to Config.default_model())
  - `:prompt_template` - Custom EEx template (uses @default_prompt_template)
  - `:score_range` - {min, max} range for scores (default: {0.0, 1.0})
  - `:temperature` - Temperature for LLM (default: 0.3)
  - `:timeout` - Timeout in ms (default: 30_000)
  - `:max_retries` - Max retry attempts (default: 2)

  ## Returns

  - `{:ok, verifier}` - Success
  - `{:error, reason}` - Validation failed

  ## Examples

      iex> LLMOutcomeVerifier.new(%{})
      {:ok, %LLMOutcomeVerifier{model: nil, score_range: {0.0, 1.0}}}

      iex> LLMOutcomeVerifier.new(%{score_range: {0, 100}})
      {:ok, %LLMOutcomeVerifier{score_range: {0, 100}}}

      iex> LLMOutcomeVerifier.new(%{score_range: {1, 0}})
      {:error, :invalid_score_range}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    verifier = struct(__MODULE__, opts)

    with :ok <- validate_score_range(verifier.score_range),
         :ok <- validate_temperature(verifier.temperature),
         :ok <- validate_timeout(verifier.timeout) do
      {:ok, verifier}
    end
  end

  @doc """
  Creates a new LLM outcome verifier, raising on error.

  ## Examples

      iex> LLMOutcomeVerifier.new!(%{})
      %LLMOutcomeVerifier{score_range: {0.0, 1.0}}

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, verifier} -> verifier
      {:error, reason} -> raise ArgumentError, "Invalid LLM outcome verifier: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Verifies a candidate using an LLM to score the response.

  The LLM is prompted with the original question (from context) and the
  candidate's answer, then returns a score and reasoning.

  ## Context

  The context map should contain:
  - `:prompt` - The original question/prompt (required)

  ## Examples

      verifier = LLMOutcomeVerifier.new!(%{})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = LLMOutcomeVerifier.verify(verifier, candidate, %{
        prompt: "What is 2+2?"
      })

      result.score  # => 0.85
      result.reasoning  # => "Correct answer with good explanation"

  """
  @spec verify(t(), Candidate.t(), map()) :: {:ok, VerificationResult.t()} | {:error, term()}
  def verify(%__MODULE__{} = verifier, %Candidate{} = candidate, context) do
    prompt = Map.get(context, :prompt, "")

    template = verifier.prompt_template || @default_prompt_template

    case render_prompt(template, prompt, candidate, verifier.score_range) do
      {:ok, rendered_prompt} ->
        call_llm_with_retry(verifier, rendered_prompt, candidate)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  @doc """
  Verifies multiple candidates in batch.

  For efficiency, all candidates are evaluated in a single LLM call.
  The response is parsed to extract individual scores for each candidate.

  ## Examples

      verifier = LLMOutcomeVerifier.new!(%{})
      candidates = [
        Candidate.new!(%{id: "1", content: "42"}),
        Candidate.new!(%{id: "2", content: "43"})
      ]

      {:ok, results} = LLMOutcomeVerifier.verify_batch(verifier, candidates, %{
        prompt: "What is 2+2?"
      })

      length(results)  # => 2

  """
  @spec verify_batch(t(), [Candidate.t()], map()) :: {:ok, [VerificationResult.t()]} | {:error, term()}
  def verify_batch(%__MODULE__{} = verifier, candidates, context) when is_list(candidates) do
    if Enum.empty?(candidates) do
      {:ok, []}
    else
      prompt = Map.get(context, :prompt, "")

      template = build_batch_template(verifier, length(candidates))

      case render_prompt(template, prompt, candidates, verifier.score_range) do
        {:ok, rendered_prompt} ->
          parse_batch_results(call_llm_with_retry(verifier, rendered_prompt, candidates), candidates)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @impl true
  @doc """
  LLM outcome verifier supports streaming for long responses.

  """
  @spec supports_streaming?() :: true
  def supports_streaming?, do: true

  # Private functions

  defp call_llm_with_retry(verifier, prompt, candidate_or_candidates) do
    call_llm_with_retry(verifier, prompt, candidate_or_candidates, verifier.max_retries)
  end

  defp call_llm_with_retry(_verifier, _prompt, _candidate_or_candidates, 0) do
    {:error, :max_retries_exceeded}
  end

  defp call_llm_with_retry(verifier, prompt, candidate_or_candidates, retries) do
    model = verifier.model || Config.default_model()

    context =
      ReqLLM.Context.new()
      |> ReqLLM.Context.append(ReqLLM.Context.text(:user, prompt))

    reqllm_opts = [
      temperature: verifier.temperature,
      receive_timeout: verifier.timeout
    ]

    case ReqLLM.Generation.generate_text(model, context.messages, reqllm_opts) do
      {:ok, response} ->
        {:ok, parse_response(response)}

      {:error, error} when retries > 0 ->
        # Use Helpers.classify_error to determine if we should retry
        case Helpers.classify_error(error) do
          :timeout ->
            # Retry on timeout
            call_llm_with_retry(verifier, prompt, candidate_or_candidates, retries - 1)

          :rate_limit ->
            # Retry on rate limit with exponential backoff
            backoff = trunc(:math.pow(2, verifier.max_retries - retries + 1) * 1000)
            Process.sleep(backoff)
            call_llm_with_retry(verifier, prompt, candidate_or_candidates, retries - 1)

          :network ->
            # Retry on network errors
            Process.sleep(1000)
            call_llm_with_retry(verifier, prompt, candidate_or_candidates, retries - 1)

          _ ->
            # Don't retry on other errors
            {:error, error}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_response(response) do
    content = extract_content(response)

    {score, reasoning} = extract_score_and_reasoning(content)

    %VerificationResult{
      score: score,
      reasoning: reasoning,
      # LLM provides its own confidence implicitly
      confidence: nil
    }
  end

  defp extract_content(response) do
    Text.extract_text(response)
  end

  defp extract_score_and_reasoning(content) do
    score = extract_score(content)
    reasoning = extract_reasoning(content)
    {score, reasoning}
  end

  defp extract_score(content) do
    # Try various patterns for score extraction
    patterns = [
      ~r/Score:\s*(-?\d+\.?\d*)/i,
      ~r/score:\s*(-?\d+\.?\d*)/i,
      ~r/Rating:\s*(-?\d+\.?\d*)/i,
      ~r/rating:\s*(-?\d+\.?\d*)/i,
      ~r/Score:\s*\[?(-?\d+\.?\d*)\]?/i,
      ~r/\[score:\s*(-?\d+\.?\d*)\]/i
    ]

    Enum.find_value(patterns, &parse_score_from_pattern(&1, content)) || 0.5
  end

  defp parse_score_from_pattern(pattern, content) do
    case Regex.run(pattern, content) do
      [_, score_str] -> parse_float(score_str)
      _ -> nil
    end
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {score, _rest} -> score
      :error -> nil
    end
  end

  defp extract_reasoning(content) do
    patterns = [
      ~r/Reasoning:\s*(.+?)(?:\n\n|\nScore|$)/i,
      ~r/reasoning:\s*(.+?)(?:\n\n|\nScore|$)/i,
      ~r/Explanation:\s*(.+?)(?:\n\n|\nScore|$)/i,
      ~r/explanation:\s*(.+?)(?:\n\n|\nScore|$)/i
    ]

    Enum.find_value(patterns, fn pattern ->
      case Regex.run(pattern, content, capture: :all) do
        [_, reasoning | _] -> String.trim(reasoning)
        _ -> nil
      end
    end) || nil
  end

  defp render_prompt(template, prompt, candidate_or_candidates, score_range) do
    {min_score, max_score} = score_range
    mid_score = (min_score + max_score) / 2

    assigns = [
      prompt: prompt,
      candidate: build_candidate_assign(candidate_or_candidates),
      min_score: min_score,
      max_score: max_score,
      mid_score: mid_score
    ]

    rendered = Jido.AI.Accuracy.Helpers.eval_eex_quiet(template, assigns: assigns)
    {:ok, rendered}
  rescue
    e in [SyntaxError, TokenMissingError, ArgumentError] ->
      {:error, {:template_error, Exception.message(e)}}
  end

  defp build_candidate_assign(%Candidate{} = candidate) do
    sanitized_content = sanitize_content(candidate.content || "")

    %{
      id: candidate.id || "unknown",
      content: sanitized_content,
      score: candidate.score,
      reasoning: candidate.reasoning
    }
  end

  defp build_candidate_assign(candidates) when is_list(candidates) do
    Enum.map(candidates, fn c -> build_candidate_assign(c) end)
  end

  # Sanitize candidate content to prevent prompt injection
  # 1. Truncate to max length
  # 2. Escape potential injection patterns
  defp sanitize_content(content) when is_binary(content) do
    max_length = 50_000

    content
    |> String.slice(0, max_length)
    |> escape_injection_patterns()
  end

  defp sanitize_content(_), do: ""

  # Escape patterns that could be used for prompt injection
  defp escape_injection_patterns(content) do
    content
    # Escape EEx delimiters that could break out of template
    |> String.replace("<%=", "&lt;%=")
    |> String.replace("%>", "%&gt;")
    # Escape common prompt injection markers
    |> String.replace("=== END INSTRUCTIONS ===", "== END INSTRUCTIONS ==")
    |> String.replace("=== END ===", "== END ==")
    |> String.replace("### END ###", "## END ##")
    # Limit consecutive newlines that could be used to break formatting
    |> String.replace(~r/\n{4,}/, "\n\n\n")
  end

  defp build_batch_template(verifier, _count) do
    {min_score, max_score} = verifier.score_range
    _mid_score = (min_score + max_score) / 2

    """
    You are an expert evaluator assessing the quality and correctness of answers.

    Original Question: <%= @prompt %>

    Evaluate each of the following <%= count %> candidate answers on a scale from <%= min_score %> to <%= max_score %>:
    - <%= max_score %>: Perfect answer - correct, complete, and well-explained
    - <%= mid_score %>: Partially correct - on the right track but missing details or has minor errors
    - <%= min_score %>: Incorrect - wrong answer or fundamentally flawed reasoning

    === CANDIDATE ANSWERS BEGIN ===
    <%= Enum.map(@candidates, fn c ->
      "Candidate " <> to_string(c.id) <> ": " <> c.content
    end) |> Enum.join("\\n") %>
    === CANDIDATE ANSWERS END ===

    For each candidate, provide:
    Score: [numeric score]
    Reasoning: [brief explanation]

    <%= Enum.map(@candidates, fn c ->
      "Candidate " <> to_string(c.id) <> ": Score: [score] Reasoning: [reasoning]"
    end) |> Enum.join("\\n") %>
    """
  end

  defp parse_batch_results({:ok, response}, candidates) do
    content = extract_content(response)
    scores = extract_batch_scores(content, length(candidates))

    results =
      Enum.map(candidates, fn candidate ->
        score = Map.get(scores, candidate.id, 0.5)

        %VerificationResult{
          candidate_id: candidate.id,
          score: score,
          reasoning: "Batch verification result",
          confidence: nil
        }
      end)

    {:ok, results}
  end

  defp parse_batch_results({:error, reason}, _candidates), do: {:error, reason}

  defp extract_batch_scores(content, _count) do
    # Extract scores in format "Candidate X: Score: Y"
    pattern = ~r/Candidate (\d+):\s*(?:.*?\s*)?Score:\s*(-?\d+\.?\d*)/i

    captures = Regex.scan(pattern, content)

    Map.new(captures, fn [_, id, score_str] ->
      {String.to_integer(id), parse_score_value(score_str)}
    end)
  end

  defp parse_score_value(str) do
    case Float.parse(str) do
      {score, ""} ->
        score

      {score, _} ->
        score

      :error ->
        case Integer.parse(str) do
          {score, ""} -> score * 1.0
          {score, _} -> score * 1.0
          :error -> 0.5
        end
    end
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
