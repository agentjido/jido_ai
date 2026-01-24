# Phase 3: Algorithm Framework

This phase implements the pluggable algorithm framework for different execution patterns. Algorithms define how AI operations are sequenced, parallelized, or composed.

## Module Structure

```
lib/jido_ai/
├── algorithms/
│   ├── algorithm.ex   # Algorithm behavior definition
│   ├── base.ex        # Base algorithm implementation
│   ├── sequential.ex  # Sequential execution algorithm
│   ├── parallel.ex    # Parallel execution algorithm
│   ├── hybrid.ex      # Hybrid execution algorithm
│   └── composite.ex   # Composite algorithm (combines others)
```

## Dependencies

- Phase 1: ReqLLM Integration Layer

---

## 3.1 Algorithm Behavior

Define the behavior interface that all algorithms must implement.

### 3.1.1 Behavior Definition

Create the algorithm behavior module with required callbacks.

- [x] 3.1.1.1 Create `lib/jido_ai/algorithms/algorithm.ex` with module documentation
- [x] 3.1.1.2 Define `@callback execute(input :: map(), context :: map()) :: {:ok, result :: map()} | {:error, reason :: term()}`
- [x] 3.1.1.3 Define `@callback can_execute?(input :: map(), context :: map()) :: boolean()`
- [x] 3.1.1.4 Define `@callback metadata() :: map()` for algorithm metadata
- [x] 3.1.1.5 Define `@optional_callbacks` for optional hooks

### 3.1.2 Optional Hooks

Define optional callback hooks for algorithm customization.

- [x] 3.1.2.1 Define `@callback before_execute(input :: map(), context :: map()) :: {:ok, input :: map()} | {:error, reason :: term()}`
- [x] 3.1.2.2 Define `@callback after_execute(result :: map(), context :: map()) :: {:ok, result :: map()} | {:error, reason :: term()}`
- [x] 3.1.2.3 Define `@callback on_error(error :: term(), context :: map()) :: {:retry, opts :: keyword()} | {:fail, reason :: term()}`

### 3.1.3 Type Specifications

Define type specifications for algorithm module.

- [x] 3.1.3.1 Define `@type t :: module()` for algorithm type
- [x] 3.1.3.2 Define `@type input :: map()` for algorithm input
- [x] 3.1.3.3 Define `@type result :: {:ok, map()} | {:error, term()}`
- [x] 3.1.3.4 Define `@type context :: map()` for execution context

### 3.1.4 Unit Tests for Algorithm Behavior

- [x] Test behavior callbacks are defined
- [x] Test optional callbacks are marked optional
- [x] Test type specifications compile correctly
- [x] Test example algorithm implements behavior

---

## 3.2 Base Algorithm

Implement the base algorithm module with shared functionality.

### 3.2.1 Using Macro

Create the base module with `__using__` macro.

- [x] 3.2.1.1 Create `lib/jido_ai/algorithms/base.ex` with module documentation
- [x] 3.2.1.2 Implement `__using__/1` macro with opts
- [x] 3.2.1.3 Inject `@behaviour Jido.AI.Algorithms.Algorithm`
- [x] 3.2.1.4 Provide default `metadata/0` from opts

### 3.2.2 Default Implementations

Implement default implementations for optional callbacks.

- [x] 3.2.2.1 Implement default `can_execute?/2` returning `true`
- [x] 3.2.2.2 Implement default `before_execute/2` returning `{:ok, input}`
- [x] 3.2.2.3 Implement default `after_execute/2` returning `{:ok, result}`
- [x] 3.2.2.4 Allow override via `defoverridable`

### 3.2.3 Helper Functions

Implement helper functions for algorithm implementations.

- [x] 3.2.3.1 Implement `run_with_hooks/2` that wraps execute with before/after hooks
- [x] 3.2.3.2 Implement `handle_error/2` for error handling with on_error callback
- [x] 3.2.3.3 Implement `merge_context/2` for context manipulation

### 3.2.4 Unit Tests for Base Algorithm

- [x] Test `__using__` macro injects behavior
- [x] Test default metadata/0 from opts
- [x] Test default can_execute?/2 returns true
- [x] Test default before_execute/2 passes through
- [x] Test default after_execute/2 passes through
- [x] Test run_with_hooks/2 calls hooks in order
- [x] Test handle_error/2 calls on_error callback
- [x] Test defoverridable allows customization

---

## 3.3 Sequential Algorithm

Implement sequential execution algorithm that runs steps in order.

