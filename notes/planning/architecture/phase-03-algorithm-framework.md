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

- [ ] 3.2.1.1 Create `lib/jido_ai/algorithms/base.ex` with module documentation
- [ ] 3.2.1.2 Implement `__using__/1` macro with opts
- [ ] 3.2.1.3 Inject `@behaviour Jido.AI.Algorithms.Algorithm`
- [ ] 3.2.1.4 Provide default `metadata/0` from opts

### 3.2.2 Default Implementations

Implement default implementations for optional callbacks.

- [ ] 3.2.2.1 Implement default `can_execute?/2` returning `true`
- [ ] 3.2.2.2 Implement default `before_execute/2` returning `{:ok, input}`
- [ ] 3.2.2.3 Implement default `after_execute/2` returning `{:ok, result}`
- [ ] 3.2.2.4 Allow override via `defoverridable`

### 3.2.3 Helper Functions

Implement helper functions for algorithm implementations.

- [ ] 3.2.3.1 Implement `run_with_hooks/3` that wraps execute with before/after hooks
- [ ] 3.2.3.2 Implement `handle_error/3` for error handling with on_error callback
- [ ] 3.2.3.3 Implement `merge_context/2` for context manipulation

### 3.2.4 Unit Tests for Base Algorithm

- [ ] Test `__using__` macro injects behavior
- [ ] Test default metadata/0 from opts
- [ ] Test default can_execute?/2 returns true
- [ ] Test default before_execute/2 passes through
- [ ] Test default after_execute/2 passes through
- [ ] Test run_with_hooks/3 calls hooks in order
- [ ] Test handle_error/3 calls on_error callback
- [ ] Test defoverridable allows customization

---

## 3.3 Sequential Algorithm

Implement sequential execution algorithm that runs steps in order.

### 3.3.1 Module Setup

Create the sequential algorithm module.

- [ ] 3.3.1.1 Create `lib/jido_ai/algorithms/sequential.ex` with module documentation
- [ ] 3.3.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [ ] 3.3.1.3 Document sequential execution semantics

### 3.3.2 Execute Implementation

Implement sequential execution logic.

- [ ] 3.3.2.1 Implement `execute/2` function
- [ ] 3.3.2.2 Extract algorithms list from context
- [ ] 3.3.2.3 Use `Enum.reduce_while/3` for sequential execution
- [ ] 3.3.2.4 Halt on first error, continue on success

### 3.3.3 Can Execute Check

Implement execution readiness check.

- [ ] 3.3.3.1 Override `can_execute?/2` function
- [ ] 3.3.3.2 Check all algorithms in list can execute
- [ ] 3.3.3.3 Use `Enum.all?/2` with can_execute? check

### 3.3.4 Step Tracking

Implement step tracking for debugging.

- [ ] 3.3.4.1 Track current step index in context
- [ ] 3.3.4.2 Include step name in error messages
- [ ] 3.3.4.3 Emit telemetry for each step

### 3.3.5 Unit Tests for Sequential Algorithm

- [ ] Test execute/2 runs algorithms in order
- [ ] Test execute/2 passes output to next algorithm input
- [ ] Test execute/2 halts on first error
- [ ] Test execute/2 returns final result on success
- [ ] Test can_execute?/2 checks all algorithms
- [ ] Test empty algorithm list handling
- [ ] Test step tracking in context
- [ ] Test telemetry emission per step

---

## 3.4 Parallel Algorithm

Implement parallel execution algorithm that runs steps concurrently.

### 3.4.1 Module Setup

Create the parallel algorithm module.

- [ ] 3.4.1.1 Create `lib/jido_ai/algorithms/parallel.ex` with module documentation
- [ ] 3.4.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [ ] 3.4.1.3 Document parallel execution semantics and result merging

### 3.4.2 Execute Implementation

Implement parallel execution logic.

- [ ] 3.4.2.1 Implement `execute/2` function
- [ ] 3.4.2.2 Extract algorithms list from context
- [ ] 3.4.2.3 Use `Task.async_stream/3` for parallel execution
- [ ] 3.4.2.4 Collect results and merge

### 3.4.3 Result Merging

Implement result merging strategies.

- [ ] 3.4.3.1 Implement `merge_results/1` for combining parallel results
- [ ] 3.4.3.2 Support `:merge_maps` strategy (deep merge)
- [ ] 3.4.3.3 Support `:collect` strategy (list of results)
- [ ] 3.4.3.4 Support custom merge function via context

### 3.4.4 Error Handling

Implement parallel error handling.

- [ ] 3.4.4.1 Support `:fail_fast` mode (cancel on first error)
- [ ] 3.4.4.2 Support `:collect_errors` mode (return all errors)
- [ ] 3.4.4.3 Support `:ignore_errors` mode (return successful results)
- [ ] 3.4.4.4 Configure via context option

### 3.4.5 Concurrency Control

Implement concurrency control.

- [ ] 3.4.5.1 Support `max_concurrency` option
- [ ] 3.4.5.2 Support `timeout` option per task
- [ ] 3.4.5.3 Handle task timeout gracefully

### 3.4.6 Unit Tests for Parallel Algorithm

