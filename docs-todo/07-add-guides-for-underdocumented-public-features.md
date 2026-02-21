# Issue 07: Add Guides for Underdocumented Public Features

## Severity

- P3

## Problem

Some public APIs are documented at module level but missing dedicated user-facing guides.

## Impact

- Users discover APIs but do not get task-oriented usage patterns.
- Increases support load and trial-and-error for common use cases.

## Evidence

- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai.ex:208`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai.ex:229`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai.ex:250`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/plugin_stack.ex:1`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/quality/checkpoint.ex:1`

## Recommended New Guides

- `guides/user/llm_facade_quickstart.md`
  - `Jido.AI.generate_text/2`, `generate_object/3`, `stream_text/2`, `ask/2`.
- `guides/user/model_routing_and_policy.md`
  - practical plugin config and routing/policy behavior.
- `guides/user/retrieval_and_quota.md`
  - runtime plugin setup and action usage together.
- `guides/user/strategy_recipes.md`
  - one runnable snippet per strategy family.

## Acceptance Criteria

- Each high-traffic public feature has at least one task-oriented guide.
- README docs map links to all new guides.
