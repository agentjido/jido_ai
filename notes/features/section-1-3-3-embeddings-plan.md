# Section 1.3.3 Embeddings Integration - Implementation Plan

## Problem Statement

### Current State Analysis

The Jido AI framework currently implements embeddings functionality through the `Jido.AI.Actions.OpenaiEx.Embeddings` module, which directly uses OpenaiEx's `OpenaiEx.Embeddings.create/2` function. This provider-specific implementation limits the framework to only OpenAI-compatible providers and requires separate handling for each provider (OpenAI, OpenRouter, Google) through custom base URLs and headers.

### Impact of Current Implementation

1. **Provider Limitations**: Restricted to 3 providers (OpenAI, OpenRouter, Google) vs. ReqLLM's 47+ providers
2. **Code Duplication**: Provider-specific URL and header management across multiple action modules
3. **Maintenance Burden**: Each new provider requires custom integration logic
4. **Inconsistent API**: Different error handling and response patterns across providers
5. **Security Concerns**: Potential atom creation vulnerabilities (similar to those fixed in 1.3.1)

### Business Impact

- Limited ecosystem access for embedding-based applications
- Increased development effort for multi-provider support
- Inconsistent developer experience across different AI capabilities
- Technical debt accumulation from provider-specific implementations

## Solution Overview

### Design Decisions

Following the successful patterns established in sections 1.3.1 (Chat/Completion Actions) and 1.3.2 (Streaming Support), we will migrate the embeddings functionality to use ReqLLM's unified `ReqLLM.embed_many/3` interface while maintaining complete backward compatibility.

**Key Design Principles:**

1. **Preserve API Surface**: Maintain exact function signatures and response formats
2. **Follow Established Patterns**: Use the same migration approach proven successful in 1.3.1/1.3.2
3. **Unified Error Handling**: Extend existing ReqLLM error mapping for embedding-specific cases
4. **Memory Efficiency**: Implement Elixir-idiomatic patterns for vector processing
5. **Zero Breaking Changes**: Ensure all existing consumers continue working unchanged

### Architecture Approach

- **In-Place Migration**: Modify existing `lib/jido_ai/actions/openai_ex/embeddings.ex` directly
- **Bridge Integration**: Leverage existing `Jido.AI.ReqLLM` module for error mapping and response conversion
- **Response Format Preservation**: Maintain exact `{:ok, %{embeddings: [[0.1, 0.2, 0.3]]}}` structure
- **Provider Unification**: Replace provider-specific logic with ReqLLM's unified interface

## Agent Consultations Performed

### Research Agent - ReqLLM Embedding Capabilities
**Key Findings:**
- `ReqLLM.embed_many/3` signature: `embed_many(model_spec, texts, opts \\ [])`
- Supports batch processing with list of texts: `["Hello", "World"]`
- Returns format: `{:ok, [[0.1, -0.2, ...], [0.3, 0.4, ...]]}`
- Options include `:dimensions` and `:provider_options`
- Model specification format: `"openai:text-embedding-3-small"`

### Elixir Expert - Vector Processing Patterns
**Key Recommendations:**
- Use `with` chains for clean error propagation in embedding operations
- Implement polymorphic input handling with guards for string vs list inputs
- Apply Stream processing for memory-efficient large batch operations
- Use pattern matching for response format normalization
- Implement ETS caching for frequently requested embeddings
- Add telemetry for monitoring embedding operations

### Senior Engineer Reviewer - Architectural Decisions
**Key Decisions:**
- ✅ **Migration Strategy**: Follow established pattern from 1.3.1/1.3.2 - modify existing file in place
- ✅ **Integration Points**: Reuse `Jido.AI.ReqLLM` bridge module, no new modules needed
- ✅ **Error Handling**: Extend existing error mapping with embedding-specific cases
- ✅ **Batch Processing**: Handle at ReqLLM level with action-level safeguards
- ✅ **Testing Strategy**: Modify existing test file, maintain mock-based approach
- ✅ **Backward Compatibility**: Full API preservation with internal replacement

## Technical Details

### File Locations and Dependencies

**Primary Implementation File:**
- `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/actions/openai_ex/embeddings.ex`
  - Current: 204 lines using OpenaiEx.Embeddings.create/2
  - Target: Replace with ReqLLM.embed_many/3 while preserving all functions

**Supporting Bridge Module:**
- `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/lib/jido_ai/req_llm.ex`
  - Extend existing error mapping for embedding-specific errors
  - Add embedding response format conversion helpers

