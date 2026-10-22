defmodule Jido.AI.Actions.ToolCalling.RunTools do
  @moduledoc false
  use Jido.Action, name: "tool_calling_run_tools"

  def run(state, context) do
    with {:ok, turn} <-
           Jido.AI.Tools.Executor.run_tools(state.turn, context, tools: state.tools, timeout: state.timeout) do
      {:ok,
       %{
         state
         | round: state.round + 1,
           messages: state.messages ++ Jido.AI.Model.Response.tool_messages(turn)
       }}
    end
  end
end