### 3.3.1 Module Setup

Create the sequential algorithm module.

- [x] 3.3.1.1 Create `lib/jido_ai/algorithms/sequential.ex` with module documentation
- [x] 3.3.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [x] 3.3.1.3 Document sequential execution semantics

### 3.3.2 Execute Implementation

Implement sequential execution logic.

- [x] 3.3.2.1 Implement `execute/2` function
- [x] 3.3.2.2 Extract algorithms list from context
- [x] 3.3.2.3 Use `Enum.reduce_while/3` for sequential execution
- [x] 3.3.2.4 Halt on first error, continue on success

### 3.3.3 Can Execute Check

Implement execution readiness check.

- [x] 3.3.3.1 Override `can_execute?/2` function
- [x] 3.3.3.2 Check all algorithms in list can execute
- [x] 3.3.3.3 Use `Enum.all?/2` with can_execute? check

### 3.3.4 Step Tracking

Implement step tracking for debugging.

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

## 3.4 Parallel Algorithm

Implement parallel execution algorithm that runs steps concurrently.

### 3.4.1 Module Setup

Create the parallel algorithm module.

- [x] 3.4.1.1 Create `lib/jido_ai/algorithms/parallel.ex` with module documentation
- [x] 3.4.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [x] 3.4.1.3 Document parallel execution semantics and result merging

### 3.4.2 Execute Implementation

Implement parallel execution logic.

- [x] 3.4.2.1 Implement `execute/2` function
- [x] 3.4.2.2 Extract algorithms list from context
- [x] 3.4.2.3 Use `Task.async_stream/3` for parallel execution
- [x] 3.4.2.4 Collect results and merge

### 3.4.3 Result Merging

Implement result merging strategies.

- [x] 3.4.3.1 Implement `merge_results/2` for combining parallel results
- [x] 3.4.3.2 Support `:merge_maps` strategy (deep merge)
- [x] 3.4.3.3 Support `:collect` strategy (list of results)
- [x] 3.4.3.4 Support custom merge function via context

### 3.4.4 Error Handling

Implement parallel error handling.

- [x] 3.4.4.1 Support `:fail_fast` mode (cancel on first error)
- [x] 3.4.4.2 Support `:collect_errors` mode (return all errors)
- [x] 3.4.4.3 Support `:ignore_errors` mode (return successful results)
- [x] 3.4.4.4 Configure via context option

### 3.4.5 Concurrency Control

Implement concurrency control.

- [x] 3.4.5.1 Support `max_concurrency` option
- [x] 3.4.5.2 Support `timeout` option per task
- [x] 3.4.5.3 Handle task timeout gracefully

### 3.4.6 Unit Tests for Parallel Algorithm

- [x] Test execute/2 runs algorithms concurrently
- [x] Test merge_results with merge_maps strategy
- [x] Test merge_results with collect strategy
- [x] Test merge_results with custom function
- [x] Test fail_fast mode cancels on error
- [x] Test collect_errors mode returns all errors
- [x] Test ignore_errors mode returns successes
- [x] Test max_concurrency limits parallel tasks
- [x] Test timeout handling per task

---

## 3.5 Hybrid Algorithm

Implement hybrid algorithm that combines sequential and parallel execution.

### 3.5.1 Module Setup

Create the hybrid algorithm module.

- [x] 3.5.1.1 Create `lib/jido_ai/algorithms/hybrid.ex` with module documentation
- [x] 3.5.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [x] 3.5.1.3 Document hybrid execution semantics

### 3.5.2 Execution Stages

Implement stage-based execution.

- [x] 3.5.2.1 Define stage map structure with algorithms and mode
- [x] 3.5.2.2 Implement `execute/2` that processes stages in order
- [x] 3.5.2.3 Execute each stage according to its mode
- [x] 3.5.2.4 Pass stage output to next stage input

### 3.5.3 Stage Configuration

Implement stage configuration.

- [x] 3.5.3.1 Support inline stage definition in context
- [x] 3.5.3.2 Support shorthand for single-algorithm stages
- [x] 3.5.3.3 Validate stage configuration

### 3.5.4 Fallback Support

Implement fallback algorithm support.

- [x] 3.5.4.1 Support algorithm to fallbacks mapping in context
- [x] 3.5.4.2 Try primary algorithm first
- [x] 3.5.4.3 Fall back on error
- [x] 3.5.4.4 Support multiple fallback levels

### 3.5.5 Unit Tests for Hybrid Algorithm

