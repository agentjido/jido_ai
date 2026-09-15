defmodule JidoAI.Examples.Planning do
  @moduledoc "Planning Actions and their explicit capability routes share one domain Agent."

  def definition(config \\ []) do
    Jido.Agent.new(%{
      name: "planning_capability",
      schema:
        Zoi.object(%{
          result: Zoi.any() |> Zoi.default(nil),
          review: Zoi.any() |> Zoi.default(nil),
          case_id: Zoi.string() |> Zoi.default("release-17")
        }),
      plugins: [{Jido.AI.Plugins.Planning, config}],
      routes: Jido.AI.Plugins.Planning.signal_routes(config)
    })
  end

  def text(:plan),
    do:
      "## Plan Overview\nPrepare a release.\n\n## Steps\n1. **Scope**\n   - Agree scope.\n2. **Ship**\n   - Deliver it.\n\n## Milestones\n- Release ready"

  def text(:decompose),
    do: "1. Release\n1.1. Agree scope\n1.2. Review changes\n1.2.1. Check tests"

  def text(:prioritize),
    do:
      "## Task Analysis\n1. **Scope** - Score: 9\n2. **Ship** - Score: 7\n\n## Recommended Execution Order\n1. **Scope**\n2. **Ship**\n\n## Notes\nDo scope first."

  def params(:plan),
    do: %{
      goal: "Release the package",
      constraints: ["Keep the API"],
      resources: ["Two developers"],
      max_steps: 2
    }

  def params(:decompose),
    do: %{goal: "Release the package", context: "Keep the API", max_depth: 2}

  def params(:prioritize),
    do: %{tasks: ["Ship", "Scope"], criteria: "Dependencies", context: "Keep the API"}
end
