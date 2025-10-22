# Phase 5: Replace Instructor with Internal Structured Output Implementation

## Phase Overview

This phase focuses on replacing the external Instructor library dependency with an internal structured output extraction implementation. The goal is to eliminate the dependency while preserving all existing functionality for ChatResponse, BooleanResponse, and ChoiceResponse actions. The internal implementation will use ReqLLM's JSON mode capabilities combined with custom schema validation to achieve the same structured output guarantees that Instructor provides, maintaining backward compatibility and the same public APIs.

---

## Section 5.1: Schema Definition and Validation System

This section establishes the foundational schema system that will replace Instructor's Ecto schema validation. The internal schema system needs to define response structures, validate JSON data against those structures, and provide clear error messages when validation fails. This is the core replacement for Instructor's schema validation mechanism.

### Task 5.1.1: Design Internal Schema DSL

Design a lightweight schema definition system that can replace Ecto schemas for response validation purposes. The DSL should be simple, declarative, and focused solely on validation without the overhead of database integration.

- [ ] Research Ecto schema usage in existing Instructor actions
- [ ] Identify required field types: string, boolean, float, integer, list
- [ ] Design schema definition macro or function
- [ ] Determine whether to use structs or maps for validated data
- [ ] Document schema DSL format and usage
- [ ] Create examples for ChatResponse, BooleanResponse, and ChoiceResponse schemas

### Task 5.1.2: Implement Schema Validator Module

Create a module that validates JSON data against defined schemas. This validator needs to check types, required fields, and provide helpful error messages for validation failures.

- [ ] Create `Jido.AI.SchemaValidator` module
- [ ] Implement `validate/2` function taking data and schema
- [ ] Add type checking for: string, boolean, float, integer, list
- [ ] Implement required field validation
- [ ] Add optional field handling with defaults
- [ ] Create detailed error messages for validation failures
- [ ] Add support for nested schemas if needed
- [ ] Write comprehensive unit tests for all validation scenarios

### Task 5.1.3: Define Response Schemas

Convert existing Ecto schemas from Instructor actions to internal schema definitions. Each response type needs its own schema definition.

- [ ] Create schema for ChatResponse (simple string response)
- [ ] Create schema for BooleanResponse (answer, explanation, confidence, is_ambiguous)
- [ ] Create schema for ChoiceResponse (selected_option, explanation, confidence)
- [ ] Document each schema's purpose and fields
- [ ] Add example valid responses for each schema
- [ ] Write tests validating correct responses pass
- [ ] Write tests ensuring invalid responses fail with clear errors

---

## Section 5.2: JSON Mode Integration with ReqLLM

This section focuses on configuring ReqLLM to produce structured JSON outputs that match our internal schemas. Many modern LLM providers support JSON mode, which enforces JSON formatting in responses. We need to leverage this capability and handle providers that don't support it gracefully.

### Task 5.2.1: Research ReqLLM JSON Mode Support

Investigate how ReqLLM handles JSON mode across different providers. Different providers have different JSON mode implementations, and we need to understand the capabilities and limitations.

- [ ] Review ReqLLM documentation for JSON mode options
- [ ] Test JSON mode with OpenAI (response_format: json_object)
- [ ] Test JSON mode with Anthropic (JSON mode support)
- [ ] Identify which providers support native JSON mode
- [ ] Determine fallback strategy for providers without JSON mode
- [ ] Document provider-specific JSON mode configurations
- [ ] Create provider capability matrix

### Task 5.2.2: Implement JSON Mode Request Builder

Create helper functions to build ReqLLM requests with appropriate JSON mode settings. These functions need to handle provider-specific differences and include schema information in prompts when necessary.

- [ ] Create `Jido.AI.JsonRequestBuilder` module
- [ ] Implement function to add JSON mode options to ReqLLM requests
- [ ] Add schema-to-prompt conversion (include schema in system message)
- [ ] Handle provider-specific JSON mode parameters
- [ ] Add schema examples to prompts to guide LLM output
- [ ] Implement fallback prompt instructions for non-JSON-mode providers
- [ ] Write tests for request building with various providers

### Task 5.2.3: Implement Response Parser

Create a robust JSON response parser that handles various LLM output formats. LLMs sometimes include markdown code blocks or extra text around JSON, so the parser needs to be resilient.

- [ ] Create `Jido.AI.ResponseParser` module
- [ ] Implement JSON extraction from response content
- [ ] Handle markdown code blocks (```json ... ```)
- [ ] Strip extraneous text before/after JSON
- [ ] Validate JSON syntax before schema validation
- [ ] Provide clear error messages for unparseable responses
- [ ] Add support for partial JSON extraction if needed
- [ ] Write tests for various response formats

---

## Section 5.3: Specialized Action Migration

This section handles the migration of the three specialized Instructor actions to use the internal implementation. Each action needs to be updated to use the new schema validation system while maintaining identical public APIs and behavior.

### Task 5.3.1: Migrate ChatResponse Action

Update ChatResponse to use internal schema validation instead of Instructor. This is the simplest action, returning just a string response, making it a good starting point.

