defmodule Jido.AI.Examples.Tools.Github.SafeUpdateIssue do
  @moduledoc "Guarded GitHub issue update action for examples. Defaults to read-only mode."

  use Jido.Action,
    schema:
      Zoi.object(%{
        owner: Zoi.string(description: "Repository owner"),
        repo: Zoi.string(description: "Repository name"),
        number: Zoi.integer(description: "Issue number"),
        title: Zoi.string(description: "Updated issue title") |> Zoi.optional(),
        body: Zoi.string(description: "Updated issue body") |> Zoi.optional(),
        state: Zoi.string(description: "Issue state") |> Zoi.optional(),
        labels: Zoi.list(Zoi.string([]), description: "Issue labels") |> Zoi.optional(),
        assignees: Zoi.list(Zoi.string([]), description: "Issue assignees") |> Zoi.optional(),
        milestone: Zoi.integer(description: "Milestone ID") |> Zoi.optional(),
        metadata: Zoi.map(description: "Metadata map") |> Zoi.optional(),
        lock_reason: Zoi.string(description: "Lock reason") |> Zoi.optional(),
        assignee: Zoi.string(description: "Primary assignee") |> Zoi.optional()
      }),
    name: "github_issues_update_safe",
    description: "Update a GitHub issue only when example write mode is explicitly enabled"

  @impl true
  def run(params, context) do
    with :ok <- ensure_write_enabled(),
         :ok <- ensure_target_matches(params),
         {:ok, result} <- Jido.Exec.run(Jido.Tools.Github.Issues.Update, params, context) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_write_enabled do
    case System.get_env("JIDO_AI_EXAMPLES_ALLOW_GITHUB_WRITES") do
      "true" -> :ok
      _ -> {:error, "GitHub writes are disabled. Set JIDO_AI_EXAMPLES_ALLOW_GITHUB_WRITES=true to enable."}
    end
  end

  defp ensure_target_matches(%{owner: owner, repo: repo}) do
    expected_owner = System.get_env("JIDO_AI_EXAMPLES_GITHUB_OWNER")
    expected_repo = System.get_env("JIDO_AI_EXAMPLES_GITHUB_REPO")

    cond do
      expected_owner in [nil, ""] or expected_repo in [nil, ""] ->
        {:error,
         "Missing JIDO_AI_EXAMPLES_GITHUB_OWNER/JIDO_AI_EXAMPLES_GITHUB_REPO for guarded write target validation."}

      owner != expected_owner or repo != expected_repo ->
        {:error, "Write target mismatch. Expected #{expected_owner}/#{expected_repo}, got #{owner}/#{repo}."}

      true ->
        :ok
    end
  end
end
