# Issue 02: Align Beta Installation and Version Guidance

## Severity

- P1

## Problem

Installation guidance mixes stable and prerelease constraints, which can cause dependency resolution confusion for beta users.

## Impact

- New users may install mismatched versions.
- Beta onboarding becomes inconsistent and brittle.

## Evidence

- `/Users/mhostetler/Source/Jido/jido_ai/guides/user/getting_started.md:9`
- `/Users/mhostetler/Source/Jido/jido_ai/guides/user/getting_started.md:18`
- `/Users/mhostetler/Source/Jido/jido_ai/guides/user/getting_started.md:19`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:28`
- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:11`
- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:62`

## Recommended Fix

- Standardize all docs on one explicit beta-compatible install matrix:
  - Elixir requirement.
  - `jido` and `jido_ai` dependency constraints.
  - Any required prerelease notes.
- Keep README and `getting_started.md` fully in sync.

## Acceptance Criteria

- All installation snippets show consistent version constraints.
- A fresh project can run the quickstart without version edits.
