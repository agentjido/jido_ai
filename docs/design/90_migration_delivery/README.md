> Seam review entry point. This document is pending approval.

# 90 — Migration, delivery, and consumer support

## Briefing

The V3 migration has history records, examples, CLI code, test helpers, and a
large test baseline. The target is a release gate tied to approved seam
requirements and one V3 package set. V3 does not preserve V2 source or data
formats.

## Why this seam exists

- Owner: Package release, documentation, CLI, and test-support maintainers.
- Owns: V2 migration notes, package metadata, removals, CLI, test helpers, guides, release checks, and sibling-package verification.
- Does not own: New production behavior, hidden runtime shims, mixed V2/V3 dependencies, or release before required contracts pass.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Migration | V2 source and V3 migration records coexist | Explicit retain, replace, move, defer, and remove list |
| Verification | Focused tests pass, but root status is not fully green | Requirement-linked full release matrix |
| Metadata and docs | Some ownership text is stale | Current package boundary and examples |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| V2 removal list is incomplete | Old paths can remain active | Complete V2 removal inventory | 90 |
| Release gate is not final | A migration can ship with unknown failures | Exact required suite and package matrix | 90 |

## Decisions requested

1. **V2 removal:** Remove source and data compatibility paths.
   Effect: V3 has one contract.
2. **Release gate:** Require all approved seam acceptance tests and the compatible V3 package matrix to pass.
   Effect: The release result is measurable.

## Dependencies

- Prerequisites: All approved production seams.
- Dependents: None.
- Blockers: CLI scope, checkpoint status, and full-suite gate.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
