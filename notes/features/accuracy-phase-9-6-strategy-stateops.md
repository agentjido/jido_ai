# Phase 9.6: Strategy StateOps Migration

**Feature**: Complete StateOps Migration for All Strategy Files
**Status**: In Progress
**Date**: 2025-01-18
**Branch**: `feature/accuracy-phase-9-6-strategy-stateops`

## Overview

Phase 9.1 introduced StateOps for the main `Jido.AI.Strategy.ReAct` module, but several other strategy files still use direct state mutations (`Map.put`, `Map.update`). This phase completes the StateOps migration for all remaining strategy files.

## Problem Statement

Several strategy files still use direct state manipulation instead of the Jido V2 StateOps pattern:

- `lib/jido_ai/strategies/react.ex` - Multiple `Map.put` operations
- `lib/jido_ai/strategies/tree_of_thoughts.ex` - Lines 212, 251
- `lib/jido_ai/strategies/chain_of_thoughts.ex` - Line 184
- `lib/jido_ai/strategies/graph_of_thoughts.ex` - Lines 188, 309, 328, 350
- `lib/jido_ai/strategies/trm.ex` - Line 198
- `lib/jido_ai/strategies/adaptive.ex` - Line 347

Additionally, `lib/jido_ai/strategy/react.ex` has some direct state mutations for config updates.

## Solution Overview

1. **Extend StateOpsHelpers** with config update helpers
2. **Migrate each strategy file** to use StateOps instead of direct mutations
3. **Return state ops from strategy commands** for agent state updates
4. **Add tests** to verify StateOps usage

## Technical Details

### Current Patterns to Replace

```elixir
# Pattern 1: Update config with Map.put
new_config = config |> Map.put(:tools, new_tools)
new_state = Map.put(state, :config, new_config)
agent = StratState.put(agent, new_state)

# Pattern 2: Update state with Map.put
machine
|> Machine.to_map()
|> Map.put(:config, config)

# Pattern 3: Nested Map.put for config updates
new_actions_by_name = Map.put(config[:actions_by_name], module.name(), module)
```

### Target StateOps Pattern

```elixir
# Use StateOps helpers for state updates
state_ops = [
  StateOpsHelpers.update_strategy_state(%{config: new_config})
]

# Return state ops from strategy commands
{:ok, result, state_ops}
```

### New StateOpsHelpers Needed

```elixir
# Config-specific helpers
def update_config(config), do: update_strategy_state(%{config: config})
def set_config_field(key, value), do: set_strategy_field(key, value)
```

## Implementation Plan

### Step 1: Extend StateOpsHelpers (lib/jido_ai/strategy/state_ops_helpers.ex)

- [ ] Add `update_config/1` helper
- [ ] Add `set_config_field/2` helper
- [ ] Add `set_tools/1` helper
- [ ] Add `set_actions_by_name/1` helper
- [ ] Add `set_reqllm_tools/1` helper
- [ ] Add tests for new helpers

### Step 2: Migrate lib/jido_ai/strategy/react.ex

- [ ] Replace `Map.put(:config, ...)` with StateOps
- [ ] Replace `Map.put(state, :config, ...)` with StateOps
- [ ] Return state ops from commands where appropriate
- [ ] Verify tests pass

### Step 3: Migrate lib/jido_ai/strategies/react.ex

- [ ] Replace `Map.put(:config, ...)` with StateOps
- [ ] Replace `Map.put(state, :config, ...)` with StateOps
- [ ] Return state ops from commands where appropriate
- [ ] Verify tests pass

### Step 4: Migrate lib/jido_ai/strategies/tree_of_thoughts.ex

- [ ] Identify Map.put patterns at lines 212, 251
- [ ] Replace with StateOps
- [ ] Verify tests pass

### Step 5: Migrate lib/jido_ai/strategies/chain_of_thoughts.ex

- [ ] Identify Map.put pattern at line 184
- [ ] Replace with StateOps
- [ ] Verify tests pass

### Step 6: Migrate lib/jido_ai/strategies/graph_of_thoughts.ex

- [ ] Identify Map.put patterns at lines 188, 309, 328, 350
- [ ] Replace with StateOps
- [ ] Verify tests pass

### Step 7: Migrate lib/jido_ai/strategies/trm.ex

- [ ] Identify Map.put pattern at line 198
- [ ] Replace with StateOps
- [ ] Verify tests pass

### Step 8: Migrate lib/jido_ai/strategies/adaptive.ex

- [ ] Identify Map.put pattern at line 347
- [ ] Replace with StateOps
- [ ] Verify tests pass

### Step 9: Verification

- [ ] Run all strategy tests
- [ ] Run integration tests
- [ ] Verify no direct Map.put in strategy files
- [ ] Update documentation

## Success Criteria

1. All strategy files use StateOps instead of direct Map.put
2. StateOpsHelpers has config-specific helpers
3. All tests pass
4. No direct state mutations in strategy layer
5. 100% Jido V2 compliance

## Dependencies

- Phase 9.1: StateOps Migration (Complete)
- StateOpsHelpers module (Exists)
- Jido.Agent.StateOp (Available from jido)

## Notes

- Strategies use `StratState` for state management
- StateOps should be returned from strategy commands
- The agent framework applies StateOps to update agent state
- This is the final piece of Jido V2 migration

## References

- Phase 9.1 Summary: `notes/summaries/accuracy-phase-9-1-stateops.md`
- Phase 9 Planning: `notes/planning/accuracy/phase-09-jido-v2-migration.md`
- StateOpsHelpers: `lib/jido_ai/strategy/state_ops_helpers.ex`
