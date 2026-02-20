defmodule Jido.AI.Examples.IssueTriageAgent do
  @moduledoc """
  Agent for GitHub issue triage (`Jido.AI.Agent`, ReAct strategy implied).

  Demonstrates iterative tool-use reasoning with secure token handling:
  1. Reads GITHUB_TOKEN from environment to create authenticated client
  2. Requires target repo env (`JIDO_AI_EXAMPLES_GITHUB_OWNER` + `JIDO_AI_EXAMPLES_GITHUB_REPO`)
  3. Injects client into tool_context for all tool calls
  3. Fetches issues from a repository
  4. Analyzes content to suggest labels/assignments

  **Why ReAct?** Issue triage is inherently iterative - you rarely know upfront
  which filters or fields you need. ReAct enables: fetch → interpret → refine → act.

  **Security Pattern:** This agent demonstrates how to handle secrets:
  - Token is read from environment (never hardcoded)
  - Client is created in `on_before_cmd/2` callback
  - Client is injected into `tool_context` for tool access
  - Tools receive client via context, not LLM-generated params

  ## Usage

      # Ensure GITHUB_TOKEN is set
      export GITHUB_TOKEN="ghp_your_token_here"
      export JIDO_AI_EXAMPLES_GITHUB_OWNER="agentjido"
      export JIDO_AI_EXAMPLES_GITHUB_REPO="jido"

      # Start the agent
      {:ok, pid} = Jido.start_agent(MyApp.Jido, Jido.AI.Examples.IssueTriageAgent)

      # Ask it to triage issues
      :ok = Jido.AI.Examples.IssueTriageAgent.ask(pid,
        "Find open issues in agentjido/jido and categorize them")

      # Check result
      agent = Jido.AgentServer.get(pid)
      agent.state.last_answer

  ## CLI Usage

      GITHUB_TOKEN=ghp_xxx mix jido_ai --agent Jido.AI.Examples.IssueTriageAgent \\
        "List the 5 most recent issues in agentjido/jido and categorize them"

      # Optional write mode (disabled by default)
      JIDO_AI_EXAMPLES_ALLOW_GITHUB_WRITES=true mix jido_ai --agent Jido.AI.Examples.IssueTriageAgent \\
        "Apply labels to issue #123 in agentjido/jido"

  ## How Token Injection Works

  1. `on_before_cmd/2` intercepts the `:ai_react_start` action
  2. Reads `GITHUB_TOKEN` from environment
  3. Creates `Tentacat.Client` with the token
  4. Merges `%{client: client}` into `tool_context` in the action params
  5. ReAct strategy passes `tool_context` to all tool executions
  6. Tools receive `client` via their execution context

  This pattern keeps secrets out of LLM context while making them available to tools.
  """

  use Jido.AI.Agent,
    name: "issue_triage_agent",
    description: "GitHub issue triage assistant using ReAct reasoning",
    tools: [
      Jido.Tools.Github.Issues.List,
      Jido.Tools.Github.Issues.Filter,
      Jido.Tools.Github.Issues.Find,
      Jido.AI.Examples.Tools.Github.SafeUpdateIssue
    ],
    system_prompt: """
    You are a GitHub issue triage assistant. Your job is to help organize and
    prioritize issues in repositories.

    IMPORTANT: The GitHub client is automatically provided via context - you do NOT
    need to create or pass a client parameter. Just use the owner and repo parameters.

    When triaging issues:
    1. First, list or filter issues to understand what exists
    2. Analyze issue titles and bodies to understand their nature
    3. Categorize issues (bug, feature, docs, question, etc.)
    4. Suggest appropriate labels and priorities
    5. If asked, update issues with your recommendations

    Available tools:
    - github_issues_list: List all issues (params: owner, repo)
    - github_issues_filter: Filter issues (params: owner, repo, state, assignee, labels, etc.)
    - github_issues_find: Get specific issue (params: owner, repo, number)
    - github_issues_update: Update issue (params: owner, repo, number, title, body, state, labels)

    Always explain your reasoning when categorizing issues. Be concise but thorough.
    """,
    max_iterations: 15

  def ask(pid, query, opts) when is_binary(query) do
    with :ok <- validate_required_env() do
      super(pid, query, opts)
    end
  end

  def ask_sync(pid, query, opts) when is_binary(query) do
    with :ok <- validate_required_env() do
      super(pid, query, opts)
    end
  end

  @impl true
  def on_before_cmd(agent, {:ai_react_start, %{query: query} = params} = _action) do
    token = System.get_env("GITHUB_TOKEN")
    owner = System.get_env("JIDO_AI_EXAMPLES_GITHUB_OWNER")
    repo = System.get_env("JIDO_AI_EXAMPLES_GITHUB_REPO")

    missing =
      [{"GITHUB_TOKEN", token}, {"JIDO_AI_EXAMPLES_GITHUB_OWNER", owner}, {"JIDO_AI_EXAMPLES_GITHUB_REPO", repo}]
      |> Enum.filter(fn {_name, value} -> is_nil(value) or value == "" end)
      |> Enum.map(&elem(&1, 0))

    if missing != [] do
      {:error, "Missing required environment variables: #{Enum.join(missing, ", ")}"}
    else
      client = Tentacat.Client.new(%{access_token: token})
      allow_writes = System.get_env("JIDO_AI_EXAMPLES_ALLOW_GITHUB_WRITES") == "true"

      existing_context = Map.get(params, :tool_context, %{})

      new_context =
        existing_context
        |> Map.put(:client, client)
        |> Map.put(:repo_owner, owner)
        |> Map.put(:repo_name, repo)
        |> Map.put(:allow_github_writes, allow_writes)

      updated_params = Map.put(params, :tool_context, new_context)

      agent = %{
        agent
        | state:
            agent.state
            |> Map.put(:last_query, query)
            |> Map.put(:completed, false)
            |> Map.put(:last_answer, "")
            |> Map.put(:github_token_present, true)
            |> Map.put(:github_target, "#{owner}/#{repo}")
            |> Map.put(:github_write_enabled, allow_writes)
      }

      {:ok, agent, {:ai_react_start, updated_params}}
    end
  end

  @impl true
  def on_before_cmd(agent, action), do: {:ok, agent, action}

  @impl true
  def on_after_cmd(agent, _action, directives) do
    snap = strategy_snapshot(agent)

    agent =
      if snap.done? do
        %{
          agent
          | state:
              Map.merge(agent.state, %{
                last_answer: snap.result || "",
                completed: true
              })
        }
      else
        agent
      end

    {:ok, agent, directives}
  end

  defp validate_required_env do
    token = System.get_env("GITHUB_TOKEN")
    owner = System.get_env("JIDO_AI_EXAMPLES_GITHUB_OWNER")
    repo = System.get_env("JIDO_AI_EXAMPLES_GITHUB_REPO")

    missing =
      [{"GITHUB_TOKEN", token}, {"JIDO_AI_EXAMPLES_GITHUB_OWNER", owner}, {"JIDO_AI_EXAMPLES_GITHUB_REPO", repo}]
      |> Enum.filter(fn {_name, value} -> is_nil(value) or value == "" end)
      |> Enum.map(&elem(&1, 0))

    if missing == [] do
      :ok
    else
      {:error, "Missing required environment variables: #{Enum.join(missing, ", ")}"}
    end
  end
end
