# Feature Planning: Mock Registry Functions in Tests

**Feature ID**: mock-registry-tests
**Branch**: feature/mock-registry-tests
**Status**: Planning
**Priority**: Critical
**Created**: 2025-10-18
**Author**: Planning Agent

---

## 1. Problem Statement

### Current Issue

The Jido AI test suite has a critical 60GB memory leak that causes Out-Of-Memory (OOM) kills during test runs. The root cause has been identified:

- **Memory Leak Source**: `Jido.AI.Model.Registry.list_models()` and `discover_models()` create 2000+ full `Jido.AI.Model` structs on each call
- **Test Impact**: 165+ test files call these registry functions throughout the test suite
- **Memory Accumulation**: Tests accumulate hundreds of thousands of structs faster than garbage collection can clean them up
- **Failed Attempts**: Multiple mitigation strategies have failed:
  - Lazy loading mechanisms
  - Cache cleanup routines
  - Disabling cache entirely in test mode
  - Conservative concurrency settings (max_cases: 2)

### Why Previous Fixes Failed

The issue is not with caching or memory management - it's the fundamental problem of creating 2000+ full structs on every registry call. Even with disabled caching and aggressive GC, the test suite calls these functions 165+ times, creating:

```
165 calls × 2000+ models × ~5KB per struct = ~1.65GB minimum
```

In practice, with nested test contexts and concurrent execution, memory usage balloons to 60GB+ before OOM kills occur.

### Current Test Configuration

From `test/test_helper.exs`:
```elixir
ExUnit.start(
  max_cases: 2,        # Reduced from default to prevent memory issues
  timeout: 120_000     # Extended timeout due to memory pressure
)
```

This is a workaround that slows down the entire test suite but doesn't solve the root cause.

---

## 2. Solution Overview

### Core Strategy: Mock Minimal Test Data

Instead of loading 2000+ real models in tests, we will:

1. **Create test helpers** that return minimal mock model data (3-5 models per provider)
2. **Update all 165+ test call sites** to use mocked registry functions
3. **Preserve test coverage** by ensuring mocks still validate correct behavior
4. **Maintain test correctness** by using representative model data that exercises all code paths

### Key Principles

- **Minimal Data**: Return only 3-5 carefully chosen models per test
- **Representative Models**: Include models that exercise different capabilities, modalities, and pricing tiers
- **Consistent Mocking**: Use Mimic library (already in use) for all mocks
- **Test Isolation**: Each test gets independent mock data, preventing cross-test pollution
- **Zero Real Registry Calls**: No test should ever call the real registry functions

### Expected Outcomes

- **Memory Usage**: Reduce from 60GB to under 500MB
- **Test Speed**: Reduce test suite runtime by 50-70% (no network/registry overhead)
- **Test Reliability**: Eliminate OOM kills and flaky tests due to memory pressure
- **Test Maintainability**: Clear, documented mocking patterns for future tests

---

## 3. Agent Consultations

### Consultation with elixir-expert

**Topic**: Best practices for test mocking in Elixir/ExUnit

**Key Insights**:

1. **Mimic vs Mox**:
   - Mimic is already in use and appropriate for mocking concrete modules
   - Provides `copy/1`, `stub/3`, and `expect/4` functions
   - Allows per-test isolation with `set_mimic_global` and `set_mimic_private`

2. **Mocking Strategy**:
   - Create test helper module that provides fixture data
   - Use `stub/3` for general mock behavior across tests
   - Use `expect/4` when specific call counts/arguments matter
   - Always call `copy/1` in setup to enable mocking

3. **Test Data Patterns**:
   ```elixir
   # Good: Minimal, focused test data
   def minimal_models(:anthropic) do
     [
       %Model{id: "claude-3-5-sonnet", provider: :anthropic, capabilities: %{tool_call: true}},
       %Model{id: "claude-3-haiku", provider: :anthropic, capabilities: %{tool_call: false}}
     ]
   end

   # Bad: Loading real data in tests
   def all_models(:anthropic) do
     # Don't fetch from real registry!
     Jido.AI.Model.Registry.list_models(:anthropic)
   end
   ```

