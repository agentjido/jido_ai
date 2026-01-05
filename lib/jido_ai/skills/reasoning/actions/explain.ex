defmodule Jido.AI.Skills.Reasoning.Actions.Explain do
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
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Reasoning.Actions.Explain, %{
        topic: "Recursion",
        detail_level: :basic
      })

      # Advanced explanation
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Reasoning.Actions.Explain, %{
        topic: "Tail Call Optimization",
        detail_level: :advanced,
        audience: "Elixir developers"
      })

      # Without examples
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Reasoning.Actions.Explain, %{
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
    schema: [
      model: [
        type: :string,
        required: false,
        doc: "Model spec (e.g., 'anthropic:claude-sonnet-4-20250514') or alias (e.g., :reasoning)"
      ],
      topic: [
        type: :string,
        required: true,
        doc: "The topic to explain"
      ],
      detail_level: [
        type: {:in, [:basic, :intermediate, :advanced]},
        required: false,
        default: :intermediate,
        doc: "Detail level: :basic, :intermediate, or :advanced"
      ],
      audience: [
        type: :string,
        required: false,
        doc: "Target audience description"
      ],
      include_examples: [
        type: :boolean,
        required: false,
        default: true,
        doc: "Whether to include examples"
      ],
      max_tokens: [
        type: :integer,
        required: false,
        default: 2048,
        doc: "Maximum tokens to generate"
      ],
      temperature: [
        type: :float,
        required: false,
        default: 0.5,
        doc: "Sampling temperature"
      ],
      timeout: [
        type: :integer,
        required: false,
        doc: "Request timeout in milliseconds"
      ]
    ]

  alias Jido.AI.Config
  alias Jido.AI.Helpers

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
         {:ok, messages} <- build_explanation_messages(params),
         opts = build_opts(params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, messages, opts) do
      {:ok, format_result(response, model, params[:detail_level])}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Config.resolve_model(:reasoning)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Config.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_explanation_messages(params) do
    system_prompt = build_explanation_system_prompt(params[:detail_level], params[:include_examples])
    user_prompt = build_explanation_user_prompt(params)
    Helpers.build_messages(user_prompt, system_prompt: system_prompt)
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
      audience when is_binary(audience) -> base <> "\n\nTarget Audience: " <> audience
    end
  end

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
      result: extract_text(response),
      detail_level: detail_level,
      model: model,
      usage: extract_usage(response)
    }
  end

  defp extract_text(%{message: %{content: content}}) when is_binary(content), do: content

  defp extract_text(%{message: %{content: content}}) when is_list(content) do
    content
    |> Enum.filter(fn part ->
      case part do
        %{type: :text} -> true
        _ -> false
      end
    end)
    |> Enum.map_join("", fn
      %{text: text} -> text
      _ -> ""
    end)
  end

  defp extract_text(_), do: ""

  defp extract_usage(%{usage: usage}) when is_map(usage) do
    %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, 0)
    }
  end

  defp extract_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
end
