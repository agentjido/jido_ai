defmodule Jido.AI.Reasoning.ReAct.Actions.ProjectConversation do
  @moduledoc "Projects the canonical Thread into one model request."

  alias Jido.AI.Thread.Projection

  use Jido.Action,
    id: "jido.ai/reasoning/react/actions/project-conversation",
    vsn: 1,
    name: "jido_ai_react_project_conversation",
    description: "Project Session history into model messages",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, _context) do
    with {:ok, projection} <-
           turn.session
           |> Jido.Session.decode!()
           |> Projection.project(turn.context_window) do
      messages = [%{role: :system, content: turn.instructions}] ++ projection.messages
      messages = maybe_add_repair(messages, turn.repair_instruction)
      {:ok, %{turn: turn, messages: messages, projection: Map.delete(projection, :messages)}}
    end
  end

  defp maybe_add_repair(messages, nil), do: messages

  defp maybe_add_repair(messages, instruction),
    do: messages ++ [%{role: :system, content: instruction}]
end
