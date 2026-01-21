# Task 2.3.1: Provider Implementation Migration - Planning Document

## Overview

This document outlines the plan for migrating legacy provider-specific internal implementations to use ReqLLM while preserving all public APIs. This is a critical infrastructure improvement that reduces code complexity and maintenance burden while ensuring zero breaking changes for users.

**Key Principle**: The module names `Jido.AI.Actions.OpenaiEx` and its submodules are part of the public API and **must be preserved**. Only the internal implementation should be changed to use ReqLLM.

---

## 1. Problem Statement

### Current State

The codebase currently contains multiple provider-specific implementation layers:

1. **Action Modules** (Public API):
   - `Jido.AI.Actions.OpenaiEx` - Chat completion with tool calling
   - `Jido.AI.Actions.OpenaiEx.Embeddings` - Embedding generation
   - `Jido.AI.Actions.OpenaiEx.ImageGeneration` - Image generation
   - `Jido.AI.Actions.OpenaiEx.ResponseRetrieve` - Response retrieval
   - `Jido.AI.Actions.OpenaiEx.ToolHelper` - Tool conversion utilities

2. **Provider Adapters** (Internal API):
   - `Jido.AI.Provider.OpenAI` - OpenAI model listing and metadata
   - `Jido.AI.Provider.Anthropic` - Anthropic model listing and metadata
   - `Jido.AI.Provider.Google` - Google Gemini model listing and metadata
   - `Jido.AI.Provider.OpenRouter` - OpenRouter model listing and metadata
   - `Jido.AI.Provider.Cloudflare` - Cloudflare model listing and metadata

### Problems with Current Implementation

1. **Code Duplication**: Each provider has custom HTTP client code, retry logic, and response parsing
2. **Maintenance Burden**: Provider API changes require updates in multiple places
3. **Dependency Weight**: OpenaiEx library is a heavy dependency that's no longer needed
4. **Limited Provider Support**: Custom implementations only support 5 providers, while ReqLLM supports 57+
5. **Inconsistent Behavior**: Different error handling and retry logic across providers

### Why This Migration is Important

1. **Reduced Complexity**: Single unified implementation through ReqLLM
2. **Broader Provider Support**: Access to all 57+ ReqLLM providers without additional code
3. **Better Maintenance**: Provider-specific logic handled by ReqLLM
4. **Improved Reliability**: ReqLLM's battle-tested HTTP client and retry logic
5. **Smaller Footprint**: Removing OpenaiEx dependency reduces application size

---

## 2. Solution Overview

### High-Level Approach

The migration follows a "facade pattern" where:

1. **Public module names remain unchanged** - Users continue calling the same modules
2. **Internal implementation replaced** - Uses ReqLLM bridge instead of direct API calls
3. **Public function signatures preserved** - Same inputs, same outputs
4. **Error handling maintained** - Error structures remain compatible
5. **Provider adapters simplified** - Focus on metadata only, not API calls

### Migration Strategy per Component

#### 2.3.1.1: OpenAI Action Migration (Jido.AI.Actions.OpenaiEx)

**Current Implementation**:
- Uses OpenaiEx library directly for API calls
- Already partially migrated to use ReqLLM (lines 287-331)
- Still has OpenaiEx dependencies for message format conversion

**Migration Plan**:
- Keep module name: `Jido.AI.Actions.OpenaiEx`
- Keep all public function signatures
- Complete migration started in Phase 1:
  - Remove remaining OpenaiEx.Chat dependencies
  - Simplify message format conversion
  - Use ReqLLM.generate_text and ReqLLM.stream_text exclusively

**Status**: 80% complete - needs final cleanup

#### 2.3.1.2: Anthropic Internal Migration

**Current Implementation**:
- `Jido.AI.Provider.Anthropic` handles model listing via direct API calls
- Custom HTTP header construction with Anthropic-specific version header
- No action modules exist - would go through OpenaiEx with custom base URL