**Test File:**
- `/home/ducky/code/agentjido/jido_ai_integrate_req_llm/test/jido_ai/actions/openai_ex/embeddings_test.exs`
  - Current: 213 lines with 16 comprehensive tests
  - Target: Update mocks from OpenaiEx to ReqLLM, maintain test coverage

### Dependencies Analysis

**Current Dependencies:**
```elixir
alias Jido.AI.Model
alias OpenaiEx.Embeddings  # To be replaced
```

**Target Dependencies:**
```elixir
alias Jido.AI.Model
alias Jido.AI.ReqLLM       # For response conversion and error mapping
# ReqLLM.embed_many/3 will be called directly
```

### Embedding-Specific Considerations

#### Vector Dimensions and Metadata Preservation
- Current: Optional `dimensions` parameter passed to OpenaiEx
- Target: Forward to ReqLLM via `opts` parameter
- Preserve: All metadata about vector dimensions in response structure
- Enhancement: Add optional `_metadata` field for debugging without breaking existing consumers

#### Batch Processing Implementation
```elixir
# Current approach (OpenaiEx)
def build_request(model, input, params) do
  req = Embeddings.new(model: model.model, input: input)
  # ... parameter mapping
end

# Target approach (ReqLLM)
def build_reqllm_request(model, input, params) do
  opts = build_reqllm_options(params)
  # Direct call to ReqLLM.embed_many/3
end
```

#### Provider Support Matrix
| Provider | Current Status | ReqLLM Status | Migration Notes |
|----------|---------------|---------------|-----------------|
| OpenAI | ✅ Custom base URL | ✅ Native support | Direct mapping via reqllm_id |
| OpenRouter | ✅ Custom base URL | ✅ Native support | Simplified via ReqLLM routing |
| Google | ✅ Custom headers | ✅ Native support | Remove custom header logic |
| Others | ❌ Not supported | ✅ 44+ additional | Immediate access post-migration |

#### Performance Considerations for Large Text Inputs

**Memory Management:**
- Input validation: Limit batch size to 2048 texts maximum
- Text preprocessing: Trim inputs to token limits before embedding
- Vector storage: Use efficient list structures for embedding results

**Batch Processing:**
- ReqLLM handles provider-specific batching internally
- Add client-side batch size validation for memory protection
- Stream processing for very large embedding operations

#### Error Handling for Embedding-Specific Failures

**New Error Types to Handle:**
```elixir
# In Jido.AI.ReqLLM.map_error/1
def map_error({:error, %{reason: "dimension_mismatch"} = error}) do
  {:error, "Requested dimensions not supported by model: #{error.details}"}
end

def map_error({:error, %{reason: "model_unavailable"} = error}) do
  {:error, "Embedding model unavailable: #{error.details}"}
end

def map_error({:error, %{reason: "context_length_exceeded"} = error}) do
  {:error, "Input text too long for embedding model: #{error.details}"}
end
```

## Success Criteria

### Measurable Outcomes for Embeddings Functionality

#### Functional Requirements
1. **API Compatibility**: ✅ `run/2` function signature preserved exactly
2. **Response Structure**: ✅ `{:ok, %{embeddings: [[...]]}}` format maintained
3. **Parameter Support**: ✅ All existing parameters (dimensions, encoding_format) functional
4. **Provider Coverage**: ✅ OpenAI, OpenRouter, Google providers working + 44+ new providers accessible
5. **Input Handling**: ✅ Both single string and list of strings inputs supported

#### Performance Requirements
1. **Memory Efficiency**: ✅ No memory leaks or excessive memory usage for large batches
2. **Response Time**: ✅ No significant latency degradation vs. current implementation
3. **Batch Processing**: ✅ Efficient handling of 1-2048 embedding requests
4. **Error Recovery**: ✅ Graceful handling of provider timeouts and failures

#### Quality Requirements
1. **Test Coverage**: ✅ All 16 existing tests pass with updated mocks
2. **Error Handling**: ✅ Embedding-specific errors properly mapped and reported
3. **Documentation**: ✅ All function documentation remains accurate
4. **Logging**: ✅ Preserve existing opt-in logging behavior

#### Security Requirements
1. **Input Validation**: ✅ Proper validation of text inputs and parameters
2. **Provider Authentication**: ✅ Secure API key handling via ReqLLM.Keys system
3. **Error Information**: ✅ No sensitive information leaked in error messages

## Implementation Plan

### Phase 1: Core Migration (2-3 hours)

#### Step 1.1: Update Core Function Implementation
**Target:** Replace OpenaiEx.Embeddings.create/2 with ReqLLM.embed_many/3

