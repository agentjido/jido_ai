# Quota accounting and Agent admission

The [Agent example](../lib/examples/13_policy/13_01_quota/agent.ex) combines
Quota, Chat and a native AI profile. Its DSL variant uses the same core Agent
extension and explicit routes. The
[integration cases](../test/examples/13_policy/13_01_quota_test.exs) exercise
real Actions, Flows, Agents, sessions and the shared HTTP mock.

```sh
mix test test/examples/13_policy/13_01_quota_test.exs --include integration --seed 0
```

There are 28 integration cases and 15 retained root Store, Action and updated
Plugin cases. Integration cases are excluded from the default test command.

## Ownership and admission

Supervise the shared store before starting Agents that use Quota:

```elixir
children = [
  {Jido.AI.Quota.Store, []},
  {Jido, name: MyApp.Jido}
]
```

The GenServer owns counters and call records. There is no implicit process,
public ETS table or global heir. Agents with the same store and scope share the
budget. Data survives an Agent or caller stop. A replacement Store starts empty.
An Agent state snapshot is not a backup of this external ledger.

Declare Plugin options as a keyword list. `state_spec/1` replaces v2 mount
configuration. `store:` selects a registered name; the default is
`Jido.AI.Quota.Store`. Direct Store and Action calls can use an unnamed Store PID
in transient context. An omitted scope resolves to the current Agent ID.
Standalone status/reset Actions retain their context defaults and `"default"`
fallback. An explicit Action scope still wins.

Pure preparation binds the declared policy. Live admission rejects work when
the current budget is exhausted. The model boundary then checks and reserves
one request slot in a single Store operation. This second check also protects
pure `Agent.cmd` execution and concurrent Agents. Caller context cannot replace
the declared store, scope, limits or internal call ID.

The four generation Chat routes, legacy reasoning query/run namespaces and
actual native AI bindings enforce limits. Native routes can have custom names.
Embedding, Planning and unrelated routes retain their previous admission scope.
They are not blocked by this Plugin's model budget. Calls that reach the shared
model boundary still record usage. `enabled: false` disables enforcement while
retaining accounting.

A quota failure is a structured, nonretryable `quota_exceeded` error with scope
and available request/Signal identity. It replaces the old Signal rewrite to
`ai.request.error`. Status and reset remain callable when the budget is exhausted.

## What the counters mean

`usage.requests` counts guarded model invocations. It does not count successful
Agent commits, complete user requests or physical HTTP attempts. A tool loop,
structured-output repair or nested built-in reasoning call can use another slot.
A provider call that fails without a usage report still consumes its slot.
ReqLLM can perform transport retries inside one invocation. The retry example
captures two actual HTTP requests and one completed ledger record.

`usage.total_tokens` sums observed per-call totals. Stream snapshots update a
call by the maximum observed cumulative total; repeated or decreasing snapshots
cannot add the same tokens again. The final response settles that call. Failed
output validation or a failed Agent commit cannot erase completed model cost.

The ledger retains each call ID, start time, state and observed total:

| State | Meaning |
| --- | --- |
| `pending` | The model invocation is still active; partial tokens can be known. |
| `complete` | A usable final usage report was recorded. |
| `unknown` | The call ended without a usable final report; known partial tokens remain. |

Store status also reports `pending_calls`, `unknown_calls` and
`unattributed_calls`. The last count identifies imported aggregate requests
without individual call records. These fields prevent an empty token total from
being presented as proof that no provider work occurred.

ReqLLM normalizes absent OpenAI usage to zero. The accounting boundary therefore
keeps a zero-only normalized response unknown. This includes a genuine zero
response when no separate source can prove it. The public Usage helper retains
its explicit-zero behavior. An explicit external `ai.usage` report can settle a
call at zero. Provider usage provenance and cache-hit accounting remain part of
the full migration checks.

## Correlation and failure

Native model calls retain their actual call IDs. An `ai.usage` mirror uses
`call_id` before request correlation and Signal ID. Separate calls in one user
request remain separate ledger records. A completed report cannot charge again,
even if a repeated event has a different total. An unknown record can accept a
later final report once, adding only newly known tokens. Legacy external token
reports retain valid total precedence and atom/string input/output fallback.

Streaming cancellation, disconnect and work-owner termination preserve known
partial tokens. The owner monitor marks unfinished calls unknown. The mock can
send `{:usage, map}` during a stream. These are nonterminal OpenAI-compatible
usage events; its ordinary final usage event remains terminal.

Native tool rounds and repair calls share the outer budget. A built-in
RunStrategy tool receives the private binding through the existing tool and
session context. The nested example uses a core Flow with a declared prompt
schema and a fixed method. It does not create another AI executor.

Raw RunStrategy as a model tool still exposes a generic `Zoi.atom` option that
cannot currently export to JSON Schema. The Flow example is valid composition,
but it does not close that raw tool-schema compatibility gap. Resolve the gap
without silently narrowing the public Action's accepted values.

## Window and v2 data conversion

Each active call belongs to the window generation that admitted it. Reset or
expiry starts a new generation. A held call's later progress or completion
cannot charge the replacement window. Active records and duplicate protection
are local to the Store lifetime and window. Uncorrelated external reports do
not carry an old generation; they apply to the current window. This is not
durable exactly-once delivery.

The old Store function arities remain. `ensure_table!/0` now checks readiness.
`get/1` retains the stored raw counters; `status/3` reports an expired window as
empty. Positive windows expire at their boundary; a nonpositive window retains
the old no-expiry behavior. Its call records remain until reset; application
retention limits must account for that.

`import_rows/2` accepts v2 `{scope, timestamp, requests, tokens}` tuples or
`{scope, usage_map}` rows. It retains timestamps and aggregate counters. It
validates the entire batch, rejects malformed or duplicate scopes and refuses
to overwrite an existing scope. Use this API instead of writing to the removed
public ETS table. Imported rows cannot recover call IDs absent from v2 data.

GetStatus and Reset retain their direct `{:ok, %{quota: ...}}` result envelopes.
The route helper now selects the shared capability Action, which writes that
result to the declared `into` field, default `:result`, and returns complete Agent
state. Status/reset input accepts known string keys through the common Action
validation path. No runtime PID or call ledger is stored in Agent configuration.

## Remaining migration checks

Token limits reject later calls after observed usage reaches the limit. They do
not reserve unknown output tokens or provide a hard cap on external provider
spend. In-flight calls and failed HTTP attempts can have unknown cost. Durable
Store backup/restore, deployment import, all source-format parity, public usage
provenance and default PluginStack integration remain required. Root dependencies
still select v2; this example does not complete the package migration.
