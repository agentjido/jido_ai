# Phase 1: Core ReqLLM Integration Infrastructure

## Overview
This phase establishes the foundational infrastructure to integrate ReqLLM into Jido AI while preserving all existing public APIs and behavior. We follow the research document's migration strategy to replace provider-specific implementations with ReqLLM's unified interface. The goal is to create a seamless transition where existing Jido AI users experience no breaking changes while gaining access to ReqLLM's broader provider and model ecosystem.

The integration maintains Jido AI's philosophy of minimal, opt-in logging and preserves all existing error handling patterns. By the end of this phase, all current Jido AI functionality will be powered by ReqLLM internally, but externally indistinguishable from the current implementation.

---

## 1.1 Prerequisites and Setup
- [x] **Section 1.1 Complete**

This section establishes the basic dependencies and foundational modules needed for ReqLLM integration. We create the bridge layer that will handle translation between Jido AI's current interfaces and ReqLLM's API, ensuring seamless interoperability.

### 1.1.1 Dependency Management
- [x] **Task 1.1.1 Complete**

The first step involves adding ReqLLM as a dependency while ensuring compatibility with existing dependencies. This includes updating the mix.exs file and verifying that ReqLLM doesn't conflict with current dependencies like OpenaiEx, Instructor, and LangChain.

- [x] 1.1.1.1 Add `:req_llm` dependency to mix.exs with appropriate version constraints
- [x] 1.1.1.2 Update dependency versions for compatibility, ensuring no conflicts with existing libs
- [x] 1.1.1.3 Run `mix deps.get` to verify dependency resolution and compilation
- [x] 1.1.1.4 Create initial ReqLLM configuration structure in application config

### 1.1.2 Core Module Architecture
- [x] **Task 1.1.2 Complete**

This subtask creates the primary bridge module that will serve as the translation layer between Jido AI and ReqLLM. The bridge handles message format conversion, error mapping, and ensures that ReqLLM's responses are shaped to match Jido AI's existing contracts.

- [x] 1.1.2.1 Create `Jido.AI.ReqLLM` bridge module with core conversion functions
- [x] 1.1.2.2 Define message conversion helpers for translating between formats
- [x] 1.1.2.3 Implement error mapping utilities to preserve existing error structures
- [x] 1.1.2.4 Add logging integration preservation to maintain opt-in logging behavior

### Unit Tests - Section 1.1
- [x] **Unit Tests 1.1 Complete**
- [x] Test ReqLLM dependency loading and module availability
- [x] Test bridge module compilation and basic function exports
- [x] Test error mapping functions for common error scenarios
- [x] Test logging preservation and configuration handling

---

## 1.2 Model Integration Layer
- [x] **Section 1.2 Complete**

This section focuses on extending the existing `%Jido.AI.Model{}` struct to work with ReqLLM while maintaining full backward compatibility. The key addition is the `reqllm_id` field that maps Jido AI's provider/model combinations to ReqLLM's "provider:model" format.

### 1.2.1 Model Struct Enhancement
- [x] **Task 1.2.1 Complete**

The Model struct needs to be enhanced with ReqLLM-specific information while preserving all existing fields and behavior. The `reqllm_id` field will be computed automatically when models are created through `Jido.AI.Model.from/1`.

- [x] 1.2.1.1 Add `reqllm_id :: String.t()` field to `%Jido.AI.Model{}` struct definition
- [x] 1.2.1.2 Implement ReqLLM ID computation logic (e.g., "openai:gpt-4o" from {:openai, model: "gpt-4o"})
- [x] 1.2.1.3 Update `Jido.AI.Model.from/1` to automatically populate `reqllm_id` field
- [x] 1.2.1.4 Maintain backward compatibility for all existing model fields and behaviors

### 1.2.2 Provider Mapping
- [x] **Task 1.2.2 Complete**

This creates the mapping logic between Jido AI's current provider system and ReqLLM's provider addressing scheme. It handles model name normalization and provides fallbacks for edge cases.

- [x] 1.2.2.1 Create provider-to-ReqLLM mapping configuration with all supported providers
- [x] 1.2.2.2 Handle model name normalization for ReqLLM format requirements
- [x] 1.2.2.3 Implement fallback mechanisms for unsupported or deprecated models
- [x] 1.2.2.4 Add validation to ensure ReqLLM model availability before requests

### Unit Tests - Section 1.2
- [x] **Unit Tests 1.2 Complete**
- [x] Test model struct creation with automatically computed reqllm_id
- [x] Test provider mapping accuracy across all supported providers
- [x] Test model name normalization for various input formats
- [x] Test backward compatibility preservation for existing model creation patterns

