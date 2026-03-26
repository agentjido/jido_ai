defmodule Jido.AI.Signal.ToolStarted do
  @moduledoc """
  Signal emitted when a tool execution starts.
  """

  use Jido.Signal,
    type: "ai.tool.started",
    default_source: "/ai/tool",
    schema: [
      call_id: [type: :string, required: true, doc: "Tool call ID from the LLM"],
      tool_name: [type: :string, required: true, doc: "Name of the tool being executed"],
      arguments: [
        type: :any,
        required: false,
        doc: "Arguments passed to the tool (may be redacted for sensitive data)"
      ],
      metadata: [type: :map, default: %{}, doc: "Optional request/run/origin metadata for correlation"]
    ]
end
