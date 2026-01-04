defmodule Jido.AI.Signal do
  @moduledoc """
  Custom signal types for LLM-based agents.

  These signals are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  They follow a consistent naming convention: `reqllm.<event_type>` for ReqLLM-specific signals
  and `ai.<event_type>` for generic AI signals.

  ## Signal Types

  - `Jido.AI.Signal.ReqLLMResult` - Result from a ReqLLM streaming/generation call
  - `Jido.AI.Signal.ReqLLMPartial` - Streaming token chunk from ReqLLM
  - `Jido.AI.Signal.ReqLLMError` - Structured error from ReqLLM call
  - `Jido.AI.Signal.UsageReport` - Token usage and cost tracking
  - `Jido.AI.Signal.ToolResult` - Result from a tool execution
  - `Jido.AI.Signal.EmbedResult` - Result from an embedding generation call

  ## Helper Functions

  - `extract_tool_calls/1` - Extract tool calls from a ReqLLMResult signal
  - `is_tool_call?/1` - Check if a signal contains tool calls
  - `from_reqllm_response/2` - Create signals from ReqLLM response structs

  ## Usage

      alias Jido.AI.Signal

      # Create an LLM result signal
      {:ok, signal} = Signal.ReqLLMResult.new(%{
        call_id: "call_123",
        result: {:ok, %{type: :final_answer, text: "Hello!", tool_calls: []}}
      })

      # Create a tool result signal
      {:ok, signal} = Signal.ToolResult.new(%{
        call_id: "tool_456",
        tool_name: "calculator",
        result: {:ok, %{result: 42}}
      })

      # Bang versions for when you know data is valid
      signal = Signal.ReqLLMResult.new!(%{call_id: "call_123", result: {:ok, response}})
  """

  defmodule ReqLLMResult do
    @moduledoc """
    Signal for ReqLLM streaming/call completion.

    Emitted when a ReqLLM call completes, containing either tool calls to execute
    or a final answer.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original ReqLLMStream directive
    - `:result` (required) - `{:ok, result_map}` or `{:error, reason}` from the LLM call
    - `:usage` (optional) - Token usage map with `:input_tokens` and `:output_tokens`
    - `:model` (optional) - The actual model used for the request
    - `:duration_ms` (optional) - Request duration in milliseconds
    - `:thinking_content` (optional) - Extended thinking content (for reasoning models)

    The result map (when successful) contains:
    - `:type` - `:tool_calls` or `:final_answer`
    - `:text` - Accumulated text from the response
    - `:tool_calls` - List of tool calls (if type is :tool_calls)
    """

    use Jido.Signal,
      type: "reqllm.result",
      default_source: "/reqllm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"],
        usage: [type: :map, doc: "Token usage: %{input_tokens: N, output_tokens: M}"],
        model: [type: :string, doc: "Actual model used for the request"],
        duration_ms: [type: :integer, doc: "Request duration in milliseconds"],
        thinking_content: [type: :string, doc: "Extended thinking content (for reasoning models)"]
      ]
  end

  defmodule ReqLLMPartial do
    @moduledoc """
    Signal for streaming ReqLLM token chunks.

    Emitted incrementally as the LLM streams response tokens, enabling real-time
    display of responses before the full answer is complete.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original ReqLLMStream directive
    - `:delta` (required) - The text chunk/token from the stream
    - `:chunk_type` (optional) - Type of chunk: `:content` or `:thinking` (default: `:content`)

    ## Usage

    Strategies can handle these signals via `signal_routes/1` to route them
    to strategy commands that accumulate partial responses. The ReAct strategy
    automatically handles these signals when using `Jido.AI.Strategy.ReAct`.
    """

    use Jido.Signal,
      type: "reqllm.partial",
      default_source: "/reqllm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        delta: [type: :string, required: true, doc: "Text chunk from the stream"],
        chunk_type: [type: :atom, default: :content, doc: "Type: :content or :thinking"]
      ]
  end

  defmodule ReqLLMError do
    @moduledoc """
    Signal for structured ReqLLM errors.

    Emitted when a ReqLLM call fails, providing structured error information
    for error handling, retry logic, and monitoring.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original directive
    - `:error_type` (required) - Error classification atom
    - `:message` (required) - Human-readable error message
    - `:details` (optional) - Additional error details map
    - `:retry_after` (optional) - Seconds to wait before retry (for rate limits)

    ## Error Types

    - `:rate_limit` - Provider rate limit exceeded
    - `:auth` - Authentication/authorization error
    - `:timeout` - Request timeout
    - `:provider_error` - Provider-side error
    - `:validation` - Request validation error
    - `:network` - Network connectivity error
    - `:unknown` - Unclassified error
    """

    use Jido.Signal,
      type: "reqllm.error",
      default_source: "/reqllm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        error_type: [type: :atom, required: true, doc: "Error classification"],
        message: [type: :string, required: true, doc: "Human-readable error message"],
        details: [type: :map, default: %{}, doc: "Additional error details"],
        retry_after: [type: :integer, doc: "Seconds to wait before retry (for rate limits)"]
      ]
  end

  defmodule UsageReport do
    @moduledoc """
    Signal for token usage and cost tracking.

    Emitted after LLM calls to report token consumption for monitoring,
    billing, and cost optimization.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original directive
    - `:model` (required) - Model identifier used for the request
    - `:input_tokens` (required) - Number of input/prompt tokens
    - `:output_tokens` (required) - Number of output/completion tokens
    - `:total_tokens` (optional) - Total tokens (input + output)
    - `:duration_ms` (optional) - Request duration in milliseconds
    - `:metadata` (optional) - Additional tracking metadata
    """

    use Jido.Signal,
      type: "ai.usage_report",
      default_source: "/ai/usage",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        model: [type: :string, required: true, doc: "Model identifier"],
        input_tokens: [type: :integer, required: true, doc: "Number of input tokens"],
        output_tokens: [type: :integer, required: true, doc: "Number of output tokens"],
        total_tokens: [type: :integer, doc: "Total tokens (input + output)"],
        duration_ms: [type: :integer, doc: "Request duration in milliseconds"],
        metadata: [type: :map, default: %{}, doc: "Additional tracking metadata"]
      ]
  end

  defmodule ToolResult do
    @moduledoc """
    Signal for tool execution completion.

    Emitted when a tool (Jido.Action) finishes executing.

    ## Data Fields

    - `:call_id` (required) - Tool call ID from the LLM for correlation
    - `:tool_name` (required) - Name of the tool that was executed
    - `:result` (required) - `{:ok, result}` or `{:error, reason}` from tool execution
    """

    use Jido.Signal,
      type: "ai.tool_result",
      default_source: "/ai/tool",
      schema: [
        call_id: [type: :string, required: true, doc: "Tool call ID from the LLM"],
        tool_name: [type: :string, required: true, doc: "Name of the executed tool"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"]
      ]
  end

  defmodule EmbedResult do
    @moduledoc """
    Signal for embedding generation completion.

    Emitted when an embedding request completes, containing the embedding vectors.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original ReqLLMEmbed directive
    - `:result` (required) - `{:ok, result_map}` or `{:error, reason}` from the embedding call

    The result map (when successful) contains:
    - `:embeddings` - Single embedding vector or list of embedding vectors
    - `:count` - Number of embeddings generated (1 for single, N for batch)
    """

    use Jido.Signal,
      type: "ai.embed_result",
      default_source: "/ai/embedding",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the embedding call"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"]
      ]
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Extracts tool calls from a ReqLLMResult signal.

  Returns a list of tool call maps if the result contains tool calls,
  or an empty list otherwise.

  ## Examples

      iex> signal = Signal.ReqLLMResult.new!(%{
      ...>   call_id: "call_1",
      ...>   result: {:ok, %{type: :tool_calls, tool_calls: [%{id: "tc_1", name: "calc"}]}}
      ...> })
      iex> Signal.extract_tool_calls(signal)
      [%{id: "tc_1", name: "calc"}]

      iex> signal = Signal.ReqLLMResult.new!(%{
      ...>   call_id: "call_2",
      ...>   result: {:ok, %{type: :final_answer, text: "Hello"}}
      ...> })
      iex> Signal.extract_tool_calls(signal)
      []
  """
  @spec extract_tool_calls(Jido.Signal.t()) :: [map()]
  def extract_tool_calls(%{type: "reqllm.result", data: %{result: {:ok, result}}}) do
    case result do
      %{type: :tool_calls, tool_calls: tool_calls} when is_list(tool_calls) -> tool_calls
      %{tool_calls: tool_calls} when is_list(tool_calls) and tool_calls != [] -> tool_calls
      _ -> []
    end
  end

  def extract_tool_calls(_signal), do: []

  @doc """
  Checks if a ReqLLMResult signal contains tool calls.

  Returns `true` if the signal is a successful ReqLLMResult with tool calls,
  `false` otherwise.

  ## Examples

      iex> signal = Signal.ReqLLMResult.new!(%{
      ...>   call_id: "call_1",
      ...>   result: {:ok, %{type: :tool_calls, tool_calls: [%{id: "tc_1"}]}}
      ...> })
      iex> Signal.tool_call?(signal)
      true

      iex> signal = Signal.ReqLLMResult.new!(%{
      ...>   call_id: "call_2",
      ...>   result: {:ok, %{type: :final_answer, text: "Hello"}}
      ...> })
      iex> Signal.tool_call?(signal)
      false
  """
  @spec tool_call?(Jido.Signal.t()) :: boolean()
  def tool_call?(%{type: "reqllm.result", data: %{result: {:ok, result}}}) do
    case result do
      %{type: :tool_calls} -> true
      %{tool_calls: tool_calls} when is_list(tool_calls) and tool_calls != [] -> true
      _ -> false
    end
  end

  def tool_call?(_signal), do: false

  @doc """
  Deprecated: Use `tool_call?/1` instead.
  """
  @deprecated "Use tool_call?/1 instead"
  @spec is_tool_call?(Jido.Signal.t()) :: boolean()
  def is_tool_call?(signal), do: tool_call?(signal)

  @doc """
  Creates a ReqLLMResult signal from a ReqLLM response struct.

  Takes a ReqLLM response (from `ReqLLM.stream_text/3` or `ReqLLM.Generation.generate_text/3`)
  and creates a properly formatted signal with extracted metadata.

  ## Options

  - `:call_id` (required) - Correlation ID for the signal
  - `:duration_ms` - Request duration in milliseconds
  - `:model` - Model identifier (if not in response)

  ## Examples

      iex> response = %ReqLLM.Response{message: %{content: "Hello"}, usage: %{input_tokens: 10, output_tokens: 5}}
      iex> Signal.from_reqllm_response(response, call_id: "call_1")
      {:ok, %Jido.Signal{type: "reqllm.result", ...}}
  """
  @spec from_reqllm_response(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def from_reqllm_response(response, opts) do
    call_id = Keyword.fetch!(opts, :call_id)
    duration_ms = Keyword.get(opts, :duration_ms)
    model_override = Keyword.get(opts, :model)

    # Extract tool calls from response
    tool_calls = extract_response_tool_calls(response)

    # Determine response type
    type = if tool_calls == [], do: :final_answer, else: :tool_calls

    # Extract text content
    text = extract_response_text(response)

    # Extract thinking content if present
    thinking_content = extract_thinking_content(response)

    # Build result map
    result = %{
      type: type,
      text: text,
      tool_calls: tool_calls
    }

    # Extract usage from response
    usage = extract_response_usage(response)

    # Extract model from response or use override
    model = model_override || extract_response_model(response)

    # Build signal data
    signal_data = %{
      call_id: call_id,
      result: {:ok, result}
    }

    signal_data = if usage, do: Map.put(signal_data, :usage, usage), else: signal_data
    signal_data = if model, do: Map.put(signal_data, :model, model), else: signal_data
    signal_data = if duration_ms, do: Map.put(signal_data, :duration_ms, duration_ms), else: signal_data
    signal_data = if thinking_content, do: Map.put(signal_data, :thinking_content, thinking_content), else: signal_data

    ReqLLMResult.new(signal_data)
  end

  # Private helpers for from_reqllm_response

  defp extract_response_tool_calls(%{message: %{tool_calls: tool_calls}}) when is_list(tool_calls) do
    Enum.map(tool_calls, fn tc ->
      case tc do
        %ReqLLM.ToolCall{} = tool_call ->
          %{
            id: tool_call.id || "call_#{:erlang.unique_integer([:positive])}",
            name: ReqLLM.ToolCall.name(tool_call),
            arguments: ReqLLM.ToolCall.args_map(tool_call) || %{}
          }

        %{} = map ->
          %{
            id: map[:id] || map["id"] || "call_#{:erlang.unique_integer([:positive])}",
            name: map[:name] || map["name"],
            arguments: map[:arguments] || map["arguments"] || %{}
          }
      end
    end)
  end

  defp extract_response_tool_calls(_), do: []

  defp extract_response_text(%{message: %{content: content}}) when is_binary(content), do: content

  defp extract_response_text(%{message: %{content: content}}) when is_list(content) do
    content
    |> Enum.filter(&match?(%{type: :text}, &1))
    |> Enum.map_join("", & &1.text)
  end

  defp extract_response_text(_), do: ""

  defp extract_thinking_content(%{message: %{content: content}}) when is_list(content) do
    thinking =
      content
      |> Enum.filter(&match?(%{type: :thinking}, &1))
      |> Enum.map_join("", & &1.thinking)

    if thinking != "", do: thinking
  end

  defp extract_thinking_content(_), do: nil

  defp extract_response_usage(%{usage: %{input_tokens: input, output_tokens: output}}) do
    %{input_tokens: input, output_tokens: output}
  end

  defp extract_response_usage(%{usage: %{"input_tokens" => input, "output_tokens" => output}}) do
    %{input_tokens: input, output_tokens: output}
  end

  defp extract_response_usage(_), do: nil

  defp extract_response_model(%{model: model}) when is_binary(model), do: model
  defp extract_response_model(_), do: nil
end
