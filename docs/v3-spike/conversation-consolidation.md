# Conversation consolidation

Status: active. Started 2026-09-15.

## Goal

Use Jido.Session, Jido.Thread, and Jido.Thread.Entry as the canonical
conversation values. Remove duplicate stores and conversions. Preserve all
supported reasoning methods, standalone ReAct, Plugins, recovery, controls,
and commit behavior. Keep these modules in jido_ai.

## Confirmed ownership

Jido.Session already owns exactly one Jido.Thread. Thread owns ordered entries
and its append revision. Session revision also covers session metadata and
closure. Keep these separate revision meanings. Do not add a second entry list
to Session. Jido.AI.Session remains the live request API, not the portable value.

Thread.Entry already has kind, payload, refs, identity, sequence, and time.
Define an AI message payload contract above this provider-independent value;
do not put ReqLLM structs or runtime resources into the portable format.

## Migration order and checkpoints

1. Verify and commit the existing Haiku tool example as the baseline.
2. Establish canonical message-entry and projection contracts with tests.
3. Migrate runtime conversation reads, candidate entries, and commits.
4. Migrate lifecycle, recovery, checkpoints, controls, and standalone adapters.
5. Migrate Profile/DSL configuration, examples, and public inspection APIs.
6. Remove replaced Context/History stores, helpers, configuration, and adapters.
7. Refresh inventories and guides; run all tests and one bounded live Haiku
   ReAct example; commit the completed work.

## Initial consumer map

| Boundary | Current consumers | Required change |
| --- | --- | --- |
| Authoring | Profile.memory.history, Authoring state validation and Context.Operations Plugin installation | One canonical conversation field contract |
| Import | Agent.InitialState converts Context into message maps | Accept canonical values; reject competing stores |
| Native execution | Runtime.Prepare, CallModel, NextBatch, PendingInput, Run | Read a snapshot, collect entries, commit through existing state boundary |
| Session execution | Session.Start, HistoryAction, Settle, Cancel, Inspection | Preserve capture, control, correlation, and completion semantics |
| Checkpoint/resume | ReAct.Checkpoint, Runner, State | Preserve canonical conversation data without runtime resources |
| Provider projection | History, Context, RequestTransform, Operations.Generate | One AI projection path with metadata filtering |
| Context controls | Context.Operations and its Plugin | Preserve tested mutation and stale-request behavior under canonical ownership |

## Acceptance rules

- One authoritative conversation value; no synchronized legacy message list.
- Preserve text, tool exchanges, structured and multimodal content, references,
  and required metadata across serialization and projection.
- Preserve existing failure/cancellation behavior. Do not assume all modes
  commit entries at the same time; inspect and retain their tested contracts.
- Application entries remain valid extension points. Define explicitly which
  entries the AI projection consumes and how invalid AI entries are rejected.
- No new skipped tests, weakened assertions, or mock runtime replacements.
- Format, warnings-as-errors compile, unit/authoring/example tests, inventory
  checks, and one live Haiku three-tool-round run must pass before completion.
- Keep checkpoint commits scoped to this repository. No dependency or
  cross-package changes without a demonstrated need.

## Progress

- Goal started; baseline format, forced compile, and full test command passed.
  Log: `/tmp/jido-ai-conversation-baseline.log`.
- Confirmed Session-to-Thread ownership in the current value implementation.
- Identified the migration boundaries above. Runtime migration has not started.
- Context.Operations already keeps a Session/Thread beside the Profile history
  list. Its sync function records snapshots when the two views differ. This is
  the concrete duplicate-store boundary to remove, not preserve behind a new
  name. Existing lane switching, replacement, deferred operations, operation
  deduplication, and durable skill compaction must survive the migration.
- Current Session-mode history can be published during execution; turn-mode
  history is appended by Runtime.Run. Preserve this distinction in tests.
- Added the first Conversation projection implementation and contract tests.
  It encodes versioned AI message payloads without provider structs, handles
  binary content, and projects only AI entries. Tool-exchange validation moved
  from History into this boundary. History delegates during migration; this is
  temporary, not a second final API. Runtime storage migration remains open.
