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
