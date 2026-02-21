# Issue 06: Fix Module Grouping and Docs Nav Curation

## Severity

- P2

## Problem

Module grouping config in `mix.exs` includes stale entries and leaves real modules ungrouped in API docs navigation.

## Impact

- API reference feels inconsistent and harder to browse.
- Important supporting modules are hidden under ungrouped buckets.

## Evidence

- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:175`
- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:238`

Ungrouped modules observed:
- `Jido.AI.Request.Handle`
- `Jido.AI.Retrieval.Store`
- `Jido.AI.Thread.Entry`

Stale grouped module:
- `Jido.AI.Streaming.ID` (not present)

## Recommended Fix

- Remove stale group entries.
- Add explicit groups for nested support modules (or include them under existing `Core`/`Quality & Quota` buckets).
- Rebuild docs and confirm no ungrouped core-support modules remain.

## Acceptance Criteria

- Sidebar grouping cleanly reflects actual module surface.
- No stale module references in `groups_for_modules`.
