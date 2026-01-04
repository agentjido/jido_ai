# Phase 3 Section 3.3: Sequential Algorithm

**Branch**: `feature/phase3-sequential-algorithm`
**Status**: Completed
**Created**: 2026-01-04

## Problem Statement

We need an algorithm that executes multiple sub-algorithms in sequence, passing the output of each step as input to the next. This is a fundamental composition pattern for building complex AI workflows.

## Solution Overview

Create `Jido.AI.Algorithms.Sequential` module that:
1. Uses Base module for standard algorithm infrastructure
2. Executes algorithms in order using `Enum.reduce_while/3`
3. Passes each algorithm's output as the next algorithm's input
4. Halts on first error
5. Tracks step progress and emits telemetry

## Technical Details

### File Structure

```
lib/jido_ai/
├── algorithms/
│   ├── algorithm.ex   # Behavior (done in 3.1)
│   ├── base.ex        # Base (done in 3.2)
│   └── sequential.ex  # Sequential execution

test/jido_ai/
├── algorithms/
│   ├── algorithm_test.exs  # (done in 3.1)
│   ├── base_test.exs       # (done in 3.2)
│   └── sequential_test.exs # Sequential tests
```

### Context Structure

The sequential algorithm expects:
- `context[:algorithms]` - List of algorithm modules to execute in order

### Execution Flow

1. Extract algorithms from context
2. For each algorithm in order:
   - Check if algorithm can execute
   - Call algorithm's `execute/2` with current input
   - On success, use result as next input
   - On error, halt and return error with step info
3. Return final result

### Telemetry Events

- `[:jido, :ai, :algorithm, :sequential, :step, :start]` - Step started
- `[:jido, :ai, :algorithm, :sequential, :step, :stop]` - Step completed
- `[:jido, :ai, :algorithm, :sequential, :step, :exception]` - Step failed

---

## Implementation Plan

### 3.3.1 Module Setup
- [x] 3.3.1.1 Create `lib/jido_ai/algorithms/sequential.ex` with module documentation
- [x] 3.3.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [x] 3.3.1.3 Document sequential execution semantics

### 3.3.2 Execute Implementation
- [x] 3.3.2.1 Implement `execute/2` function
- [x] 3.3.2.2 Extract algorithms list from context
- [x] 3.3.2.3 Use `Enum.reduce_while/3` for sequential execution
- [x] 3.3.2.4 Halt on first error, continue on success

### 3.3.3 Can Execute Check
- [x] 3.3.3.1 Override `can_execute?/2` function
- [x] 3.3.3.2 Check all algorithms in list can execute
- [x] 3.3.3.3 Use `Enum.all?/2` with can_execute? check

### 3.3.4 Step Tracking
- [x] 3.3.4.1 Track current step index in context
- [x] 3.3.4.2 Include step name in error messages
- [x] 3.3.4.3 Emit telemetry for each step

### 3.3.5 Unit Tests for Sequential Algorithm
- [x] Test execute/2 runs algorithms in order
- [x] Test execute/2 passes output to next algorithm input
- [x] Test execute/2 halts on first error
- [x] Test execute/2 returns final result on success
- [x] Test can_execute?/2 checks all algorithms
- [x] Test empty algorithm list handling
- [x] Test step tracking in context
- [x] Test telemetry emission per step

---

## Success Criteria

1. [x] Sequential algorithm module created using Base
2. [x] Execute function correctly chains algorithms
3. [x] Errors halt execution with step information
4. [x] Telemetry emitted for each step
5. [x] All unit tests pass (25 tests)

## Current Status

**What Works**: All implementation complete, 25 tests passing
**Completed**: Module setup, execute/2, can_execute?/2, step tracking, telemetry
**How to Run**: `mix test test/jido_ai/algorithms/`

---

## Notes

- The algorithm list comes from context, not from module configuration
- Each step receives the accumulated result from previous steps
- Step tracking enables debugging and observability