4. **Setup Patterns**:
   ```elixir
   setup :set_mimic_global  # Share mocks across all processes in test

   setup do
     copy(Jido.AI.Model.Registry)
     stub(Registry, :list_models, fn -> {:ok, TestHelpers.minimal_models()} end)
     :ok
   end
   ```

5. **Avoiding Common Pitfalls**:
   - Always return `{:ok, data}` or `{:error, reason}` tuples (match production API)
   - Don't forget to mock all public functions that tests might call
   - Use `stub_with/2` to replace entire module behavior when appropriate
   - Remember that `async: false` is required when using global mocks

**Recommendations**:
- Create `test/support/registry_test_helpers.ex` for all mock data
- Document each mock fixture with comments explaining what it tests
- Use pattern matching in stubs to return different data per provider
- Keep mock data in version control for reproducibility

### Consultation with senior-engineer-reviewer

**Topic**: Architectural decisions on test data strategy

**Key Insights**:

1. **Test Data Architecture**:
   - **Three-tier approach**: Minimal (3-5 models), Standard (10-15 models), Comprehensive (50-100 models)
   - Most tests should use Minimal tier
   - Standard tier for integration tests
   - Comprehensive tier only for registry-specific tests

2. **Mock Data Selection Criteria**:
   ```
   Choose models that represent:
   - Different providers (OpenAI, Anthropic, Google, local)
   - Different capability sets (tool_call: true/false, reasoning, multimodal)
   - Different pricing tiers (premium, standard, economy)
   - Different context lengths (small: 8K, medium: 32K, large: 200K+)
   - Edge cases (missing fields, nil values, legacy format)
   ```

3. **Test Migration Strategy**:
   - **Phase 1**: Create helpers and mock infrastructure (1 file)
   - **Phase 2**: Update registry-specific tests (2 files, 23 occurrences)
   - **Phase 3**: Update provider validation tests (10 files, ~80 occurrences)
   - **Phase 4**: Update integration tests (10 files, ~60 occurrences)
   - **Phase 5**: Verification and documentation

4. **Risk Mitigation**:
   - Run tests after each file update to catch issues early
   - Keep a "golden test" that validates mock data matches production structure
   - Document any behavioral differences between mocks and real registry
   - Create CI job that periodically validates mocks against real registry

5. **Long-term Maintainability**:
   - Create clear naming conventions: `minimal_anthropic_models/0`, `standard_openai_models/0`
   - Version mock data with comments when production registry changes
   - Add property-based tests to validate mock data structure
   - Consider extracting to separate package if other projects need it

**Recommendations**:
- Start with the most memory-intensive tests first (provider validation suite)
- Create a migration checklist for each file to ensure consistency
- Add telemetry to track when tests use mocks vs real registry (for future debugging)
- Document the trade-off: faster tests with less real-world coverage

---

## 4. Technical Details

### 4.1 Files to Create

#### New Test Helper Module

**File**: `test/support/registry_test_helpers.ex`

**Purpose**: Centralized mock data for all registry function mocks

**Structure**:
```elixir
defmodule Jido.AI.Test.RegistryTestHelpers do
  @moduledoc """
  Test helpers providing minimal mock data for Registry functions.

  This module prevents the 60GB memory leak by returning small, focused
  test datasets instead of 2000+ real models from the registry.
  """

  alias Jido.AI.Model

  # Minimal model sets (3-5 models) for most tests
  def minimal_models(provider \\ nil)
  def minimal_anthropic_models()
  def minimal_openai_models()
  def minimal_google_models()

  # Standard model sets (10-15 models) for integration tests
  def standard_models(provider \\ nil)

  # Comprehensive sets (50-100 models) for registry tests only
  def comprehensive_models(provider \\ nil)

  # Registry stats mocks
  def mock_registry_stats()

  # Helper to setup common mocks
  def setup_registry_mocks(opts \\ [])
end
```

### 4.2 Files to Modify

#### Test Files with Registry Calls (22 files, 165 occurrences)

**Category 1: Registry-Specific Tests (2 files, 23 occurrences)**
- `test/jido_ai/model/registry_test.exs` - Already uses mocks, verify completeness
- `test/jido_ai/model/modality_validation_test.exs` - Update to use test helpers

