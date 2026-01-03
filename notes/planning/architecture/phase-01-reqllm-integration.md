# Phase 1: ReqLLM Integration Layer

This phase implements the foundational ReqLLM integration layer that provides a Jido-friendly interface to ReqLLM's capabilities including streaming, tool calling, and metadata handling.

## Module Structure

```
lib/jido_ai/
├── req_llm/
│   ├── adapter.ex     # ReqLLM adapter for Jido
│   ├── client.ex      # ReqLLM client wrapper
│   ├── streaming.ex   # Streaming response handling
│   └── metadata.ex    # Metadata extraction and processing
```

---

## 1.1 Adapter Module

Implement the main adapter module that provides the public API for ReqLLM integration with Jido AI.

### 1.1.1 Module Setup

Create the adapter module with type specifications and documentation.

- [ ] 1.1.1.1 Create `lib/jido_ai/req_llm/adapter.ex` with module documentation
- [ ] 1.1.1.2 Define `@type model_spec :: String.t() | {:atom, String.t(), keyword()} | ReqLLM.Model.t()`
- [ ] 1.1.1.3 Add module aliases for Client, Streaming, and Metadata

### 1.1.2 Text Generation Functions

Implement text generation with both blocking and streaming modes.

- [ ] 1.1.2.1 Implement `generate_text/3` function with model_spec, prompt, and opts
- [ ] 1.1.2.2 Implement `stream_text/3` function that returns a stream response
- [ ] 1.1.2.3 Add `@spec` for both functions with proper return types

### 1.1.3 Structured Output Functions

Implement schema-based structured output generation.

- [ ] 1.1.3.1 Implement `generate_object/4` with model_spec, prompt, schema, opts
- [ ] 1.1.3.2 Add Zoi schema validation support
- [ ] 1.1.3.3 Add `@spec` with schema parameter types

### 1.1.4 Tool Calling Functions

Implement tool calling integration.

- [ ] 1.1.4.1 Implement `call_with_tools/4` with model_spec, prompt, tools, opts
- [ ] 1.1.4.2 Define tool list type specification
- [ ] 1.1.4.3 Add `@spec` for tool calling function

### 1.1.5 Embedding Functions

Implement embedding generation.

- [ ] 1.1.5.1 Implement `generate_embeddings/3` with model_spec, texts, opts
- [ ] 1.1.5.2 Support batch embedding for multiple texts
- [ ] 1.1.5.3 Add `@spec` with list return type

### 1.1.6 Response Processing

Implement unified response processing.

- [ ] 1.1.6.1 Implement `process_response/1` function
- [ ] 1.1.6.2 Delegate to Metadata module for extraction
- [ ] 1.1.6.3 Return normalized response structure

### 1.1.7 Unit Tests for Adapter

- [ ] Test generate_text/3 delegates to Client correctly
- [ ] Test stream_text/3 returns stream response
- [ ] Test generate_object/4 validates schema
- [ ] Test call_with_tools/4 converts tools properly
- [ ] Test generate_embeddings/3 handles batch input
- [ ] Test process_response/1 extracts metadata

---

## 1.2 Client Implementation

Implement the client wrapper that handles actual ReqLLM requests.

### 1.2.1 Text Generation

Implement text generation with context building.

- [ ] 1.2.1.1 Create `lib/jido_ai/req_llm/client.ex` with module documentation
- [ ] 1.2.1.2 Implement `generate_text/3` with context building
- [ ] 1.2.1.3 Implement `build_context/2` helper for prompt conversion
- [ ] 1.2.1.4 Implement `maybe_add_system_message/2` helper
- [ ] 1.2.1.5 Handle conversation history from opts

### 1.2.2 Streaming Implementation

Implement streaming text generation.

- [ ] 1.2.2.1 Implement `stream_text/3` with context building
- [ ] 1.2.2.2 Delegate stream processing to Streaming module
- [ ] 1.2.2.3 Return structured stream response

### 1.2.3 Structured Output

Implement schema-based output generation.

- [ ] 1.2.3.1 Implement `generate_object/4` with schema parameter
- [ ] 1.2.3.2 Pass schema to ReqLLM.generate_object
- [ ] 1.2.3.3 Validate response against schema

### 1.2.4 Tool Calling

Implement tool calling with conversion.

- [ ] 1.2.4.1 Implement `call_with_tools/4` function
- [ ] 1.2.4.2 Implement `convert_tool/1` for Jido to ReqLLM tool conversion
- [ ] 1.2.4.3 Extract tool_module.name(), description(), schema()

### 1.2.5 Embedding Generation

Implement embedding generation.

- [ ] 1.2.5.1 Implement `generate_embeddings/3` function
- [ ] 1.2.5.2 Delegate to ReqLLM.Embedding.generate
- [ ] 1.2.5.3 Process and normalize response

### 1.2.6 Response Processing

Implement response normalization.

- [ ] 1.2.6.1 Implement `process_response/1` private function
- [ ] 1.2.6.2 Extract content, usage, finish_reason, model, provider
- [ ] 1.2.6.3 Implement `extract_metadata/1` for detailed metadata

### 1.2.7 Unit Tests for Client