- [x] Test execute/2 processes stages in order
- [x] Test sequential stage execution
- [x] Test parallel stage execution
- [x] Test mixed mode stages
- [x] Test stage output passed to next stage
- [x] Test fallback on primary failure
- [x] Test multiple fallback levels
- [x] Test empty stages handling

---

## 3.6 Composite Algorithm

Implement composite algorithm for combining multiple algorithms.

### 3.6.1 Module Setup

Create the composite algorithm module.

- [x] 3.6.1.1 Create `lib/jido_ai/algorithms/composite.ex` with module documentation
- [x] 3.6.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [x] 3.6.1.3 Document composition patterns

### 3.6.2 Composition Operators

Implement composition operators.

- [x] 3.6.2.1 Implement `sequence/1` for sequential composition
- [x] 3.6.2.2 Implement `parallel/1` for parallel composition
- [x] 3.6.2.3 Implement `choice/3` for conditional selection
- [x] 3.6.2.4 Implement `repeat/2` for repeated execution

### 3.6.3 Dynamic Composition

Implement dynamic algorithm composition.

- [x] 3.6.3.1 Implement `compose/2` for runtime composition
- [x] 3.6.3.2 Support nested compositions
- [x] 3.6.3.3 Validate composition graph

### 3.6.4 Conditional Execution

Implement conditional algorithm selection.

- [x] 3.6.4.1 Implement `when_cond/2` for conditional execution
- [x] 3.6.4.2 Support predicate functions
- [x] 3.6.4.3 Support pattern matching on input

### 3.6.5 Unit Tests for Composite Algorithm

- [x] Test sequence/1 creates sequential composite
- [x] Test parallel/1 creates parallel composite
- [x] Test choice/3 selects based on condition
- [x] Test repeat/2 executes multiple times
- [x] Test compose/2 combines algorithms dynamically
- [x] Test nested compositions
- [x] Test when_cond/2 conditional execution
- [x] Test predicate function evaluation

---

## 3.7 Phase 3 Integration Tests

Comprehensive integration tests verifying all Phase 3 components work together.

### 3.7.1 Algorithm Composition Integration

Verify algorithms compose correctly.

- [x] 3.7.1.1 Create `test/jido_ai/integration/algorithms_phase3_test.exs`
- [x] 3.7.1.2 Test: Sequential of parallel algorithms
- [x] 3.7.1.3 Test: Parallel of sequential algorithms
- [x] 3.7.1.4 Test: Complex nested compositions

### 3.7.2 Error Propagation Integration

Test error handling across compositions.

- [x] 3.7.2.1 Test: Error in sequential stops chain
- [x] 3.7.2.2 Test: Error in parallel with fail_fast
- [x] 3.7.2.3 Test: Fallback execution on error
- [x] 3.7.2.4 Test: Error recovery with retry

### 3.7.3 Performance Integration

Test performance characteristics.

- [x] 3.7.3.1 Test: Parallel speedup vs sequential
- [x] 3.7.3.2 Test: Concurrency limits respected
- [x] 3.7.3.3 Test: Timeout handling across compositions
- [x] 3.7.3.4 Test: Resource cleanup on failure

---

## Phase 3 Success Criteria

1. **Algorithm Behavior**: Clean interface for implementing algorithms
2. **Base Algorithm**: Reusable base with hooks and helpers
3. **Sequential**: Correct ordered execution with error halting
4. **Parallel**: Concurrent execution with merge strategies
5. **Hybrid**: Flexible stage-based execution
6. **Composite**: Rich composition operators
7. **Test Coverage**: Minimum 80% for Phase 3 modules

---

## Phase 3 Critical Files

**New Files:**
- `lib/jido_ai/algorithms/algorithm.ex`
- `lib/jido_ai/algorithms/base.ex`
- `lib/jido_ai/algorithms/sequential.ex`
- `lib/jido_ai/algorithms/parallel.ex`
- `lib/jido_ai/algorithms/hybrid.ex`
- `lib/jido_ai/algorithms/composite.ex`
- `test/jido_ai/algorithms/algorithm_test.exs`
- `test/jido_ai/algorithms/base_test.exs`
- `test/jido_ai/algorithms/sequential_test.exs`
- `test/jido_ai/algorithms/parallel_test.exs`
- `test/jido_ai/algorithms/hybrid_test.exs`
- `test/jido_ai/algorithms/composite_test.exs`
- `test/jido_ai/integration/algorithms_phase3_test.exs`