---

## 1.3 Core Action Migration
- [x] **Section 1.3 Complete**

This section represents the heart of the migration, replacing the current provider-specific implementations in actions like `Jido.AI.Actions.OpenaiEx` with ReqLLM calls. The critical requirement is preserving exact response shapes and error formats that existing Jido AI consumers depend on.

### 1.3.1 Chat/Completion Actions
- [x] **Task 1.3.1 Complete**

The primary chat completion functionality needs to be migrated from OpenaiEx and provider-specific implementations to ReqLLM's unified `generate_text/3` function. This requires careful message format conversion and response shape preservation.

- [x] 1.3.1.1 Replace `OpenaiEx.Chat.Completions.create` calls with `ReqLLM.generate_text/3`
- [x] 1.3.1.2 Implement message format conversion from Jido's message format to ReqLLM's expected format
- [x] 1.3.1.3 Preserve existing response structure and contracts that downstream consumers expect
- [x] 1.3.1.4 Handle provider-specific parameter mapping and validation through ReqLLM

### 1.3.2 Streaming Support
- [x] **Task 1.3.2 Complete**

Streaming functionality is critical for real-time applications. The migration must preserve the exact streaming chunk format and timing that existing consumers rely on, while leveraging ReqLLM's streaming capabilities.

- [x] 1.3.2.1 Replace current streaming implementations with `ReqLLM.stream_text/3`
- [x] 1.3.2.2 Maintain existing stream chunk contracts and shapes for backward compatibility
- [x] 1.3.2.3 Implement stream adapter layer to transform ReqLLM chunks to Jido format
- [x] 1.3.2.4 Preserve error handling and recovery mechanisms in streaming context

### 1.3.3 Embeddings Integration
- [x] **Task 1.3.3 Complete**

Embeddings support needs to be migrated to ReqLLM while maintaining the existing result structure and metadata that applications depend on for vector operations.

- [x] 1.3.3.1 Replace current embedding actions with `ReqLLM.embed_many/3` calls
- [x] 1.3.3.2 Maintain existing embedding result structure including dimensions and metadata
- [x] 1.3.3.3 Handle dimension validation and preserve embedding metadata for compatibility
- [x] 1.3.3.4 Implement batch processing compatibility for large embedding operations

### Unit Tests - Section 1.3
- [x] **Unit Tests 1.3 Complete**
- [x] Test chat completion response format preservation across all providers
- [x] Test streaming chunk structure compatibility and timing behavior
- [x] Test embedding result structure maintenance and metadata preservation
- [x] Test error response format consistency with existing implementations

---

## 1.4 Tool/Function Calling Integration
- [x] **Section 1.4 Complete**

Tool calling is a complex feature that requires careful integration with ReqLLM's tool system while preserving Jido AI's existing Action-based tool framework. This section ensures that existing Jido Actions can be seamlessly used as ReqLLM tools.

### 1.4.1 Tool Descriptor Creation
- [x] **Task 1.4.1 Complete**

This creates the bridge between Jido's Action system and ReqLLM's tool descriptor format, ensuring that existing Jido Actions can be automatically converted to ReqLLM-compatible tools.

- [x] 1.4.1.1 Implement conversion from Jido Action modules to ReqLLM tool descriptor format
- [x] 1.4.1.2 Create callback system for tool execution that invokes Jido Actions properly
- [x] 1.4.1.3 Ensure all tool return values are JSON-serializable as required by ReqLLM
- [x] 1.4.1.4 Preserve existing tool response aggregation and result formatting

### 1.4.2 Tool Execution Pipeline
- [x] **Task 1.4.2 Complete**

The tool execution pipeline needs to integrate ReqLLM's tool calling with Jido's existing tool flow, maintaining the same execution semantics and error handling.

- [x] 1.4.2.1 Integrate ReqLLM tool calling mechanism with existing Jido tool execution flow
- [x] 1.4.2.2 Maintain `tool_response` structure compatibility for existing consumers
- [x] 1.4.2.3 Handle tool choice parameter mapping between Jido and ReqLLM formats
- [x] 1.4.2.4 Preserve tool error handling, validation, and timeout behaviors

### Unit Tests - Section 1.4
- [x] **Unit Tests 1.4 Complete**
- [x] Test tool descriptor generation from various Jido Action module types
- [x] Test tool execution callback mechanism and parameter passing
- [x] Test tool response structure preservation and formatting
- [x] Test tool error handling compatibility and error propagation

---

## 1.5 Key Management Bridge
- [x] **Section 1.5 Complete**

