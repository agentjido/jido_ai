alias Jido.AI.{Actions, Flows, SimpleAgent}

program = SimpleAgent.route_executable!("jido.ai.request")

IO.puts("Agent route: jido.ai.request -> #{inspect(program)} -> jido.ai.response")

for flow <- [program, Flows.ModelRound, Flows.ToolRound] do
  IO.puts("Graph: #{inspect(flow)}")

  flow.flow().components
  |> Enum.sort_by(&elem(&1, 0))
  |> Enum.each(fn {name, component} -> IO.puts("  #{name}: #{component.kind}") end)
end

tool_input = %{
  tool_calls: [
    %{id: "add-1", name: "add", arguments: %{"left" => 2, "right" => 3}},
    %{
      id: "multiply-1",
      name: "multiply",
      arguments: %{"left" => 4, "right" => 5}
    }
  ]
}

{:continue, ^tool_input, tool_flow} =
  Actions.ExpandToolCalls.run(%{kind: :continue, input: tool_input}, %{})

IO.puts("Graph: runtime Parallel tool calls")

tool_flow.components
|> Enum.sort_by(&elem(&1, 0))
|> Enum.each(fn
  {name, %{kind: :parallel, actions: actions}} ->
    IO.puts("  #{name}: parallel")

    Enum.each(actions, fn action ->
      IO.puts("    #{action.name}: #{inspect(action.call.target)}")
    end)

  {name, component} ->
    IO.puts("  #{name}: #{component.kind}")
end)

agent = SimpleAgent.instantiate!(id: "graph-first-example")

request =
  SimpleAgent.request_signal!(%{
    input:
      "Use add for 2 plus 3 and multiply for 4 times 5. Use both tools in the same round, then report both results."
  })

{:ok, unchanged_agent, [%Jido.Agent.Directive.Reply{signal: response}]} =
  SimpleAgent.cmd(agent, request)

IO.inspect(response.data, label: "Result")
IO.inspect(unchanged_agent.state, label: "Agent state")
