defmodule Jido.AI.Signal do
  @moduledoc """
  Custom signal types for LLM-based agents.

  These signals are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  They follow a consistent naming convention: `reqllm.<event_type>` for ReqLLM-specific signals
  and `ai.<event_type>` for generic AI signals.

  ## Signal Types

  - `Jido.AI.Signal.ReqLLMResult` - Result from a ReqLLM streaming call
  - `Jido.AI.Signal.ReqLLMPartial` - Streaming token chunk from ReqLLM
  - `Jido.AI.Signal.ToolResult` - Result from a tool execution

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
        result: [type: :any, required: true, doc: "{:ok, result} | {:error, reason}"]
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
end