- [ ] Read current `Jido.AI.Actions.Instructor.ChatResponse` implementation
- [ ] Create `Jido.AI.Actions.Internal.ChatResponse` with new implementation
- [ ] Replace Instructor calls with internal validator
- [ ] Use JSON mode in ReqLLM request
- [ ] Validate response against ChatResponse schema
- [ ] Ensure response format matches original (string content)
- [ ] Update parameter schema to match original
- [ ] Maintain all existing parameters (model, prompt, temperature, etc.)
- [ ] Write unit tests matching original test coverage
- [ ] Write integration test with real API (tagged skip)

### Task 5.3.2: Migrate BooleanResponse Action

Update BooleanResponse to use internal schema validation. This action is more complex, requiring boolean answer plus explanation, confidence, and ambiguity detection.

- [ ] Read current `Jido.AI.Actions.Instructor.BooleanResponse` implementation
- [ ] Create `Jido.AI.Actions.Internal.BooleanResponse` with new implementation
- [ ] Replace Instructor calls with internal validator
- [ ] Use JSON mode in ReqLLM request with BooleanResponse schema
- [ ] Validate response against BooleanResponse schema (answer, explanation, confidence, is_ambiguous)
- [ ] Ensure response format matches original structure
- [ ] Add schema details to system prompt for better LLM compliance
- [ ] Update parameter schema to match original
- [ ] Write unit tests for all response fields
- [ ] Write integration test with real API (tagged skip)

### Task 5.3.3: Migrate ChoiceResponse Action

Update ChoiceResponse to use internal schema validation. This action handles multiple choice selection with reasoning and confidence scoring.

- [ ] Read current `Jido.AI.Actions.Instructor.ChoiceResponse` implementation
- [ ] Create `Jido.AI.Actions.Internal.ChoiceResponse` with new implementation
- [ ] Replace Instructor calls with internal validator
- [ ] Use JSON mode in ReqLLM request with ChoiceResponse schema
- [ ] Validate response against ChoiceResponse schema (selected_option, explanation, confidence)
- [ ] Add options list to system prompt
- [ ] Validate selected_option is one of provided options
- [ ] Ensure response format matches original structure
- [ ] Update parameter schema to match original
- [ ] Write unit tests for choice validation
- [ ] Write integration test with real API (tagged skip)

### Task 5.3.4: Update Skill Module Defaults

Update the Skill module to use the new internal actions as defaults instead of Instructor actions. Maintain backward compatibility by allowing explicit Instructor usage with deprecation warnings.

- [ ] Update default chat_action to `Jido.AI.Actions.Internal.ChatResponse`
- [ ] Update default boolean_action to `Jido.AI.Actions.Internal.BooleanResponse`
- [ ] Keep choice_action available (not default, but documented)
- [ ] Add deprecation warning for Instructor action usage
- [ ] Update router to use internal actions
- [ ] Document migration path in deprecation warnings
- [ ] Test Skill initialization with new defaults
- [ ] Verify backward compatibility with explicit Instructor usage

---

## Section 5.4: Retry and Validation Logic

This section implements retry logic for handling validation failures. When an LLM response doesn't match the expected schema, we should retry with additional context about what went wrong, similar to how Instructor handles validation errors.

### Task 5.4.1: Design Retry Strategy

Design a retry mechanism that gives the LLM multiple chances to produce valid output. The strategy should include error feedback, attempt limits, and backoff logic.

- [ ] Determine maximum retry attempts (default: 3)
- [ ] Design error feedback format for LLM
- [ ] Decide whether to use exponential backoff
- [ ] Plan for token usage concerns with retries
- [ ] Consider caching schema examples between retries
- [ ] Document retry strategy and configuration options
- [ ] Research Instructor's retry approach for inspiration

### Task 5.4.2: Implement Retry Module

Create a module that handles retry logic with validation error feedback. This module should coordinate with the validator and parser to retry requests when validation fails.

- [ ] Create `Jido.AI.RetryHandler` module
- [ ] Implement `retry_with_validation/3` function
- [ ] Add validation error to retry prompt
- [ ] Include schema details in retry attempts
- [ ] Track retry count and enforce maximum attempts
- [ ] Log retry attempts for debugging
- [ ] Return aggregated errors if all retries fail
- [ ] Write tests for successful retry scenarios
- [ ] Write tests for exhausted retry scenarios

### Task 5.4.3: Integrate Retry Logic into Actions

Update the three migrated actions to use retry logic when validation fails. Each action should attempt retries before returning validation errors to users.

- [ ] Add retry logic to ChatResponse action
- [ ] Add retry logic to BooleanResponse action
- [ ] Add retry logic to ChoiceResponse action
- [ ] Make retry attempts configurable per action
- [ ] Allow disabling retries via parameter
- [ ] Log retry statistics in verbose mode
- [ ] Test retry behavior with intentionally invalid responses
- [ ] Verify performance impact of retry logic

---

## Section 5.5: Testing and Backward Compatibility

This section ensures the new internal implementation maintains 100% backward compatibility with existing Instructor-based code and that all tests pass. We need comprehensive testing to verify the migration doesn't break any existing functionality.

