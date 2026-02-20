defmodule Jido.AI.Examples.Tools.Github.SafeUpdateIssue do
  @moduledoc "Guarded GitHub issue update action for examples. Defaults to read-only mode."

  use Jido.Action,
    name: "github_issues_update_safe",
    description: "Update a GitHub issue only when example write mode is explicitly enabled",
    schema: [
      owner: [type: :string, required: true, doc: "Repository owner"],
      repo: [type: :string, required: true, doc: "Repository name"],
      number: [type: :integer, required: true, doc: "Issue number"],
      title: [type: :string, required: false, doc: "Updated issue title"],
      body: [type: :string, required: false, doc: "Updated issue body"],
      state: [type: :string, required: false, doc: "Issue state"],
      labels: [type: {:list, :string}, required: false, doc: "Issue labels"],
      assignees: [type: {:list, :string}, required: false, doc: "Issue assignees"],
      milestone: [type: :integer, required: false, doc: "Milestone ID"],
      metadata: [type: :map, required: false, doc: "Metadata map"],
      lock_reason: [type: :string, required: false, doc: "Lock reason"],
      assignee: [type: :string, required: false, doc: "Primary assignee"]
    ]

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