- Context.Operations now captures versioned canonical AI message entries and
  projects them through Conversation when switching lanes. Context reference
  moved to entry refs. The 83-test ReAct/projection run passed after migrating
  payload-specific assertions. Duplicate domain history storage is still open;
  this checkpoint changes its entry boundary, not the final ownership yet.
- Active storage migration: History now reads/writes a Session in the selected
  Profile field. Context.Operations no longer stores another Session or has a
  sync/capture path. Session admission allocates the value; commits append to
  its Thread. The canonical runtime test proves two requests retain one Session
  identity and grow its Thread from two to four entries, with no duplicate
  conversation in Plugin state. Eight projection/runtime tests passed.
- Migration is not yet a green checkpoint. Older list schemas, direct list
  assertions, initial-state fixtures, and examples still require conversion.
  Context remains a temporary projection type and must be removed as planned.
  Before storage migration, the full entry suite had two outdated payload
  assertions (skill example and context lifecycle integration); migrate them.
- ReasoningDetails require an explicit normalized representation in JSON and
  reconstruction at the ReqLLM boundary; plain JSON maps lose provider replay
  behavior. The codec now preserves that distinction from raw provider maps.
- Migrated list-based history/messages schema declarations in examples and
  fixtures to Conversation.schema (nullable Session; nil means not started).
- Replacement operations now store canonical Thread snapshots, not Context
  structs. Focused tests cover preserved Session identity and the next provider
  request after replacement. Context is still used as a transient projection;
  its removal and remaining list-based assertions are open.
- Request/run reference ownership now applies directly to the canonical store.
  Removed the old split behavior where domain history could retain spoofed IDs
  while a second Thread copy held the trusted IDs. Projection timestamps now
  come from the canonical entry rather than being regenerated on each read.
- Migrated steering and incomplete-response example assertions to public
  conversation inspection; all 29 focused tests passed. Shared example support
  reads the selected Profile's conversation instead of enumerating Session.
- Fixed reference loss in standalone history reconstruction and replacement,
  and preserved entry timestamps through compaction. ReAct/context lifecycle
  and durable skill tests are the current regression gate.
- The first full storage-migration run completed with 82 failures out of 2,871
  tests (one existing exclusion). This is a repair inventory, not a release
  result. Several listed failures have since been fixed; rerun after migration.
- Import now preserves the saved conversation identity and per-entry refs when
  constructing the canonical Session. Import/resume tests check unchanged
  canonical entry prefixes, multimodal provider input, and no tool replay.
  All 39 focused import/resume tests passed.
- Migrated Session inspection and skill-authoring consumers; all 30 focused
  tests passed. A new full-suite run is in
  `/tmp/jido-ai-session-migration-refresh.log`.
- Still required before completion: remove transient Context adapters and old
  configuration/import forms; verify JSON round trips of context-operation
  snapshots, not just message entries; finish remaining suite repairs; refresh
  current documentation and inventories; run final MockLLM and live gates.
- Committed context-operation snapshots now use a versioned JSON-safe payload
  containing an encoded canonical Thread. A runtime test exports/imports the
  owning Session and proves the selected replacement conversation survives.
  All 80 focused snapshot/ReAct tests passed.
- Removed unused duplicate-store validators and the obsolete synchronization
  snapshot branch. All 16 focused state-operation/runtime tests passed.
- Authoring construction/execution checks passed all 119 tests after migrating
  expected initial Session fields and entry-count assertions.
- Fixed the private callable Agent's generated conversation schema. A separate
  confirmatory lifecycle run passed all 12 tests. One earlier run hit its
  400 ms deadline before the provider barrier under concurrent compilation;
  no timeout assertion was weakened.
- Current checkpoint gate: `/tmp/jido-ai-canonical-checkpoint.log` (format,
  regenerated inventory, forced compile, full unit/authoring/example suite).
  The first run found one stale operation-payload assertion. The test now uses
  the operation decoder. The final gate in
  `/tmp/jido-ai-canonical-checkpoint-final.log` passed format, inventory,
  forced compilation, and all 2,872 tests (one existing exclusion).
  This is the canonical-storage checkpoint, not goal completion. Shared
  selection, removal of transient Context values, final documentation, and
  the final live Haiku run remain open.
