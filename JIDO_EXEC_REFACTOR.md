# Jido.Exec Refactoring Plan

## Overview

The `Jido.Exec` module (located at `projects/jido_action/lib/exec.ex`) is a 1,000-line monolithic module that handles action execution, retries, timeouts, async orchestration, and error handling. This plan breaks it down into focused helper modules while maintaining the existing public API as a facade.

## Target Architecture

All new modules will be placed under `projects/jido_action/lib/jido_action/exec/`:

- **exec/validator.ex** - Action and output validation (behaviour-friendly)
- **exec/retry.ex** - Backoff calculation and retry orchestration  
- **exec/telemetry.ex** - Telemetry events and logging helpers
- **exec/compensation.ex** - Error handling and compensation logic
- **exec/async.ex** - Async execution (`run_async`, `await`, `cancel`)

The main `Jido.Exec` module remains as the primary interface, keeping core execution logic while delegating specialized concerns to helper modules.

## Refactoring Steps

### Step 0: Baseline Safety Net

**Goal**: Establish comprehensive test coverage and safety checks before refactoring.

**Actions**:
1. Ensure current test suite passes: `mix test && mix dialyzer`
2. Add high-level integration tests covering:
   - Happy path sync execution
   - Happy path async execution
   - Timeout scenarios
   - Retry scenarios (inject failing Action)
   - Compensation scenarios (Action with `on_error/4`)
3. Enable code coverage (`excoveralls`) to guard against regressions

**Files to touch**: `test/jido_action/exec_test.exs` (add integration tests)

**Validation**: 
- `mix test && mix dialyzer` passes
- Coverage ≥ current baseline
- All integration scenarios covered

### Step 1: Create Internal Namespace & Extract Validator

**Goal**: Create the exec namespace and extract validation logic as the first separation of concerns.

**Actions**:
1. Create directory: `mkdir lib/jido_action/exec`
2. Create `Jido.Exec.Validator` module with:
   - `validate_action/1`
   - `validate_params/2` 
   - `validate_output/3`
3. Update Exec module to call `Validator.*` functions
4. Keep parameter normalization in main module for now

**Files to touch**:
- `lib/jido_action/exec/validator.ex` (new)
- `lib/exec.ex` (update validation calls)

**Validation**: 
- Compilation successful
- Full test suite passes
- No new dialyzer warnings

### Step 2: Extract Telemetry Module

**Goal**: Centralize all telemetry, logging, and debugging helpers.

**Actions**:
1. Create `Jido.Exec.Telemetry` module with:
   - `emit_start_event/3`, `emit_end_event/4`
   - `log_execution_start/3`, `log_execution_end/4`
   - `extract_safe_error_message/1`
   - `cond_log` wrapper functions
2. Update Exec to use Telemetry module for all logging/events
3. Remove telemetry private functions from main module

**Files to touch**:
- `lib/jido_action/exec/telemetry.ex` (new)
- `lib/exec.ex` (update telemetry calls)

**Validation**: Telemetry events and logs still work as expected

### Step 3: Extract Retry Module

**Goal**: Centralize retry logic and backoff calculations.

**Actions**:
1. Create `exec/retry.ex` with:
   - `calculate_backoff/2`
   - `should_retry?/4` (error, attempt, max_attempts, opts)
   - Move retry-specific option handling
2. Update main module to use Retry functions for backoff and retry decisions
3. Keep core retry loop in main module but delegate calculations

**Files to touch**:
- `lib/jido_action/exec/retry.ex` (new)
- `lib/exec.ex` (update retry logic)

**Validation**: 
- Failing Action with eventual success still works
- Max retries behavior maintained

### Step 4: Extract Compensation Module

**Goal**: Isolate error handling and compensation logic.

**Actions**:
1. Create `exec/compensation.ex` with:
   - `enabled?/1`
   - `handle_error/4` - orchestrates compensation when needed
   - `execute_compensation/4` - runs the compensation action
2. Update Exec's error path to delegate to Compensation
3. Keep main error flow in Exec but delegate compensation specifics

**Files to touch**:
- `lib/jido_action/exec/compensation.ex` (new)
- `lib/exec.ex` (update error handling)

**Validation**: Failing Action with `on_error/4` returns compensated error

### Step 5: Extract Async Module

**Goal**: Separate asynchronous execution concerns while keeping sync API in main module.

**Actions**:
1. Create `exec/async.ex` with:
   - `start/4` (calls back to `Jido.Exec.run/4` for feature consistency)
   - `await/2`
   - `cancel/1`
   - Task supervision and cleanup logic
2. Update main `Jido.Exec` async functions to delegate to Async module
3. Maintain all `run_async`, `await`, `cancel` functions in main module

**Files to touch**:
- `lib/jido_action/exec/async.ex` (new)
- `lib/exec.ex` (update async functions to delegate)

**Validation**: All async tests pass (start, await, timeout, cancel)

### Step 6: Final Cleanup & Documentation

**Goal**: Polish documentation, remove unnecessary complexity, and ensure code quality.

**Actions**:
1. Remove unused imports, aliases, and dead code
2. Clean up any remaining private functions that weren't extracted
3. Run code quality tools: `mix format`, `mix credo --strict`, `mix dialyzer`
4. Update module documentation to explain the new architecture
5. Ensure all public functions (`run/4`, `run_async/4`, `await/2`, `cancel/1`) remain unchanged

**Files to touch**:
- `lib/exec.ex` (cleanup and documentation)
- All new modules (documentation and formatting)

**Validation**:
- All quality tools pass
- Public API remains exactly the same
- Module is significantly smaller and more focused

## Global Validation Criteria

For each step and the overall migration:

1. **Tests**: `mix test` passes at every step
2. **Type Safety**: Dialyzer has no new warnings
3. **API Compatibility**: Public API signature and behavior unchanged
4. **Coverage**: Code coverage does not drop >2%
5. **History**: Each commit builds and tests green

## Key Principles

- **Preserve Public API**: All top-level functions (`run/4`, `run_async/4`, `await/2`, `cancel/1`) remain in `Jido.Exec`
- **Incremental**: Each step builds on the previous and maintains functionality
- **Focused Modules**: Each extracted module has a single, clear responsibility
- **Delegation**: Main module delegates specialized logic but retains core orchestration
- **Testable**: Each step maintains full test coverage

## Implementation Notes

- Each step should be implementable by a subagent
- Tests and quality checks must be maintained throughout
- The refactor is designed to be incremental and reversible
- Main module retains core execution flow, helper modules handle specialized logic
- No breaking changes to external API

## Future Improvements (Post-Refactor)

- Introduce behaviours in Validator/Compensation for alternative implementations
- Consider structured telemetry events over raw logging
- Add compile-time boundaries in umbrella's `mix.exs`