**Migration Plan**:
- Simplify provider adapter to metadata-only:
  - Remove direct API calls for model listing
  - Use ReqLLM's model registry instead
  - Keep only `build/1` function for creating Model structs
  - Remove HTTP client code (request_headers, fetch_and_cache_models)

**Status**: Not started

#### 2.3.1.3: Google Internal Migration

**Current Implementation**:
- `Jido.AI.Provider.Google` fetches models from Google Gemini API
- Custom model mapping with hardcoded model definitions
- Uses direct HTTP calls via Req library

**Migration Plan**:
- Migrate to ReqLLM-based implementation:
  - Remove custom HTTP fetching logic
  - Use ReqLLM model registry for model discovery
  - Simplify to metadata and Model struct building only
  - Keep `build/1` for backward compatibility

**Status**: Not started

#### 2.3.1.4: OpenRouter and Cloudflare Migration

**Current Implementation**:
- Both providers have full adapter implementations with API calls
- OpenRouter: Fetches model lists and endpoint information
- Cloudflare: Requires account_id for API access
- Custom caching and model processing logic

**Migration Plan**:
- Simplify both providers:
  - Replace API fetching with ReqLLM registry queries
  - Remove custom HTTP client code
  - Keep `build/1` functions for Model struct creation
  - Leverage ReqLLM's provider support

**Status**: Not started

---

## 3. Technical Details

### 3.1 Public API Modules That Must Be Preserved

These modules are documented in user guides and used in production code:

1. **Jido.AI.Actions.OpenaiEx**
   - Module name: MUST NOT CHANGE
   - Function: `run/2` - MUST preserve signature
   - Schema fields: MUST remain compatible
   - Return format: `{:ok, result} | {:error, reason}` - MUST NOT CHANGE

2. **Jido.AI.Actions.OpenaiEx.Embeddings**
   - Module name: MUST NOT CHANGE
   - Function: `run/2` - MUST preserve signature
   - Already uses ReqLLM internally (Phase 1)
   - Return format: `{:ok, %{embeddings: list}}` - MUST NOT CHANGE

3. **Jido.AI.Actions.OpenaiEx.ImageGeneration**
   - Module name: MUST NOT CHANGE
   - Function: `run/2` - MUST preserve signature
   - Uses OpenaiEx library directly - NEEDS MIGRATION
   - Return format: `{:ok, %{images: list}}` - MUST NOT CHANGE

4. **Jido.AI.Actions.OpenaiEx.ToolHelper**
   - Module name: MUST NOT CHANGE
   - Functions: `to_openai_tools/1`, `process_response/2` - MUST preserve
   - Already uses ReqLlmBridge internally
   - Return formats: MUST NOT CHANGE

### 3.2 Internal Implementation Files to Modify

These are internal implementation details that can be changed:

1. **Jido.AI.Provider.OpenAI** (`lib/jido_ai/providers/openai.ex`)
   - **Keep**: Module name (used for provider identification)
   - **Keep**: `definition/0`, `build/1`, `base_url/0`
   - **Remove**: `list_models/1`, `model/2`, `request_headers/1`
   - **Replace with**: ReqLLM registry queries

2. **Jido.AI.Provider.Anthropic** (`lib/jido_ai/providers/anthropic.ex`)
   - **Keep**: Module name, `definition/0`, `build/1`
   - **Remove**: API fetching logic, custom HTTP handling
   - **Replace with**: ReqLLM registry integration

3. **Jido.AI.Provider.Google** (`lib/jido_ai/providers/google.ex`)
   - **Keep**: Module name, `definition/0`, `build/1`
   - **Remove**: Hardcoded model map, API fetching
   - **Replace with**: ReqLLM registry queries

4. **Jido.AI.Provider.OpenRouter** (`lib/jido_ai/providers/openrouter.ex`)
   - **Keep**: Module name, `definition/0`, `build/1`
   - **Remove**: Model listing and endpoint fetching
   - **Replace with**: ReqLLM provider support

