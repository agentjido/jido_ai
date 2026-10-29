Code.require_file("support.exs", __DIR__)

alias JidoAI.Bench.ReAct.{Probe, Report}

[rounds] = JidoAI.Bench.ReAct.rounds!(System.argv(), [20], one: true)
rounds |> Probe.run_memory() |> Report.print_memory()
