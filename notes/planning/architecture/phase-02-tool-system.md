# Phase 2: Tool System

This phase implements the tool calling infrastructure for LLM function execution. Tools provide structured interfaces for LLMs to interact with external systems and execute actions.

## Module Structure

```
lib/jido_ai/
├── tools/
│   ├── tool.ex        # Tool behavior definition
│   ├── registry.ex    # Tool registry (GenServer)
│   ├── executor.ex    # Tool execution with context
│   └── reqllm.ex      # ReqLLM tool format conversion
```

## Dependencies

- Phase 1: ReqLLM Integration Layer (for tool calling API)

---

## 2.1 Tool Behavior

Define the behavior interface that all tools must implement.

### 2.1.1 Behavior Definition

Create the tool behavior module with required callbacks.

- [ ] 2.1.1.1 Create `lib/jido_ai/tools/tool.ex` with module documentation
- [ ] 2.1.1.2 Define `@callback schema() :: map()` for parameter schema
- [ ] 2.1.1.3 Define `@callback execute(params :: map(), context :: map()) :: {:ok, result :: map()} | {:error, reason :: term()}`
- [ ] 2.1.1.4 Define `@callback description() :: String.t()` for tool description
- [ ] 2.1.1.5 Define `@callback name() :: String.t()` for tool name

### 2.1.2 Using Macro

Implement the `__using__` macro for tool modules.

- [ ] 2.1.2.1 Implement `__using__/1` macro with opts
- [ ] 2.1.2.2 Inject `@behaviour Jido.AI.Tools.Tool`
- [ ] 2.1.2.3 Provide default implementations for name/0 and description/0 from opts
- [ ] 2.1.2.4 Allow override of default implementations

### 2.1.3 Schema Helpers

Implement schema helper functions.

- [ ] 2.1.3.1 Implement `validate_params/2` for parameter validation
- [ ] 2.1.3.2 Use Zoi for schema validation
- [ ] 2.1.3.3 Return `{:ok, validated_params}` or `{:error, validation_errors}`

### 2.1.4 Unit Tests for Tool Behavior

- [ ] Test behavior callbacks are defined
- [ ] Test `__using__` macro injects behavior
- [ ] Test default name/description from opts
- [ ] Test validate_params/2 with valid params
- [ ] Test validate_params/2 with invalid params
- [ ] Test custom tool module implements behavior

---

## 2.2 Tool Registry

Implement the GenServer-based tool registry for managing available tools.

### 2.2.1 GenServer Setup

Create the registry GenServer.

- [ ] 2.2.1.1 Create `lib/jido_ai/tools/registry.ex` with module documentation
- [ ] 2.2.1.2 Implement `start_link/1` with opts
- [ ] 2.2.1.3 Set default name to `__MODULE__`
- [ ] 2.2.1.4 Initialize state with empty tools map

### 2.2.2 Tool Registration

Implement tool registration functionality.

- [ ] 2.2.2.1 Implement `register/1` client function with tool_module
- [ ] 2.2.2.2 Implement `handle_call({:register, tool_module}, _, state)` callback
- [ ] 2.2.2.3 Store tool info map with module, name, description, schema
- [ ] 2.2.2.4 Return `:ok` on successful registration

### 2.2.3 Tool Listing

Implement tool listing functionality.

- [ ] 2.2.3.1 Implement `list_tools/0` client function
- [ ] 2.2.3.2 Implement `handle_call(:list_tools, _, state)` callback
- [ ] 2.2.3.3 Return list of tool info maps
- [ ] 2.2.3.4 Implement `get_tool/1` for single tool lookup by name

### 2.2.4 Tool Execution Dispatch

Implement tool execution dispatch through the registry.

- [ ] 2.2.4.1 Implement `execute_tool/3` with tool_name, params, context
- [ ] 2.2.4.2 Implement `handle_call({:execute, tool_name, params, context}, _, state)` callback
- [ ] 2.2.4.3 Look up tool module and call execute/2
- [ ] 2.2.4.4 Return `{:error, :tool_not_found}` for unknown tools

### 2.2.5 ReqLLM Format Conversion

Implement conversion to ReqLLM tool format.

- [ ] 2.2.5.1 Implement `to_reqllm_tools/0` client function
- [ ] 2.2.5.2 Implement `handle_call(:to_reqllm_tools, _, state)` callback
- [ ] 2.2.5.3 Implement `convert_to_reqllm_tool/1` private function
- [ ] 2.2.5.4 Create ReqLLM.tool with name, description, parameter_schema, callback

### 2.2.6 Unit Tests for Registry

- [ ] Test start_link/1 starts GenServer
- [ ] Test register/1 adds tool to registry
- [ ] Test register/1 validates tool implements behavior
- [ ] Test list_tools/0 returns all registered tools
- [ ] Test get_tool/1 returns specific tool
- [ ] Test get_tool/1 returns nil for unknown tool
- [ ] Test execute_tool/3 calls tool module
- [ ] Test execute_tool/3 returns error for unknown tool
- [ ] Test to_reqllm_tools/0 converts all tools
- [ ] Test conversion includes correct ReqLLM format

---

## 2.3 Tool Executor

Implement the tool executor for running tools with context and validation.

### 2.3.1 Execution Pipeline

Create the executor module with execution pipeline.

- [ ] 2.3.1.1 Create `lib/jido_ai/tools/executor.ex` with module documentation
- [ ] 2.3.1.2 Implement `execute/3` with tool_module, params, context
- [ ] 2.3.1.3 Validate params against tool schema
- [ ] 2.3.1.4 Call tool_module.execute/2 with validated params

### 2.3.2 Context Handling

Implement context management for tool execution.

