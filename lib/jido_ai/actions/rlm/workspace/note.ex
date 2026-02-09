defmodule Jido.AI.Actions.RLM.Workspace.Note do
  @moduledoc """
  Record a hypothesis, finding, or plan in the exploration workspace.

  Appends a timestamped note to the workspace's `:notes` list and returns
  a summary of the current workspace state.

  ## Parameters

  * `text` (required) - The note text to record
  * `kind` (optional) - One of `"hypothesis"`, `"finding"`, or `"plan"` (default: `"finding"`)

  ## Examples

      {:ok, result} = Jido.Exec.run(Jido.AI.Actions.RLM.Workspace.Note,
        %{text: "Magic number appears in the middle third"},
        %{workspace_ref: ref}
      )
  """

  use Jido.Action,
    name: "workspace_note",
    description: "Record a hypothesis, finding, or plan in the exploration workspace",
    category: "rlm",
    tags: ["rlm", "workspace", "notes"],
    vsn: "1.0.0",
    schema:
      Zoi.object(%{
        text: Zoi.string(),
        kind: Zoi.enum(["hypothesis", "finding", "plan"]) |> Zoi.default("finding")
      })

  alias Jido.AI.RLM.WorkspaceStore

  @impl Jido.Action
  @spec run(map(), map()) :: {:ok, map()}
  def run(params, context) do
    workspace_ref = context.workspace_ref

    note = %{
      kind: Map.get(params, :kind, "finding"),
      text: params.text,
      at: DateTime.utc_now()
    }

    :ok =
      WorkspaceStore.update(workspace_ref, fn workspace ->
        Map.update(workspace, :notes, [note], &[note | &1])
      end)

    summary = WorkspaceStore.summary(workspace_ref)

    {:ok, %{recorded: true, workspace_summary: summary}}
  end
end
