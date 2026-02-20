Code.require_file(Path.expand("../shared/bootstrap.exs", __DIR__))

alias Jido.AI.Actions.ToolCalling.{CallWithTools, ExecuteTool, ListTools}
alias Jido.AI.Examples.Scripts.Bootstrap
alias Jido.AI.Examples.Tools.ConvertTemperature

Bootstrap.init!(required_env: ["ANTHROPIC_API_KEY"])
Bootstrap.print_banner("Actions Tool Calling Runtime Demo")

context = %{tools: %{ConvertTemperature.name() => ConvertTemperature}}

{:ok, listed} = Jido.Exec.run(ListTools, %{}, context)
Bootstrap.assert!(is_map(listed), "ListTools action did not return a map.")

{:ok, executed} =
  Jido.Exec.run(
    ExecuteTool,
    %{tool_name: ConvertTemperature.name(), params: %{value: 72.0, from: "fahrenheit", to: "celsius"}},
    context
  )

Bootstrap.assert!(is_map(executed), "ExecuteTool action did not return a map.")

{:ok, called} =
  Jido.Exec.run(
    CallWithTools,
    %{
      prompt: "Use convert_temperature for 72F to C and explain.",
      tools: [ConvertTemperature.name()],
      auto_execute: true,
      max_turns: 5
    },
    context
  )

Bootstrap.assert!(is_map(called), "CallWithTools action did not return a map.")

IO.puts("✓ Tool-calling actions list/execute/call_with_tools passed")