- [ ] 2.3.2.1 Implement `build_context/2` for context building
- [ ] 2.3.2.2 Include agent state in context if available
- [ ] 2.3.2.3 Include session info in context
- [ ] 2.3.2.4 Allow context extension via opts

### 2.3.3 Result Processing

Implement result processing and normalization.

- [ ] 2.3.3.1 Implement `process_result/1` for result normalization
- [ ] 2.3.3.2 Handle `{:ok, result}` responses
- [ ] 2.3.3.3 Handle `{:error, reason}` responses
- [ ] 2.3.3.4 Convert results to string format for LLM consumption

### 2.3.4 Error Handling

Implement error handling for tool execution.

- [ ] 2.3.4.1 Catch exceptions during tool execution
- [ ] 2.3.4.2 Return structured error with tool name and reason
- [ ] 2.3.4.3 Log errors via telemetry
- [ ] 2.3.4.4 Support timeout handling for long-running tools

### 2.3.5 Unit Tests for Executor

- [ ] Test execute/3 validates params before execution
- [ ] Test execute/3 rejects invalid params
- [ ] Test execute/3 passes context to tool
- [ ] Test build_context/2 includes agent state
- [ ] Test process_result/1 normalizes success responses
- [ ] Test process_result/1 normalizes error responses
- [ ] Test exception handling during execution
- [ ] Test timeout handling for slow tools

---

## 2.4 ReqLLM Tool Integration

Implement integration between Jido tools and ReqLLM's tool calling system.

### 2.4.1 Tool Conversion

Extend the existing tool_adapter.ex for ReqLLM integration.

- [ ] 2.4.1.1 Create `lib/jido_ai/tools/reqllm.ex` with module documentation
- [ ] 2.4.1.2 Implement `convert/1` for single tool conversion
- [ ] 2.4.1.3 Implement `convert_all/1` for batch conversion
- [ ] 2.4.1.4 Map Jido tool schema to ReqLLM parameter_schema format

### 2.4.2 Schema Conversion

Implement schema format conversion.

- [ ] 2.4.2.1 Implement `convert_schema/1` for Zoi to JSON Schema conversion
- [ ] 2.4.2.2 Handle string, integer, float, boolean types
- [ ] 2.4.2.3 Handle optional and required fields
- [ ] 2.4.2.4 Handle nested object schemas

### 2.4.3 Callback Wiring

Implement callback wiring for tool execution.

- [ ] 2.4.3.1 Implement callback tuple `{module, :execute, [:extra_args]}`
- [ ] 2.4.3.2 Ensure callbacks receive parsed parameters
- [ ] 2.4.3.3 Handle callback result formatting

### 2.4.4 Tool Result Formatting

Implement result formatting for LLM consumption.

- [ ] 2.4.4.1 Implement `format_result/1` for tool results
- [ ] 2.4.4.2 Convert maps to JSON strings
- [ ] 2.4.4.3 Handle binary data gracefully
- [ ] 2.4.4.4 Truncate large results with indicator

### 2.4.5 Unit Tests for ReqLLM Integration

- [ ] Test convert/1 produces valid ReqLLM tool
- [ ] Test convert_all/1 converts multiple tools
- [ ] Test convert_schema/1 handles all types
- [ ] Test convert_schema/1 handles nested objects
- [ ] Test callback wiring executes correct module
- [ ] Test format_result/1 produces JSON strings
- [ ] Test format_result/1 truncates large results

---

## 2.5 Phase 2 Integration Tests

Comprehensive integration tests verifying all Phase 2 components work together.

### 2.5.1 Registry Integration

Verify registry integrates with executor.

- [ ] 2.5.1.1 Create `test/jido_ai/integration/tools_phase2_test.exs`
- [ ] 2.5.1.2 Test: Register tool → execute via registry → get result
- [ ] 2.5.1.3 Test: Multiple tools registered and executed
- [ ] 2.5.1.4 Test: Tool not found error handling

### 2.5.2 ReqLLM Integration

Test tool integration with ReqLLM.

- [ ] 2.5.2.1 Test: Convert tools → use with Adapter.call_with_tools
- [ ] 2.5.2.2 Test: Tool call response parsing
- [ ] 2.5.2.3 Test: Tool execution from LLM request
- [ ] 2.5.2.4 Test: Multi-tool conversation flow

### 2.5.3 End-to-End Tool Calling

Test complete tool calling flow.

- [ ] 2.5.3.1 Test: LLM request → tool call → execute → result → LLM response
- [ ] 2.5.3.2 Test: Error during tool execution handling
- [ ] 2.5.3.3 Test: Timeout during tool execution
- [ ] 2.5.3.4 Test: Tool chain (multiple sequential tool calls)

---

## Phase 2 Success Criteria

1. **Tool Behavior**: Clean interface for implementing tools
2. **Registry**: Central management of available tools
3. **Executor**: Safe execution with validation and error handling
4. **ReqLLM Integration**: Seamless conversion and callback wiring
5. **Test Coverage**: Minimum 80% for Phase 2 modules

---

## Phase 2 Critical Files

**New Files:**
- `lib/jido_ai/tools/tool.ex`
- `lib/jido_ai/tools/registry.ex`
- `lib/jido_ai/tools/executor.ex`
- `lib/jido_ai/tools/reqllm.ex`
- `test/jido_ai/tools/tool_test.exs`
- `test/jido_ai/tools/registry_test.exs`
- `test/jido_ai/tools/executor_test.exs`
- `test/jido_ai/tools/reqllm_test.exs`
- `test/jido_ai/integration/tools_phase2_test.exs`

**Modified Files:**
- `lib/jido_ai/tool_adapter.ex` - Extend with ReqLLM support
