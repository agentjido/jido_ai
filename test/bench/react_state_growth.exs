Code.require_file("support.exs", __DIR__)

alias JidoAI.Bench.ReAct.{Probe, Report}

rounds = JidoAI.Bench.ReAct.rounds!(System.argv(), [5, 20])
reports = Enum.map(rounds, &Probe.run/1)

Report.print_summary(reports)
Enum.each(reports, &Report.print_rounds/1)
