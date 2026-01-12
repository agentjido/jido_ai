defmodule Jido.AI.Accuracy.Critiquers.LLMCritiquer do
  @moduledoc """
  LLM-based critiquer that uses a language model to analyze and critique candidates.

  This critiquer sends candidate responses to an LLM with a structured prompt
  asking for analysis of issues, suggestions for improvement, and severity scoring.

  ## Configuration

  - `:model` - Model to use for critique (default: from Config)
  - `:prompt_template` - Custom EEx template for critique prompt
  - `:temperature` - Temperature for LLM calls (default: 0.3)
  - `:timeout` - Timeout for LLM calls in ms (default: 30_000)
  - `:max_retries` - Maximum retry attempts (default: 2)
  - `:domain` - Optional domain for specialized critique (e.g., :math, :code)

  ## Usage

      # Create critiquer with defaults
      critiquer = LLMCritiquer.new!(%{})

      # Critique a candidate
      {:ok, critique} = LLMCritiquer.critique(critiquer, candidate, %{
        prompt: "What is 15 * 23?"
      })

      critique.issues  # => ["Calculation error"]
      critique.suggestions  # => ["Re-check the math"]
      critique.severity  # => 0.7

  ## Critique Format

  The LLM is asked to provide:
  - Issues: List of identified problems
  - Suggestions: List of improvement suggestions
  - Severity: Score from 0.0 (no issues) to 1.0 (critical issues)

  ## Prompt Template

  The default prompt template uses EEx interpolation with these variables:
  - `@prompt` - The original question/prompt
  - `@candidate` - The candidate being critiqued
  - `@domain` - Optional domain for specialized critique

  ## Security

  Candidate content is sanitized before being interpolated into prompts to prevent
  prompt injection attacks:
  - Content is truncated to `max_content_length`
  - Special delimiter markers are used to delineate content
  - JSON output is requested for structured parsing

  """

  @behaviour Jido.AI.Accuracy.Critique

  alias Jido.AI.Accuracy.{Candidate, Config, CritiqueResult}
  alias Jido.AI.Config, as: MainConfig

  @type t :: %__MODULE__{
          model: String.t(),
          prompt_template: String.t() | nil,
          temperature: number(),
          timeout: pos_integer(),
          max_retries: non_neg_integer(),
          domain: atom() | nil
        }

  defstruct [
    :model,
    prompt_template: nil,
    temperature: 0.3,
    timeout: 30_000,
    max_retries: 2,
    domain: nil
  ]

  @default_prompt_template """
  You are an expert critic analyzing answers for quality and correctness.

  Original Question: <%= @prompt %>

  === CANDIDATE ANSWER BEGINS ===
  <%= @candidate.content %>
  === CANDIDATE ANSWER ENDS ===

  Analyze this answer and provide a critique in the following JSON format:

  ```json
  {
    "issues": ["list of identified issues"],
    "suggestions": ["list of specific improvement suggestions"],
    "severity": <number from 0.0 to 1.0>,
    "feedback": "overall feedback summary"
  }
  ```

  Severity guidelines:
  - 0.0-0.3: Minor issues, optional improvements
  - 0.3-0.7: Notable issues that should be addressed
  - 0.7-1.0: Critical issues that must be addressed

  <%= if @domain do %>
  Domain-specific considerations for <%= @domain %>:
  <%= @domain_guidelines %>
  <% end %>

  JSON:
  """

  @domain_guidelines %{
    math: "- Check calculation accuracy\n- Verify mathematical reasoning\n- Look for calculation errors",
    code: "- Check for syntax errors\n- Verify logic correctness\n- Look for edge cases not handled",
    writing: "- Check grammar and spelling\n- Evaluate clarity and coherence\n- Look for structural issues",
    reasoning: "- Check logical consistency\n- Verify conclusion follows from premises\n- Look for missing steps"
  }

  @doc """
  Creates a new LLM critiquer from the given attributes.

  ## Options

  - `:model` - Model to use (defaults to Config.default_model())
  - `:prompt_template` - Custom EEx template for critique
  - `:temperature` - Temperature for LLM (default: 0.3)
  - `:timeout` - Timeout in ms (default: 30_000)
  - `:max_retries` - Max retry attempts (default: 2)
  - `:domain` - Optional domain atom for specialized critique

  ## Returns

  - `{:ok, critiquer}` - Success
  - `{:error, reason}` - Validation failed

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) when is_list(opts) do
    model = Keyword.get(opts, :model, Config.default_model())

    # Resolve model alias if atom
    resolved_model =
      case model do
        atom when is_atom(atom) -> MainConfig.resolve_model(atom)
        binary when is_binary(binary) -> binary
      end

    # Validate model
    with :ok <- validate_model(resolved_model),
         :ok <- validate_temperature(Keyword.get(opts, :temperature, 0.3)),
         :ok <- validate_timeout(Keyword.get(opts, :timeout, 30_000)) do
      critiquer = struct(__MODULE__, [
        model: resolved_model,
        prompt_template: Keyword.get(opts, :prompt_template),
        temperature: Keyword.get(opts, :temperature, 0.3),
        timeout: Keyword.get(opts, :timeout, 30_000),
        max_retries: Keyword.get(opts, :max_retries, 2),
        domain: Keyword.get(opts, :domain)
      ])

      {:ok, critiquer}
    end
  end

  @doc """
  Creates a new LLM critiquer, raising on error.

  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, critiquer} -> critiquer
      {:error, reason} -> raise ArgumentError, "Invalid LLMCritiquer: #{inspect(reason)}"
    end
  end

  @impl true
  @spec critique(t(), Candidate.t(), map()) :: {:ok, CritiqueResult.t()} | {:error, term()}
  def critique(%__MODULE__{} = critiquer, %Candidate{} = candidate, context) do
    prompt = Map.get(context, :prompt, "")

    with {:ok, rendered_prompt} <- render_prompt(critiquer, candidate, prompt),
         {:ok, response} <- call_llm(critiquer, rendered_prompt),
         {:ok, parsed} <- parse_critique(response) do
      result = CritiqueResult.new!(%{
        issues: Map.get(parsed, "issues", []),
        suggestions: Map.get(parsed, "suggestions", []),
        severity: Map.get(parsed, "severity", 0.5),
        feedback: Map.get(parsed, "feedback", ""),
        actionable: true,
        metadata: %{critiquer: :llm, model: critiquer.model}
      })

      {:ok, result}
    end
  end

  # Private functions

  defp render_prompt(%__MODULE__{} = critiquer, candidate, prompt) do
    template = critiquer.prompt_template || @default_prompt_template

    # Build sanitized candidate assign
    sanitized_content = sanitize_content(candidate.content || "")
    domain_guidelines_text = if critiquer.domain, do: domain_guidelines(critiquer.domain), else: ""

    assigns = [
      prompt: prompt,
      candidate: %{candidate | content: sanitized_content},
      domain: critiquer.domain,
      domain_guidelines: domain_guidelines_text
    ]

    try do
      rendered = EEx.eval_string(template, assigns: assigns)
      {:ok, rendered}
    rescue
      e ->
        {:error, {:template_error, Exception.message(e)}}
    end
  end

  defp sanitize_content(content) when is_binary(content) do
    # Truncate very long content to prevent token overflow
    max_length = 10_000
    String.slice(content, 0, max_length)
  end

  defp domain_guidelines(domain) when is_atom(domain) do
    Map.get(@domain_guidelines, domain, "")
  end

  defp call_llm(%__MODULE__{} = critiquer, prompt) do
    model = critiquer.model || Config.default_model()

    messages = [%ReqLLM.Message{role: :user, content: prompt}]

    reqllm_opts = [
      temperature: critiquer.temperature,
      receive_timeout: critiquer.timeout
    ]

    try do
      case ReqLLM.Generation.generate_text(model, messages, reqllm_opts) do
        {:ok, response} ->
          content = extract_content(response)

          if content do
            {:ok, content}
          else
            {:error, :no_content}
          end

        {:error, reason} ->
          {:error, {:llm_error, reason}}
      end
    rescue
      e ->
        {:error, {:llm_exception, Exception.message(e)}}
    end
  end

  defp extract_content(response) do
    case response.message.content do
      nil -> ""
      content when is_binary(content) -> content
      content when is_list(content) ->
        content
        |> Enum.filter(fn %{type: type} -> type == :text end)
        |> Enum.map_join("", fn %{text: text} -> text end)
    end
  end

  defp parse_critique(response) when is_binary(response) do
    # Try to extract JSON from the response
    json_str = extract_json(response)

    case Jason.decode(json_str) do
      {:ok, parsed} when is_map(parsed) ->
        {:ok, parsed}

      {:error, _} ->
        # Fallback: try to parse structured text
        {:ok, parse_fallback(response)}
    end
  end

  defp extract_json(response) do
    # Look for JSON code blocks
    json_block_regex = ~r/```json\s*(\{.*?\})\s*```/s
    code_block_regex = ~r/```\s*(\{.*?\})\s*```/s
    plain_json_regex = ~r/(\{[^{}]*"issues"[^{}]*\})/s

    cond do
      Regex.run(json_block_regex, response) != nil ->
        [[_, match]] = Regex.run(json_block_regex, response, capture: :all)
        match

      Regex.run(code_block_regex, response) != nil ->
        [[_, match]] = Regex.run(code_block_regex, response, capture: :all)
        match

      Regex.run(plain_json_regex, response) != nil ->
        [[_, match]] = Regex.run(plain_json_regex, response, capture: :all)
        match

      true ->
        response
    end
  end

  defp parse_fallback(response) do
    # Try to extract issues, suggestions, severity from text
    issues =
      ~r/(?:issues?|problems?|errors?):\s*([^\n]*)/i
      |> Regex.scan(response)
      |> Enum.map(fn [_, match] -> String.trim(match) end)
      |> Enum.filter(fn s -> s != "" end)

    suggestions =
      ~r/(?:suggestions?|improvements?|fixes?):\s*([^\n]*)/i
      |> Regex.scan(response)
      |> Enum.map(fn [_, match] -> String.trim(match) end)
      |> Enum.filter(fn s -> s != "" end)

    # Try to find severity score
    severity =
      case Regex.run(~r/(?:severity|score|rating):\s*([0-9.]+)/i, response) do
        [_, score] ->
          case Float.parse(score) do
            {s, ""} -> s / 1.0
            _ -> 0.5
          end

        _ ->
          0.5
      end

    %{
      "issues" => issues,
      "suggestions" => suggestions,
      "severity" => severity,
      "feedback" => String.slice(response, 0, 500)
    }
  end

  # Validation

  defp validate_model(model) when is_binary(model) and model != "", do: :ok
  defp validate_model(_), do: {:error, :invalid_model}

  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 2.0, do: :ok
  defp validate_temperature(_), do: {:error, :invalid_temperature}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout >= 1000 and timeout <= 300_000,
    do: :ok

  defp validate_timeout(_), do: {:error, :invalid_timeout}
end
