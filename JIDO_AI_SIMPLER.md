# JidoAI Provider Architecture Simplification Plan

## Current State Analysis

The recent introduction of middleware for provider requests has created some architectural complexity and "cruft" that can be streamlined. The current flow has several inefficiencies:

### Issues Identified

1. **Duplicate Token Counting**: Transport counts request tokens even though TokenCounter already handles this
2. **Inconsistent Error Handling**: Streaming vs non-streaming requests return different error types (`Request` vs `Invalid.Parameter`)
3. **Unused Code**: Several middleware components are defined but never used (`run_safe/4`, `provider_pipeline/2`, `MonitoringMiddleware`)
4. **Overly Complex Transport**: The Transport module (~450 LOC) handles validation, HTTP calls, and error decoration - violating single responsibility
5. **Confusing Execution Order**: HTTP call happens *after* next middleware is invoked, opposite of typical middleware patterns

## Current Pipeline Flow

```
Provider → HTTP.do_http_request/4 → [TokenCounter, CostCalculator, Transport] → HTTP Call
```

**Request Phase**: TokenCounter → CostCalculator → Transport → `final_fun` (flips to response)
**Response Phase**: Transport (HTTP) → CostCalculator (cost) → TokenCounter (response tokens)

## Proposed Simplified Architecture

```
Provider → [Validation, TokenCounter, CostCalculator, Transport] → HTTP Call
```

Where each middleware has a single responsibility:
- **Validation**: Parameter validation only
- **TokenCounter**: Token counting only  
- **CostCalculator**: Cost calculation only
- **Transport**: HTTP communication only

## Implementation Plan

### Phase 0: Safety Net (Setup)
**Goal**: Ensure we can refactor safely

#### 0.1 Extend Test Coverage
- [ ] Add tests asserting `:request_tokens` is set only once (stream & non-stream)
- [ ] Add contract tests for error shapes (`Invalid.Parameter` for missing opts, `API.Request` for HTTP errors)
- [ ] Verify all existing tests pass

#### 0.2 Enable Code Quality Checks
- [ ] Enable dialyzer or credo "unused function" warnings if not already enabled
- [ ] Run `mix quality` to establish baseline

**Verification**: `mix test && mix quality`

---

### Phase 1: Remove Duplicate Token Counting (Low Risk)
**Goal**: Eliminate redundant token counting in Transport

#### 1.1 Remove Duplicate Logic
- [ ] Remove lines 80-86 in `Middleware.Transport` that call `TokenCounter.count_request_tokens/1`
- [ ] Keep the log line but fetch already present value: `request_tokens = Context.get_meta(context, :request_tokens, 0)`
- [ ] Update relevant documentation

#### 1.2 Test & Verify
- [ ] Run full test suite
- [ ] Verify token counting still works correctly
- [ ] Check that logs still show correct token counts

**Verification**: `mix test && mix quality`

---

### Phase 2: Extract Validation Middleware (Medium Risk)
**Goal**: Separate validation concerns from Transport

#### 2.1 Create Validation Middleware
- [ ] Create `Jido.AI.Middleware.Validation` (~40 LOC)
- [ ] Runs only in request phase
- [ ] Uses existing `Provider.Util.Validation.get_required_opt/2`
- [ ] On failure, sets `:error` meta and flips phase to `:response`

#### 2.2 Update Transport
- [ ] Remove validation block (lines 76-113) from Transport
- [ ] Transport now focuses solely on HTTP communication

#### 2.3 Update Pipelines
- [ ] Update `http_pipeline` to: `[Validation, TokenCounter, CostCalculator, Transport]`
- [ ] Update `stream_pipeline` to: `[Validation, TokenCounter, CostCalculator]`

#### 2.4 Simplify Streaming Logic
- [ ] Remove duplicated validation from `HTTP.do_stream_request/4`
- [ ] Simplify to: `result = run(stream_pipeline, context, &flip_phase/1)`

**Verification**: `mix test && mix quality`

---

### Phase 3: Single-Responsibility Transport (Medium Risk)
**Goal**: Make Transport handle only HTTP communication

#### 3.1 Remove Duplicate Response Token Counting
- [ ] Delete response token counting lines (65-67) from Transport
- [ ] TokenCounter already handles this in response phase

#### 3.2 Extract Cost Logic
- [ ] Remove cost calculation logic (lines 195-206) from Transport
- [ ] CostCalculator will handle all cost-related operations
- [ ] Create helper `Transport.decorate/2` for backwards compatibility if needed

#### 3.3 Update Documentation
- [ ] Update module docs to reflect single responsibility
- [ ] Update pipeline documentation

**Verification**: `mix test && mix quality`

---

### Phase 4: Unify Error Handling (Low Risk)
**Goal**: Consistent error shapes across request types

#### 4.1 Align Error Types
- [ ] With Validation extracted, both stream and non-stream paths yield same errors
- [ ] Remove dedicated "stream vs non-stream" expectations in tests
- [ ] Assert consistent error shape across all request types

#### 4.2 Update Tests
- [ ] Consolidate error handling tests
- [ ] Remove branching logic for different error types in client code

**Verification**: `mix test && mix quality`

---

### Phase 5: Remove Unused Code (Low Risk)
**Goal**: Clean up unused middleware helpers

#### 5.1 Audit Unused Functions
- [ ] Search codebase for usage of:
  - `Middleware.run_safe/4`
  - `Middleware.provider_pipeline/2` 
  - `MonitoringMiddleware`
  - `Context.merge_private/2`

#### 5.2 Deprecate/Remove
- [ ] If unused, add `@deprecated` annotations in current release
- [ ] Plan removal in next release
- [ ] Update documentation

**Verification**: `mix test && mix quality`

---

### Phase 6: Future Improvements (Optional)
**Goal**: Further architectural improvements (larger scope)

#### 6.1 HTTP as Final Function (Breaking Change)
- [ ] Make HTTP call the `final_fun` instead of middleware
- [ ] Delete ~300 lines of phase juggling logic in Transport
- [ ] Turn Transport into small "HTTP adapter"
- [ ] **Note**: This is a breaking refactor - schedule for major version

## Expected Benefits

1. **Reduced Complexity**: ~250+ LOC removed
2. **Clear Mental Model**: `Validation → TokenCounter → CostCalculator → HTTP`
3. **No Duplicate Work**: Single sources for token counts and costs
4. **Consistent Error Handling**: Same error structures for sync & stream
5. **Easier Extension**: Adding new cross-cutting middlewares becomes simpler
6. **Provider Agnostic**: Transport can be swapped to Finch/Mint/Tesla without touching other middleware

## Pull Request Strategy

- **PR-1** (Phase 1): "Remove duplicate request token count in Transport"
- **PR-2** (Phase 2): "Introduce Validation middleware & reuse in streaming"  
- **PR-3** (Phase 3): "Make Transport single-responsibility"
- **PR-4** (Phase 4): "Align error shapes across request types"
- **PR-5** (Phase 5): "Deprecate unused middleware helpers"

Each PR removes complexity without altering public APIs, keeping existing tests and `mix quality` green.

## Quality Gates

Before each phase:
1. Run `mix test` - all tests must pass
2. Run `mix quality` - quality checks must pass
3. Verify no public API changes that would break consumers
4. Ensure error handling remains consistent for clients

After completion, the architecture will be significantly cleaner while maintaining full backward compatibility and test coverage.
