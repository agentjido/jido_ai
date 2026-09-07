# Retrieval memory and Agent enrichment

The [Agent example](../lib/examples/07_retrieval/07_01_memory/agent.ex) combines
Retrieval, Chat and native AI. The
[integration cases](../test/examples/07_retrieval/07_01_memory_test.exs) run the
real Actions, core Agent calls and the shared HTTP mock. Run them with:

```sh
mix test test/examples/07_retrieval/07_01_memory_test.exs --include integration --seed 0
```

There are 21 integration cases. The Agent DSL also declares RecallMemory as a
model tool, with explicit `state` and `retrieval_store` context forwarding. The
model consumes the actual stored result in its next request.

## Store ownership

Add the store to the application supervisor before Agents use it:

```elixir
children = [
  {Jido.AI.Retrieval.Store, []},
  {Jido, name: MyApp.Jido}
]
```

The store owns a private ETS table. Store calls do not start a process. There
is no global heir process or public named table. Writes and clear operations
are serialized by the store. Entries survive the end of an Action task or an
Agent. They survive only as long as the store process; its replacement starts
empty. An Agent checkpoint does not back up this external memory.

The old Store function arities remain. `ensure_table!/0` now checks that the
supervised store is ready; applications must start the owner first. A final
store argument on upsert/clear/namespace inspection, or `store:` in recall
options, selects another owner. Direct Actions accept `context.retrieval_store`.
Unnamed stores can use a PID in transient context. A Plugin's `store:` option
uses a registered name so the declaration stays portable.

Agents with the same store and namespace share memory. An omitted Plugin
namespace resolves to the current Agent ID at the request boundary. Standalone
Actions retain context namespace precedence and the `"default"` fallback.
Explicit Action `namespace` input still wins. Declared Plugin state contains
configuration, not a store PID or a copy of the table.

## Actions and routes

| Signal | Public Action | Retained result under `retrieval` |
| --- | --- | --- |
| `retrieval.upsert` | `Actions.Retrieval.UpsertMemory` | `namespace`, `last_upsert` |
| `retrieval.recall` | `Actions.Retrieval.RecallMemory` | `namespace`, `query`, `memories`, `count` |
| `retrieval.clear` | `Actions.Retrieval.ClearMemory` | `namespace`, `cleared` |

All module names have the `Jido.AI` prefix. Direct and Exec calls retain those
maps. The Plugin's route helper now targets `Actions.Retrieval.RunCapability`.
It puts the Action result in the declared domain `into` field, default `:result`,
and returns the complete Agent state. It preserves unrelated state and protected
Plugin configuration. Forged caller bindings cannot select another Action,
store or result field.

Keyword configuration and `state_spec/1` replace map configuration and `mount/2`.
Core `admit/3` performs live enrichment. `prepare/2` only binds declared Action
defaults and performs no store read. Pure `Agent.cmd` execution therefore has
no automatic enrichment. A pure Flow can explicitly call RecallMemory before
its model Action. Public Plugin metadata, schema, Action catalog and route helper
remain; the old `handle_signal/2` and generated manifest are replaced.

Known string input keys are normalized before validation. Invalid direct and
routed Action inputs fail before a write. Store boundary conversion only reads
known keys and creates no atoms. An unknown string key no longer prevents valid
ID/text/metadata keys from being read. Invalid text conversion fails in the
caller and cannot stop the shared store.

## Ranking and enrichment

The existing token-overlap score remains. Text is lowercased, tokenized with the
original ASCII rule, and compared by intersection divided by union. Results sort
by descending score, then latest update, then ID for stable ties. Upserts retain
the original insertion time and replace text, metadata and update time.
`min_score` defaults to zero, so unrelated or empty queries can still return
entries with zero score. This is not embedding retrieval.

Enrichment retains enabled/disabled settings, per-request atom or string
`disable_retrieval`, top-k selection and snippet length limits. It keeps the
`Relevant memory` and `User prompt` sections and attaches snippet IDs, scores
and metadata. Empty stores and requests without usable text remain unchanged.
Chat enrichment retains its `chat.message` scope; other simple Chat routes
remain unchanged. Legacy reasoning routes retain their enrichment scope.

Native AI routes now use the actual declared query binding, including custom
Signal names. Both one-Turn and session calls receive recalled text. A separate
`prompt` field cannot replace the native query. Session records contain the
enriched query used for execution. Non-text queries pass through without
automatic enrichment.

## Failure and migration limits

A missing store fails live enrichment before model work. Explicit opt-out still
permits that model request. A completed external memory write remains when a
later Agent result validation fails. Consumers must not use the Agent commit
as proof that an external write was rolled back.

The tests cover ordinary Store access, concurrent writes/readiness, direct and
Exec Actions, live routes, the Agent DSL, session requests, namespace sharing,
store replacement and the core checkpoint boundary. The retained root suite
has 17 Store/Action cases and six updated Plugin cases.

Full source-format parity, old-data import with timestamp preservation,
application deployment setup, durable store backup/restore and root consumer
checks remain required. Root dependencies still select v2. This example does
not complete Quota, default PluginStack integration or the full migration goal.
