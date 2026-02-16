defmodule Jido.AI.Signal.LLMResponse do
  @moduledoc """
  Signal for LLM streaming/call completion.

  Emitted when an LLM call completes, containing either tool calls to execute
  or a final answer.
  """

  alias Jido.AI.Turn

  use Jido.Signal,
    type: "ai.llm.response",
    default_source: "/ai/llm",
    schema: [
      call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
      result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"],
      usage: [type: :map, doc: "Token usage: %{input_tokens: N, output_tokens: M}"],
      model: [type: :string, doc: "Actual model used for the request"],
      duration_ms: [type: :integer, doc: "Request duration in milliseconds"],
      thinking_content: [type: :string, doc: "Extended thinking content (for reasoning models)"]
    ]

  @doc """
  Extracts tool calls from an LLMResponse signal.
  """
  @spec extract_tool_calls(Jido.Signal.t()) :: [map()]
  def extract_tool_calls(%{type: "ai.llm.response", data: %{result: {:ok, result}}}) do
    result
    |> Turn.from_result_map()
    |> Map.get(:tool_calls, [])
  end

  def extract_tool_calls(_signal), do: []

  @doc """
  Checks if an LLMResponse signal contains tool calls.
  """
  @spec tool_call?(Jido.Signal.t()) :: boolean()
  def tool_call?(%{type: "ai.llm.response", data: %{result: {:ok, result}}}) do
    result
    |> Turn.from_result_map()
    |> Turn.needs_tools?()
  end

  def tool_call?(_signal), do: false

  @doc """
  Creates an LLMResponse signal from a ReqLLM response struct.
  """
  @spec from_reqllm_response(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def from_reqllm_response(response, opts) do
    call_id = Keyword.fetch!(opts, :call_id)
    duration_ms = Keyword.get(opts, :duration_ms)
    model_override = Keyword.get(opts, :model)
    turn_opts = if is_binary(model_override), do: [model: model_override], else: []

    turn = Turn.from_response(response, turn_opts)

    signal_data = %{
      call_id: call_id,
      result: {:ok, turn}
    }

    signal_data = if turn.usage, do: Map.put(signal_data, :usage, turn.usage), else: signal_data
    signal_data = if turn.model, do: Map.put(signal_data, :model, turn.model), else: signal_data
    signal_data = if duration_ms, do: Map.put(signal_data, :duration_ms, duration_ms), else: signal_data

    signal_data =
      if turn.thinking_content, do: Map.put(signal_data, :thinking_content, turn.thinking_content), else: signal_data

    new(signal_data)
  end
end