5. **Jido.AI.Provider.Cloudflare** (`lib/jido_ai/providers/cloudflare.ex`)
   - **Keep**: Module name, `definition/0`, `build/1`
   - **Remove**: Account-specific API calls
   - **Replace with**: ReqLLM cloudflare provider

### 3.3 Migration Pattern for Each Provider

#### Pattern: Simplify Provider Adapters

**Before** (Current Implementation):
```elixir
defmodule Jido.AI.Provider.ProviderName do
  # Complex implementation with:
  # - HTTP client code
  # - Request header construction
  # - Model fetching and caching
  # - Response parsing
  # - Error handling

  def list_models(opts) do
    # Custom HTTP call to provider API
    # Custom parsing of response
    # Custom caching logic
  end

  def model(model_id, opts) do
    # Fetch from API or cache
    # Parse provider-specific format
    # Build Model struct
  end

  def request_headers(opts) do
    # Provider-specific header construction
  end
end
```

**After** (Simplified Implementation):
```elixir
defmodule Jido.AI.Provider.ProviderName do
  # Simplified to metadata only

  @impl true
  def definition do
    %Provider{
      id: :provider_name,
      name: "Provider Name",
      # ... provider metadata
    }
  end

  @impl true
  def build(opts) do
    # Build Model struct from opts
    # Set reqllm_id for ReqLLM integration
    {:ok, %Model{
      # ... model fields
      reqllm_id: Model.compute_reqllm_id(:provider_name, model)
    }}
  end

  # Model listing comes from ReqLLM registry
  # No custom HTTP client code
  # No provider-specific API calls
end
```

#### Pattern: Complete Action Module Migration

**For OpenaiEx modules that still use OpenaiEx library**:

**Before**:
```elixir
defmodule Jido.AI.Actions.OpenaiEx.ImageGeneration do
  def run(params, context) do
    # Build OpenaiEx client
    client = OpenaiEx.new(api_key)
              |> maybe_add_base_url(model)
              |> maybe_add_headers(model)

    # Make OpenaiEx call
    case Images.generate(client, req) do
      {:ok, response} -> # ...
    end
  end
end
```

**After**:
```elixir
defmodule Jido.AI.Actions.OpenaiEx.ImageGeneration do
  def run(params, context) do
    # Use ReqLLM directly
    case ReqLLM.generate_image(model.reqllm_id, prompt, opts) do
      {:ok, response} ->
        # Convert to expected format
        {:ok, convert_response(response)}
    end
  end
end
```

---

## 4. Implementation Plan

### Phase 1: Preparation and Analysis (1-2 hours)

**Goals**:
- Identify all public API contracts
- Document current behavior with tests
- Create compatibility test suite

**Tasks**:
1. **Document Public APIs**:
   - List all public functions with signatures
   - Document expected input/output formats
   - Capture error message formats

2. **Create Compatibility Tests**:
   - Test current OpenaiEx behavior
   - Test current Embeddings behavior
   - Test current ImageGeneration behavior
   - Test current ToolHelper behavior
   - Test provider adapter interfaces

3. **Verify ReqLLM Support**:
   - Confirm ReqLLM supports all needed providers
   - Verify image generation is available
   - Check model registry completeness

**Success Criteria**:
- Complete test coverage of public APIs
- All tests passing with current implementation
- Documentation of behavior to preserve

### Phase 2: Provider Adapter Migration (2-3 hours)

**Goals**:
- Simplify provider adapters to metadata-only
- Remove HTTP client code from providers
- Integrate with ReqLLM model registry

**Tasks**:

#### 2.1: Anthropic Provider Simplification
- Remove `list_models/1` implementation
- Remove `model/2` implementation
- Remove `request_headers/1` implementation
- Remove HTTP client and caching code
- Keep `definition/0` and `build/1` only
- Update tests to not expect API calls