This section creates the bridge between Jido AI's existing key management system (Jido.AI.Keyring) and ReqLLM's key storage and precedence system. The goal is to maintain the exact same key management behavior from the user's perspective.

### 1.5.1 Keyring Integration
- [x] **Task 1.5.1 Complete**

The keyring integration ensures that existing key management workflows continue to work while leveraging ReqLLM's key storage capabilities internally.

- [x] 1.5.1.1 Map Jido.AI.Keyring helper functions to ReqLLM key store operations
- [x] 1.5.1.2 Implement key precedence delegation (ENV vars → app config → in-memory keys)
- [x] 1.5.1.3 Preserve existing key management API surface for backward compatibility
- [x] 1.5.1.4 Handle per-request key overrides and session-based key management

### 1.5.2 Authentication Flow
- [x] **Task 1.5.2 Complete**

The authentication flow needs to bridge between Jido's current authentication mechanisms and ReqLLM's authentication system while preserving existing validation behavior.

- [x] 1.5.2.1 Bridge authentication mechanisms between Jido and ReqLLM systems
- [x] 1.5.2.2 Maintain existing API key validation behavior and error messages
- [x] 1.5.2.3 Preserve session-based key management and per-user key isolation
- [x] 1.5.2.4 Handle provider-specific authentication requirements through ReqLLM

### Unit Tests - Section 1.5
- [x] **Unit Tests 1.5 Complete**
- [x] Test key precedence order preservation across different key sources
- [x] Test API key validation compatibility and error message consistency
- [x] Test per-request override functionality and session isolation
- [x] Test session key management behavior and lifecycle

### 1.5.5 JidoKeys Hybrid Integration
- [x] **Task 1.5.5 Complete**

This creates a hybrid approach that integrates JidoKeys for secure credential management while preserving Jido.AI.Keyring's process isolation and session management features. The integration provides enhanced security benefits while maintaining full backward compatibility with existing applications.

- [x] 1.5.5.1 Integrate JidoKeys as the underlying credential store while maintaining Jido.AI.Keyring API
- [x] 1.5.5.2 Create compatibility wrapper that delegates basic operations to JidoKeys for global configuration
- [x] 1.5.5.3 Preserve process-specific session management functionality using existing ETS/process isolation patterns
- [x] 1.5.5.4 Implement secure credential filtering and log redaction through JidoKeys integration

### Benefits of JidoKeys Integration

**Security Enhancement**:
- Built-in credential filtering prevents accidental exposure in logs
- Automatic redaction of sensitive patterns (API keys, passwords, tokens)
- Safe atom conversion with hardcoded allowlists for untrusted input

**API Preservation**:
- Maintain all existing `Jido.AI.Keyring` functions and method signatures
- Preserve process isolation and session management capabilities
- No breaking changes to existing applications or test suites

**Enhanced Functionality**:
- Runtime configuration updates through JidoKeys.put/2 for global settings
- Improved error handling with specific error types and better messaging
- Livebook integration with LB_ prefix handling for development environments

### Implementation Strategy

The hybrid approach uses JidoKeys as the backend for global configuration while Jido.AI.Keyring provides process-specific session management:

```elixir
# Delegation pattern for basic operations
defmodule Jido.AI.Keyring do
  # Basic get/2 delegates to JidoKeys for global config
  def get(server \\ __MODULE__, key, default \\ nil) do
    case get_session_value(server, key) do
      nil -> JidoKeys.get(key, default)  # Fall back to JidoKeys
      value -> value  # Use session override
    end
  end

  # Session functions remain unchanged for process isolation
  def set_session_value(server, key, value, pid), do: # existing implementation
end
```

**Configuration Hierarchy with JidoKeys Backend**:
1. Session values (per-process) - handled by Jido.AI.Keyring
2. JidoKeys runtime overrides - handled by JidoKeys.put/2
3. Environment variables - handled by JidoKeys
4. Application config - handled by JidoKeys
5. Default values - provided by calling code

### Unit Tests - Section 1.5.5
- [x] **Unit Tests 1.5.5 Complete**
- [x] Test JidoKeys integration without affecting existing API behavior and method signatures
- [x] Test credential security filtering and log redaction functionality in production scenarios
- [x] Test session management preservation with JidoKeys backend delegation
- [x] Test configuration precedence order with hybrid system across all hierarchy levels
- [x] Test process isolation behavior remains unchanged with JidoKeys backend
- [x] Test backward compatibility with existing applications and test suites

---

## 1.6 Provider Discovery and Listing
- [ ] **Section 1.6 Pending Implementation**

