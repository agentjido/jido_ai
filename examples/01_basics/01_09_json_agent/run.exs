alias Jido.AI.Result
alias JidoAI.Examples.JSONAgent, as: Example

{:ok, definition} = Example.import()
{:ok, graph} = Jido.AI.graph(definition)

IO.puts("Loaded Agent from JSON: #{definition.name}")
IO.puts("Selected graph: #{inspect(graph)}")
IO.puts("Root graph nodes:")

graph.flow().components
|> Enum.sort_by(&elem(&1, 0))
|> Enum.each(fn {name, component} ->
  IO.puts("  #{name}: #{component.kind}")
end)

agent = Jido.Agent.instantiate!(definition, id: "json-graph-example")
input = "Reply in one short sentence that confirms the graph completed. Do not call a tool."

{:ok, %Result{status: :completed} = result} =
  Jido.AI.run(agent, input,
    max_tokens: 32,
    temperature: 0.0,
    receive_timeout: 30_000
  )

event_path = result.events |> Enum.map(& &1.type) |> Enum.join(" -> ")

IO.puts("Status: #{result.status}")
IO.puts("Output: #{result.output}")
IO.puts("Events: #{event_path}")
IO.inspect(result.usage, label: "Usage")
