Code.require_file("json_agent.ex", __DIR__)

alias Jido.AI.Strategy
alias JidoAI.Examples.JSONAgent

{:ok, definition} = JSONAgent.import()

[%{handler: %{kind: :flow, target: root_flow}}] = definition.routes
true = root_flow == Strategy.ReAct

IO.puts("Loaded Agent from JSON: #{definition.name}")
IO.puts("Root reasoning Flow: #{inspect(root_flow)}")

agent = Jido.Agent.instantiate!(definition, id: "json-simple-agent")

signal =
  JSONAgent.request_signal!(definition, %{
    input: "Use add for 2 plus 3 and multiply for 4 times 5. Report both results."
  })

{:ok, unchanged_agent, [%Jido.Agent.Directive.Reply{signal: reply}]} =
  Jido.Agent.cmd(agent, signal)

IO.inspect(reply.data, label: "Result")
IO.inspect(unchanged_agent.state, label: "Agent state")
