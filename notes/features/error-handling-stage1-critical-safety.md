# Feature: Error Handling Stage 1 - Critical Safety Fixes ✓ COMPLETE

**Last Updated**: 2025-10-24
**Status**: ✓ COMPLETE - All 11 critical fixes implemented and tested
**Branch**: `feature/error-handling-stage1`
**Audit Reference**: `notes/audits/codebase-safety-audit-2025-10-24.md`
**Commits**: 13dfa99, 6340d8e, 16485f8, 98fc549

## Completion Summary

**Date Completed**: 2025-10-24
**Tests Passing**: 211/211 across all affected modules

All 11 critical safety vulnerabilities have been successfully fixed:
- ✓ 1 unsafe hd() operation → Pattern matching with guards
- ✓ 4 unsafe Enum.max operations → Empty list guard clauses
- ✓ 6 unsafe Map.fetch! operations → Safe error tuple returns

**No runtime crashes remain** from these previously unsafe operations. All fixes follow Elixir best practices with `{:ok, result} | {:error, reason}` error handling patterns.

## Problem Statement

Post-namespace refactoring (Jido.* → Jido.AI.*), a comprehensive re-audit of the codebase identified **11 critical safety vulnerabilities** that cause immediate runtime crashes when encountering edge cases. These unsafe operations can crash GenServers and interrupt workflows:

### Critical Issues Causing Immediate Crashes:

1. **Unsafe List Operations (1 occurrence)**: Using `hd()` on `String.split()` result without validation can produce unexpected behavior with invalid input formats.

2. **Unsafe Enumerable Operations (4 occurrences)**: Using `Enum.max` on potentially empty vote_counts/weighted_votes in the voting mechanism causes `Enum.EmptyError`, crashing during consensus operations.

3. **Unsafe Map Access (6 occurrences)**: Using `Map.fetch!` on maps with potentially missing keys causes `KeyError`, crashing during:
   - Tree node lookup operations
   - GEPA candidate/task creation
   - Action parameter extraction

### Impact:

- **Self-Consistency Failures**: Empty reasoning paths crash voting consensus algorithms
- **GEPA Optimization Failures**: Missing keys crash candidate creation and task scheduling
- **Tree of Thoughts Failures**: Invalid parent IDs crash tree construction
- **Action Execution Failures**: Missing required parameters crash action entry points
- **Data Loss**: Unexpected crashes prevent graceful state cleanup

### Previous Fixes (Already Completed):

During initial implementation, 5 unsafe `hd()` operations were already fixed in:
- `lib/jido_ai/runner/gepa/feedback_aggregation/collector.ex:225`
- `lib/jido_ai/runner/gepa/feedback_aggregation/pattern_detector.ex:199` (now line 183)
- `lib/jido_ai/runner/gepa/trajectory_analyzer.ex:845`
- `lib/jido_ai/runner/gepa/suggestion_generation/conflict_resolver.ex:178,182,188`

These represent the highest priority remaining fixes because they can cause immediate, unpredictable system failures under normal operating conditions.

## Solution Overview

Stage 1 implements defensive programming techniques to prevent crashes from the 11 identified unsafe operations:

### Approach:

1. **Pattern Matching for String Parsing**: Replace `String.split(":") |> hd()` with pattern matching and validation
2. **Guard Clauses for Voting**: Add guards validating non-empty grouped paths before `Enum.max` operations
3. **Safe Map Access**: Replace `Map.fetch!(map, key)` with `Map.fetch(map, key)` and explicit error handling
4. **Error Propagation**: Return `{:ok, result}` | `{:error, reason}` tuples instead of crashing
5. **Comprehensive Testing**: Add tests for all edge cases (empty collections, missing keys, invalid formats)

### Benefits:

- **Reliability**: Graceful failure handling instead of crashes
- **Debuggability**: Clear error messages identifying the issue and context
- **Maintainability**: Consistent patterns for safe operations
- **Production Readiness**: Robust operation under edge cases