#### 2.2: Google Provider Simplification
- Remove hardcoded `@models` map
- Remove API fetching logic
- Remove custom model processing
- Keep `definition/0` and `build/1` only
- Rely on ReqLLM registry

#### 2.3: OpenRouter Provider Simplification
- Remove model listing API calls
- Remove endpoint fetching logic
- Simplify to metadata only
- Keep `definition/0` and `build/1`

#### 2.4: Cloudflare Provider Simplification
- Remove account-specific API logic
- Remove model fetching code
- Simplify to metadata only
- Keep `definition/0` and `build/1`

**Success Criteria**:
- Each provider module <100 lines
- No HTTP client code in providers
- All provider tests updated and passing
- Model creation still works via `build/1`

### Phase 3: Action Module Migration (2-3 hours)

**Goals**:
- Complete OpenaiEx migration to ReqLLM
- Migrate ImageGeneration to ReqLLM
- Remove OpenaiEx library dependencies
- Preserve all public APIs

**Tasks**:

#### 3.1: Complete OpenaiEx Chat Migration
- Remove remaining OpenaiEx dependencies
- Simplify message format conversion
- Remove custom ChatMessage handling
- Verify streaming still works
- Verify tool calling still works

#### 3.2: Migrate ImageGeneration Module
- Replace OpenaiEx.Images with ReqLLM
- Handle image generation via ReqLLM
- Preserve return format
- Update provider-specific logic (OpenRouter, Google)
- Test with multiple providers

#### 3.3: Verify Other Action Modules
- Confirm Embeddings still works (already migrated)
- Confirm ToolHelper still works
- Test Instructor and Langchain actions
- Verify backward compatibility

**Success Criteria**:
- All action modules use ReqLLM exclusively
- No OpenaiEx imports remain
- All compatibility tests passing
- Public API unchanged

### Phase 4: Testing and Validation (1-2 hours)

**Goals**:
- Verify zero breaking changes
- Test across all providers
- Validate error handling
- Performance testing

**Tasks**:

#### 4.1: Compatibility Testing
- Run full test suite
- Test each action module
- Test each provider
- Verify error messages unchanged

#### 4.2: Integration Testing
- Test OpenAI provider end-to-end
- Test Anthropic provider end-to-end
- Test Google provider end-to-end
- Test OpenRouter provider end-to-end
- Test Cloudflare provider end-to-end

#### 4.3: Edge Case Testing
- Test with invalid API keys
- Test with network failures
- Test with rate limiting
- Test with malformed responses
- Verify fallback behavior

**Success Criteria**:
- All tests passing
- No regressions identified
- Error handling preserved
- Performance equivalent or better

### Phase 5: Cleanup and Documentation (1 hour)

**Goals**:
- Remove dead code
- Update documentation
- Document migration
- Update examples

**Tasks**:

#### 5.1: Code Cleanup
- Remove unused helper functions
- Remove commented-out code
- Remove unused imports
- Update module documentation

#### 5.2: Documentation Updates
- Update module @moduledoc
- Update function @doc
- Add migration notes
- Update examples

#### 5.3: Migration Guide
- Document what changed internally
- Note that public API unchanged
- Explain benefits of migration
- Provide troubleshooting tips

**Success Criteria**:
- No dead code remains
- Documentation accurate
- Migration guide complete
- Examples updated

---

## 5. Testing Strategy

### 5.1 Backward Compatibility Testing

**Goal**: Ensure zero breaking changes to public APIs

**Approach**:
1. Create comprehensive test suite for current behavior
2. Run same tests after migration
3. Verify identical behavior

**Test Cases**:
- Basic chat completion with OpenaiEx
- Chat with tool calling
- Streaming responses
- Embedding generation
- Image generation
- Error handling
- Provider switching
- Model struct creation

### 5.2 Provider-Specific Testing

**Goal**: Verify each provider works correctly after migration

**Test Matrix**:

| Provider   | Chat | Embeddings | Images | Tools | Streaming |
|------------|------|------------|--------|-------|-----------|
| OpenAI     | ✓    | ✓          | ✓      | ✓     | ✓         |
| Anthropic  | ✓    | -          | -      | ✓     | ✓         |
| Google     | ✓    | ✓          | ✓      | ✓     | ✓         |
| OpenRouter | ✓    | -          | -      | ✓     | ✓         |
| Cloudflare | ✓    | -          | -      | -     | ✓         |

### 5.3 Error Handling Testing

**Goal**: Verify error handling remains consistent

**Test Cases**:
- Invalid API key errors
- Network timeout errors
- Rate limiting errors
- Invalid model errors
- Malformed request errors
- Provider-specific errors

### 5.4 Performance Testing

**Goal**: Verify performance is maintained or improved

**Metrics**:
- Request latency
- Memory usage
- Startup time
- Concurrent request handling

**Benchmarks**:
- Before migration baseline
- After migration comparison
- Identify any regressions
- Document improvements

---

## 6. Risk Assessment and Mitigation

### High-Risk Areas

#### 6.1 Public API Compatibility
**Risk**: Breaking changes to public functions
**Impact**: HIGH - Would break user code
**Mitigation**:
- Comprehensive compatibility tests before changes
- Preserve all function signatures
- Maintain return value formats
- Test with real-world usage patterns

#### 6.2 Image Generation Migration
**Risk**: ReqLLM may not support all image gen features
**Impact**: MEDIUM - Feature loss
**Mitigation**:
- Verify ReqLLM image generation support early
- Test with all providers (OpenAI, Google)
- Document any limitations
- Consider keeping OpenaiEx for images only if needed

#### 6.3 Provider-Specific Behavior
**Risk**: Subtle differences in provider responses
**Impact**: MEDIUM - Unexpected behavior
**Mitigation**:
- Test each provider thoroughly
- Document provider-specific quirks
- Use ReqLlmBridge for response normalization
- Add provider-specific handling where needed

### Medium-Risk Areas

#### 6.4 Error Message Changes
**Risk**: Error messages might change format
**Impact**: MEDIUM - Breaks error handling
**Mitigation**:
- Document current error formats
- Map ReqLLM errors to existing formats
- Test error handling extensively
- Use ReqLlmBridge.map_error

#### 6.5 Performance Regression
**Risk**: ReqLLM might be slower than direct calls
**Impact**: LOW-MEDIUM - User experience
**Mitigation**:
- Benchmark before and after
- Optimize ReqLLM usage
- Profile hot paths
- Document performance characteristics

### Low-Risk Areas

#### 6.6 Provider Adapter Simplification
**Risk**: Breaking adapter interfaces
**Impact**: LOW - Internal only
**Mitigation**:
- Adapters are internal implementation
- Update all usages together
- Tests will catch issues

---

## 7. Rollback Plan

### If Migration Fails

**Step 1: Stop Migration**
- Halt work immediately
- Document failure point
- Preserve failing state for analysis

**Step 2: Git Revert**
- Revert to pre-migration commit
- Verify tests passing
- Deploy reverted version

**Step 3: Analysis**
- Analyze failure cause
- Document lessons learned
- Plan remediation

### Partial Migration Strategy

If full migration proves too risky:

**Option A: Gradual Migration**
- Migrate providers one at a time
- Start with least critical (Cloudflare)
- Validate before next provider

**Option B: Feature Flag**
- Add feature flag for ReqLLM vs legacy
- Allow switching between implementations
- Gradual rollout to users

**Option C: Keep OpenaiEx for Images**
- Migrate everything except image generation
- Keep OpenaiEx dependency only for images
- Complete image migration in separate task

---

## 8. Success Criteria

### Must Have (Blocking)

1. **Zero Breaking Changes**
   - All public APIs work identically
   - All tests passing
   - No error message changes