**Tasks:**
- [ ] Modify `make_request/2` function in embeddings.ex
- [ ] Replace OpenaiEx client creation with direct ReqLLM call
- [ ] Update function to use model.reqllm_id instead of model.model
- [ ] Remove provider-specific base URL and header logic

**Code Changes:**
```elixir
# Before
def make_request(model, req) do
  client = OpenaiEx.new(model.api_key)
           |> maybe_add_base_url(model)
           |> maybe_add_headers(model)

  case Embeddings.create(client, req) do
    {:ok, %{data: data}} ->
      {:ok, %{embeddings: Enum.map(data, & &1.embedding)}}
    error -> error
  end
end

# After
def make_request(model, input, opts) do
  case ReqLLM.embed_many(model.reqllm_id, input, opts) do
    {:ok, vectors} ->
      {:ok, %{embeddings: vectors}}
    error ->
      Jido.AI.ReqLLM.map_error(error)
  end
end
```

#### Step 1.2: Update Request Building Logic
**Target:** Adapt parameter mapping for ReqLLM format

**Tasks:**
- [ ] Modify `build_request/3` to build ReqLLM options instead of OpenaiEx request
- [ ] Map `dimensions` and `encoding_format` to ReqLLM opts format
- [ ] Remove OpenaiEx-specific request struct creation

#### Step 1.3: Input Format Normalization
**Target:** Handle both string and list inputs for ReqLLM

**Tasks:**
- [ ] Ensure input format compatibility between OpenaiEx and ReqLLM
- [ ] Add input normalization if needed for string vs list handling
- [ ] Preserve existing validation logic in `validate_input/1`

#### Step 1.4: Provider Validation Update
**Target:** Update provider validation to use ReqLLM's provider list

**Tasks:**
- [ ] Replace `@valid_providers` list with ReqLLM provider validation
- [ ] Use secure provider checking (similar to 1.3.1 security fixes)
- [ ] Remove provider-specific URL and header functions

### Phase 2: Error Handling and Edge Cases (1-2 hours)

#### Step 2.1: Extend ReqLLM Error Mapping
**Target:** Add embedding-specific error handling

**Tasks:**
- [ ] Add embedding error cases to `Jido.AI.ReqLLM.map_error/1`
- [ ] Handle dimension mismatch errors
- [ ] Handle model unavailability for embedding-specific models
- [ ] Map context length exceeded errors

#### Step 2.2: Response Format Preservation
**Target:** Ensure exact response compatibility

**Tasks:**
- [ ] Add response format conversion if ReqLLM format differs
- [ ] Preserve `embeddings` key in response map
- [ ] Handle any metadata preservation requirements
- [ ] Test response structure with multiple providers

#### Step 2.3: Parameter Validation Enhancement
**Target:** Robust parameter validation for embeddings

**Tasks:**
- [ ] Add batch size validation (max 2048 texts)
- [ ] Validate dimension parameter ranges
- [ ] Add encoding_format parameter validation
- [ ] Implement memory usage estimation and warnings

### Phase 3: Testing and Validation (2-3 hours)

#### Step 3.1: Update Unit Tests
**Target:** Migrate all tests to use ReqLLM mocks

**Tasks:**
- [ ] Update test setup to mock `ReqLLM.embed_many/3` instead of `OpenaiEx.Embeddings.create/2`
- [ ] Modify expected request structures for ReqLLM format
- [ ] Update provider-specific tests (OpenRouter, Google)
- [ ] Ensure all 16 existing tests pass

#### Step 3.2: Add Embedding-Specific Tests
**Target:** Test embedding-specific functionality

**Tasks:**
- [ ] Add tests for dimension parameter validation
- [ ] Add tests for batch size limits
- [ ] Add tests for new error cases (dimension mismatch, model unavailable)
- [ ] Add tests for response format preservation

#### Step 3.3: Integration Testing
**Target:** Validate real-world functionality

**Tasks:**
- [ ] Test with real API keys on development environment
- [ ] Verify response formats match existing implementation
- [ ] Test batch processing with various sizes
- [ ] Validate error handling with invalid parameters

#### Step 3.4: Performance Validation
**Target:** Ensure no performance regressions

**Tasks:**
- [ ] Benchmark embedding generation times vs. current implementation
- [ ] Test memory usage with large batches
- [ ] Validate concurrent request handling
- [ ] Test timeout and retry behavior

### Phase 4: Documentation and Cleanup (1 hour)

#### Step 4.1: Update Documentation
**Target:** Ensure documentation accuracy

**Tasks:**
- [ ] Review and update module documentation
- [ ] Update function documentation for any signature changes
- [ ] Update examples to reflect new provider capabilities
- [ ] Document any new error cases or behaviors

