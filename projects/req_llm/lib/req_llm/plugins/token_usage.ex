defmodule ReqLLM.Plugins.TokenUsage do
  @moduledoc """
  Req plugin that extracts token usage information from AI provider responses.

  This plugin:
  * Extracts token usage numbers from provider responses
  * Calculates costs using ReqLLM.Model cost metadata
  * Stores usage data in `response.private[:req_llm][:usage]`
  * Emits telemetry events for monitoring and dashboards

  ## Usage

      req
      |> ReqLLM.Plugins.TokenUsage.attach(model)

  The model is needed for cost calculation. If the model is already stored
  in `req.options[:model]`, the model parameter can be omitted.

  ## Telemetry Events

  Emits `[:req_llm, :token_usage]` events with:
  * Measurements: `%{tokens: %{input: 123, output: 456, reasoning: 64}, cost: 0.0123}`
  * Metadata: `%{model: %ReqLLM.Model{}}`
  """

  @doc """
  Attaches the TokenUsage plugin to a Req request.

  ## Parameters

  - `req` - The Req.Request struct
  - `model` - Optional ReqLLM.Model struct for cost calculation

  ## Examples

      req
      |> ReqLLM.Plugins.TokenUsage.attach(model)

  """
  @spec attach(Req.Request.t(), ReqLLM.Model.t() | nil) :: Req.Request.t()
  def attach(%Req.Request{} = req, model \\ nil) do
    req
    |> Req.Request.append_response_steps(token_usage: &__MODULE__.handle/1)
    |> then(fn r ->
      if model, do: Req.Request.put_private(r, :req_llm_model, model), else: r
    end)
  end

  @doc false
  @spec handle({Req.Request.t(), Req.Response.t()}) :: {Req.Request.t(), Req.Response.t()}
  def handle({req, resp}) do
    with {:ok, usage} <- extract_usage(resp.body),
         {:ok, model} <- fetch_model(req),
         {:ok, cost} <- compute_cost(usage, model) do
      meta = %{tokens: usage, cost: cost}

      # Emit telemetry event for monitoring
      :telemetry.execute([:req_llm, :token_usage], meta, %{model: model})

      # Store usage data in response private for access by callers
      req_llm_data = Map.get(resp.private, :req_llm, %{})
      updated_req_llm_data = Map.put(req_llm_data, :usage, meta)
      updated_resp = %{resp | private: Map.put(resp.private, :req_llm, updated_req_llm_data)}
      {req, updated_resp}
    else
      _ -> {req, resp}
    end
  end

  # Extracts token usage from various provider response formats
  @spec extract_usage(any) :: {:ok, map()} | :error
  defp extract_usage(%{"usage" => usage}) when is_map(usage) do
    base_usage = %{
      input: usage["prompt_tokens"] || usage["input_tokens"] || 0,
      output: usage["completion_tokens"] || usage["output_tokens"] || 0
    }

    # Check for detailed token breakdown (e.g., OpenAI o1 models with reasoning)
    case usage["completion_tokens_details"] do
      %{"reasoning_tokens" => reasoning_tokens}
      when is_integer(reasoning_tokens) and reasoning_tokens > 0 ->
        {:ok, Map.put(base_usage, :reasoning, reasoning_tokens)}

      _ ->
        {:ok, base_usage}
    end
  end

  defp extract_usage(_), do: :error

  # Finds the model from request private data or options
  @spec fetch_model(Req.Request.t()) :: {:ok, ReqLLM.Model.t()} | :error
  defp fetch_model(%Req.Request{private: private, options: options}) do
    case private[:req_llm_model] || options[:model] do
      %ReqLLM.Model{} = model -> {:ok, model}
      _ -> :error
    end
  end

  # Calculates cost based on token usage and model pricing
  @spec compute_cost(%{input: non_neg_integer, output: non_neg_integer}, ReqLLM.Model.t()) ::
          {:ok, float() | nil} | :error
  defp compute_cost(%{input: _input_tokens, output: _output_tokens}, %ReqLLM.Model{cost: nil}) do
    {:ok, nil}
  end

  defp compute_cost(%{input: input_tokens, output: output_tokens}, %ReqLLM.Model{cost: cost_map})
       when is_map(cost_map) do
    # Handle both atom and string keys from model metadata
    input_cost = cost_map[:input] || cost_map["input"]
    output_cost = cost_map[:output] || cost_map["output"]

    if input_cost && output_cost do
      calculated_cost =
        Float.round(input_tokens / 1000 * input_cost + output_tokens / 1000 * output_cost, 6)

      {:ok, calculated_cost}
    else
      {:ok, nil}
    end
  end
end
