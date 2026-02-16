defmodule Jido.AI.Signal do
  @moduledoc """
  Custom signal types for LLM-based agents.

  These signals are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  Signal types follow the `ai.*` namespace, with strategy-specific events nested under
  sub-namespaces like `ai.react.*`.

  ## Signal Types

  ### LLM Signals
  - `LLMRequest` - LLM call initiated (`ai.llm.request`)
  - `LLMResponse` - LLM call completed (`ai.llm.response`)
  - `LLMDelta` - Streaming token chunk (`ai.llm.delta`)
  - `LLMError` - Structured LLM error (`ai.llm.error`)
  - `LLMCancelled` - LLM call cancelled (`ai.llm.cancelled`)
  - `Usage` - Token usage tracking (`ai.usage`)

  ### Tool Signals
  - `ToolCall` - Tool invocation intent (`ai.tool.call`)
  - `ToolResult` - Tool execution completed (`ai.tool.result`)
  - `ToolError` - Structured tool error (`ai.tool.error`)

  ### Embedding Signals
  - `EmbedRequest` - Embedding request initiated (`ai.embed.request`)
  - `EmbedResult` - Embedding completed (`ai.embed.result`)
  - `EmbedError` - Structured embedding error (`ai.embed.error`)

  ### Request Lifecycle Signals
  - `RequestStarted` - Request lifecycle started (`ai.request.started`)
  - `RequestCompleted` - Request lifecycle completed (`ai.request.completed`)
  - `RequestFailed` - Request lifecycle failed (`ai.request.failed`)
  - `RequestError` - Request rejected (`ai.request.error`)

  ### ReAct Signals
  - `Step` - ReAct step tracking (`ai.react.step`)

  ## Helper Functions

  - `extract_tool_calls/1` - Extract tool calls from an LLMResponse signal
  - `tool_call?/1` - Check if a signal contains tool calls
  - `from_reqllm_response/2` - Create signals from ReqLLM response structs

  ## Usage

      alias Jido.AI.Signal

      # Create an LLM response signal
      {:ok, signal} = Signal.LLMResponse.new(%{
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
      signal = Signal.LLMResponse.new!(%{call_id: "call_123", result: {:ok, response}})
  """

  alias Jido.AI.Turn

  defmodule LLMResponse do
    @moduledoc """
    Signal for LLM streaming/call completion.

    Emitted when an LLM call completes, containing either tool calls to execute
    or a final answer.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original LLMStream directive
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
  end

  defmodule LLMDelta do
    @moduledoc """
    Signal for streaming LLM token chunks.

    Emitted incrementally as the LLM streams response tokens, enabling real-time
    display of responses before the full answer is complete.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original LLMStream directive
    - `:delta` (required) - The text chunk/token from the stream
    - `:chunk_type` (optional) - Type of chunk: `:content` or `:thinking` (default: `:content`)

    ## Usage

    Strategies can handle these signals via `signal_routes/1` to route them
    to strategy commands that accumulate partial responses. The ReAct strategy
    automatically handles these signals when using `Jido.AI.Strategies.ReAct`.
    """

    use Jido.Signal,
      type: "ai.llm.delta",
      default_source: "/ai/llm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        delta: [type: :string, required: true, doc: "Text chunk from the stream"],
        chunk_type: [type: :atom, default: :content, doc: "Type: :content or :thinking"]
      ]
  end

  defmodule LLMError do
    @moduledoc """
    Signal for structured LLM errors.

    Emitted when an LLM call fails, providing structured error information
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
      type: "ai.llm.error",
      default_source: "/ai/llm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        error_type: [type: :atom, required: true, doc: "Error classification"],
        message: [type: :string, required: true, doc: "Human-readable error message"],
        details: [type: :map, default: %{}, doc: "Additional error details"],
        retry_after: [type: :integer, doc: "Seconds to wait before retry (for rate limits)"]
      ]
  end

  defmodule Usage do
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
      type: "ai.usage",
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
      type: "ai.tool.result",
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

    - `:call_id` (required) - Correlation ID matching the original LLMEmbed directive
    - `:result` (required) - `{:ok, result_map}` or `{:error, reason}` from the embedding call

    The result map (when successful) contains:
    - `:embeddings` - Single embedding vector or list of embedding vectors
    - `:count` - Number of embeddings generated (1 for single, N for batch)
    """

    use Jido.Signal,
      type: "ai.embed.result",
      default_source: "/ai/embed",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the embedding call"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"]
      ]
  end

  defmodule RequestError do
    @moduledoc """
    Signal for request rejection.

    Emitted when a request cannot be processed (e.g., agent is busy).
    This provides feedback to the caller instead of silently dropping requests.

    ## Data Fields

    - `:request_id` (required) - Correlation ID for the rejected request
    - `:reason` (required) - Error reason atom (e.g., :busy, :invalid_state)
    - `:message` (required) - Human-readable error message
    """

    use Jido.Signal,
      type: "ai.request.error",
      default_source: "/ai/strategy",
      schema: [
        request_id: [type: :string, required: true, doc: "Correlation ID for the request"],
        reason: [type: :atom, required: true, doc: "Error reason atom"],
        message: [type: :string, required: true, doc: "Human-readable error message"]
      ]
  end

  defmodule RequestStarted do
    @moduledoc """
    Signal for request lifecycle start.

    Emitted when a ReAct request is accepted for processing.
    """

    use Jido.Signal,
      type: "ai.request.started",
      default_source: "/ai/request",
      schema: [
        request_id: [type: :string, required: true, doc: "Request correlation ID"],
        query: [type: :string, required: true, doc: "Original user query"],
        run_id: [type: :string, doc: "Request-scoped run ID"]
      ]
  end

  defmodule RequestCompleted do
    @moduledoc """
    Signal for request lifecycle completion.

    Emitted when a ReAct request reaches a successful terminal state.
    """

    use Jido.Signal,
      type: "ai.request.completed",
      default_source: "/ai/request",
      schema: [
        request_id: [type: :string, required: true, doc: "Request correlation ID"],
        result: [type: :any, required: true, doc: "Final result payload"],
        run_id: [type: :string, doc: "Request-scoped run ID"]
      ]
  end

  defmodule RequestFailed do
    @moduledoc """
    Signal for request lifecycle failure.

    Emitted when a ReAct request fails, is rejected, or is cancelled.
    """

    use Jido.Signal,
      type: "ai.request.failed",
      default_source: "/ai/request",
      schema: [
        request_id: [type: :string, required: true, doc: "Request correlation ID"],
        error: [type: :any, required: true, doc: "Failure reason payload"],
        run_id: [type: :string, doc: "Request-scoped run ID"]
      ]
  end

  # ============================================================================
  # LLM Lifecycle Signals
  # ============================================================================

  defmodule LLMRequest do
    @moduledoc """
    Signal for LLM call initiation.

    Emitted when an LLM call starts, enabling tracing, concurrency control,
    and cancellation support.

    ## Data Fields

    - `:call_id` (required) - Correlation ID for the LLM call
    - `:model` (required) - Model identifier being used
    - `:message_count` (optional) - Number of messages in the conversation
    - `:tool_count` (optional) - Number of tools available
    - `:params` (optional) - Request parameters (temperature, max_tokens, etc.)
    - `:trace_id` (optional) - Parent trace ID for distributed tracing
    """

    use Jido.Signal,
      type: "ai.llm.request",
      default_source: "/ai/llm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        model: [type: :string, required: true, doc: "Model identifier"],
        message_count: [type: :integer, doc: "Number of messages in conversation"],
        tool_count: [type: :integer, doc: "Number of tools available"],
        params: [type: :map, default: %{}, doc: "Request parameters"],
        trace_id: [type: :string, doc: "Parent trace ID for distributed tracing"]
      ]
  end

  defmodule LLMCancelled do
    @moduledoc """
    Signal for LLM call cancellation.

    Emitted when an LLM call is cancelled before completion.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original request
    - `:reason` (required) - Cancellation reason atom
    - `:at_ms` (optional) - Timestamp when cancellation occurred

    ## Reason Types

    - `:user_cancel` - User-initiated cancellation
    - `:timeout` - Request timed out
    - `:superseded` - Replaced by a newer request
    - `:shutdown` - System shutdown
    """

    use Jido.Signal,
      type: "ai.llm.cancelled",
      default_source: "/ai/llm",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the LLM call"],
        reason: [type: :atom, required: true, doc: "Cancellation reason"],
        at_ms: [type: :integer, doc: "Timestamp when cancellation occurred"]
      ]
  end

  # ============================================================================
  # Tool Lifecycle Signals
  # ============================================================================

  defmodule ToolCall do
    @moduledoc """
    Signal for tool invocation intent.

    Emitted when a tool is about to be executed, before `ToolResult`.

    ## Data Fields

    - `:call_id` (required) - Tool call ID from the LLM
    - `:llm_call_id` (optional) - Parent LLM call ID for correlation
    - `:tool_name` (required) - Name of the tool to execute
    - `:args` (required) - Arguments passed to the tool
    - `:timeout_ms` (optional) - Timeout for tool execution
    """

    use Jido.Signal,
      type: "ai.tool.call",
      default_source: "/ai/tool",
      schema: [
        call_id: [type: :string, required: true, doc: "Tool call ID from the LLM"],
        llm_call_id: [type: :string, doc: "Parent LLM call ID"],
        tool_name: [type: :string, required: true, doc: "Name of the tool to execute"],
        args: [type: :map, required: true, doc: "Arguments passed to the tool"],
        timeout_ms: [type: :integer, doc: "Timeout for tool execution"]
      ]
  end

  defmodule ToolError do
    @moduledoc """
    Signal for structured tool execution errors.

    Emitted when a tool execution fails, providing structured error information
    analogous to `LLMError`.

    ## Data Fields

    - `:call_id` (required) - Tool call ID from the LLM
    - `:tool_name` (required) - Name of the tool that failed
    - `:error_type` (required) - Error classification atom
    - `:message` (required) - Human-readable error message
    - `:details` (optional) - Additional error details
    - `:retry_after` (optional) - Seconds to wait before retry

    ## Error Types

    - `:timeout` - Tool execution timed out
    - `:validation` - Invalid arguments
    - `:not_found` - Tool not found
    - `:rate_limit` - Rate limit exceeded
    - `:auth` - Authorization error
    - `:tool_crash` - Tool raised an exception
    - `:unknown` - Unclassified error
    """

    use Jido.Signal,
      type: "ai.tool.error",
      default_source: "/ai/tool",
      schema: [
        call_id: [type: :string, required: true, doc: "Tool call ID from the LLM"],
        tool_name: [type: :string, required: true, doc: "Name of the tool that failed"],
        error_type: [type: :atom, required: true, doc: "Error classification"],
        message: [type: :string, required: true, doc: "Human-readable error message"],
        details: [type: :map, default: %{}, doc: "Additional error details"],
        retry_after: [type: :integer, doc: "Seconds to wait before retry"]
      ]
  end

  # ============================================================================
  # Embedding Lifecycle Signals
  # ============================================================================

  defmodule EmbedRequest do
    @moduledoc """
    Signal for embedding request initiation.

    Emitted when an embedding request starts.

    ## Data Fields

    - `:call_id` (required) - Correlation ID for the embedding call
    - `:model` (required) - Embedding model identifier
    - `:input_count` (required) - Number of texts to embed
    - `:dimensions` (optional) - Requested embedding dimensions
    """

    use Jido.Signal,
      type: "ai.embed.request",
      default_source: "/ai/embed",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the embedding call"],
        model: [type: :string, required: true, doc: "Embedding model identifier"],
        input_count: [type: :integer, required: true, doc: "Number of texts to embed"],
        dimensions: [type: :integer, doc: "Requested embedding dimensions"]
      ]
  end

  defmodule EmbedError do
    @moduledoc """
    Signal for structured embedding errors.

    Emitted when an embedding request fails.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original request
    - `:error_type` (required) - Error classification atom
    - `:message` (required) - Human-readable error message
    - `:details` (optional) - Additional error details
    - `:retry_after` (optional) - Seconds to wait before retry
    """

    use Jido.Signal,
      type: "ai.embed.error",
      default_source: "/ai/embed",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the embedding call"],
        error_type: [type: :atom, required: true, doc: "Error classification"],
        message: [type: :string, required: true, doc: "Human-readable error message"],
        details: [type: :map, default: %{}, doc: "Additional error details"],
        retry_after: [type: :integer, doc: "Seconds to wait before retry"]
      ]
  end

  # ============================================================================
  # ReAct Step Signals
  # ============================================================================

  defmodule Step do
    @moduledoc """
    Signal for ReAct step tracking.

    Provides normalized step records for debugging, evaluation, and replay.

    ## Data Fields

    - `:step_id` (required) - Unique identifier for this step
    - `:call_id` (required) - Root request correlation ID
    - `:step_type` (required) - Type of step
    - `:content` (required) - Step content (text or structured data)
    - `:parent_step_id` (optional) - Parent step for nested reasoning
    - `:at_ms` (optional) - Timestamp when step occurred

    ## Step Types

    - `:thought` - Agent reasoning/planning
    - `:action` - Tool invocation decision
    - `:observation` - Tool result observation
    - `:final` - Final answer
    """

    use Jido.Signal,
      type: "ai.react.step",
      default_source: "/ai/react/step",
      schema: [
        step_id: [type: :string, required: true, doc: "Unique step identifier"],
        call_id: [type: :string, required: true, doc: "Root request correlation ID"],
        step_type: [type: :atom, required: true, doc: "Step type: :thought, :action, :observation, :final"],
        content: [type: :any, required: true, doc: "Step content"],
        parent_step_id: [type: :string, doc: "Parent step for nested reasoning"],
        at_ms: [type: :integer, doc: "Timestamp when step occurred"]
      ]
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Extracts tool calls from an LLMResponse signal.

  Returns a list of tool call maps if the result contains tool calls,
  or an empty list otherwise.

  ## Examples

      iex> signal = Signal.LLMResponse.new!(%{
      ...>   call_id: "call_1",
      ...>   result: {:ok, %{type: :tool_calls, tool_calls: [%{id: "tc_1", name: "calc"}]}}
      ...> })
      iex> Signal.extract_tool_calls(signal)
      [%{id: "tc_1", name: "calc"}]

      iex> signal = Signal.LLMResponse.new!(%{
      ...>   call_id: "call_2",
      ...>   result: {:ok, %{type: :final_answer, text: "Hello"}}
      ...> })
      iex> Signal.extract_tool_calls(signal)
      []
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

  Returns `true` if the signal is a successful LLMResponse with tool calls,
  `false` otherwise.

  ## Examples

      iex> signal = Signal.LLMResponse.new!(%{
      ...>   call_id: "call_1",
      ...>   result: {:ok, %{type: :tool_calls, tool_calls: [%{id: "tc_1"}]}}
      ...> })
      iex> Signal.tool_call?(signal)
      true

      iex> signal = Signal.LLMResponse.new!(%{
      ...>   call_id: "call_2",
      ...>   result: {:ok, %{type: :final_answer, text: "Hello"}}
      ...> })
      iex> Signal.tool_call?(signal)
      false
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

  Takes a ReqLLM response (from `ReqLLM.stream_text/3` or `ReqLLM.Generation.generate_text/3`)
  and creates a properly formatted signal with extracted metadata.

  ## Options

  - `:call_id` (required) - Correlation ID for the signal
  - `:duration_ms` - Request duration in milliseconds
  - `:model` - Model identifier (if not in response)

  ## Examples

      iex> response = %ReqLLM.Response{message: %{content: "Hello"}, usage: %{input_tokens: 10, output_tokens: 5}}
      iex> Signal.from_reqllm_response(response, call_id: "call_1")
      {:ok, %Jido.Signal{type: "ai.llm.response", ...}}
  """
  @spec from_reqllm_response(map(), keyword()) :: {:ok, Jido.Signal.t()} | {:error, term()}
  def from_reqllm_response(response, opts) do
    call_id = Keyword.fetch!(opts, :call_id)
    duration_ms = Keyword.get(opts, :duration_ms)
    model_override = Keyword.get(opts, :model)
    turn_opts = if is_binary(model_override), do: [model: model_override], else: []

    turn = Turn.from_response(response, turn_opts)

    # Build signal data
    signal_data = %{
      call_id: call_id,
      result: {:ok, turn}
    }

    signal_data = if turn.usage, do: Map.put(signal_data, :usage, turn.usage), else: signal_data
    signal_data = if turn.model, do: Map.put(signal_data, :model, turn.model), else: signal_data
    signal_data = if duration_ms, do: Map.put(signal_data, :duration_ms, duration_ms), else: signal_data

    signal_data =
      if turn.thinking_content, do: Map.put(signal_data, :thinking_content, turn.thinking_content), else: signal_data

    LLMResponse.new(signal_data)
  end
end
