defmodule Jido.AI.Actions.Reasoning.Explain do
  @moduledoc """
  A Jido.Action for getting clear explanations of complex topics.

  This action uses ReqLLM with specialized system prompts to explain topics
  at different detail levels (basic, intermediate, advanced).

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:reasoning`) or direct spec
  * `topic` (required) - The topic to explain
  * `detail_level` (optional) - Detail level: `:basic`, `:intermediate`, `:advanced`
  * `audience` (optional) - Target audience description
  * `include_examples` (optional) - Whether to include examples (default: `true`)
  * `max_tokens` (optional) - Maximum tokens to generate (default: `2048`)
  * `temperature` (optional) - Sampling temperature (default: `0.5`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic explanation
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Reasoning.Explain, %{
        topic: "Recursion",
        detail_level: :basic
      })

      # Advanced explanation
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Reasoning.Explain, %{
        topic: "Tail Call Optimization",
        detail_level: :advanced,
        audience: "Elixir developers"
      })

      # Without examples
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Reasoning.Explain, %{
        topic: "Machine Learning",
        detail_level: :intermediate,
        include_examples: false
      })
  """

  use Jido.Action,
    name: "reasoning_explain",
    description: "Get explanations for complex topics at different detail levels",
    category: "ai",
    tags: ["reasoning", "explanation", "teaching"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :reasoning) or direct model spec string")
          |> Zoi.optional(),
        topic: Zoi.string(description: "The topic to explain"),
        detail_level:
          Zoi.atom(description: "Detail level: :basic, :intermediate, or :advanced")
          |> Zoi.default(:intermediate),
        audience: Zoi.string(description: "Target audience description") |> Zoi.optional(),
        include_examples: Zoi.boolean(description: "Whether to include examples") |> Zoi.default(true),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(2048),
        temperature: Zoi.float(description: "Sampling temperature") |> Zoi.default(0.5),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers
  alias Jido.AI.Security
  alias Jido.AI.Turn
  alias ReqLLM.Context

  @basic_prompt """
  You are an expert teacher explaining concepts to beginners.

  Your goal is to make complex topics accessible to someone with no prior knowledge.
  Use simple language, avoid jargon (or explain it when necessary), and use relatable
  analogies and examples.

  Structure your explanation to include:
  - A simple, clear definition
  - Why the topic matters
  - Key concepts in simple terms
  - Relatable examples
  - Common misconceptions to avoid
  """

  @intermediate_prompt """
  You are an expert teacher explaining concepts to learners with some familiarity.

  Your goal is to provide a clear explanation that builds on existing knowledge.
  Use appropriate technical terms while ensuring clarity, and include practical examples.

  Structure your explanation to include:
  - A clear definition
  - How it relates to common concepts
  - Key components and how they work
  - Practical examples
  - Common use cases
  """

  @advanced_prompt """
  You are an expert teacher explaining concepts to advanced learners or practitioners.

  Your goal is to provide deep technical detail appropriate for someone seeking expertise.
  Use precise terminology, discuss edge cases and considerations, and include advanced examples.

  Structure your explanation to include:
  - Precise technical definition
  - Underlying principles and mechanisms
  - Advanced considerations and edge cases
  - Best practices and patterns
  - Common pitfalls and how to avoid them
  """

  @doc """
  Executes the explain action.

  ## Returns

  * `{:ok, result}` - Successful response with `result`, `detail_level`, `model`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        result: "The explanation text",
        detail_level: :intermediate,
        model: "anthropic:claude-sonnet-4-20250514",
        usage: %{...}
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, model} <- resolve_model(params[:model]),
         {:ok, validated_params} <- validate_and_sanitize_params(params),
         {:ok, req_context} <- build_explanation_messages(validated_params),
         opts = build_opts(validated_params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, req_context.messages, opts) do
      {:ok, format_result(response, model, validated_params[:detail_level])}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Jido.AI.resolve_model(:reasoning)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Jido.AI.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_explanation_messages(params) do
    system_prompt = build_explanation_system_prompt(params[:detail_level], params[:include_examples])
    user_prompt = build_explanation_user_prompt(params)
    Context.normalize(user_prompt, system_prompt: system_prompt)
  end

  defp build_explanation_system_prompt(:basic, include_examples?) do
    prompt = @basic_prompt

    if include_examples? do
      prompt <> "\n\nAlways include simple, relatable examples to illustrate key points."
    else
      prompt
    end
  end

  defp build_explanation_system_prompt(:intermediate, include_examples?) do
    prompt = @intermediate_prompt

    if include_examples? do
      prompt <> "\n\nAlways include practical examples to illustrate key points."
    else
      prompt
    end
  end

  defp build_explanation_system_prompt(:advanced, include_examples?) do
    prompt = @advanced_prompt

    if include_examples? do
      prompt <> "\n\nAlways include advanced examples or code snippets to illustrate key points."
    else
      prompt
    end
  end

  defp build_explanation_user_prompt(params) do
    base = "Explain: #{params[:topic]}"

    case params[:audience] do
      nil -> base
      # Audience is already validated in validate_and_sanitize_params
      audience when is_binary(audience) -> base <> "\n\nTarget Audience: " <> audience
    end
  end

  # Validates and sanitizes input parameters to prevent security issues
  defp validate_and_sanitize_params(params) do
    with {:ok, _topic} <-
           Security.validate_string(params[:topic], max_length: Security.max_input_length()),
         {:ok, _validated} <- validate_audience_if_needed(params) do
      {:ok, params}
    else
      {:error, :empty_string} -> {:error, :topic_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_audience_if_needed(%{audience: audience}) when is_binary(audience) do
    Security.validate_string(audience, max_length: 1000)
  end

  defp validate_audience_if_needed(_params), do: {:ok, nil}

  defp build_opts(params) do
    opts = [
      max_tokens: params[:max_tokens],
      temperature: params[:temperature]
    ]

    opts =
      if params[:timeout] do
        Keyword.put(opts, :receive_timeout, params[:timeout])
      else
        opts
      end

    opts
  end

  defp format_result(response, model, detail_level) do
    %{
      result: Turn.extract_text(response),
      detail_level: detail_level,
      model: model,
      usage: Helpers.extract_usage(response)
    }
  end
end