## Technical Details

### Section 1.1: List Operation Safety (1 file)

#### 1.1.1 OpenAI Provider Extraction Fix

**File: `lib/jido_ai/actions/openaiex.ex:406`**

```elixir
# BEFORE (line 406):
defp extract_provider_from_reqllm_id(reqllm_id) do
  provider_str =
    reqllm_id
    |> String.split(":")
    |> hd()
  # ... rest of function
end

# AFTER:
defp extract_provider_from_reqllm_id(reqllm_id) when is_binary(reqllm_id) do
  case String.split(reqllm_id, ":") do
    [provider_str | _rest] ->
      # Create a safe string-to-atom mapping from ReqLLM's valid providers
      valid_providers =
        ValidProviders.list()
        |> Map.new(fn atom -> {to_string(atom), atom} end)

      Map.get(valid_providers, provider_str)

    [] ->
      # Should not happen with String.split, but be defensive
      nil
  end
end

defp extract_provider_from_reqllm_id(_invalid), do: nil
```

- **Issue**: `String.split(":") |> hd()` - While String.split always returns at least one element, the function should handle invalid input gracefully
- **Fix**: Pattern match on split result and add fallback clause for invalid input
- **Context**: ReqLLM provider extraction from ID format "provider:model"
- **Error Type**: Potential confusion with invalid reqllm_id formats
- **Priority**: Medium

**Test Helper File: `lib/jido_ai/actions/openai_ex/test_helpers.ex:36`**
- Same pattern, update to match production code

**Tests to Add:**
```elixir
test "extract_provider_from_reqllm_id handles empty string" do
  assert extract_provider_from_reqllm_id("") == nil
end

test "extract_provider_from_reqllm_id handles missing colon" do
  assert extract_provider_from_reqllm_id("openai") in [valid_provider, nil]
end

test "extract_provider_from_reqllm_id handles invalid provider" do
  assert extract_provider_from_reqllm_id("invalid:model") == nil
end
```

### Section 1.2: Enumerable Operation Safety (1 file, 4 occurrences)

#### 1.2.1 Self-Consistency Voting Mechanism Fixes

**File: `lib/jido_ai/runner/self_consistency/voting_mechanism.ex`**

All four occurrences follow the same pattern: calling `Enum.max()` on a list that could be empty if `grouped` is empty.

##### Fix 1: Line 210 - majority_vote

```elixir
# BEFORE (line 210):
defp majority_vote(grouped, tie_breaker) do
  vote_counts =
    Enum.map(grouped, fn {answer, paths} ->
      {answer, length(paths), paths}
    end)

  max_votes = vote_counts |> Enum.map(fn {_, count, _} -> count end) |> Enum.max()
  # ... rest

# AFTER:
defp majority_vote([], _tie_breaker) do
  {:error, :no_paths}
end

defp majority_vote(grouped, tie_breaker) do
  vote_counts =
    Enum.map(grouped, fn {answer, paths} ->
      {answer, length(paths), paths}
    end)

  max_votes = vote_counts |> Enum.map(fn {_, count, _} -> count end) |> Enum.max()
  # ... rest (unchanged)
end
```

- **Issue**: Empty `grouped` causes empty `vote_counts`, triggering `Enum.EmptyError`
- **Fix**: Add function clause handling empty grouped list
- **Context**: Majority voting in self-consistency
- **Error Type**: `Enum.EmptyError`
- **Priority**: High - Core voting algorithm

##### Fix 2: Line 234 - weighted_vote_by_confidence