### Task 5.5.1: Create Comprehensive Test Suite

Build a thorough test suite for the new internal implementation covering all response types, validation scenarios, and error cases.

- [ ] Write parameter validation tests for each action
- [ ] Write schema validation tests for each response type
- [ ] Write JSON parsing tests with various formats
- [ ] Write retry logic tests
- [ ] Write error handling tests
- [ ] Write integration tests with real APIs (tagged skip)
- [ ] Add edge case tests (empty responses, malformed JSON, etc.)
- [ ] Ensure test coverage matches or exceeds Instructor tests
- [ ] Run full test suite and verify 0 failures

### Task 5.5.2: Backward Compatibility Verification

Verify that code using the old Instructor actions continues to work without changes. Users explicitly using Instructor should receive deprecation warnings but not break.

- [ ] Test Skill initialization with default actions
- [ ] Test explicit Instructor action usage
- [ ] Verify deprecation warnings appear correctly
- [ ] Test existing applications using Instructor actions
- [ ] Check that response formats are identical
- [ ] Verify parameter schemas are unchanged
- [ ] Test error message formats match expectations
- [ ] Document any behavioral differences (if any)

### Task 5.5.3: Performance Comparison

Compare the performance of the internal implementation against Instructor to ensure we haven't introduced significant overhead or latency.

- [ ] Create benchmark suite for response validation
- [ ] Measure schema validation performance
- [ ] Measure JSON parsing performance
- [ ] Measure retry logic overhead
- [ ] Compare end-to-end action performance vs Instructor
- [ ] Test with large response payloads
- [ ] Profile memory usage
- [ ] Document performance characteristics

### Task 5.5.4: Documentation and Migration Guide

Create comprehensive documentation for the new internal implementation and provide a clear migration guide for users currently using Instructor actions explicitly.

- [ ] Write module documentation for all new modules
- [ ] Add usage examples to action moduledocs
- [ ] Create migration guide document
- [ ] Document schema DSL usage
- [ ] Document retry configuration options
- [ ] Add troubleshooting section for common issues
- [ ] Update CHANGELOG with deprecation notices
- [ ] Create summary document when complete

---

## Section 5.6: Cleanup and Deprecation

This section handles the gradual deprecation of Instructor dependency. We'll add deprecation warnings, update defaults, and prepare for eventual removal of Instructor in a future version.

### Task 5.6.1: Add Deprecation Warnings

Add clear deprecation warnings for Instructor usage guiding users to migrate to internal implementation.

- [ ] Add warning when Instructor actions explicitly used
- [ ] Include migration instructions in warnings
- [ ] Add timeline for removal (e.g., v0.7.0)
- [ ] Update Skill mount/2 to check for Instructor usage
- [ ] Log warnings with appropriate log level
- [ ] Test deprecation warnings appear correctly
- [ ] Document deprecation timeline in CHANGELOG

### Task 5.6.2: Update Dependencies

Mark Instructor as optional dependency to allow users to opt out once migrated. This reduces installation size for users not using deprecated features.

- [ ] Mark instructor as optional in mix.exs
- [ ] Update dependency documentation
- [ ] Test project compiles without Instructor
- [ ] Test Instructor actions still work when installed
- [ ] Verify internal actions work without Instructor
- [ ] Update installation documentation
- [ ] Note dependency changes in CHANGELOG

### Task 5.6.3: Plan for Future Removal

Document the plan for complete Instructor removal in a future major version. This gives users clear expectations and migration timeline.

- [ ] Set target version for Instructor removal (v0.7.0 or v1.0.0)
- [ ] Document what will break in that version
- [ ] Create migration checklist for users
- [ ] Plan for removal of Instructor-specific code
- [ ] Update roadmap documentation
- [ ] Communicate timeline in deprecation warnings
- [ ] Add removal plan to migration guide

---

## Success Criteria

Phase 5 will be considered complete when:

- [ ] All internal implementation modules created and tested
- [ ] ChatResponse, BooleanResponse, and ChoiceResponse migrated
- [ ] All existing tests pass (567+ tests, 0 failures)
- [ ] New tests added for internal implementation (25+ tests)
- [ ] Backward compatibility verified (no breaking changes)
- [ ] Deprecation warnings in place for Instructor usage
- [ ] Performance meets or exceeds Instructor implementation
- [ ] Documentation complete with migration guide
- [ ] Summary document created

---

## Dependencies and Risks

### Dependencies
- ReqLLM JSON mode capabilities (may vary by provider)
- Existing ReqLlmBridge infrastructure
- Ecto-like schema validation requirements

### Risks
- JSON mode support varies across providers (mitigation: fallback prompt instructions)
- LLM output may not always be valid JSON (mitigation: retry logic with error feedback)
- Schema validation complexity may grow (mitigation: keep DSL simple and focused)
- Performance overhead from validation and retries (mitigation: benchmark and optimize)
- Backward compatibility challenges (mitigation: extensive testing)

### Benefits
- Eliminates Instructor dependency (lighter installation)
- Full control over validation logic
- Consistent with ReqLLM architecture
- Better error messages and debugging
- Unified error handling across all AI actions
