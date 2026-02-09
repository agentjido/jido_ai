defmodule Jido.AI.Actions.RLM.Workspace.GetSummary do
  @moduledoc """
  Get a compact summary of exploration progress so far.

  Returns a text summary of the current workspace state including chunk,
  hit, note, and subquery counts, truncated to the specified character limit.

  ## Parameters

  * `max_chars` (optional) - Maximum characters in the summary (default: `2000`)

  ## Examples

      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.RLM.Workspace.GetSummary,
        %{},
        %{workspace_ref: ref}
      )
  """

  use Jido.Action,
    name: "workspace_summary",
    description: "Get a compact summary of exploration progress so far",
    category: "rlm",
    tags: ["rlm", "workspace", "summary"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        max_chars: Zoi.integer() |> Zoi.default(2000)
      })

  alias Jido.AI.RLM.WorkspaceStore

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()}
  def run(params, context) do
    workspace_ref = context.workspace_ref
    max_chars = Map.get(params, :max_chars, 2000)
    summary_text = WorkspaceStore.summary(workspace_ref, max_chars: max_chars)

    {:ok, %{summary: summary_text}}
  end
end