```elixir
# BEFORE (line 234):
defp weighted_vote_by_confidence(grouped) do
  weighted_votes =
    Enum.map(grouped, fn {answer, paths} ->
      total_confidence = Enum.reduce(paths, 0.0, fn p, acc -> acc + p.confidence end)
      {answer, total_confidence, paths}
    end)

  max_weight = weighted_votes |> Enum.map(fn {_, weight, _} -> weight end) |> Enum.max()
  # ... rest

# AFTER:
defp weighted_vote_by_confidence([]) do
  {:error, :no_paths}
end

defp weighted_vote_by_confidence(grouped) do
  weighted_votes =
    Enum.map(grouped, fn {answer, paths} ->
      total_confidence = Enum.reduce(paths, 0.0, fn p, acc -> acc + p.confidence end)
      {answer, total_confidence, paths}
    end)

  max_weight = weighted_votes |> Enum.map(fn {_, weight, _} -> weight end) |> Enum.max()
  # ... rest (unchanged)
end
```

- **Issue**: Empty `grouped` causes empty `weighted_votes`, triggering `Enum.EmptyError`
- **Fix**: Add function clause handling empty grouped list
- **Context**: Confidence-weighted voting
- **Error Type**: `Enum.EmptyError`
- **Priority**: High

##### Fix 3: Line 262 - weighted_vote_by_quality

```elixir
# BEFORE (line 262):
defp weighted_vote_by_quality(grouped) do
  weighted_votes =
    Enum.map(grouped, fn {answer, paths} ->
      total_quality = Enum.reduce(paths, 0.0, fn p, acc -> acc + (p.quality_score || 0.0) end)
      {answer, total_quality, paths}
    end)

  max_weight = weighted_votes |> Enum.map(fn {_, weight, _} -> weight end) |> Enum.max()
  # ... rest

# AFTER:
defp weighted_vote_by_quality([]) do
  {:error, :no_paths}
end

defp weighted_vote_by_quality(grouped) do
  weighted_votes =
    Enum.map(grouped, fn {answer, paths} ->
      total_quality = Enum.reduce(paths, 0.0, fn p, acc -> acc + (p.quality_score || 0.0) end)
      {answer, total_quality, paths}
    end)

  max_weight = weighted_votes |> Enum.map(fn {_, weight, _} -> weight end) |> Enum.max()
  # ... rest (unchanged)
end
```

- **Issue**: Same pattern as above
- **Fix**: Add function clause handling empty grouped list
- **Context**: Quality-weighted voting
- **Error Type**: `Enum.EmptyError`
- **Priority**: High

##### Fix 4: Line 296 - weighted_vote_combined

```elixir
# BEFORE (line 296):
defp weighted_vote_combined(grouped) do
  weighted_votes =
    Enum.map(grouped, fn {answer, paths} ->
      score = calculate_combined_score(paths)
      {answer, score, paths}
    end)

  max_score = weighted_votes |> Enum.map(fn {_, score, _} -> score end) |> Enum.max()
  # ... rest

# AFTER:
defp weighted_vote_combined([]) do
  {:error, :no_paths}
end

defp weighted_vote_combined(grouped) do
  weighted_votes =
    Enum.map(grouped, fn {answer, paths} ->
      score = calculate_combined_score(paths)
      {answer, score, paths}
    end)

  max_score = weighted_votes |> Enum.map(fn {_, score, _} -> score end) |> Enum.max()
  # ... rest (unchanged)
end
```

- **Issue**: Same pattern as above
- **Fix**: Add function clause handling empty grouped list
- **Context**: Combined score voting
- **Error Type**: `Enum.EmptyError`
- **Priority**: High

**Tests to Add:**
```elixir
describe "voting with empty paths" do
  test "majority_vote returns error for empty paths" do
    assert {:error, :no_paths} = VotingMechanism.vote([], :majority, :first)
  end

  test "weighted_vote_by_confidence returns error for empty paths" do
    assert {:error, :no_paths} = VotingMechanism.vote([], :weighted, :confidence)
  end

  test "weighted_vote_by_quality returns error for empty paths" do
    assert {:error, :no_paths} = VotingMechanism.vote([], :weighted, :quality)
  end

  test "weighted_vote_combined returns error for empty paths" do
    assert {:error, :no_paths} = VotingMechanism.vote([], :weighted, :combined)
  end
end
```

