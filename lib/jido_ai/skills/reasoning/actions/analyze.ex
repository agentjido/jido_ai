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
    schema:
      Zoi.object(%{
        model:
          Zoi.string(description: "Model spec (e.g., 'anthropic:claude-sonnet-4-20250514') or alias (e.g., :reasoning)")
          |> Zoi.optional(),
        input: Zoi.string(description: "The text or data to analyze"),
        analysis_type:
          Zoi.atom(description: "Type of analysis to perform (:sentiment, :topics, :entities, :summary, :custom)")
          |> Zoi.default(:summary),
        custom_prompt:
          Zoi.string(description: "Custom analysis instructions (when analysis_type: :custom)")
          |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(2048),
        temperature:
          Zoi.float(description: "Sampling temperature (lower for more deterministic analysis)")
          |> Zoi.default(0.3),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Config
  alias Jido.AI.Helpers
  alias Jido.AI.Security

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
         {:ok, validated_params} <- validate_and_sanitize_params(params),
         context = build_analysis_messages(validated_params),
         opts = build_opts(validated_params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, context.messages, opts) do
      {:ok, format_result(response, model, validated_params[:analysis_type])}
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
    # Validate and sanitize custom prompt to prevent prompt injection
    case Security.validate_custom_prompt(custom, max_length: Security.max_prompt_length()) do
      {:ok, sanitized} -> sanitized
      {:error, _reason} -> "You are an expert analyst. Analyze the provided input."
    end
  end

  # Validates and sanitizes input parameters to prevent security issues
  defp validate_and_sanitize_params(params) do
    with {:ok, _input} <- Security.validate_string(params[:input], max_length: Security.max_input_length()),
         {:ok, _validated} <- validate_custom_prompt_if_needed(params) do
      {:ok, params}
    else
      {:error, :empty_string} -> {:error, :input_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_custom_prompt_if_needed(%{analysis_type: :custom, custom_prompt: custom}) do
    Security.validate_custom_prompt(custom, max_length: Security.max_prompt_length())
  end

  defp validate_custom_prompt_if_needed(_params), do: {:ok, nil}

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

  defp extract_text(%{message: %{content: content}}) do
    case content do
      c when is_binary(c) ->
        c

      c when is_list(c) ->
        c
        |> Enum.filter(&text_part?/1)
        |> Enum.map_join("", fn
          %{text: text} -> text
          _ -> ""
        end)

      _ ->
        ""
    end
  end

  @dialyzer {:nowarn_function, extract_text: 1}

  defp extract_text(_), do: ""

  defp text_part?(%{type: :text}), do: true
  defp text_part?(_), do: false

  defp extract_usage(%{usage: usage}) when is_map(usage) do
    %{
      input_tokens: Map.get(usage, :input_tokens, 0),
      output_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, 0)
    }
  end

  defp extract_usage(_), do: %{input_tokens: 0, output_tokens: 0, total_tokens: 0}
end
