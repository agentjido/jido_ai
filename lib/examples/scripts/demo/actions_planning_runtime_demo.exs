Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Actions.Planning.{Decompose, Plan, Prioritize}
alias Jido.AI.Examples.Scripts.Bootstrap

Bootstrap.init!(required_env: ["ANTHROPIC_API_KEY"])
Bootstrap.print_banner("Actions Planning Runtime Demo")

{:ok, plan} =
  Jido.Exec.run(Plan, %{
    goal: "Ship v1 onboarding flow",
    constraints: ["Two engineers", "Six-week timeline"],
    resources: ["Existing auth service", "Hosted Postgres"]
  })

Bootstrap.assert!(is_map(plan), "Plan action did not return a map.")

{:ok, decomposition} =
  Jido.Exec.run(Decompose, %{
    goal: "Ship v1 onboarding flow",
    max_depth: 3,
    context: "B2B SaaS onboarding"
  })

Bootstrap.assert!(is_map(decomposition), "Decompose action did not return a map.")

{:ok, prioritized} =
  Jido.Exec.run(Prioritize, %{
    tasks: ["Design onboarding steps", "Implement analytics events", "Write migration docs"],
    criteria: "Customer impact first, then dependency risk"
  })

Bootstrap.assert!(is_map(prioritized), "Prioritize action did not return a map.")

IO.puts("✓ Planning actions plan/decompose/prioritize passed")