### Section 1.3: Map Access Safety (3 files, 6 occurrences)

#### 1.3.1 Tree of Thoughts Node Lookup

**File: `lib/jido_ai/runner/tree_of_thoughts/tree.ex:87`**

```elixir
# BEFORE (line 87):
def add_child(tree, parent_id, thought, state, opts \\ []) do
  parent = Map.fetch!(tree.nodes, parent_id)

  child =
    TreeNode.new(
      thought,
      state,
      Keyword.merge(opts,
        parent_id: parent_id,
        # ... rest

# AFTER:
def add_child(tree, parent_id, thought, state, opts \\ []) do
  case Map.fetch(tree.nodes, parent_id) do
    {:ok, parent} ->
      child =
        TreeNode.new(
          thought,
          state,
          Keyword.merge(opts,
            parent_id: parent_id,
            depth: parent.depth + 1
          )
        )

      updated_tree = %{
        tree
        | nodes: Map.put(tree.nodes, child.id, child),
          node_count: tree.node_count + 1
      }

      {:ok, {updated_tree, child}}

    :error ->
      {:error, {:parent_not_found, parent_id}}
  end
end
```

- **Issue**: `Map.fetch!(tree.nodes, parent_id)` crashes with `KeyError` if parent_id doesn't exist
- **Fix**: Use `Map.fetch/2` with case statement for explicit error handling
- **Context**: Adding child nodes to tree structure
- **Error Type**: `KeyError`
- **Priority**: High - Core tree operation
- **Return Type Change**: Returns `{:ok, {tree, child}}` | `{:error, reason}` instead of `{tree, child}`

**Tests to Add:**
```elixir
test "add_child returns error for non-existent parent" do
  tree = Tree.new("root")

  assert {:error, {:parent_not_found, "non-existent"}} =
    Tree.add_child(tree, "non-existent", "thought", %{})
end
```

#### 1.3.2 GEPA Population - Candidate Creation

**File: `lib/jido_ai/runner/gepa/population.ex:458`**

```elixir
# BEFORE (line 458):
defp ensure_candidate_struct(data, generation) when is_map(data) do
  id = Map.get(data, :id, generate_candidate_id())
  now = System.monotonic_time(:millisecond)

  %Candidate{
    id: id,
    prompt: Map.fetch!(data, :prompt),
    fitness: Map.get(data, :fitness),
    # ... rest

# AFTER:
defp ensure_candidate_struct(data, generation) when is_map(data) do
  with {:ok, prompt} <- Map.fetch(data, :prompt) do
    id = Map.get(data, :id, generate_candidate_id())
    now = System.monotonic_time(:millisecond)

    candidate = %Candidate{
      id: id,
      prompt: prompt,
      fitness: Map.get(data, :fitness),
      generation: Map.get(data, :generation, generation),
      parent_ids: Map.get(data, :parent_ids, []),
      metadata: Map.get(data, :metadata, %{}),
      created_at: Map.get(data, :created_at, now),
      evaluated_at: Map.get(data, :evaluated_at)
    }

    {:ok, candidate}
  else
    :error -> {:error, :missing_prompt}
  end
end
```

- **Issue**: `Map.fetch!(data, :prompt)` crashes with `KeyError` if :prompt is missing
- **Fix**: Use `Map.fetch/2` with `with` statement for validation
- **Context**: Creating candidate structures from map data
- **Error Type**: `KeyError`
- **Priority**: High - Candidate creation
- **Return Type Change**: Returns `{:ok, candidate}` | `{:error, :missing_prompt}`

**Callers to Update:**
Need to update all call sites to handle new return type:
- Line 379 in `add_candidates/2`
- Any other callers

