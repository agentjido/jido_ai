# Issue 04: Make README Quickstart Copy-Paste Runnable

## Severity

- P2

## Problem

The top README example references undefined application modules, so users cannot run it as-is.

## Impact

- First-run experience fails.
- Lowers confidence in docs quality during evaluation.

## Evidence

- `/Users/mhostetler/Source/Jido/jido_ai/README.md:11`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:14`
- `/Users/mhostetler/Source/Jido/jido_ai/README.md:15`
- `/Users/mhostetler/Source/Jido/jido_ai/DOCS_MANIFESTO.md:559`

## Recommended Fix

- Replace the first code block with a complete runnable quickstart:
  - includes a defined tool module,
  - agent definition,
  - startup and one query call.
- Keep this example under two minutes to run in a fresh app.

## Acceptance Criteria

- README quickstart runs in a new Mix project with documented deps/config.
- No undefined modules in the first runnable block.
