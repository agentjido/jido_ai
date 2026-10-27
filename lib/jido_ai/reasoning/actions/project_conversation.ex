defmodule Jido.AI.Reasoning.Actions.ProjectConversation do
  @moduledoc "Projects the canonical Thread into one model request."

  alias Jido.AI.Context

  use Jido.Action,
    id: "jido.ai/reasoning/actions/project-conversation",
    vsn: 1,
    name: "jido_ai_project_conversation",
    description: "Project Session history into model messages",
    schema: Zoi.map(),
    output_schema: Zoi.map()

  @impl Jido.Action
  def run(%{turn: turn}, _context) do
    with {:ok, context} <-
           Context.new(turn.session,
             instructions: turn.instructions,
             repair_instruction: turn.repair_instruction,
             context_window: turn.context_window,
             request_id: turn.request_id,
             run_id: turn.run_id,
             model_call: turn.model_calls + 1,
             prompt_cache: turn.prompt_cache
           ) do
      {:ok, %{turn: turn, context: context}}
    end
  end
end