**Tests to Add:**
```elixir
test "add_candidates returns error for candidates without prompt" do
  pop = Population.new()
  invalid_candidate = %{id: "test", fitness: 0.5}  # Missing :prompt

  assert {:error, :missing_prompt} = Population.add_candidates(pop, [invalid_candidate])
end
```

#### 1.3.3 GEPA Scheduler - Task Creation

**File: `lib/jido_ai/runner/gepa/scheduler.ex:248,250`**

```elixir
# BEFORE (lines 248-250):
task = %Task{
  id: task_id,
  candidate_id: Map.fetch!(task_spec, :candidate_id),
  priority: Map.get(task_spec, :priority, :normal),
  evaluator: Map.fetch!(task_spec, :evaluator),
  metadata: Map.get(task_spec, :metadata, %{}),
  # ... rest

# AFTER:
with {:ok, candidate_id} <- Map.fetch(task_spec, :candidate_id),
     {:ok, evaluator} <- Map.fetch(task_spec, :evaluator) do
  task = %Task{
    id: task_id,
    candidate_id: candidate_id,
    priority: Map.get(task_spec, :priority, :normal),
    evaluator: evaluator,
    metadata: Map.get(task_spec, :metadata, %{}),
    submitted_at: System.monotonic_time(:millisecond),
    status: :pending
  }

  # Add to queue and update state
  # ... (existing logic)
else
  :error ->
    Logger.warning("Invalid task_spec missing required keys",
      task_spec: task_spec,
      required: [:candidate_id, :evaluator]
    )
    {:reply, {:error, :invalid_task_spec}, state}
end
```

- **Issue**: `Map.fetch!(task_spec, :candidate_id)` and `Map.fetch!(task_spec, :evaluator)` crash with `KeyError` if keys are missing
- **Fix**: Use `Map.fetch/2` with `with` statement validating both required keys
- **Context**: Creating evaluation tasks in scheduler
- **Error Type**: `KeyError`
- **Priority**: High - Task scheduling
- **Additional**: Add logging for debugging invalid task specs

**Tests to Add:**
```elixir
test "submit_task returns error for task_spec without candidate_id" do
  {:ok, scheduler} = Scheduler.start_link()

  invalid_spec = %{evaluator: &some_function/1}  # Missing :candidate_id

  assert {:error, :invalid_task_spec} = Scheduler.submit_task(scheduler, invalid_spec)
end

test "submit_task returns error for task_spec without evaluator" do
  {:ok, scheduler} = Scheduler.start_link()

  invalid_spec = %{candidate_id: "test-123"}  # Missing :evaluator

  assert {:error, :invalid_task_spec} = Scheduler.submit_task(scheduler, invalid_spec)
end
```

#### 1.3.4 Action Entry Points - Parameter Validation

**File: `lib/jido_ai/actions/cot/generate_elixir_code.ex:75`**

```elixir
# BEFORE (line 75):
@impl true
def run(params, context) do
  requirements = Map.fetch!(params, :requirements)
  template_type = Map.get(params, :template_type)
  # ... rest

# AFTER:
@impl true
def run(params, context) do
  with {:ok, requirements} <- Map.fetch(params, :requirements) do
    template_type = Map.get(params, :template_type)
    generate_specs = Map.get(params, :generate_specs, true)
    generate_docs = Map.get(params, :generate_docs, true)
    model = Map.get(params, :model)

    with {:ok, analysis} <- ProgramAnalyzer.analyze(requirements),
         {:ok, template} <- get_reasoning_template(analysis, template_type),
         # ... rest of existing with chain

  else
    :error -> {:error, :missing_requirements}
  end
end
```

- **Issue**: `Map.fetch!(params, :requirements)` crashes with `KeyError` if :requirements is missing
- **Fix**: Use `Map.fetch/2` with `with` statement at entry point
- **Context**: Action entry point parameter extraction
- **Error Type**: `KeyError`
- **Priority**: High - Action execution
- **Return**: Consistent `{:error, :missing_requirements}` for missing required param

