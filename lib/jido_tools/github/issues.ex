defmodule Jido.Tools.Github.Issues do
  @moduledoc """
  Tools for interacting with GitHub Issues API.

  Provides actions for creating, listing, filtering, finding, and updating GitHub issues.
  """
  defmodule Create do
    @moduledoc "Action for creating new GitHub issues."

    use Jido.Action,
      name: "github_issues_create",
      description: "Create a new issue on GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, description: "The Github client"],
        owner: [type: :string, description: "The owner of the repository"],
        repo: [type: :string, description: "The name of the repository"],
        title: [type: :string, description: "The title of the issue"],
        body: [type: :string, description: "The body of the issue"],
        assignee: [type: :string, description: "The assignee of the issue"],
        milestone: [type: :string, description: "The milestone of the issue"],
        labels: [type: :array, description: "The labels of the issue"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, _context) do
      body = %{
        title: params.title,
        body: params.body,
        assignee: params.assignee,
        milestone: params.milestone,
        labels: params.labels
      }

      result = Tentacat.Issues.create(params.client, params.owner, params.repo, body)

      {:ok,
       %{
         status: "success",
         data: result,
         raw: result
       }}
    end
  end

  defmodule Filter do
    @moduledoc "Action for filtering GitHub issues by various criteria."

    use Jido.Action,
      name: "github_issues_filter",
      description: "Filter repository issues on GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, description: "The Github client"],
        owner: [type: :string, description: "The owner of the repository"],
        repo: [type: :string, description: "The name of the repository"],
        state: [type: :string, description: "The state of the issues (open, closed, all)"],
        assignee: [type: :string, description: "Filter by assignee"],
        creator: [type: :string, description: "Filter by creator"],
        labels: [type: :string, description: "Filter by labels (comma-separated)"],
        sort: [type: :string, description: "Sort by (created, updated, comments)"],
        direction: [type: :string, description: "Sort direction (asc, desc)"],
        since: [type: :string, description: "Only show issues updated after this time"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, _context) do
      filters = %{
        state: params.state,
        assignee: params.assignee,
        creator: params.creator,
        labels: params.labels,
        sort: params.sort,
        direction: params.direction,
        since: params.since
      }

      result = Tentacat.Issues.filter(params.client, params.owner, params.repo, filters)

      {:ok,
       %{
         status: "success",
         data: result,
         raw: result
       }}
    end
  end

  defmodule Find do
    @moduledoc "Action for finding a specific GitHub issue by number."

    use Jido.Action,
      name: "github_issues_find",
      description: "Get a specific issue from GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, description: "The Github client"],
        owner: [type: :string, description: "The owner of the repository"],
        repo: [type: :string, description: "The name of the repository"],
        number: [type: :integer, description: "The issue number"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, _context) do
      result = Tentacat.Issues.find(params.client, params.owner, params.repo, params.number)

      {:ok,
       %{
         status: "success",
         data: result,
         raw: result
       }}
    end
  end

  defmodule List do
    @moduledoc "Action for listing all issues from a GitHub repository."

    use Jido.Action,
      name: "github_issues_list",
      description: "List all issues from a GitHub repository",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, description: "The Github client"],
        owner: [type: :string, description: "The owner of the repository"],
        repo: [type: :string, description: "The name of the repository"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, _context) do
      result = Tentacat.Issues.list(params.client, params.owner, params.repo)

      {:ok,
       %{
         status: "success",
         data: result,
         raw: result
       }}
    end
  end

  defmodule Update do
    @moduledoc "Action for updating existing GitHub issues."

    use Jido.Action,
      name: "github_issues_update",
      description: "Update an existing issue on GitHub",
      category: "Github API",
      tags: ["github", "issues", "api"],
      vsn: "1.0.0",
      schema: [
        client: [type: :any, description: "The Github client"],
        owner: [type: :string, description: "The owner of the repository"],
        repo: [type: :string, description: "The name of the repository"],
        number: [type: :integer, description: "The issue number"],
        title: [type: :string, description: "The new title of the issue"],
        body: [type: :string, description: "The new body of the issue"],
        assignee: [type: :string, description: "The new assignee of the issue"],
        state: [type: :string, description: "The new state of the issue (open, closed)"],
        milestone: [type: :string, description: "The new milestone of the issue"],
        labels: [type: :array, description: "The new labels of the issue"]
      ]

    @spec run(map(), map()) :: {:ok, map()} | {:error, Jido.Action.Error.t()}
    def run(params, _context) do
      body = %{
        title: params.title,
        body: params.body,
        assignee: params.assignee,
        state: params.state,
        milestone: params.milestone,
        labels: params.labels
      }

      result =
        Tentacat.Issues.update(params.client, params.owner, params.repo, params.number, body)

      {:ok,
       %{
         status: "success",
         data: result,
         raw: result
       }}
    end
  end
end
