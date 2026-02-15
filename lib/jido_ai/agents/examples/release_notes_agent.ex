defmodule Jido.AI.Examples.ReleaseNotesAgent do
  @moduledoc """
  Graph-of-Thoughts agent for synthesizing release notes from GitHub issues.

  Demonstrates GoT's strength in synthesis:
  1. Fetches issues for a milestone/label
  2. Clusters them by theme (features, fixes, chores)
  3. Synthesizes connections and cross-cutting themes
  4. Produces structured release notes

  **Why Graph-of-Thoughts?** Release notes require synthesis across clusters
  where items have non-tree relationships (shared components, cross-cutting
  themes). GoT models these connections explicitly.

  ## Usage

      # Start the agent
      {:ok, pid} = Jido.start_agent(MyApp.Jido, Jido.AI.Examples.ReleaseNotesAgent)

      # Generate release notes
      :ok = Jido.AI.Examples.ReleaseNotesAgent.explore(pid,
        "Generate release notes for the v1.0 milestone of agentjido/jido")

      # Check result
      agent = Jido.AgentServer.get(pid)
      agent.state.last_result

  ## CLI Usage

      mix jido_ai --agent Jido.AI.Examples.ReleaseNotesAgent \\
        "Create release notes summarizing recent changes to the Jido framework"

      mix jido_ai --agent Jido.AI.Examples.ReleaseNotesAgent \\
        "Synthesize a changelog from these themes: new agent strategies, \\
         improved error handling, and CLI enhancements"

  ## How GoT Works Here

  The Graph-of-Thoughts strategy:
  1. **Generates** multiple thought nodes (issue categories, themes)
  2. **Connects** nodes that share relationships (same component, related features)
  3. **Aggregates** via synthesis to produce coherent release notes

  This is superior to linear CoT because release notes naturally have
  cross-references (e.g., "The new ReAct strategy (#42) works with the
  improved error handling (#38) to provide better debugging").
  """

  use Jido.AI.GoTAgent,
    name: "release_notes_agent",
    description: "Synthesizes release notes using Graph-of-Thoughts reasoning",
    max_nodes: 25,
    max_depth: 4,
    aggregation_strategy: :synthesis,
    generation_prompt: """
    You are generating thought nodes for release notes synthesis.

    For each issue or change, create a thought node that captures:
    - Category: feature, fix, improvement, docs, chore, breaking
    - Component: which part of the system it affects
    - User impact: how this affects end users
    - Related items: what other changes this connects to

    Generate diverse perspectives:
    - User-facing view (what they'll notice)
    - Developer view (what changed technically)
    - Migration view (what needs updating)
    """,
    connection_prompt: """
    Find connections between thought nodes for release notes.

    Look for:
    - Shared components (multiple changes to the same module)
    - Causal relationships (fix X enables feature Y)
    - Thematic groupings (all changes related to "performance")
    - Breaking change clusters (changes requiring migration)

    Strong connections should be marked when changes are directly related.
    Weak connections for thematic similarity.
    """,
    aggregation_prompt: """
    Synthesize the thought graph into polished release notes.

    Structure the output as:
    ## 🚀 New Features
    - Feature descriptions with issue references

    ## 🐛 Bug Fixes
    - Fix descriptions

    ## ⚡ Improvements
    - Enhancement descriptions

    ## 📚 Documentation
    - Doc updates

    ## ⚠️ Breaking Changes
    - Migration notes

    ## 🙏 Contributors
    - Thank contributors if known

    Use the graph connections to:
    - Group related changes together
    - Note when features work together
    - Highlight breaking changes prominently
    """

  def cli_adapter, do: Jido.AI.CLI.Adapters.GoT
end