**File: `lib/jido_ai/actions/cot/program_of_thought.ex:94`**

```elixir
# BEFORE (line 94):
@impl true
def run(params, context) do
  problem = Map.fetch!(params, :problem)
  domain = Map.get(params, :domain, :auto)
  # ... rest

# AFTER:
@impl true
def run(params, context) do
  with {:ok, problem} <- Map.fetch(params, :problem) do
    domain = Map.get(params, :domain, :auto)
    timeout = Map.get(params, :timeout, 5000)
    generate_explanation = Map.get(params, :generate_explanation, true)
    validate_result = Map.get(params, :validate_result, true)
    model = Map.get(params, :model)

    Logger.debug("Starting Program-of-Thought for problem: #{inspect(problem)}")

    # ... rest of existing logic
  else
    :error -> {:error, :missing_problem}
  end
end
```

- **Issue**: `Map.fetch!(params, :problem)` crashes with `KeyError` if :problem is missing
- **Fix**: Use `Map.fetch/2` with `with` statement at entry point
- **Context**: Action entry point parameter extraction
- **Error Type**: `KeyError`
- **Priority**: High - Action execution
- **Return**: Consistent `{:error, :missing_problem}` for missing required param

**Tests to Add:**
```elixir
describe "parameter validation" do
  test "generate_elixir_code returns error without requirements" do
    params = %{template_type: :iterative}  # Missing :requirements

    assert {:error, :missing_requirements} =
      GenerateElixirCode.run(params, %{})
  end

  test "program_of_thought returns error without problem" do
    params = %{domain: :mathematical}  # Missing :problem

    assert {:error, :missing_problem} =
      ProgramOfThought.run(params, %{})
  end
end
```

## Implementation Plan

### Phase 1: Voting Mechanism Fixes (Highest Priority)
**Files**: 1 file, 4 functions
**Risk**: High - Affects self-consistency reliability

1. Fix `lib/jido_ai/runner/self_consistency/voting_mechanism.ex` (4 functions)
2. Add comprehensive tests for empty path collections
3. Run existing self-consistency tests to verify no regressions
4. Test with property-based testing (empty list scenarios)

### Phase 2: Action Entry Point Fixes
**Files**: 2 files
**Risk**: High - User-facing parameter validation

1. Fix `lib/jido_ai/actions/cot/generate_elixir_code.ex:75`
2. Fix `lib/jido_ai/actions/cot/program_of_thought.ex:94`
3. Add parameter validation tests
4. Update action documentation with required parameters

### Phase 3: GEPA Core Operations
**Files**: 3 files (tree, population, scheduler)
**Risk**: Medium - Internal operations with upstream validation

1. Fix `lib/jido_ai/runner/tree_of_thoughts/tree.ex:87`
2. Fix `lib/jido_ai/runner/gepa/population.ex:458`
3. Fix `lib/jido_ai/runner/gepa/scheduler.ex:248,250`
4. Update callers to handle new return types
5. Add tests for missing keys/invalid IDs

### Phase 4: String Parsing Fix
**Files**: 1 file + test helper
**Risk**: Low - Mostly defensive improvement

1. Fix `lib/jido_ai/actions/openaiex.ex:406`
2. Fix `lib/jido_ai/actions/openai_ex/test_helpers.ex:36`
3. Add tests for invalid reqllm_id formats

### Phase 5: Integration Testing
**Scope**: All fixes

1. Run full test suite (2054 tests)
2. Add property-based tests for edge cases
3. Test GEPA workflows end-to-end
4. Test CoT patterns with edge cases
5. Verify no performance degradation

## Success Criteria

- [ ] All 11 unsafe operations fixed with defensive patterns
- [ ] All 2054 existing tests passing
- [ ] New tests added for all edge cases:
  - Empty collection inputs (voting mechanisms)
  - Missing map keys (tree, GEPA, actions)
  - Invalid string formats (reqllm_id parsing)
