Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Actions.Retrieval.{ClearMemory, RecallMemory, UpsertMemory}
alias Jido.AI.Examples.Scripts.Bootstrap

Bootstrap.init!()
Bootstrap.print_banner("Actions Retrieval Runtime Demo")

namespace = "weather_ops_examples_demo"

{:ok, upsert} =
  Jido.Exec.run(UpsertMemory, %{
    namespace: namespace,
    id: "seattle_weekly",
    text: "Seattle mornings are cooler this week with intermittent rain.",
    metadata: %{source: "weekly_summary", region: "pnw"}
  })

Bootstrap.assert!(is_map(upsert), "UpsertMemory action did not return a map.")

{:ok, recall} = Jido.Exec.run(RecallMemory, %{namespace: namespace, query: "seattle rain outlook", top_k: 2})
Bootstrap.assert!(is_map(recall), "RecallMemory action did not return a map.")

{:ok, cleared} = Jido.Exec.run(ClearMemory, %{namespace: namespace})
Bootstrap.assert!(is_map(cleared), "ClearMemory action did not return a map.")

IO.puts("✓ Retrieval actions upsert/recall/clear passed")