**Category 2: Provider Validation Tests (10 files, ~80 occurrences)**
- `test/jido_ai/provider_validation/provider_system_validation_test.exs` (highest priority)
- `test/jido_ai/provider_validation/functional/azure_openai_validation_test.exs`
- `test/jido_ai/provider_validation/functional/groq_validation_test.exs`
- `test/jido_ai/provider_validation/functional/replicate_validation_test.exs`
- `test/jido_ai/provider_validation/functional/cohere_validation_test.exs`
- `test/jido_ai/provider_validation/functional/alibaba_cloud_validation_test.exs`
- `test/jido_ai/provider_validation/functional/amazon_bedrock_validation_test.exs`
- `test/jido_ai/provider_validation/functional/lm_studio_validation_test.exs`
- `test/jido_ai/provider_validation/functional/ollama_validation_test.exs`
- `test/jido_ai/provider_validation/functional/together_ai_validation_test.exs`

**Category 3: Integration Tests (10 files, ~60 occurrences)**
- `test/integration/model_catalog_integration_test.exs`
- `test/integration/provider_registry_integration_test.exs`
- `test/jido_ai/provider/openrouter_test.exs`
- `test/jido_ai/provider/google_test.exs`
- `test/jido_ai/provider_validation/functional/perplexity_validation_test.exs`
- `test/jido_ai/provider_validation/functional/local_connection_health_test.exs`
- `test/jido_ai/provider_validation/functional/ai21_validation_test.exs`
- `test/jido_ai/provider_validation/functional/local_model_discovery_test.exs`
- `test/jido_ai/provider_validation/performance/benchmarks_test.exs`
- `test/jido_ai/provider_validation/integration/enterprise_auth_flow_test.exs`

### 4.3 Mock Data Specifications

#### Minimal Model Set (Default for Most Tests)

**Purpose**: Cover basic functionality with minimal memory footprint

**Models**:
1. **Anthropic Claude 3.5 Sonnet**
   - Capabilities: `%{tool_call: true, reasoning: true}`
   - Context: 200,000 tokens
   - Tier: Premium

2. **OpenAI GPT-4**
   - Capabilities: `%{tool_call: true, reasoning: true}`
   - Context: 128,000 tokens
   - Tier: Premium

3. **Google Gemini Pro**
   - Capabilities: `%{tool_call: true, reasoning: false, multimodal: true}`
   - Context: 32,000 tokens
   - Tier: Standard

4. **Anthropic Claude 3 Haiku**
   - Capabilities: `%{tool_call: false, reasoning: false}`
   - Context: 200,000 tokens
   - Tier: Economy

5. **Local Ollama Model** (edge case)
   - Capabilities: `nil` (legacy format)
   - Context: 8,192 tokens
   - Tier: Local

**Total Memory**: ~25KB (vs 10MB+ for real data)

#### Standard Model Set (Integration Tests)

**Purpose**: More comprehensive coverage for multi-provider tests

**Includes**: Minimal set + 10 additional models covering:
- More providers (Groq, Cohere, Mistral, Replicate)
- Edge cases (missing pricing, nil capabilities)
- Various context lengths (4K, 16K, 32K, 128K, 200K)

**Total Memory**: ~75KB

#### Comprehensive Model Set (Registry Tests Only)

**Purpose**: Validate registry functionality without loading all 2000+ models

**Includes**: 50-100 carefully chosen models representing:
- All major providers
- Full range of capabilities and modalities
- Pricing tier distribution
- Legacy and modern model formats

**Total Memory**: ~500KB (still 1/20th of current test memory usage)

### 4.4 Mocking Patterns

#### Pattern 1: Simple Stub (Most Common)

```elixir
setup do
  copy(Jido.AI.Model.Registry)

  stub(Registry, :list_models, fn
    nil -> {:ok, TestHelpers.minimal_models()}
    provider -> {:ok, TestHelpers.minimal_models(provider)}
  end)

  stub(Registry, :discover_models, fn filters ->
    models = TestHelpers.minimal_models()
    filtered = apply_test_filters(models, filters)
    {:ok, filtered}
  end)

  :ok
end
```