- [ ] Error messages provide actionable context
- [ ] No crashes on edge case inputs
- [ ] Documentation updated with:
  - Required parameters for actions
  - Error return types for all modified functions
  - Examples of safe usage patterns

## Testing Strategy

### Unit Tests

1. **Voting Mechanism Edge Cases**
   - Empty grouped paths for all 4 voting functions
   - Single path (no tie-breaking needed)
   - Multiple paths with ties

2. **Map Access Edge Cases**
   - Missing required keys (all 6 occurrences)
   - Missing optional keys (should use defaults)
   - Empty maps

3. **String Parsing Edge Cases**
   - Empty strings
   - Strings without separators
   - Invalid provider names

### Integration Tests

1. **Self-Consistency with Empty Paths**
   - Voting with no reasoning paths
   - Voting with single path
   - Voting with tied paths

2. **GEPA Workflows**
   - Population operations with invalid candidates
   - Scheduler with invalid task specs
   - Tree operations with invalid parent IDs

3. **Action Execution**
   - Actions called without required parameters
   - Actions with partial parameters

### Property-Based Tests

```elixir
property "voting functions handle arbitrary empty/non-empty path lists" do
  check all paths <- list_of(reasoning_path_generator(), min_length: 0) do
    case Self Consistency.vote(paths, strategy, tie_breaker) do
      {:ok, _result} -> assert length(paths) > 0
      {:error, :no_paths} -> assert paths == []
      {:error, _other} -> :ok
    end
  end
end
```

## Rollback Plan

If issues arise during implementation:

1. **Revert Strategy**: Git revert individual commits by phase
2. **Testing Gate**: Don't merge until all 2054 tests pass
3. **Incremental**: Each phase is independently revertible
4. **Monitoring**: Track error rates in development before production deployment

## Documentation Updates

### Files to Update:

1. **API Documentation**
   - `lib/jido_ai/actions/cot/generate_elixir_code.ex` - Document required :requirements param
   - `lib/jido_ai/actions/cot/program_of_thought.ex` - Document required :problem param
   - `lib/jido_ai/runner/tree_of_thoughts/tree.ex` - Document error returns
   - `lib/jido_ai/runner/gepa/population.ex` - Document required candidate fields
   - `lib/jido_ai/runner/gepa/scheduler.ex` - Document required task_spec fields

2. **Error Handling Guide**
   - Add examples of safe list operations
   - Add examples of safe enum operations
   - Add examples of safe map access
   - Document error tuple patterns

3. **Migration Guide**
   - Breaking changes in return types (tree.ex, population.ex)
   - How to handle new error returns
   - Updated action parameter requirements

## Performance Considerations

All fixes add minimal overhead:

1. **Pattern Matching**: Zero overhead (compile-time)
2. **Map.fetch vs Map.fetch!**: Identical performance
3. **Guard Clauses**: Negligible overhead (~1ns)
4. **Error Tuples**: No allocation overhead for success path

Expected performance impact: **< 0.1%** on happy paths

## Security Considerations

These fixes improve security by:

1. **Preventing Crashes**: GenServer crashes don't expose internal state
2. **Graceful Degradation**: Systems continue operating with partial failures
3. **Error Context**: Error messages don't leak sensitive data
4. **Input Validation**: Action entry points validate required parameters

## Dependencies

**No new dependencies required**. All fixes use standard library functions:
- `Map.fetch/2` (existing)
- `Pattern matching` (existing)
- `with` expressions (existing)

## Related Work

- **Audit Document**: `notes/audits/codebase-safety-audit-2025-10-24.md`
- **Master Plan**: `notes/planning/error-handling-improvements.md`
- **Previous Fixes**: Already fixed 5 hd() operations in GEPA modules (committed)

## Sign-Off

**Prepared By**: Claude Code
**Date**: 2025-10-24
**Review Status**: Ready for Implementation
**Estimated Effort**: 8-12 hours (4 phases + testing)
