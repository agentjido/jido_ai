defmodule Jido.AI.Signal.ToolError do
  @moduledoc """
  Signal for structured tool execution errors.
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