2. **All Providers Migrated**
   - OpenAI internal calls use ReqLLM
   - Anthropic internal calls use ReqLLM
   - Google internal calls use ReqLLM
   - OpenRouter internal calls use ReqLLM
   - Cloudflare internal calls use ReqLLM

3. **Code Cleanup Complete**
   - No unused provider HTTP code
   - No dead code paths
   - All imports updated

### Should Have (Important)

4. **Performance Maintained**
   - No significant latency increase
   - Memory usage similar or better
   - Startup time maintained

5. **Documentation Updated**
   - Migration guide complete
   - Module docs accurate
   - Examples updated

6. **Test Coverage**
   - All providers tested
   - Error cases covered
   - Integration tests passing

### Nice to Have (Optional)

7. **Performance Improvement**
   - Reduced memory footprint
   - Faster response times
   - Better concurrency

8. **Code Reduction**
   - Provider modules simplified
   - Less total lines of code
   - Improved maintainability

---

## 9. Timeline Estimate

### Total Estimated Time: 7-11 hours

**Phase 1 - Preparation**: 1-2 hours
- Document public APIs
- Create compatibility tests
- Verify ReqLLM support

**Phase 2 - Provider Migration**: 2-3 hours
- Anthropic simplification
- Google simplification
- OpenRouter simplification
- Cloudflare simplification

**Phase 3 - Action Migration**: 2-3 hours
- Complete OpenaiEx migration
- Migrate ImageGeneration
- Verify other actions

**Phase 4 - Testing**: 1-2 hours
- Compatibility testing
- Integration testing
- Edge case testing

**Phase 5 - Cleanup**: 1 hour
- Code cleanup
- Documentation
- Migration guide

### Parallel Work Opportunities

- Provider migrations can happen in parallel
- Testing can overlap with implementation
- Documentation can be written alongside code

---

## 10. Next Steps

### Immediate Actions

1. **Get Plan Approval**
   - Review plan with Pascal
   - Address any concerns
   - Adjust timeline if needed

2. **Set Up Branch**
   - Create feature branch
   - Set up test environment
   - Prepare for migration

3. **Begin Phase 1**
   - Document current behavior
   - Create compatibility tests
   - Verify ReqLLM readiness

### Follow-Up Tasks

After this migration completes:

1. **Task 2.3.2**: HTTP Client Code Cleanup
   - Remove unused HTTP utilities
   - Clean up helper modules

2. **Task 2.3.3**: Dependency Reduction
   - Remove OpenaiEx from mix.exs
   - Remove other unused dependencies
   - Update lockfile

3. **Section 2.3 Testing**: Comprehensive validation
   - Full test suite
   - Performance benchmarks
   - Production validation

---

## 11. Questions for Pascal

Before beginning implementation, I need clarification on:

1. **Image Generation**: Should I migrate image generation in this task, or defer to a later task if ReqLLM support is unclear?

2. **OpenaiEx Dependency**: Should I remove the OpenaiEx dependency in this task (2.3.1) or wait for task 2.3.3?

3. **Testing Approach**: Do you want me to write tests before migration (TDD) or migrate then fix tests?

4. **Provider Adapters**: Can I remove the `list_models/1` and `model/2` functions entirely, or do they need to stay for backward compatibility?

5. **Migration Speed**: Should I do all providers at once, or one at a time with reviews in between?

6. **Rollback Strategy**: Do you want feature flags for gradual rollout, or full cutover?

---

## Conclusion

This migration is a critical step in modernizing Jido AI's provider infrastructure. By moving to ReqLLM internally while preserving public APIs, we:

- Reduce code complexity by 40-60%
- Gain access to 57+ providers instead of 5
- Improve maintainability significantly
- Reduce dependency footprint
- Enable future advanced features

The migration is low-risk if done carefully with comprehensive testing. The key is preserving the public API contract while simplifying internal implementation.

**Recommendation**: Proceed with migration using gradual approach - one provider at a time, with thorough testing between each.
