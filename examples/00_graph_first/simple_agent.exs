Code.require_file("simple_agent.ex", __DIR__)

alias Jido.AI.Reasoning.ReAct
alias Jido.AI.Reasoning.ReAct.Actions
alias JidoAI.Examples.SimpleAgent

program = SimpleAgent.route_executable!("jido.ai.request")

IO.puts("Agent route: jido.ai.request -> #{inspect(program)} -> jido.ai.response")

for flow <- [
      program,
      ReAct.ModelRound,
      ReAct.ToolReview
    ] do
  IO.puts("Graph: #{inspect(flow)}")

  flow.flow().components
  |> Enum.sort_by(&elem(&1, 0))
  |> Enum.each(fn {name, component} -> IO.puts("  #{name}: #{component.kind}") end)
end

tool_input = %{
  turn: %{
    model_outcome: %{
      tool_calls: [
        %{id: "add-1", name: "add", arguments: %{"left" => 2, "right" => 3}},
        %{
          id: "multiply-1",
          name: "multiply",
          arguments: %{"left" => 4, "right" => 5}
        }
      ]
    }
  }
}

{:continue, ^tool_input, tool_flow} =
  Actions.ExpandNext.run(%{kind: :tools, input: tool_input}, %{})

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
      "Use add for 2 plus 3 and multiply for 4 times 5. Use both tools in the same round, then report both results.",
    stream: true
  })

{:ok, next_agent, [%Jido.Agent.Directive.Reply{signal: response}]} =
  SimpleAgent.cmd(agent, request, context: %{jido_ai_dispatch: {:pid, target: self()}})

IO.inspect(response.data, label: "Result")

drain = fn drain, signals ->
  receive do
    {:signal, signal} -> drain.(drain, [signal | signals])
  after
    0 -> Enum.reverse(signals)
  end
end

stream_signals = drain.(drain, [])
IO.inspect(Enum.map(stream_signals, & &1.type), label: "Stream Signals")

session = next_agent.state.session

IO.inspect(
  %{
    session_id: session.id,
    thread_id: session.thread.id,
    thread_rev: session.thread.rev,
    entry_kinds: Enum.map(session.thread.entries, & &1.kind)
  },
  label: "Committed conversation"
)
