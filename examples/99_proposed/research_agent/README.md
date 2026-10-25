# Proposed Research Agent

This is a kitchen-sink example. It shows how the current core Jido Agent DSL
and the Jido AI DSL compose in one definition.

The example includes:

- a typed Agent state schema and metadata;
- a fresh `Jido.Session` returned by `initialize/2` for each instance;
- a typed request Action and a structured route reply projection;
- one route Action that returns Session state and reply data;
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
alias JidoAI.Examples.Proposed.ResearchAgent.Agent

{:ok, agent} = ResearchAgent.new(id: "research-1")
request = Agent.ask_signal!(%{query: "How does the Jido Agent DSL compose?"})

{:ok, updated, directives} =
  Agent.cmd(agent, request, context: %{role: :researcher})
```

`ResearchAgent.new/1` calls the Agent module's normal instantiate function.
Core Jido gives `initialize/2` the declared and explicit candidate state. The
callback keeps a supplied Session. When the candidate has no Session, it adds a
new one, so separate new instances do not share an identity.

## Run the tests

```sh
mix test test/examples/99_proposed/research_agent/research_agent_test.exs --include example
```

Buffered output controls are part of this definition. For this reason, use
`generate/2`, `reason/2`, or the routed request. `stream/2` rejects a definition
that has output controls because output validation needs the complete reply.
