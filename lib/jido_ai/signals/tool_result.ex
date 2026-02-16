defmodule Jido.AI.Signal.ToolResult do
  @moduledoc """
  Signal for tool execution completion.
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
