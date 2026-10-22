defmodule Jido.AI.Execution.ExecuteTool do
  @moduledoc false
  use Jido.Action, name: "ai_execute_tool"

  @impl Jido.Action
  def run(call, context) do
    {:ok, _} =
      Jido.AI.Orchestration.ExecutionBridge.report(
        context,
        {:event, :tool_started,
         %{
           tool_call_id: call.id,
           tool_name: call.name,
           arguments: call.prepared_arguments
         }}
      )

    remaining = max(call.deadline - System.monotonic_time(:millisecond), 0)

    try do
      Jido.Exec.run(
        Jido.AI.Execution.ToolAttempt,
        Map.merge(call, %{attempt: 1, started_at: System.monotonic_time(:millisecond)}),
        context,
        timeout: remaining
      )
    after
      Jido.AI.Orchestration.ExecutionBridge.report(context, {:activity, {:tool_finished, call.id}})
    end
  end
end
