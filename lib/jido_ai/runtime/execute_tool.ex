defmodule Jido.AI.Runtime.ExecuteTool do
  @moduledoc false
  use Jido.Action, name: "ai_execute_tool"

  @impl Jido.Action
  def run(call, context) do
    :ok =
      Jido.AI.Orchestration.emit(context, :tool_started, %{
        tool_call_id: call.id,
        tool_name: call.name,
        arguments: call.prepared_arguments
      })

    remaining = max(call.deadline - System.monotonic_time(:millisecond), 0)

    try do
      Jido.Exec.run(
        Jido.AI.Runtime.ToolAttempt,
        Map.merge(call, %{attempt: 1, started_at: System.monotonic_time(:millisecond)}),
        context,
        timeout: remaining
      )
    after
      Jido.AI.Orchestration.activity(context, {:tool_finished, call.id})
    end
  end
end
