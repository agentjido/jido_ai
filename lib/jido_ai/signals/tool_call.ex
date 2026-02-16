defmodule Jido.AI.Signal.ToolCall do
  @moduledoc """
  Signal for tool invocation intent.
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
