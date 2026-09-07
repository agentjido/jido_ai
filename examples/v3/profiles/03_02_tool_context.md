# 03_02: Persistent tool context

[Agents and Action](../lib/examples/03_tools/03_02_tool_context/agent.ex) and
[14 integration cases](../test/examples/03_tools/03_02_tool_context_test.exs)
use the existing core Agent, Configuration Plugin, Session and Flow. The shared
HTTP mock calls the real Action and receives its context result.

## Set base values

The public Agent option now stores defaults in the profile:

```elixir
use Jido.AI.Agent,
  name: "reviewer",
  model: :fast,
  tools: [MyApp.ReadCase],
  tool_context: %{tenant: "one", region: "us"}
```

The native AI profile accepts the same map:

```elixir
ai :assistant do
  tool_context %{tenant: "one", region: "us"}
  # Define models, reasoning, tools and result here.
end
```

Source data uses `tool_context: %{...}`. Builder, Agent JSON and AI-source JSON
use the same validation. The latter requires the usual host Registry entries.
`false`, `nil`, lists, structs and nonportable values are invalid explicit maps.
Omit the option or use `%{}` for no defaults.

The base map belongs to the definition or the portable Configuration Plugin
override. Runtime handles belong in host/request context. Reserved core fields
and `jido_ai_` fields cannot be base values. A skill catalogue, provider or policy
uses the host binding or automatic `skills` source described in [18_02](18_02_skill_authoring.md).

## Change later requests

```elixir
{:ok, agent} = Jido.AI.set_tool_context(server, %{tenant: "two"})
{:ok, agent} = Jido.AI.set_tool_context_direct(agent, %{tenant: "three"})
```

Both helpers return a tagged Agent result. `profile:` selects a declared profile.
The live helper also accepts `timeout:`. A change replaces the complete base map;
`%{}` clears it. The old `ai.react.set_tool_context` Signal keeps its name and
`tool_context` input field. All forms use the existing configuration directive
and commit validation. A rejected change leaves the Agent unchanged.

For ordinary application fields, the merge order is host context, then base
values, then an explicit request `tool_context`. Request values last for one
request. Tool `forward_context` still controls which fields reach the Action.
Runtime identity and state fields keep their owned values. Request skill binding
fields return an admission error; other reserved request fields are filtered.

An active request retains the context from its admission. A live change affects
the next request, including raw Signals. The public `ask` wrapper no longer
inserts old compile-time defaults into every request. Tool callbacks receive
the effective request context through the same execution path.

## Inspect and restore

`Jido.AI.get_strategy_config(agent, profile_id).base_tool_context` shows the
current base map. It excludes transient per-request values. Omit `profile_id`
for the default profile. Restore retains a committed base replacement and uses
new host/request bindings. An observer PID can reach a tool without becoming a
saved default. Profile changes stay separate from each other.

The cases cover public and raw Signal use, complete replacement, request-only
values, active work, native Turn and Session profiles, projection, format parity,
restore, rejected maps and protected runtime identity. Parent Strategy retirement,
standalone skill continuation, complete old-state conversion and root package
validation remain separate migration work.

## Protected state and module examples

`SnapshotSession` and `SnapshotTurn` declare a counter with value 7 and forward
explicit context fields to `Read`. The public Agent uses the same Action.
Three added cases send forged state/module/ID values, then check the actual
host module and ID, matching `state` and `agent_state`, preserved domain values,
base tenant, real tool output and an unchanged portable definition.

Core rejects reserved `agent_id` and `agent_state` fields in direct Turn command
context. That case proves rejection without a state change, then checks the
remaining supplied values through a real tool call. Session/public request
`tool_context` filters reserved values. These checks do not grant a projected
tool access to fields omitted from its `forward_context` list.

All 14 cases pass with integration and pending-DSL tags included. The first
run without those tags excluded all 14 and is not counted as a passing run.
See the [ReAct lifecycle transfer](../../../docs/v3-spike/react-lifecycle-test-transfer.md)
for the matching retained root cases and source-to-v3 changes.
