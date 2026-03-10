Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Actions.Quota.{GetStatus, Reset}
alias Jido.AI.Examples.Scripts.Bootstrap

Bootstrap.init!()
Bootstrap.print_banner("Actions Quota Runtime Demo")

context = %{
  plugin_state: %{quota: %{scope: "assistant_ops", window_ms: 60_000, max_requests: 50, max_total_tokens: 20_000}}
}

{:ok, status} = Jido.Exec.run(GetStatus, %{}, context)
Bootstrap.assert!(is_map(status), "GetStatus action did not return a map.")

{:ok, reset} = Jido.Exec.run(Reset, %{scope: "assistant_ops"})
Bootstrap.assert!(is_map(reset), "Reset action did not return a map.")

IO.puts("✓ Quota actions get_status/reset passed")
