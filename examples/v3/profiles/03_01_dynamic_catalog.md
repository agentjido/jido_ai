# 03_01: Dynamic tools and prompts

The [Agents and Actions](../lib/examples/03_tools/03_01_dynamic_catalog/agent.ex)
and [integration cases](../test/examples/03_tools/03_01_dynamic_catalog_test.exs)
use the public `Jido.AI` facade, native DSL, core commands and the shared mock.

```sh
mix test test/examples/03_tools/03_01_dynamic_catalog_test.exs --include integration --seed 0
```

`Jido.AI.Runtime.Plugin` now owns `state.jido_ai_config`. It stores portable
per-profile tool and instruction overrides. The static profile stays in the
Agent definition. Before each command, the Plugin validates and combines the
static profile with its overrides. Provider schema and tool lookup come from
that one effective catalog. Model options and runtime callbacks stay outside
this state.

Public live calls retain their names and tagged Agent results:

```elixir
{:ok, agent} = Jido.AI.register_tool(server, MyApp.Lookup)
{:ok, agent} = Jido.AI.set_system_prompt(server, "Use current case facts.")
{:ok, agent} = Jido.AI.unregister_tool(server, "lookup")
```

The live calls accept `timeout:`. Registration retains `validate:` for its
initial module check; the final catalog must always pass validation. Repeated
registration keeps one target, and conflicting public names fail. Missing or
invalid modules fail before a catalog commit. Removal uses the public name,
including native aliases. Empty prompt text removes the ReAct base prompt.
Other reasoning methods retain their documented prompt rules.

`profile:` selects a native profile for live calls or direct registration.
The default is the public adapter's profile, `assistant` when present, or the
only declared profile. A change on an ambiguous multi-profile Agent needs an
explicit profile. `Configuration.profile(agent, id)` reads that profile.
The short legacy list/config helpers apply to the default profile.

The pure direct APIs keep their return shapes: register and unregister return
`{:ok, agent}`; `set_system_prompt_direct/2` returns an Agent. They validate the
whole new value and make no Server call. In an ordinary Action, use a
configuration directive to commit a change to Plugin state:

```elixir
{:ok, context.agent_state,
 [%Jido.AI.Configuration.Change{
   profile_id: :assistant,
   operation: :register,
   value: MyApp.Lookup
 }]}
```

The example also calls the direct API inside a real Action, then returns its
intent as a directive. Returning a forged replacement for the protected
`jido_ai_config` domain key is rejected. No new process, mutable global catalog,
or v2 Strategy state is used.

An admitted request keeps its tool catalog and prompt. The held-tool example
removes a tool, adds a different Action with the same name and changes the
prompt while the original tool runs. That request finishes with the original
Action and prompt. The next request calls the replacement. Completion cannot
overwrite the newer configuration. A configuration update does not cancel
already admitted work; use cancellation when that is required.

The lowerer adds `jido.ai.configure` and the three retained
`ai.react.register_tool`, `ai.react.unregister_tool` and
`ai.react.set_system_prompt` routes. They share one Action and state reducer.
Explicit trusted codec registries must identify that Action and its operation
atoms. Native DSL, Builder, lowered Agent JSON and AI source JSON definitions
are equal and perform the same live updates.

The public facade now compiles from the production shared directory. Its text,
object, stream and `ask` helpers use the same Models implementation and real
HTTP/SSE transport. `get_strategy_config/1` derives the effective model,
prompt, tools, schemas and common limits instead of exposing Strategy state.
It is a compatibility view, not the full old private config structure.

`get_strategy_context/1` now projects committed domain history into an AI
Context with a stable Agent/profile ID. `update_context_entries/2` accepts
Context's reverse entry order and updates the declared history field. These
pure Agent views do not expose or replace a worker's private in-flight buffer.
Use the Session event and steering APIs for active work. Complete legacy
worker/context conversion remains a required migration check.

Portable override reconstruction succeeds, and invalid restored catalogs are
rejected. This is in-memory reconstruction evidence; durable backup, versioned
state import and rollback remain separate gates. Public consumer coverage,
all legacy options and metadata, skill/resource integration, standalone work,
root dependencies, full package and supported runtime checks remain open.


[03_02](03_02_tool_context.md) adds persistent base tool context to the same
Configuration Plugin. It preserves complete replacement and request precedence.