#### Pattern 2: Provider-Specific Expect (When Call Count Matters)

```elixir
test "fetches models from specific provider" do
  expect(Registry, :list_models, fn :anthropic ->
    {:ok, TestHelpers.minimal_anthropic_models()}
  end)

  # Test code that should call list_models(:anthropic) exactly once
end
```

#### Pattern 3: Error Case Stub

```elixir
stub(Registry, :list_models, fn :unknown_provider ->
  {:error, :provider_not_available}
end)
```

#### Pattern 4: Registry Stats Mock

```elixir
stub(Registry, :get_registry_stats, fn ->
  {:ok, %{
    total_models: 5,
    total_providers: 3,
    registry_models: 4,
    legacy_models: 1,
    provider_coverage: %{anthropic: 2, openai: 2, google: 1},
    capabilities_distribution: %{tool_call: 3, reasoning: 2}
  }}
end)
```

---

## 5. Success Criteria

### Memory Metrics

- [ ] Test suite memory usage under 500MB (down from 60GB)
- [ ] No OOM kills during full test suite run
- [ ] Individual test files use <50MB memory
- [ ] Memory usage stable across multiple test runs

### Test Execution

- [ ] All 165+ test files pass with mocked registry
- [ ] Test suite runtime reduced by 50-70%
- [ ] No flaky tests due to memory pressure
- [ ] Tests can run with `async: true` where appropriate

### Code Quality

- [ ] All mocks in centralized helper module
- [ ] Clear documentation for each mock fixture
- [ ] Consistent mocking patterns across all tests
- [ ] No direct calls to real registry functions in tests

### Verification

- [ ] Create "golden test" that validates mock structure matches production
- [ ] Add comments documenting mock data choices
- [ ] Update test README with mocking guidelines
- [ ] Add CI check that fails if real registry called in tests

---

## 6. Implementation Plan

### Phase 1: Foundation (Day 1)

**Goal**: Create test helper infrastructure

**Tasks**:
1. Create `test/support/registry_test_helpers.ex`
2. Implement minimal model fixtures for each provider
3. Implement standard and comprehensive fixtures
4. Add mock registry stats
5. Create setup helper functions
6. Add documentation and usage examples

**Verification**:
- Helper module compiles without errors
- Fixture functions return valid Model structs
- Mock data structure matches production models

**Estimated Impact**: 0 files migrated, infrastructure ready

### Phase 2: Registry Tests (Day 1-2)

**Goal**: Update registry-specific tests (highest value, lowest risk)

**Files**:
1. `test/jido_ai/model/registry_test.exs` (verify existing mocks)
2. `test/jido_ai/model/modality_validation_test.exs`

**Tasks per file**:
1. Add `alias Jido.AI.Test.RegistryTestHelpers`
2. Add `copy(Registry)` to setup if missing
3. Replace `Registry.list_models()` calls with stubs
4. Replace `Registry.discover_models()` calls with stubs
5. Update assertions if needed for smaller dataset
6. Run tests and verify they pass

**Verification**:
- Tests pass with mocked data
- Memory usage for these tests <50MB
- No calls to real registry (add assertion)

**Estimated Impact**: 2 files, ~23 occurrences

### Phase 3: Provider Validation Tests (Day 2-4)

**Goal**: Update provider validation suite (biggest memory impact)

**Priority Order** (most memory-intensive first):
1. `test/jido_ai/provider_validation/provider_system_validation_test.exs` (highest impact)
2. `test/jido_ai/provider_validation/performance/benchmarks_test.exs`
3. `test/jido_ai/provider_validation/integration/enterprise_auth_flow_test.exs`
4. Functional validation tests (8 files)

**Tasks per file**:
1. Add test helpers import
2. Add registry mocks to setup
3. Update all `list_models()` calls
4. Update all `discover_models()` calls
5. Update assertions for smaller datasets
6. Change assertions that count total models to use mock stats
7. Run tests and fix failures

**Special Considerations**:
- Concurrent request tests need independent mock data
- Benchmark tests may need standard fixtures (more models)
- Error handling tests need error case stubs

