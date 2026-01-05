defmodule Jido.AI.Skills.Reasoning.Actions.Analyze do
  @moduledoc """
  A Jido.Action for performing deep analysis of text/data with structured output.

  This action uses ReqLLM directly with specialized system prompts for different
  types of analysis: sentiment, topics, entities, summary, or custom.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:reasoning`) or direct spec
  * `input` (required) - The text or data to analyze
  * `analysis_type` (optional) - Type of analysis: `:sentiment`, `:topics`, `:entities`, `:summary`, `:custom`
  * `custom_prompt` (optional) - Custom analysis instructions (when `analysis_type: :custom`)
  * `max_tokens` (optional) - Maximum tokens to generate (default: `2048`)
  * `temperature` (optional) - Sampling temperature (default: `0.3`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Sentiment analysis
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Reasoning.Actions.Analyze, %{
        input: "I absolutely loved the movie! The acting was superb.",
        analysis_type: :sentiment
      })

      # Topic extraction
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Reasoning.Actions.Analyze, %{
        input: article_text,
        analysis_type: :topics
      })

      # Custom analysis
      {:ok, result} = Jido.Exec.run(Jido.AI.Skills.Reasoning.Actions.Analyze, %{
        input: data,
        analysis_type: :custom,
        custom_prompt: "Analyze this data for trends and anomalies."
      })
  """

  use Jido.Action,
    name: "reasoning_analyze",
    description: "Perform deep analysis of text/data with structured output",
    category: "ai",
    tags: ["reasoning", "analysis"],
    vsn: "1.0.0",
    schema: [
      model: [
        type: :string,
        required: false,
        doc: "Model spec (e.g., 'anthropic:claude-sonnet-4-20250514') or alias (e.g., :reasoning)"
      ],
      input: [
        type: :string,
        required: true,
        doc: "The text or data to analyze"
      ],
      analysis_type: [
        type: {:in, [:sentiment, :topics, :entities, :summary, :custom]},
        required: false,
        default: :summary,
        doc: "Type of analysis to perform"
      ],
      custom_prompt: [
        type: :string,
        required: false,
        doc: "Custom analysis instructions (when analysis_type: :custom)"
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
        default: 0.3,
        doc: "Sampling temperature (lower for more deterministic analysis)"
      ],
      timeout: [
        type: :integer,
        required: false,
        doc: "Request timeout in milliseconds"
      ]
    ]

  alias Jido.AI.Config
  alias Jido.AI.Helpers

  @sentiment_prompt """
  You are an expert sentiment analyst. Analyze the provided text and determine:
  - The overall sentiment (positive, negative, neutral, or mixed)
  - Key emotional indicators
  - Confidence level in your assessment

  Provide a clear, structured analysis.
  """

  @topics_prompt """
  You are an expert at identifying topics and themes. Analyze the provided text and extract:
  - Main topics discussed
  - Key themes and patterns
  - Subject matter categories
  - Relative importance of each topic

  Provide a clear, structured analysis.
  """

  @entities_prompt """
  You are an expert at entity extraction. Analyze the provided text and identify:
  - Named entities (people, organizations, locations)
  - Important dates and figures
  - Key terms and concepts
  - Relationships between entities

  Provide a clear, structured analysis.
  """

  @summary_prompt """
  You are an expert at summarization. Analyze the provided text and provide:
  - A concise summary of key points
  - Main ideas and conclusions
  - Important details and context
  - Tone and style observations

  Provide a clear, structured summary.
  """

  @doc """
  Executes the analyze action.

  ## Returns

  * `{:ok, result}` - Successful response with `result`, `analysis_type`, `model`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        result: "The analysis result text",
        analysis_type: :sentiment,
        model: "anthropic:claude-sonnet-4-20250514",
        usage: %{
          input_tokens: 100,
          output_tokens: 250,
          total_tokens: 350
        }
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, model} <- resolve_model(params[:model]),
         {:ok, messages} <- build_analysis_messages(params),
         opts = build_opts(params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, messages, opts) do
      {:ok, format_result(response, model, params[:analysis_type])}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Config.resolve_model(:reasoning)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Config.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_analysis_messages(params) do
    system_prompt = build_analysis_system_prompt(params[:analysis_type], params[:custom_prompt])
    Helpers.build_messages(params[:input], system_prompt: system_prompt)
  end

  defp build_analysis_system_prompt(:sentiment, _custom), do: @sentiment_prompt
  defp build_analysis_system_prompt(:topics, _custom), do: @topics_prompt
  defp build_analysis_system_prompt(:entities, _custom), do: @entities_prompt
  defp build_analysis_system_prompt(:summary, _custom), do: @summary_prompt

  defp build_analysis_system_prompt(:custom, nil) do
    "You are an expert analyst. Analyze the provided input according to the user's instructions."
  end

  defp build_analysis_system_prompt(:custom, custom) when is_binary(custom) do
    custom
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

  defp format_result(response, model, analysis_type) do
    %{
      result: extract_text(response),
      analysis_type: analysis_type,
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
