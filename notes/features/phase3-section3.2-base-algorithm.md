# Phase 3 Section 3.2: Base Algorithm

**Branch**: `feature/phase3-base-algorithm`
**Status**: Completed
**Created**: 2026-01-04

## Problem Statement

After defining the Algorithm behavior in section 3.1, we need a convenient base module that provides default implementations and helper functions. This allows algorithm implementations to focus on their core logic without reimplementing common patterns.

## Solution Overview

Create `Jido.AI.Algorithms.Base` module that:
1. Provides `__using__` macro for convenient algorithm creation
2. Injects the Algorithm behavior automatically
3. Provides default implementations for optional callbacks
4. Includes helper functions for common algorithm patterns

## Technical Details

### File Structure

```
lib/jido_ai/
├── algorithms/
│   ├── algorithm.ex   # Behavior (done in 3.1)
│   └── base.ex        # Base implementation

test/jido_ai/
├── algorithms/
│   ├── algorithm_test.exs  # (done in 3.1)
│   └── base_test.exs       # Base tests
```

### __using__ Macro

The macro accepts options:
- `:name` - Algorithm name for metadata
- `:description` - Algorithm description for metadata
- Additional metadata keys passed through

### Default Implementations

- `can_execute?/2` - Returns `true` (always executable by default)
- `before_execute/2` - Returns `{:ok, input}` (pass-through)
- `after_execute/2` - Returns `{:ok, result}` (pass-through)

### Helper Functions

- `run_with_hooks/3` - Executes algorithm with before/after hooks
- `handle_error/3` - Processes errors through on_error callback
- `merge_context/2` - Merges additional context into existing context

---

## Implementation Plan

### 3.2.1 Using Macro
- [x] 3.2.1.1 Create `lib/jido_ai/algorithms/base.ex` with module documentation
- [x] 3.2.1.2 Implement `__using__/1` macro with opts
- [x] 3.2.1.3 Inject `@behaviour Jido.AI.Algorithms.Algorithm`
- [x] 3.2.1.4 Provide default `metadata/0` from opts

### 3.2.2 Default Implementations
- [x] 3.2.2.1 Implement default `can_execute?/2` returning `true`
- [x] 3.2.2.2 Implement default `before_execute/2` returning `{:ok, input}`
- [x] 3.2.2.3 Implement default `after_execute/2` returning `{:ok, result}`
- [x] 3.2.2.4 Allow override via `defoverridable`
- [x] 3.2.2.5 Implement default `on_error/2` returning `{:fail, error}` (added)

### 3.2.3 Helper Functions
- [x] 3.2.3.1 Implement `run_with_hooks/2` that wraps execute with before/after hooks
- [x] 3.2.3.2 Implement `handle_error/2` for error handling with on_error callback
- [x] 3.2.3.3 Implement `merge_context/2` for context manipulation

### 3.2.4 Unit Tests for Base Algorithm
- [x] Test `__using__` macro injects behavior
- [x] Test default metadata/0 from opts
- [x] Test default can_execute?/2 returns true
- [x] Test default before_execute/2 passes through
- [x] Test default after_execute/2 passes through
- [x] Test default on_error/2 returns {:fail, error}
- [x] Test run_with_hooks/2 calls hooks in order
- [x] Test handle_error/2 calls on_error callback
- [x] Test defoverridable allows customization

---

## Success Criteria

1. [x] Base module created with `__using__` macro
2. [x] Default implementations provided for optional callbacks
3. [x] Helper functions implemented and documented
4. [x] All unit tests pass (28 tests)
5. [x] Example algorithm can use Base to simplify implementation

## Current Status

**What Works**: All implementation complete, 28 tests passing
**Completed**: __using__ macro, default callbacks, helper functions, unit tests
**How to Run**: `mix test test/jido_ai/algorithms/`

---

## Notes

- Follows the same `__using__` pattern as other Jido modules
- Helper functions are injected into the using module, not called on Base
- The on_error callback is optional, so handle_error must handle missing implementation
