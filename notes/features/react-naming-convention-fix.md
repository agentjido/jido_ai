# ReAct Naming Convention Refactoring

## Problem Statement

The ReAct (Reason-Act) agent implementation uses an inconsistent naming convention compared to all other algorithm implementations in Jido.AI:

- **Current**: `Jido.AI.Strategy.ReAct` (singular `Strategy`)
- **Expected**: `Jido.AI.Strategies.ReAct` (plural `Strategies`)

All other algorithms (ChainOfThought, TreeOfThoughts, GraphOfThoughts, TRM, Adaptive) use the plural `Jido.AI.Strategies.*` namespace.

## Impact Analysis

**Inconsistencies caused:**
1. ReAct strategy is in `lib/jido_ai/strategy/react.ex` while all others are in `lib/jido_ai/strategies/`
2. Developers must remember the exception when looking up strategies
3. Auto-completion in IDEs groups ReAct separately from other strategies
4. Documentation and examples show inconsistent patterns

**Files affected:**
- `lib/jido_ai/strategy/react.ex` → `lib/jido_ai/strategies/react.ex`
- `lib/jido_ai/react_agent.ex` (references strategy)
- `lib/jido_ai/signal.ex` (documentation)
- `lib/jido_ai/strategies/adaptive.ex` (alias)
- `lib/jido_ai/strategies/trm.ex` (comment)
- `test/jido_ai/strategy/react_test.exs` → `test/jido_ai/strategies/react_test.exs`
- `test/jido_ai/integration/strategies_phase4_test.exs`
- `test/jido_ai/strategies/adaptive_test.exs`
- `CLAUDE.md`
- Various notes/docs

## Solution Overview

**Primary Change:**
1. Move `lib/jido_ai/strategy/react.ex` → `lib/jido_ai/strategies/react.ex`
2. Rename module from `Jido.AI.Strategy.ReAct` → `Jido.AI.Strategies.ReAct`
3. Update all references throughout the codebase

**Breaking Change:** Yes - users referencing `Jido.AI.Strategy.ReAct` will need to update to `Jido.AI.Strategies.ReAct`

## Technical Details

### Files to Modify

**Core Implementation:**
| From | To |
|------|-----|
| `lib/jido_ai/strategy/react.ex` | `lib/jido_ai/strategies/react.ex` |
| `Jido.AI.Strategy.ReAct` | `Jido.AI.Strategies.ReAct` |

**References to Update:**
- `lib/jido_ai/react_agent.ex:88` - Strategy tuple reference
- `lib/jido_ai/signal.ex:97` - Documentation
- `lib/jido_ai/strategies/adaptive.ex:80` - Alias
- `lib/jido_ai/strategies/trm.ex:3` - Comment

**Tests:**
| From | To |
|------|-----|
| `test/jido_ai/strategy/react_test.exs` | `test/jido_ai/strategies/react_test.exs` |
| `Jido.AI.Strategy.ReActTest` | `Jido.AI.Strategies.ReActTest` |
| `test/jido_ai/integration/strategies_phase4_test.exs` | Update alias |
| `test/jido_ai/strategies/adaptive_test.exs` | Update alias |

**Documentation:**
- `CLAUDE.md:52` - Update reference

### Implementation Steps

1. [x] Move strategy file from `lib/jido_ai/strategy/` to `lib/jido_ai/strategies/`
2. [x] Rename module to `Jido.AI.Strategies.ReAct`
3. [x] Update `lib/jido_ai/react_agent.ex` reference
4. [x] Update `lib/jido_ai/signal.ex` documentation
5. [x] Update `lib/jido_ai/strategies/adaptive.ex` alias
6. [x] Update `lib/jido_ai/strategies/trm.ex` comment
7. [x] Move test file and update test module name
8. [x] Update integration test aliases
9. [x] Update CLAUDE.md
10. [x] Run full test suite to verify
11. [x] Run `mix format` and `mix credo`

## Success Criteria

- [x] All strategy modules are under `Jido.AI.Strategies.*` namespace
- [x] No references to `Jido.AI.Strategy.ReAct` remain in code
- [x] All 1375 tests pass
- [x] No Credo warnings for changed files
- [x] Code compiles cleanly

## Implementation Plan

### Step 1: Move and Rename Core Module
- Move `lib/jido_ai/strategy/react.ex` → `lib/jido_ai/strategies/react.ex`
- Update module declaration from `defmodule Jido.AI.Strategy.ReAct` → `defmodule Jido.AI.Strategies.ReAct`

### Step 2: Update References in lib/jido_ai/
- `react_agent.ex` - Update strategy tuple
- `signal.ex` - Update documentation
- `strategies/adaptive.ex` - Update alias
- `strategies/trm.ex` - Update comment

### Step 3: Move and Update Tests
- Move test file to strategies directory
- Update test module name
- Update aliases in integration tests

### Step 4: Update Documentation
- Update CLAUDE.md reference

### Step 5: Verify
- Run test suite
- Run formatter and linter
- Fix any issues

## Notes/Considerations

1. **Breaking Change:** This is a breaking change for any external code referencing `Jido.AI.Strategy.ReAct`. Since this is pre-1.0 software, this is acceptable but should be noted.

2. **Deprecation Path:** We could add a deprecated alias in the old location, but since this is still pre-1.0, a clean break is preferred.

3. **Import Impact:** The `Jido.AI.ReActAgent` macro uses the strategy internally, so most users won't need to change their code - they just use `use Jido.AI.ReActAgent`.

## Status

**Current Status:** ✅ Complete

**What works:**
- All strategy modules now use consistent `Jido.AI.Strategies.*` namespace
- All 1375 tests passing
- No Credo warnings for changed files
- Code formatted and clean

**What's next:** Ready for review and merge

**How to test:** Run `mix test` to verify all tests pass

---

*Last updated: 2025-01-06*