**Verification**:
- All provider validation tests pass
- Memory usage for suite <200MB
- Test runtime reduced by 60%+

**Estimated Impact**: 10 files, ~80 occurrences

### Phase 4: Integration Tests (Day 4-5)

**Goal**: Update integration and cross-component tests

**Files**:
- Integration test files (2 files)
- Provider-specific tests (2 files)
- Remaining functional tests (6 files)

**Tasks per file**:
1. Add test helpers import
2. Mock registry in setup
3. Update all registry calls
4. Adjust test expectations for mock data
5. Run and verify

**Special Considerations**:
- Integration tests may need standard fixtures
- Cross-component tests need consistent mock data
- Some tests may need `async: false` due to Mimic global mocks

**Verification**:
- All integration tests pass
- End-to-end workflows work with mocked data
- Memory usage remains low

**Estimated Impact**: 10 files, ~60 occurrences

### Phase 5: Verification & Documentation (Day 5-6)

**Goal**: Ensure quality and maintainability

**Tasks**:
1. Create golden test that validates mock structure
   ```elixir
   test "mock models match production structure" do
     mock = TestHelpers.minimal_anthropic_models() |> hd()
     assert %Model{} = mock
     assert is_atom(mock.provider)
     assert is_binary(mock.id)
     # ... validate all required fields
   end
   ```

2. Add CI check for real registry calls
   ```elixir
   # Add to test helper
   def ensure_no_real_registry_calls do
     refute function_exported?(Registry, :list_models, 1)
   end
   ```

3. Document mocking approach in test README
   - When to use minimal vs standard vs comprehensive fixtures
   - How to add new mock models
   - Mocking patterns and examples
   - Troubleshooting guide

4. Run full test suite multiple times
   - Verify memory stays under 500MB
   - Verify no flaky failures
   - Verify consistent runtime

5. Update feature planning document with results

**Deliverables**:
- Golden test added
- CI check added
- Documentation updated
- Full test suite passing consistently
- Memory metrics documented

### Phase 6: Branch Management (Day 6)

**Goal**: Create new feature branch and commit work