This section migrates Jido AI's provider and model discovery mechanisms to use ReqLLM's registry while maintaining the existing APIs that applications use for provider enumeration and model listing. **Note: This section is not yet implemented in the codebase.**

### 1.6.1 Provider Registry Migration
- [x] **Task 1.6.1 Completed**

The provider registry migration replaces Jido's custom provider listing with ReqLLM's provider registry while maintaining the same external API surface.

- [x] 1.6.1.1 Replace custom provider listing logic with ReqLLM registry queries
- [x] 1.6.1.2 Maintain existing provider enumeration APIs and response formats
- [x] 1.6.1.3 Preserve provider metadata and capability information for applications
- [x] 1.6.1.4 Handle provider-specific configuration bridging and validation

**Implementation Details:**
- Successfully migrated from 5 hardcoded providers to 57+ dynamic providers from ReqLLM registry
- Full backward compatibility maintained - all existing APIs work unchanged
- Created metadata bridging layer in `ProviderMapping` module
- Implemented graceful fallback to legacy providers when ReqLLM unavailable
- Added comprehensive unit and integration tests
- Updated mix task to show provider implementation status
- **Files Modified**: `lib/jido_ai/provider.ex`, `lib/jido_ai/req_llm_bridge.ex`, `lib/jido_ai/req_llm_bridge/provider_mapping.ex`, `lib/mix/tasks/models.ex`
- **Summary**: See `notes/features/provider-registry-migration-summary.md`

### 1.6.2 Model Catalog Integration
- [x] **Task 1.6.2 Completed**

Model catalog integration provides access to ReqLLM's broader model ecosystem while preserving Jido's existing model discovery and filtering capabilities.

- [x] 1.6.2.1 Migrate model discovery mechanisms to ReqLLM's model registry
- [x] 1.6.2.2 Preserve existing model listing and filtering APIs for applications
- [x] 1.6.2.3 Maintain model metadata structure compatibility and information richness
- [x] 1.6.2.4 Handle model availability checking and capability mapping

**Implementation Details:**
- Successfully migrated from ~20 cached models to 2000+ models from ReqLLM registry
- Full backward compatibility maintained - all existing APIs work unchanged
- Created comprehensive model registry system with three-layer architecture:
  - Model Registry Core (`Jido.AI.Model.Registry`) - unified interface
  - Registry Adapter (`Jido.AI.Model.Registry.Adapter`) - ReqLLM integration
  - Metadata Bridge (`Jido.AI.Model.Registry.MetadataBridge`) - format translation
- Enhanced Provider module with registry-backed methods (`list_all_models_enhanced`, `discover_models_by_criteria`, etc.)
- Updated Mix Tasks with advanced filtering and discovery capabilities
- Enhanced Model struct with ReqLLM fields (capabilities, modalities, cost)
- Graceful fallback to legacy providers when ReqLLM unavailable
- Comprehensive test suite: 3 unit test files + integration tests
- **Files Modified**: `lib/jido_ai/model.ex`, `lib/jido_ai/provider.ex`, `lib/mix/tasks/models.ex`
- **Files Created**: `lib/jido_ai/model/registry.ex`, `lib/jido_ai/model/registry/adapter.ex`, `lib/jido_ai/model/registry/metadata_bridge.ex`
- **Summary**: See `notes/features/model-catalog-integration-summary.md`

### Unit Tests - Section 1.6
- [x] **Unit Tests 1.6 Complete**
- [x] Test provider listing API preservation and response format consistency
- [x] Test model discovery functionality and metadata completeness
- [x] Test metadata structure compatibility across different providers
- [x] Test filtering and search capabilities for models and providers

**Implementation Details:**
- Comprehensive 5-phase test suite covering all Section 1.6 functionality
- **Phase 1**: API Preservation Tests - Legacy API compatibility validation
- **Phase 2**: Model Discovery Completeness Tests - Enhanced metadata and registry functionality
- **Phase 3**: Cross-Provider Metadata Compatibility Tests - Consistency across 57+ providers
- **Phase 4**: Filtering and Search Capabilities Tests - Advanced filtering and discovery
- **Phase 5**: Integration and Performance Tests - End-to-end workflows and performance validation
- **Files Created**: 5 comprehensive test files with 1000+ lines of test code
- **Coverage**: All 4 critical unit test areas specified in Phase 1 requirements
- **Performance**: Registry operations tested for < 10ms performance targets
- **Resilience**: Comprehensive error handling and fallback scenario testing
- **Summary**: See `notes/features/unit-tests-section-1-6-summary.md`

---

## 1.7 Error Handling and Logging
- [x] **Section 1.7 Complete**