- [ ] Test generate_text/3 builds context correctly
- [ ] Test generate_text/3 includes system message when provided
- [ ] Test generate_text/3 includes conversation history
- [ ] Test stream_text/3 returns stream via Streaming module
- [ ] Test generate_object/4 passes schema to ReqLLM
- [ ] Test call_with_tools/4 converts tools correctly
- [ ] Test generate_embeddings/3 handles single and batch texts
- [ ] Test process_response/1 extracts all fields
- [ ] Test error handling for API failures

---

## 1.3 Streaming Handler

Implement streaming response processing.

### 1.3.1 Stream Response Processing

Create the streaming module for handling ReqLLM streams.

- [ ] 1.3.1.1 Create `lib/jido_ai/req_llm/streaming.ex` with module documentation
- [ ] 1.3.1.2 Implement `process_stream/1` that wraps StreamResponse
- [ ] 1.3.1.3 Return structured map with id, tokens, usage fn, finish_reason fn

### 1.3.2 Token Handling

Implement token extraction and processing.

- [ ] 1.3.2.1 Extract tokens via StreamResponse.tokens/1
- [ ] 1.3.2.2 Provide lazy evaluation for usage and finish_reason
- [ ] 1.3.2.3 Support enumeration over token stream

### 1.3.3 Metadata Extraction

Implement stream metadata extraction.

- [ ] 1.3.3.1 Implement `extract_stream_metadata/1` private function
- [ ] 1.3.3.2 Extract model, provider, request_id, created_at
- [ ] 1.3.3.3 Provide lazy metadata function in response

### 1.3.4 Unit Tests for Streaming

- [ ] Test process_stream/1 returns structured response
- [ ] Test tokens are accessible via returned map
- [ ] Test usage function returns token counts lazily
- [ ] Test finish_reason function returns completion status
- [ ] Test metadata function returns model info
- [ ] Test stream can be enumerated

---

## 1.4 Metadata Processing

Implement metadata extraction and processing.

### 1.4.1 Response Metadata

Create the metadata module for response processing.

- [ ] 1.4.1.1 Create `lib/jido_ai/req_llm/metadata.ex` with module documentation
- [ ] 1.4.1.2 Implement `process/1` function for response metadata
- [ ] 1.4.1.3 Define metadata struct type

### 1.4.2 Usage Extraction

Implement usage metrics extraction.

- [ ] 1.4.2.1 Extract input_tokens from response.usage
- [ ] 1.4.2.2 Extract output_tokens from response.usage
- [ ] 1.4.2.3 Calculate total_tokens
- [ ] 1.4.2.4 Extract cost if available

### 1.4.3 Request Metadata

Implement request-level metadata extraction.

- [ ] 1.4.3.1 Extract request_id from response
- [ ] 1.4.3.2 Extract created_at timestamp
- [ ] 1.4.3.3 Extract model and provider info

### 1.4.4 Unit Tests for Metadata

- [ ] Test process/1 extracts all usage fields
- [ ] Test process/1 handles missing optional fields
- [ ] Test total_tokens calculation
- [ ] Test cost extraction when available
- [ ] Test request metadata extraction
- [ ] Test provider/model info extraction

---

## 1.5 Phase 1 Integration Tests

Comprehensive integration tests verifying all Phase 1 components work together.

### 1.5.1 Adapter Integration

Verify adapter functions integrate correctly.

- [ ] 1.5.1.1 Create `test/jido_ai/integration/reqllm_phase1_test.exs`
- [ ] 1.5.1.2 Test: generate_text → client → process_response chain
- [ ] 1.5.1.3 Test: stream_text → streaming → metadata chain
- [ ] 1.5.1.4 Test: generate_object with schema validation

### 1.5.2 Error Handling Integration

Test error handling across the stack.

- [ ] 1.5.2.1 Test: API errors propagate correctly
- [ ] 1.5.2.2 Test: Rate limit errors include retry info
- [ ] 1.5.2.3 Test: Authentication errors are clear
- [ ] 1.5.2.4 Test: Timeout handling

### 1.5.3 Streaming Integration

Test end-to-end streaming behavior.

- [ ] 1.5.3.1 Test: Full streaming flow from adapter to tokens
- [ ] 1.5.3.2 Test: Streaming with tool calls
- [ ] 1.5.3.3 Test: Stream cancellation handling
- [ ] 1.5.3.4 Test: Partial response handling

---

## Phase 1 Success Criteria

1. **Adapter**: Unified API for all ReqLLM operations
2. **Client**: Correct request building and response handling
3. **Streaming**: Token-by-token streaming with lazy metadata
4. **Metadata**: Complete usage and request metadata extraction
5. **Test Coverage**: Minimum 80% for Phase 1 modules

---

## Phase 1 Critical Files

**New Files:**
- `lib/jido_ai/req_llm/adapter.ex`
- `lib/jido_ai/req_llm/client.ex`
- `lib/jido_ai/req_llm/streaming.ex`
- `lib/jido_ai/req_llm/metadata.ex`
- `test/jido_ai/req_llm/adapter_test.exs`
- `test/jido_ai/req_llm/client_test.exs`
- `test/jido_ai/req_llm/streaming_test.exs`
- `test/jido_ai/req_llm/metadata_test.exs`
- `test/jido_ai/integration/reqllm_phase1_test.exs`
