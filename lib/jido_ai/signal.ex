defmodule Jido.AI.Signal do
  @moduledoc """
  Custom signal types for LLM-based agents.

  These signals are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  All signals follow a consistent `react.*` namespace convention to indicate ownership by the
  ReAct machine lifecycle.

  ## Signal Types

  ### LLM Signals
  - `LLMRequest` - LLM call initiated (`react.llm.request`)
  - `LLMResponse` - LLM call completed (`react.llm.response`)
  - `LLMDelta` - Streaming token chunk (`react.llm.delta`)
  - `LLMError` - Structured LLM error (`react.llm.error`)
  - `LLMCancelled` - LLM call cancelled (`react.llm.cancelled`)
  - `Usage` - Token usage tracking (`react.usage`)

  ### Tool Signals
  - `ToolCall` - Tool invocation intent (`react.tool.call`)
  - `ToolResult` - Tool execution completed (`react.tool.result`)
  - `ToolError` - Structured tool error (`react.tool.error`)

  ### Embedding Signals
  - `EmbedRequest` - Embedding request initiated (`react.embed.request`)
  - `EmbedResult` - Embedding completed (`react.embed.result`)
  - `EmbedError` - Structured embedding error (`react.embed.error`)

  ### Orchestration Signals
  - `RequestError` - Request rejected (`react.request.error`)
  - `DelegationRequest` - Task delegation (`ai.delegation.request`)
  - `DelegationResult` - Delegation completed (`ai.delegation.result`)
  - `DelegationError` - Delegation failed (`ai.delegation.error`)
  - `CapabilityQuery` - Capability discovery (`ai.capability.query`)
  - `CapabilityResponse` - Capability response (`ai.capability.response`)

  ### ReAct Signals
  - `Step` - ReAct step tracking (`react.step`)

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
      type: "react.llm.response",
      default_source: "/react/llm",
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
      type: "react.llm.delta",
      default_source: "/react/llm",
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
      type: "react.llm.error",
      default_source: "/react/llm",
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
      type: "react.usage",
      default_source: "/react/usage",
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
      type: "react.tool.result",
      default_source: "/react/tool",
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
      type: "react.embed.result",
      default_source: "/react/embed",
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

    - `:call_id` (required) - Correlation ID for the rejected request
    - `:reason` (required) - Error reason atom (e.g., :busy, :invalid_state)
    - `:message` (required) - Human-readable error message
    """

    use Jido.Signal,
      type: "react.request.error",
      default_source: "/react/strategy",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the request"],
        reason: [type: :atom, required: true, doc: "Error reason atom"],
        message: [type: :string, required: true, doc: "Human-readable error message"]
      ]
  end

  # ============================================================================
  # Orchestration Signals
  # ============================================================================

  defmodule DelegationRequest do
    @moduledoc """
    Signal for task delegation request.

    Emitted when a parent agent delegates a task to a child agent.

    ## Data Fields

    - `:call_id` (required) - Correlation ID for tracking the delegation
    - `:task` (required) - Task description being delegated
    - `:target` (required) - Target agent info (module, pid, or tag)
    - `:constraints` (optional) - Delegation constraints (timeout, budget, etc.)
    """

    use Jido.Signal,
      type: "ai.delegation.request",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the delegation"],
        task: [type: :string, required: true, doc: "Task being delegated"],
        target: [type: :any, required: true, doc: "Target agent (module, pid, or tag)"],
        constraints: [type: :map, default: %{}, doc: "Constraints: timeout_ms, max_cost, etc."]
      ]
  end

  defmodule DelegationResult do
    @moduledoc """
    Signal for delegation completion.

    Emitted when a delegated task completes, carrying the result back to parent.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original delegation request
    - `:result` (required) - `{:ok, result}` or `{:error, reason}` from child
    - `:source_agent` (required) - Agent that completed the task (tag or pid)
    - `:duration_ms` (optional) - Time taken to complete the task
    """

    use Jido.Signal,
      type: "ai.delegation.result",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the delegation"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"],
        source_agent: [type: :any, required: true, doc: "Agent that completed the task"],
        duration_ms: [type: :integer, doc: "Time taken in milliseconds"]
      ]
  end

  defmodule DelegationError do
    @moduledoc """
    Signal for delegation failure.

    Emitted when a delegated task fails, providing error details.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original delegation request
    - `:error_type` (required) - Error classification atom
    - `:message` (required) - Human-readable error message
    - `:source_agent` (optional) - Agent where the error occurred
    """

    use Jido.Signal,
      type: "ai.delegation.error",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the delegation"],
        error_type: [type: :atom, required: true, doc: "Error classification"],
        message: [type: :string, required: true, doc: "Human-readable error message"],
        source_agent: [type: :any, doc: "Agent where the error occurred"]
      ]
  end

  defmodule CapabilityQuery do
    @moduledoc """
    Signal for capability discovery request.

    Emitted when an orchestrator needs to discover available agent capabilities.

    ## Data Fields

    - `:call_id` (required) - Correlation ID for the query
    - `:required_capabilities` (optional) - Filter by required capabilities
    """

    use Jido.Signal,
      type: "ai.capability.query",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the query"],
        required_capabilities: [type: {:list, :string}, default: [], doc: "Required capabilities filter"]
      ]
  end

  defmodule CapabilityResponse do
    @moduledoc """
    Signal for capability discovery response.

    Response to a capability query with agent's capabilities.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the query
    - `:agent_ref` (required) - Agent reference (module, pid, or tag)
    - `:capabilities` (required) - Capability descriptor
    """

    use Jido.Signal,
      type: "ai.capability.response",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the query"],
        agent_ref: [type: :any, required: true, doc: "Agent reference"],
        capabilities: [type: :map, required: true, doc: "Capability descriptor"]
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
      type: "react.llm.request",
      default_source: "/react/llm",
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
      type: "react.llm.cancelled",
      default_source: "/react/llm",
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
      type: "react.tool.call",
      default_source: "/react/tool",
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
      type: "react.tool.error",
      default_source: "/react/tool",
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
      type: "react.embed.request",
      default_source: "/react/embed",
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
      type: "react.embed.error",
      default_source: "/react/embed",
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
      type: "react.step",
      default_source: "/react/step",
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
  # Orchestration Signals
  # ============================================================================

  defmodule DelegationRequest do
    @moduledoc """
    Signal for task delegation request.

    Emitted when a parent agent delegates a task to a child agent.

    ## Data Fields

    - `:call_id` (required) - Correlation ID for tracking the delegation
    - `:task` (required) - Task description being delegated
    - `:target` (required) - Target agent info (module, pid, or tag)
    - `:constraints` (optional) - Delegation constraints (timeout, budget, etc.)
    """

    use Jido.Signal,
      type: "ai.delegation.request",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the delegation"],
        task: [type: :string, required: true, doc: "Task being delegated"],
        target: [type: :any, required: true, doc: "Target agent (module, pid, or tag)"],
        constraints: [type: :map, default: %{}, doc: "Constraints: timeout_ms, max_cost, etc."]
      ]
  end

  defmodule DelegationResult do
    @moduledoc """
    Signal for delegation completion.

    Emitted when a delegated task completes, carrying the result back to parent.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original delegation request
    - `:result` (required) - `{:ok, result}` or `{:error, reason}` from child
    - `:source_agent` (required) - Agent that completed the task (tag or pid)
    - `:duration_ms` (optional) - Time taken to complete the task
    """

    use Jido.Signal,
      type: "ai.delegation.result",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the delegation"],
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"],
        source_agent: [type: :any, required: true, doc: "Agent that completed the task"],
        duration_ms: [type: :integer, doc: "Time taken in milliseconds"]
      ]
  end

  defmodule DelegationError do
    @moduledoc """
    Signal for delegation failure.

    Emitted when a delegated task fails, providing error details.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the original delegation request
    - `:error_type` (required) - Error classification atom
    - `:message` (required) - Human-readable error message
    - `:source_agent` (optional) - Agent where the error occurred
    """

    use Jido.Signal,
      type: "ai.delegation.error",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the delegation"],
        error_type: [type: :atom, required: true, doc: "Error classification"],
        message: [type: :string, required: true, doc: "Human-readable error message"],
        source_agent: [type: :any, doc: "Agent where the error occurred"]
      ]
  end

  defmodule CapabilityQuery do
    @moduledoc """
    Signal for capability discovery request.

    Emitted when an orchestrator needs to discover available agent capabilities.

    ## Data Fields

    - `:call_id` (required) - Correlation ID for the query
    - `:required_capabilities` (optional) - Filter by required capabilities
    """

    use Jido.Signal,
      type: "ai.capability.query",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the query"],
        required_capabilities: [type: {:list, :string}, default: [], doc: "Required capabilities filter"]
      ]
  end

  defmodule CapabilityResponse do
    @moduledoc """
    Signal for capability discovery response.

    Response to a capability query with agent's capabilities.

    ## Data Fields

    - `:call_id` (required) - Correlation ID matching the query
    - `:agent_ref` (required) - Agent reference (module, pid, or tag)
    - `:capabilities` (required) - Capability descriptor
    """

    use Jido.Signal,
      type: "ai.capability.response",
      default_source: "/ai/orchestration",
      schema: [
        call_id: [type: :string, required: true, doc: "Correlation ID for the query"],
        agent_ref: [type: :any, required: true, doc: "Agent reference"],
        capabilities: [type: :map, required: true, doc: "Capability descriptor"]
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
  def extract_tool_calls(%{type: "react.llm.response", data: %{result: {:ok, result}}}) do
    case result do
      %{type: :tool_calls, tool_calls: tool_calls} when is_list(tool_calls) -> tool_calls
      %{tool_calls: tool_calls} when is_list(tool_calls) and tool_calls != [] -> tool_calls
      _ -> []
    end
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
  def tool_call?(%{type: "react.llm.response", data: %{result: {:ok, result}}}) do
    case result do
      %{type: :tool_calls} -> true
      %{tool_calls: tool_calls} when is_list(tool_calls) and tool_calls != [] -> true
      _ -> false
    end
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
      {:ok, %Jido.Signal{type: "react.llm.response", ...}}
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

    LLMResponse.new(signal_data)
  end

  # Private helpers for from_reqllm_response

  defp extract_response_tool_calls(%{message: %{tool_calls: tool_calls}}) when is_list(tool_calls) do
    Enum.map(tool_calls, &ReqLLM.ToolCall.from_map/1)
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