This section ensures that ReqLLM's error handling and logging behavior is mapped to match Jido AI's existing patterns. This is critical for maintaining application stability and debugging capabilities.

### 1.7.1 Error Mapping Layer
- [x] **Task 1.7.1 Complete**

The error mapping layer translates ReqLLM's error formats to Jido's existing error structures, ensuring that error handling code in applications continues to work unchanged.

- [x] 1.7.1.1 Map ReqLLM error types and structures to existing Jido error formats
- [x] 1.7.1.2 Preserve `{:ok, result}` / `{:error, reason}` patterns across all functions
- [x] 1.7.1.3 Maintain existing error categorization and detailed error information
- [x] 1.7.1.4 Handle timeout, retry, and network error mapping consistently

### 1.7.2 Logging Preservation
- [x] **Task 1.7.2 Complete**

Logging preservation ensures that Jido AI's deliberately minimal and opt-in logging behavior is maintained, with ReqLLM's internal logging appropriately managed.

- [x] 1.7.2.1 Maintain existing opt-in logging behavior with no new default logging
- [x] 1.7.2.2 Preserve log levels, message formats, and logging configuration options
- [x] 1.7.2.3 Map ReqLLM internal logs appropriately without creating log noise
- [x] 1.7.2.4 Document ReqLLM debug/trace options for advanced troubleshooting

### Unit Tests - Section 1.7
- [x] **Unit Tests 1.7 Complete**
- [x] Test error structure preservation across different error scenarios
- [x] Test logging behavior consistency and configuration handling
- [x] Test error categorization accuracy and information preservation
- [x] Test timeout/retry error handling and recovery mechanisms

---

## 1.8 Integration Tests
- [x] **Section 1.8 Complete**

This section provides comprehensive end-to-end testing to validate that the ReqLLM integration works correctly across all supported providers and maintains full backward compatibility.

### 1.8.1 End-to-End Provider Testing
- [x] **Task 1.8.1 Complete**

End-to-end provider testing validates that each currently supported provider works correctly through the ReqLLM integration, maintaining the same behavior and capabilities.

- [x] 1.8.1.1 Test OpenAI provider functionality through ReqLLM integration layer
- [x] 1.8.1.2 Test Anthropic provider functionality through ReqLLM integration layer
- [x] 1.8.1.3 Test Google provider functionality through ReqLLM integration layer
- [x] 1.8.1.4 Test OpenRouter provider functionality through ReqLLM integration layer
- [x] 1.8.1.5 Test Cloudflare provider functionality through ReqLLM integration layer

### 1.8.2 Backward Compatibility Validation
- [x] **Task 1.8.2 Complete**

Backward compatibility validation ensures that existing applications and test suites continue to work without modification after the ReqLLM integration.

- [x] 1.8.2.1 Run complete existing test suite against ReqLLM-powered implementation
- [x] 1.8.2.2 Verify response shape preservation across all actions and providers
- [x] 1.8.2.3 Test streaming compatibility with existing consumer applications
- [x] 1.8.2.4 Validate tool calling flow preservation and execution semantics

### 1.8.3 Performance and Behavior Parity
- [x] **Task 1.8.3 Complete**

Performance and behavior parity testing ensures that the ReqLLM integration doesn't introduce performance regressions or behavioral changes.

- [x] 1.8.3.1 Benchmark ReqLLM implementation against current direct implementation
- [x] 1.8.3.2 Test concurrent request handling and connection management
- [x] 1.8.3.3 Verify timeout and retry behavior consistency with current implementation
- [x] 1.8.3.4 Test memory usage patterns and resource management efficiency

---

## Success Criteria

1. **API Preservation**: All existing public APIs work unchanged with identical signatures
2. **Response Compatibility**: All response shapes and error formats preserved exactly
3. **Provider Coverage**: All current providers functional through ReqLLM with same capabilities
4. **Extended Access**: New ReqLLM-supported models accessible via existing Jido AI APIs
5. **Performance Parity**: No significant performance degradation in throughput or latency
6. **Test Suite**: 100% existing test suite passes with ReqLLM backend

## Provides Foundation

This phase establishes the infrastructure for:
- Phase 2: Extended provider and model support from ReqLLM ecosystem
- Phase 3: Advanced ReqLLM features integration (advanced streaming, multimodal)
- Phase 4: Performance optimization and technical debt cleanup

## Key Outputs

- Fully functional ReqLLM integration with preserved public APIs
- Comprehensive bridge modules for seamless compatibility
- Extended model and provider coverage beyond current limitations
- Complete test coverage for integration layer and compatibility validation
- Documentation for ReqLLM configuration and troubleshooting