- [ ] Test execute/2 runs algorithms concurrently
- [ ] Test merge_results/1 with merge_maps strategy
- [ ] Test merge_results/1 with collect strategy
- [ ] Test merge_results/1 with custom function
- [ ] Test fail_fast mode cancels on error
- [ ] Test collect_errors mode returns all errors
- [ ] Test ignore_errors mode returns successes
- [ ] Test max_concurrency limits parallel tasks
- [ ] Test timeout handling per task

---

## 3.5 Hybrid Algorithm

Implement hybrid algorithm that combines sequential and parallel execution.

### 3.5.1 Module Setup

Create the hybrid algorithm module.

- [ ] 3.5.1.1 Create `lib/jido_ai/algorithms/hybrid.ex` with module documentation
- [ ] 3.5.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [ ] 3.5.1.3 Document hybrid execution semantics

### 3.5.2 Execution Stages

Implement stage-based execution.

- [ ] 3.5.2.1 Define stage struct `%Stage{algorithms: [], mode: :sequential | :parallel}`
- [ ] 3.5.2.2 Implement `execute/2` that processes stages in order
- [ ] 3.5.2.3 Execute each stage according to its mode
- [ ] 3.5.2.4 Pass stage output to next stage input

### 3.5.3 Stage Configuration

Implement stage configuration.

- [ ] 3.5.3.1 Support inline stage definition in context
- [ ] 3.5.3.2 Support pre-defined stage pipelines
- [ ] 3.5.3.3 Validate stage configuration

### 3.5.4 Fallback Support

Implement fallback algorithm support.

- [ ] 3.5.4.1 Support `primary` and `fallback` algorithm configuration
- [ ] 3.5.4.2 Try primary algorithm first
- [ ] 3.5.4.3 Fall back on error or timeout
- [ ] 3.5.4.4 Support multiple fallback levels

### 3.5.5 Unit Tests for Hybrid Algorithm

- [ ] Test execute/2 processes stages in order
- [ ] Test sequential stage execution
- [ ] Test parallel stage execution
- [ ] Test mixed mode stages
- [ ] Test stage output passed to next stage
- [ ] Test fallback on primary failure
- [ ] Test fallback on primary timeout
- [ ] Test multiple fallback levels

---

## 3.6 Composite Algorithm

Implement composite algorithm for combining multiple algorithms.

### 3.6.1 Module Setup

Create the composite algorithm module.

- [ ] 3.6.1.1 Create `lib/jido_ai/algorithms/composite.ex` with module documentation
- [ ] 3.6.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [ ] 3.6.1.3 Document composition patterns

### 3.6.2 Composition Operators

Implement composition operators.

- [ ] 3.6.2.1 Implement `sequence/1` for sequential composition
- [ ] 3.6.2.2 Implement `parallel/1` for parallel composition
- [ ] 3.6.2.3 Implement `choice/2` for conditional selection
- [ ] 3.6.2.4 Implement `repeat/2` for repeated execution

### 3.6.3 Dynamic Composition

Implement dynamic algorithm composition.

- [ ] 3.6.3.1 Implement `compose/2` for runtime composition
- [ ] 3.6.3.2 Support nested compositions
- [ ] 3.6.3.3 Validate composition graph

### 3.6.4 Conditional Execution

Implement conditional algorithm selection.

- [ ] 3.6.4.1 Implement `when/2` for conditional execution
- [ ] 3.6.4.2 Support predicate functions
- [ ] 3.6.4.3 Support pattern matching on input

### 3.6.5 Unit Tests for Composite Algorithm

- [ ] Test sequence/1 creates sequential composite
- [ ] Test parallel/1 creates parallel composite
- [ ] Test choice/2 selects based on condition
- [ ] Test repeat/2 executes multiple times
- [ ] Test compose/2 combines algorithms dynamically
- [ ] Test nested compositions
- [ ] Test when/2 conditional execution
- [ ] Test predicate function evaluation

---

## 3.7 Phase 3 Integration Tests

Comprehensive integration tests verifying all Phase 3 components work together.

### 3.7.1 Algorithm Composition Integration

Verify algorithms compose correctly.

- [ ] 3.7.1.1 Create `test/jido_ai/integration/algorithms_phase3_test.exs`
- [ ] 3.7.1.2 Test: Sequential of parallel algorithms
- [ ] 3.7.1.3 Test: Parallel of sequential algorithms
- [ ] 3.7.1.4 Test: Complex nested compositions

### 3.7.2 Error Propagation Integration

Test error handling across compositions.

- [ ] 3.7.2.1 Test: Error in sequential stops chain
- [ ] 3.7.2.2 Test: Error in parallel with fail_fast
- [ ] 3.7.2.3 Test: Fallback execution on error
- [ ] 3.7.2.4 Test: Error recovery with retry

### 3.7.3 Performance Integration

Test performance characteristics.

- [ ] 3.7.3.1 Test: Parallel speedup vs sequential
- [ ] 3.7.3.2 Test: Concurrency limits respected
- [ ] 3.7.3.3 Test: Timeout handling across compositions
- [ ] 3.7.3.4 Test: Resource cleanup on failure

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
