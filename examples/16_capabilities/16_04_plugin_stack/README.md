# Default Plugins on public AI Agents

The [Agent examples](agent.ex)
use the public ReAct and CoT macros. Their
[example tests](../../../test/examples/16_capabilities/16_04_plugin_stack/16_04_plugin_stack_test.exs)
exercise real Agent calls, callable reasoning, optional stores and the shared
HTTP mock. Run the 18 example cases with:

```sh
mix test test/examples/16_capabilities/16_04_plugin_stack/16_04_plugin_stack_test.exs --include example --seed 0
```

Three retained root PluginStack tests check the public list helper. The full
focused run also includes the callable reasoning and Quota regressions.

## Defaults and ownership

Public AI Agent macros insert Policy and ModelRouting in that order. The common
lowerer then adds the profile binding Plugin and one Session Plugin. All eight
reasoning option adapters use that composition. The private RunStrategy factory
also restores the Policy and ModelRouting defaults from its old wrappers.

The Session Plugin owns live request work through core Exec. The old
TaskSupervisor Plugin is not inserted, and a public Agent declaration that
explicitly lists it gets a removal instruction. There is no supervisor PID in
portable Agent state. The old source module remains outside the acceptance
compile paths until the remaining v2 runtime internals are removed.

Optional Retrieval and Quota stores are application services. Start them before
Agents that need them. Stopping an Agent stops its held tool work but leaves
those stores available to another Agent. Disabled optional Plugins do not start
or require their stores.

```elixir
use Jido.AI.Agent,
  name: "reviewer",
  tools: [],
  retrieval: %{namespace: "reviews"},
  quota: [scope: "team", max_requests: 20]
```

The public option adapter uses the existing Agent/Flow lowerer. It adds no new
DSL or executor. Native `agent do` and direct `Authoring.lower` definitions keep
their explicit Plugin declarations. The private reasoning factory uses the same
default-list helper without enabling optional external stores.

## Configuration and routes

`PluginStack.default_plugins/1` retains its public name. It now returns v3
keyword configuration in tuple declarations. `true` selects an optional Plugin;
`false` or nil omits it. A plain map or unique keyword list supplies options.
Malformed values and duplicate keys fail before runtime work.

An explicit entry in `plugins:` merges over the same default once. The default
keeps its position. Other explicit Plugins keep their supplied order. Repeated
explicit modules are rejected. For example, a Policy entry can select monitor
mode while ModelRouting remains enabled. A Quota entry can change the error
message while keeping a budget supplied by the `quota:` option.

The public adapter adds route helpers for the eleven supported AI capability
Plugins: Chat, Planning, Retrieval, Quota and the seven reasoning capabilities.
Custom core Plugins retain their state and lifecycle behavior. Declare their
routes explicitly with `signal_routes:`.

Explicit routes replace generated capability routes with the same path, match
and priority. Other generated routes remain available. Duplicate explicit
bindings still fail core validation. Static route input remains part of the
binding. A bare module attribute such as `signal_routes: @case_routes` is
resolved in the caller's compile context. Referenced executable modules are
compiled before core validation so first use cannot fail just because an Action
is not loaded yet.

ModelRouting retains its exact/wildcard and explicit-model rules. Default Chat
routes select their declared aliases. A configured native query route can
select another model; an explicit request model still wins. Default Policy
rejects invalid input before a model request. Monitor configuration allows that
input through the native request path. These are the existing validation rules,
not a general claim that Policy detects all unsafe text.

## Capability results and source forms

A public Agent with an AI capability gets the domain field `capability_result`.
Generated capability routes use this field by default. A quota status map,
retrieval result or callable reasoning result cannot replace `last_result`,
`last_answer` or request records. This matters for CoT and other facades whose
answer field has a string schema. Direct Action result envelopes are unchanged.
An explicit `into:` still must name a suitable declared domain field.

The examples combine all eleven capability namespaces on one Agent, execute
Planning, CoT and Chat, and account for their three actual model calls in one
quota scope. A separate example uses Retrieval and Quota through public query,
status, reset and clear routes while retaining the model answer.

The public macro definition, direct data, Builder and a JSON codec round trip
produce equal core definitions. All four forms run with memory enrichment and
quota accounting. Store scopes and memory namespaces follow distinct Agent IDs
in that example. The JSON codec uses its returned trusted registry; it does not
resolve arbitrary module names from an untrusted document.

## Core default Plugin conversion

The old `default_plugins:` option controlled core Memory, Thread and Identity
choices. It did not disable AI's own Policy or ModelRouting. `false` remains
accepted because v3 does not insert that old core default list. It leaves AI
defaults enabled. Nil means no override.

Map overrides require explicit v3 Plugin and state conversion and currently
raise an error with that instruction. Do not reinterpret a Memory/Thread key as
an AI policy switch. Required history and old state migration remain tracked in
the full migration plan. Their replacement must preserve user capability choices
without restoring removed core v2 runtime code.

## Evidence and remaining work

The first three cases failed before default insertion and option support. The
expanded cases found the missing private-runner Policy default and the route
attribute/first-use loading gaps. Their tests now execute those paths directly.
A core Exec error wraps a private Policy rejection in `details.reason`; the
original policy type remains available there. Public request rejection keeps
its direct structured error.

This example supplies partial evidence for PR 263 Plugin choices and PR 281
ordinary routes. It does not close legacy core state conversion, all facade
options, mutable tool catalogs, standalone APIs, skills/resources, durable
recovery or package gates. Admission-failure events still need the correct
method identity for non-ReAct profiles. Root dependencies still select v2.