**Tasks**:
1. Create new branch: `feature/mock-registry-tests`
2. Commit all changes with descriptive messages
3. Ensure all tests pass on new branch
4. Document changes in notes/features/mock-registry-tests-summary.md
5. Do NOT create PR (wait for Pascal's approval)

**Branch Protection**:
- Do NOT push to remote without permission
- Do NOT merge to main
- Do NOT amend commits without permission

---

## 7. Testing Strategy

### Test Validation Approach

**For Each Migrated File**:
1. Run the specific test file in isolation
2. Check memory usage with `:observer.start()`
3. Verify all tests pass
4. Check for warnings or deprecations

**Memory Monitoring**:
```elixir
# Add to test setup for validation
setup do
  before_memory = :erlang.memory(:total)
  on_exit(fn ->
    after_memory = :erlang.memory(:total)
    growth = after_memory - before_memory
    if growth > 10_000_000, do: IO.puts("WARNING: Test grew memory by #{growth} bytes")
  end)
  :ok
end
```

**Regression Testing**:
- Run full test suite before migration (baseline metrics)
- Run full test suite after each phase
- Compare pass/fail rates
- Compare memory usage
- Compare runtime

### Mock Validation

**Structure Validation**:
```elixir
test "mock models have required fields" do
  for model <- TestHelpers.minimal_models() do
    assert %Model{} = model
    assert model.id
    assert model.provider
    assert is_map(model.capabilities) or is_nil(model.capabilities)
  end
end
```

**Behavior Validation**:
```elixir
test "mock discover_models filters work like production" do
  all_models = TestHelpers.minimal_models()

  # Capability filter
  {:ok, tool_models} = mock_discover_models(capability: :tool_call)
  assert Enum.all?(tool_models, &(&1.capabilities.tool_call))

  # Context length filter
  {:ok, large_ctx} = mock_discover_models(min_context_length: 100_000)
  assert Enum.all?(large_ctx, fn m ->
    hd(m.endpoints).context_length >= 100_000
  end)
end
```

### Continuous Validation

**After Every Phase**:
1. Run full test suite
2. Record memory usage (should decrease with each phase)
3. Record runtime (should decrease with each phase)
4. Document any failures or issues
5. Verify no new flaky tests introduced

**Final Validation**:
1. Run test suite 5 times consecutively
2. Verify consistent memory usage (<500MB)
3. Verify consistent runtime (reduced by 50-70%)
4. Verify no OOM kills
5. Verify all 165+ test files pass

---

## 8. Risk Assessment

### High Risk Items

1. **Mock Data Doesn't Match Production Behavior**
   - **Mitigation**: Create golden test that validates structure
   - **Mitigation**: Periodically run tests against real registry in CI
   - **Impact**: Tests pass but production code fails

2. **Tests Become Less Effective**
   - **Mitigation**: Use representative model data that exercises all code paths
   - **Mitigation**: Keep comprehensive fixtures for critical tests
   - **Impact**: Bugs slip through that would have been caught with real data

3. **Difficult to Maintain Mock Data**
   - **Mitigation**: Centralize in single module with clear documentation
   - **Mitigation**: Version mock data with comments
   - **Impact**: Mock data drifts from production over time

### Medium Risk Items

1. **Tests Break During Migration**
   - **Mitigation**: Migrate incrementally, test after each file
   - **Mitigation**: Keep rollback plan (revert commits)
   - **Impact**: Temporary test failures during migration

2. **Some Tests Need Real Registry Data**
   - **Mitigation**: Identify these tests early (likely integration tests)
   - **Mitigation**: Tag them separately, run in isolation
   - **Impact**: Small subset of tests still have memory issues

3. **Inconsistent Mocking Patterns**
   - **Mitigation**: Document standard patterns in test helpers
   - **Mitigation**: Code review to ensure consistency
   - **Impact**: Harder to maintain and understand tests

### Low Risk Items

1. **Performance Overhead from Mocking**
   - **Mitigation**: Mocking is faster than real registry calls
   - **Impact**: Negligible, actually improves performance

2. **Mock Data Gets Stale**
   - **Mitigation**: Add CI job to validate against real registry monthly
   - **Impact**: Minor, caught by golden tests

---

## 9. Rollback Plan

If critical issues arise during migration:

### Immediate Rollback (Per File)
```bash
git checkout HEAD -- test/path/to/problematic_test.exs
```

### Phase Rollback (Entire Category)
```bash
# If Phase 3 fails
git reset --hard <commit-before-phase-3>
```

### Full Rollback (Nuclear Option)
```bash
git checkout main
git branch -D feature/mock-registry-tests
```

### Partial Success Strategy

If some tests can't be migrated:
1. Complete migration for files that work
2. Document which tests still use real registry
3. Tag them with `@tag :real_registry`
4. Run them separately with higher memory limits
5. Open issue to investigate alternatives

---

## 10. Future Enhancements

### Short Term (Next 3 months)

1. **Property-Based Testing for Mock Data**
   - Use StreamData to validate mock structure
   - Generate random mock data matching schema
   - Ensures mock data always valid

2. **Mock Data Versioning**
   - Tag mock data with ReqLLM catalog version
   - Automated updates when catalog changes
   - Changelog for mock data changes

3. **Selective Real Registry Testing**
   - CI job that runs subset of tests with real registry
   - Validates mocks haven't diverged
   - Catches production issues mocks might miss

### Long Term (6+ months)

1. **Extract to Separate Package**
   - `jido_ai_test_helpers` package
   - Reusable across projects
   - Community contributions

2. **Mock Registry Server**
   - Lightweight in-memory registry for tests
   - Behaves exactly like real registry
   - No network calls, minimal memory

3. **Automatic Mock Generation**
   - Tool to generate mock data from real registry
   - Keeps mocks up-to-date automatically
   - Configurable model selection criteria

---

## 11. Success Metrics (Target vs Baseline)

| Metric | Baseline (Before) | Target (After) | Critical Threshold |
|--------|-------------------|----------------|-------------------|
| Memory Usage | 60GB+ | <500MB | <1GB |
| OOM Kills | Frequent | 0 | 0 |
| Test Runtime | ~15-20 min | <8 min | <10 min |
| Test Pass Rate | 85-90% (OOM) | 100% | >95% |
| Flaky Tests | 10-15 | 0-2 | <5 |
| Registry Calls | 165+ | 0 | 0 |
| Memory Per Test | 50-200MB | <5MB | <10MB |

---

## 12. Implementation Checklist

### Pre-Implementation
- [ ] Review this planning document with Pascal
- [ ] Get approval to proceed
- [ ] Create feature branch: `feature/mock-registry-tests`
- [ ] Document baseline metrics (memory, runtime, pass rate)

### Phase 1: Foundation
- [ ] Create `test/support/registry_test_helpers.ex`
- [ ] Implement minimal fixtures
- [ ] Implement standard fixtures
- [ ] Implement comprehensive fixtures
- [ ] Add mock stats function
- [ ] Add setup helper functions
- [ ] Document all fixtures
- [ ] Run validation tests

### Phase 2: Registry Tests
- [ ] Update `test/jido_ai/model/registry_test.exs`
- [ ] Update `test/jido_ai/model/modality_validation_test.exs`
- [ ] Verify tests pass
- [ ] Measure memory improvement
- [ ] Document any issues

### Phase 3: Provider Validation Tests
- [ ] Update `provider_system_validation_test.exs`
- [ ] Update `benchmarks_test.exs`
- [ ] Update `enterprise_auth_flow_test.exs`
- [ ] Update 8 functional validation tests
- [ ] Verify all tests pass
- [ ] Measure memory improvement
- [ ] Document any issues

### Phase 4: Integration Tests
- [ ] Update integration test files (2)
- [ ] Update provider-specific tests (2)
- [ ] Update remaining functional tests (6)
- [ ] Verify all tests pass
- [ ] Measure memory improvement
- [ ] Document any issues

### Phase 5: Verification
- [ ] Create golden test
- [ ] Add CI check for real registry calls
- [ ] Update test documentation
- [ ] Run full suite 5x, verify consistency
- [ ] Document final metrics
- [ ] Update this planning doc with results

### Phase 6: Completion
- [ ] Commit all changes with clear messages
- [ ] Create summary document
- [ ] Update memory leak issue with resolution
- [ ] Do NOT create PR (wait for approval)
- [ ] Present results to Pascal

---

## 13. Notes and Observations

### During Planning

1. **Mimic Already in Use**: The test suite already uses Mimic extensively, which is perfect for this use case. We don't need to add new dependencies.

2. **Registry Test Already Mocked**: The `test/jido_ai/model/registry_test.exs` file already uses comprehensive mocking. This is a good example to follow for other tests.

3. **Test Concurrency Disabled**: Many tests use `async: false`, likely due to memory issues. After migration, some may be able to switch to `async: true`.

4. **Cache Workarounds Present**: The test helper has cache cleanup code that will be unnecessary after mocking.

### Key Decisions

1. **Three-tier mock data**: Provides flexibility without overcomplicating
2. **Centralized helpers**: Single source of truth for all mock data
3. **Incremental migration**: Reduces risk, allows validation at each step
4. **Keep some real tests**: Maintain a few integration tests with real registry for validation

### Questions for Pascal

1. Should any tests still use real registry data?
2. What's the acceptable memory threshold? (Target: <500MB)
3. Should we add telemetry to track mock usage?
4. Is it okay to create the new branch or should I wait?

---

## 14. References

### Related Files
- `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/model/registry.ex` - Main registry module
- `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/model.ex` - Model struct definition
- `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/test/test_helper.exs` - Test configuration
- `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/test/jido_ai/model/registry_test.exs` - Example of good mocking

### Related Issues
- Memory leak issue: 60GB usage during test suite
- OOM kills causing test suite failures
- Slow test suite runtime due to memory pressure

### External Resources
- Mimic documentation: https://hexdocs.pm/mimic
- ExUnit mocking patterns: https://hexdocs.pm/ex_unit/ExUnit.html
- Elixir test best practices: https://hexdocs.pm/elixir/writing-tests.html

---

**Status**: Ready for review and approval
**Next Steps**: Await Pascal's feedback on this plan before implementation