#### Step 4.2: Code Cleanup
**Target:** Remove unused code and optimize

**Tasks:**
- [ ] Remove unused OpenaiEx-specific functions
- [ ] Clean up imports and aliases
- [ ] Add any missing type specifications
- [ ] Format code according to project standards

#### Step 4.3: Testing Final Validation
**Target:** Comprehensive final testing

**Tasks:**
- [ ] Run complete test suite to ensure no regressions
- [ ] Test compilation with no warnings
- [ ] Validate that all existing embedding consumers work unchanged
- [ ] Confirm new provider access functionality

## Notes/Considerations

### Embedding-Specific Edge Cases

#### Vector Dimension Handling
- **Issue**: Different providers may return different dimension vectors
- **Solution**: Validate dimensions in response conversion, add metadata if dimensions differ from requested
- **Fallback**: Clear error message if dimension mismatch occurs

#### Batch Processing Limitations
- **Issue**: Some providers have different batch size limits
- **Solution**: Let ReqLLM handle provider-specific limits, add client-side batch size validation
- **Memory**: Estimate vector memory usage and warn if exceeding reasonable limits (100MB+)

#### Model Availability Variations
- **Issue**: Not all providers support all embedding models
- **Solution**: Rely on ReqLLM's model validation, provide clear error messages for unavailable models
- **Fallback**: Document provider-specific model availability in error messages

#### Performance Considerations for Large Text Inputs
- **Text Length**: Some embedding models have token limits (8192 tokens typical)
- **Solution**: Add text preprocessing to truncate inputs to model limits
- **Memory**: For very large batches, consider streaming or chunking strategies

#### Provider Differences in Embedding Capabilities
- **Encoding Format**: Not all providers support base64 encoding
- **Solution**: Handle encoding format parameter gracefully, fall back to float if base64 not supported
- **Dimensions**: Custom dimensions not supported by all models
- **Solution**: Forward parameter and let ReqLLM/provider handle, map errors appropriately

#### Metadata Preservation Requirements
- **Current Metadata**: Model name, provider information embedded in response structure
- **Target**: Preserve all existing metadata while adding optional ReqLLM metadata
- **Backward Compatibility**: Add new metadata in `_metadata` field to avoid breaking changes

#### Error Recovery Strategies
- **Provider Failures**: Some providers may be temporarily unavailable
- **Solution**: Clear error messages indicating which provider failed
- **Retry Logic**: Implement exponential backoff for rate limiting errors
- **Fallback**: Consider provider fallback strategies for critical applications

#### Security Considerations
- **API Key Handling**: Ensure secure key management through ReqLLM.Keys
- **Input Validation**: Validate all text inputs to prevent injection attacks
- **Error Information**: Avoid leaking sensitive information in error messages
- **Provider Authentication**: Trust ReqLLM's authentication handling for all providers

### Technical Debt Considerations

#### Code Simplification Opportunities
- **Provider Logic**: Remove significant amount of provider-specific code
- **Error Handling**: Consolidate error handling through ReqLLM bridge
- **Configuration**: Simplify configuration by removing provider-specific options

#### Future Enhancement Opportunities
- **Caching**: Add ETS-based caching for frequently requested embeddings
- **Streaming**: Implement streaming embeddings for very large batches
- **Monitoring**: Add telemetry for embedding operations
- **Performance**: Optimize vector operations using more efficient data structures

#### Maintenance Benefits
- **Unified Interface**: Single ReqLLM interface instead of multiple provider-specific implementations
- **Extended Providers**: Immediate access to 44+ additional providers without custom integration
- **Consistent Behavior**: Unified error handling and response formats across all providers
- **Future-Proof**: Automatic access to new providers and models added to ReqLLM

## Conclusion

This implementation plan provides a comprehensive roadmap for migrating Jido AI's embeddings functionality from OpenaiEx to ReqLLM while maintaining complete backward compatibility. Following the proven patterns from sections 1.3.1 and 1.3.2, this migration will:

1. **Preserve Compatibility**: Zero breaking changes for existing consumers
2. **Extend Capabilities**: Access to 47+ ReqLLM providers vs. current 3
3. **Improve Maintainability**: Unified interface replacing provider-specific implementations
4. **Enhance Security**: Leverage ReqLLM's secure key management and provider validation
5. **Optimize Performance**: Benefit from ReqLLM's efficient batching and error handling

The estimated implementation time is 6-8 hours total, with comprehensive testing ensuring a smooth migration that demonstrates the value and feasibility of ReqLLM integration for the remaining sections of Stage 1.

**Status**: Ready for implementation - comprehensive planning complete with expert consultations and detailed technical specifications.