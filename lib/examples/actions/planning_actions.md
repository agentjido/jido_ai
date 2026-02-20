# Planning Action Snippets

Run these from the repository root with provider credentials configured.

## Plan Action

```bash
mix run -e 'alias Jido.AI.Actions.Planning.Plan; {:ok, result} = Jido.Exec.run(Plan, %{goal: "Ship v1 onboarding flow", constraints: ["Two engineers", "Six-week timeline"], resources: ["Existing auth service", "Hosted Postgres"]}); IO.inspect(result, label: "plan")'
```

## Decompose Action

```bash
mix run -e 'alias Jido.AI.Actions.Planning.Decompose; {:ok, result} = Jido.Exec.run(Decompose, %{goal: "Ship v1 onboarding flow", max_depth: 3, context: "B2B SaaS, team is balancing reliability and speed"}); IO.inspect(result, label: "decompose")'
```

## Prioritize Action

```bash
mix run -e 'alias Jido.AI.Actions.Planning.Prioritize; {:ok, result} = Jido.Exec.run(Prioritize, %{tasks: ["Design onboarding steps", "Implement analytics events", "Write migration docs"], criteria: "Customer impact first, then dependency risk"}); IO.inspect(result, label: "prioritize")'
```

## Planning Workflow With Task Decomposition

```elixir
alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}

goal = "Launch self-serve onboarding for enterprise customers"

{:ok, plan} =
  Jido.Exec.run(Plan, %{
    goal: goal,
    constraints: ["Release in 8 weeks", "No schema-breaking migrations"],
    resources: ["2 backend engineers", "1 product designer", "existing auth and billing services"]
  })

{:ok, decomposition} =
  Jido.Exec.run(Decompose, %{
    goal: goal,
    max_depth: 3,
    context: "Need rollout gates for support and sales enablement"
  })

tasks = decomposition.sub_goals

{:ok, prioritized} =
  Jido.Exec.run(Prioritize, %{
    tasks: tasks,
    criteria: "Dependency order, customer impact, and implementation risk",
    context: "Team needs an MVP in week 6 and hardening in weeks 7-8"
  })

%{
  plan: plan.steps,
  decomposed_tasks: tasks,
  ranked_order: prioritized.ordered_tasks
}
```
