# Proposed Research Agent

This is a kitchen-sink example. It shows how the current core Jido Agent DSL
and the Jido AI DSL compose in one definition.

The example includes:

- a typed Agent state schema and metadata;
- a fresh `Jido.Session` added through the definition `initial_state` before
  each instance is built;
- a typed request and structured reply with `Jido.SignalAction`;
- one route Action that commits the Session and returns a Reply Directive;
- an inline ReAct reasoning Flow;
- one Action tool and one Flow tool;
- one module input control;
- one inline output control;
- request, model, iteration, and tool limits;
- an inline route Action;
- a child Agent, a forward route, and a topology connection.

The tools are local and deterministic. The AI request still needs a configured
model provider.

## Build an instance

```elixir
alias JidoAI.Examples.Proposed.ResearchAgent
alias JidoAI.Examples.Proposed.ResearchAgent.{Agent, Ask}

{:ok, agent} = ResearchAgent.new(id: "research-1")
request = Ask.new!(%{query: "How does the Jido Agent DSL compose?"})

{:ok, updated, directives} =
  Agent.cmd(agent, request, context: %{role: :researcher})
```

`ResearchAgent.new/1` computes the Session when the instance is requested. It
puts that Session in the map definition's `initial_state`, then calls
`Jido.Agent.instantiate/2`. Each instance gets a different Session.

## Run the tests

```sh
mix test test/examples/99_proposed/research_agent/research_agent_test.exs --include example
```

Buffered output controls are part of this definition. For this reason, use
`generate/2`, `reason/2`, or the routed request. `stream/2` rejects a definition
that has output controls because output validation needs the complete reply.
