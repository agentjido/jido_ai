# Issue 05: Reorder Guide Navigation for Onboarding Funnel

## Severity

- P2

## Problem

Guide order in HexDocs currently puts migration content before core onboarding content.

## Impact

- New users can land in upgrade material before they understand core usage.
- Increased cognitive load in the first session.

## Evidence

- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:146`
- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:147`
- `/Users/mhostetler/Source/Jido/jido_ai/mix.exs:148`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:98`
- `/Users/mhostetler/Source/Jido/jido_ai/DOCS_MANIFESTO.md:37`

## Recommended Fix

- Reorder `Build With Jido.AI` to this sequence:
  - getting started
  - first agent
  - strategy selection
  - request lifecycle
  - thread context
  - tool calling
  - observability
  - cli workflows
- Move migration guide into a separate `Upgrading` group.

## Acceptance Criteria

- New-reader path flows from install to first success before advanced/upgrade topics.
- Migration content is discoverable but not on the primary onboarding path.
