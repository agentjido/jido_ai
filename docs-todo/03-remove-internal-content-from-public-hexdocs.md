# Issue 03: Remove Internal Content from Public HexDocs Surface

## Severity

- P1

## Problem

Public docs include maintainer-oriented material that should remain contributor-only.

## Impact

- External docs become noisy and less focused.
- Violates the package-vs-contributor boundary described in the docs manifesto.

## Evidence

- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:144`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:171`
- `/Users/mhostetler/Source/Jido/jido_ai/DOCS_MANIFESTO.md:65`
- `/Users/mhostetler/Source/Jido/jido_ai/DOCS_MANIFESTO.md:453`

## Recommended Fix

- Remove contributor-focused extras from public HexDocs navigation:
  - `CONTRIBUTING.md` from `docs.extras`.
- Trim maintainer-only workflow sections from README/guide content exposed to HexDocs.
- Keep contributor workflows in internal docs only.

## Acceptance Criteria

- Public HexDocs is focused on external package adoption and usage.
- Contributor process docs are no longer first-class public nav items.
