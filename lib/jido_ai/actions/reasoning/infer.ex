defmodule Jido.AI.Actions.Reasoning.Infer do
  @moduledoc """
  A Jido.Action for drawing logical inferences from given premises.

  This action uses ReqLLM with a specialized system prompt for logical reasoning,
  helping to draw valid conclusions from given information.

  ## Parameters

  * `model` (optional) - Model alias (e.g., `:reasoning`) or direct spec
  * `premises` (required) - The given facts/information as premises
  * `question` (required) - What to infer from the premises
  * `context` (optional) - Additional background information
  * `max_tokens` (optional) - Maximum tokens to generate (default: `2048`)
  * `temperature` (optional) - Sampling temperature (default: `0.3`)
  * `timeout` (optional) - Request timeout in milliseconds

  ## Examples

      # Basic inference
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Reasoning.Infer, %{
        premises: "All cats are mammals. Fluffy is a cat.",
        question: "Is Fluffy a mammal?"
      })

      # With context
      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.Reasoning.Infer, %{
        premises: "If it rains, the ground gets wet. The ground is wet.",
        question: "Can we conclude that it rained?",
        context: "Consider that sprinklers can also make the ground wet."
      })
  """
  use Jido.Action,
    # Dialyzer has incomplete PLT information about req_llm dependencies
    name: "reasoning_infer",
    description: "Draw logical inferences from given premises",
    category: "ai",
    tags: ["reasoning", "inference", "logic"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        model:
          Zoi.any(description: "Model alias (e.g., :reasoning) or direct model spec string")
          |> Zoi.optional(),
        premises: Zoi.string(description: "The given facts/information as premises"),
        question: Zoi.string(description: "What to infer from the premises"),
        context: Zoi.string(description: "Additional background information") |> Zoi.optional(),
        max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(2048),
        temperature:
          Zoi.float(description: "Sampling temperature (lower for more deterministic reasoning)")
          |> Zoi.default(0.3),
        timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional()
      })

  alias Jido.AI.Actions.Helpers
  alias Jido.AI.Security
  alias Jido.AI.Turn
  alias ReqLLM.Context

  @inference_prompt """
  You are an expert logical reasoner. Your task is to draw valid inferences from given premises.

  For the provided premises and question:
  1. Identify relevant information in the premises
  2. Apply logical reasoning to reach a conclusion
  3. Provide your answer with supporting reasoning
  4. Indicate your confidence level

  Be explicit about your reasoning chain and acknowledge any uncertainty or missing information.
  """

  @doc """
  Executes the infer action.

  ## Returns

  * `{:ok, result}` - Successful response with `result`, `reasoning`, `confidence`, `model`, and `usage` keys
  * `{:error, reason}` - Error from ReqLLM or validation

  ## Result Format

      %{
        result: "The inferred conclusion",
        reasoning: "Step-by-step reasoning chain",
        confidence: 0.9,
        model: "anthropic:claude-sonnet-4-20250514",
        usage: %{...}
      }
  """
  @impl Jido.Action
  def run(params, _context) do
    with {:ok, model} <- resolve_model(params[:model]),
         {:ok, validated_params} <- validate_and_sanitize_params(params),
         {:ok, req_context} <- build_inference_messages(validated_params),
         opts = build_opts(validated_params),
         {:ok, response} <- ReqLLM.Generation.generate_text(model, req_context.messages, opts) do
      {:ok, format_result(response, model)}
    end
  end

  # Private Functions

  defp resolve_model(nil), do: {:ok, Jido.AI.resolve_model(:reasoning)}
  defp resolve_model(model) when is_atom(model), do: {:ok, Jido.AI.resolve_model(model)}
  defp resolve_model(model) when is_binary(model), do: {:ok, model}

  defp build_inference_messages(params) do
    user_prompt = build_inference_user_prompt(params)
    Context.normalize(user_prompt, system_prompt: @inference_prompt)
  end

  defp build_inference_user_prompt(params) do
    base = """
    Premises:
    #{params[:premises]}

    Question:
    #{params[:question]}
    """

    case params[:context] do
      nil -> base
      # Context is already validated in validate_and_sanitize_params
      context when is_binary(context) -> base <> "\n\nAdditional Context:\n" <> context
    end
  end

  # Validates and sanitizes input parameters to prevent security issues
  defp validate_and_sanitize_params(params) do
    with {:ok, _premises} <-
           Security.validate_string(params[:premises], max_length: Security.max_input_length()),
         {:ok, _question} <-
           Security.validate_string(params[:question], max_length: Security.max_input_length()),
         {:ok, _validated} <- validate_context_if_needed(params) do
      {:ok, params}
    else
      {:error, :empty_string} -> {:error, :premises_and_question_required}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_context_if_needed(%{context: context}) when is_binary(context) do
    Security.validate_string(context, max_length: Security.max_input_length())
  end

  defp validate_context_if_needed(_params), do: {:ok, nil}

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

  defp format_result(response, model) do
    %{
      result: Turn.extract_text(response),
      reasoning: Turn.extract_text(response),
      model: model,
      usage: Helpers.extract_usage(response)
    }
  end
end
