# Phase 2: Tool System

This phase implements the tool management infrastructure for LLM function execution. Tools in Jido.AI are primarily Jido.Actions that are exposed to LLMs via ReqLLM's tool calling system.

## Design Principle

**Jido.Actions are the primary tool mechanism.** The existing infrastructure already supports this:
- `Jido.AI.ToolAdapter.from_actions/1` converts Jido.Actions to `ReqLLM.Tool` structs
- `Jido.AI.Directive.ToolExec` executes actions when the LLM requests a tool call
- LLM tool calls are converted back to action invocations automatically

This phase adds:
1. A Tool behavior for non-Action tools (simple functions)
2. A registry to manage available tools (both Actions and simple tools)
3. Enhanced execution with better error handling
4. Integration with the existing ToolAdapter

## Existing Integration (Reference)

```elixir
# Current pattern: Actions as tools
tools = Jido.AI.ToolAdapter.from_actions([
  MyApp.Actions.Calculator,
  MyApp.Actions.Search
])

# Use directly with ReqLLM
ReqLLM.stream_text(model, messages, tools: tools)
```

## Module Structure

```
lib/jido_ai/
├── tools/
│   ├── tool.ex        # NEW: Tool behavior for simple tools
│   ├── registry.ex    # NEW: Tool registry (Actions + simple tools)
│   └── executor.ex    # NEW: Unified execution with error handling
├── tool_adapter.ex    # EXISTING: Action → ReqLLM.Tool conversion
└── directive.ex       # EXISTING: ToolExec directive
```

## Dependencies

- Phase 1: Foundation Enhancement

---

## 2.1 Tool Behavior

Define a behavior for simple tools that aren't full Jido.Actions. This provides a lightweight alternative when you don't need Action's full machinery.

### 2.1.1 Behavior Definition

Create the tool behavior module with required callbacks.

- [ ] 2.1.1.1 Create `lib/jido_ai/tools/tool.ex` with module documentation
- [ ] 2.1.1.2 Document relationship to Jido.Action (Actions are preferred for complex tools)
- [ ] 2.1.1.3 Define `@callback name() :: String.t()` for tool name
- [ ] 2.1.1.4 Define `@callback description() :: String.t()` for tool description
- [ ] 2.1.1.5 Define `@callback schema() :: map()` for Zoi parameter schema
- [ ] 2.1.1.6 Define `@callback run(params :: map(), context :: map()) :: {:ok, term()} | {:error, term()}`

### 2.1.2 Using Macro

Implement the `__using__` macro for tool modules.

- [ ] 2.1.2.1 Implement `__using__/1` macro with opts (name, description)
- [ ] 2.1.2.2 Inject `@behaviour Jido.AI.Tools.Tool`
- [ ] 2.1.2.3 Provide default implementations for name/0 and description/0 from opts
- [ ] 2.1.2.4 Generate `to_reqllm_tool/0` that creates `ReqLLM.Tool` struct directly

### 2.1.3 Conversion to ReqLLM

Implement conversion to ReqLLM.Tool format.

- [ ] 2.1.3.1 Implement `to_reqllm_tool/1` that takes a tool module
- [ ] 2.1.3.2 Convert Zoi schema to JSON Schema for ReqLLM
- [ ] 2.1.3.3 Use noop callback (execution via Jido, not ReqLLM callbacks)
- [ ] 2.1.3.4 Match the pattern used by ToolAdapter for consistency

### 2.1.4 Unit Tests for Tool Behavior

- [ ] Test behavior callbacks are defined
- [ ] Test `__using__` macro injects behavior and defaults
- [ ] Test to_reqllm_tool/1 creates valid ReqLLM.Tool
- [ ] Test schema validation works
- [ ] Test run/2 execution

---

## 2.2 Tool Registry

Implement a registry for managing available tools (both Jido.Actions and simple Tools).

### 2.2.1 Registry Design

Create the registry module (not a GenServer - compile-time registration preferred).

- [ ] 2.2.1.1 Create `lib/jido_ai/tools/registry.ex` with module documentation
- [ ] 2.2.1.2 Document that this manages both Actions and Tools
- [ ] 2.2.1.3 Support compile-time registration via `@tools` attribute pattern
- [ ] 2.2.1.4 Support runtime registration for dynamic tools

### 2.2.2 Action Registration

Implement action registration.

- [ ] 2.2.2.1 Implement `register_action/1` to add a Jido.Action module
- [ ] 2.2.2.2 Implement `register_actions/1` for batch registration
- [ ] 2.2.2.3 Validate module implements Jido.Action behavior
- [ ] 2.2.2.4 Store action metadata (name, description, schema)

### 2.2.3 Tool Registration

Implement simple tool registration.

- [ ] 2.2.3.1 Implement `register_tool/1` to add a Tool module
- [ ] 2.2.3.2 Validate module implements Jido.AI.Tools.Tool behavior
- [ ] 2.2.3.3 Store tool metadata

### 2.2.4 Listing and Lookup

Implement listing and lookup functionality.

- [ ] 2.2.4.1 Implement `list_all/0` to get all registered tools/actions
- [ ] 2.2.4.2 Implement `list_actions/0` for actions only
- [ ] 2.2.4.3 Implement `list_tools/0` for simple tools only
- [ ] 2.2.4.4 Implement `get/1` for lookup by name
- [ ] 2.2.4.5 Implement `get!/1` that raises on not found

### 2.2.5 ReqLLM Conversion

Implement batch conversion to ReqLLM format.

- [ ] 2.2.5.1 Implement `to_reqllm_tools/0` to convert all registered items
- [ ] 2.2.5.2 Use `ToolAdapter.from_actions/1` for actions
- [ ] 2.2.5.3 Use `Tool.to_reqllm_tool/1` for simple tools
- [ ] 2.2.5.4 Return combined list of `ReqLLM.Tool` structs

### 2.2.6 Unit Tests for Registry

- [ ] Test register_action/1 adds action
- [ ] Test register_tool/1 adds tool
- [ ] Test list_all/0 returns combined list
- [ ] Test get/1 finds by name
- [ ] Test get/1 returns nil for unknown
- [ ] Test to_reqllm_tools/0 converts all
- [ ] Test validation rejects non-Action modules
- [ ] Test validation rejects non-Tool modules

---

## 2.3 Tool Executor

Implement unified tool execution with validation and error handling.

### 2.3.1 Unified Execution

Create the executor module that handles both Actions and Tools.

- [ ] 2.3.1.1 Create `lib/jido_ai/tools/executor.ex` with module documentation
- [ ] 2.3.1.2 Implement `execute/3` with name, params, context
- [ ] 2.3.1.3 Look up tool/action in registry
- [ ] 2.3.1.4 Dispatch to appropriate executor (Jido.Exec for Actions, run/2 for Tools)

### 2.3.2 Parameter Normalization

Implement parameter normalization for LLM tool calls.

- [ ] 2.3.2.1 Implement `normalize_params/2` with schema
- [ ] 2.3.2.2 Convert string keys to atom keys
- [ ] 2.3.2.3 Parse string numbers based on schema type
- [ ] 2.3.2.4 Validate against schema after normalization

### 2.3.3 Result Formatting

Implement result formatting for LLM consumption.

- [ ] 2.3.3.1 Implement `format_result/1` for tool results
- [ ] 2.3.3.2 Convert maps/structs to JSON strings
- [ ] 2.3.3.3 Handle binary data (base64 encode or describe)
- [ ] 2.3.3.4 Truncate large results with size indicator

### 2.3.4 Error Handling

Implement comprehensive error handling.

- [ ] 2.3.4.1 Catch exceptions during execution
- [ ] 2.3.4.2 Return structured error with tool name, reason, stacktrace
- [ ] 2.3.4.3 Convert errors to LLM-friendly messages
- [ ] 2.3.4.4 Emit telemetry for execution metrics

### 2.3.5 Timeout Handling

Implement timeout handling for long-running tools.

- [ ] 2.3.5.1 Implement `execute/4` with timeout option
- [ ] 2.3.5.2 Use Task.await with timeout
- [ ] 2.3.5.3 Return timeout error with context
- [ ] 2.3.5.4 Support per-tool timeout configuration

### 2.3.6 Unit Tests for Executor

- [ ] Test execute/3 runs action via Jido.Exec
- [ ] Test execute/3 runs tool via run/2
- [ ] Test normalize_params/2 handles string keys
- [ ] Test normalize_params/2 parses string numbers
- [ ] Test format_result/1 produces JSON
- [ ] Test format_result/1 truncates large results
- [ ] Test exception handling
- [ ] Test timeout handling

---

## 2.4 ToolExec Directive Enhancement

Enhance the existing ToolExec directive to use the new executor.

### 2.4.1 Registry Integration

Integrate ToolExec with the registry.

- [ ] 2.4.1.1 Update ToolExec to look up tools in registry when action_module not provided
- [ ] 2.4.1.2 Support tool execution by name only
- [ ] 2.4.1.3 Fall back to direct action_module if provided

### 2.4.2 Enhanced Error Reporting

Improve error reporting in ToolExec.

- [ ] 2.4.2.1 Use Executor for consistent error handling
- [ ] 2.4.2.2 Include structured error in ToolResult signal
- [ ] 2.4.2.3 Add telemetry for tool execution

### 2.4.3 Unit Tests for ToolExec Enhancement

- [ ] Test ToolExec with registry lookup
- [ ] Test ToolExec with direct action_module
- [ ] Test enhanced error reporting
- [ ] Test telemetry emission

---

## 2.5 Phase 2 Integration Tests

Comprehensive integration tests verifying all Phase 2 components work together.

### 2.5.1 Registry and Executor Integration

Verify registry integrates with executor.

- [ ] 2.5.1.1 Create `test/jido_ai/integration/tools_phase2_test.exs`
- [ ] 2.5.1.2 Test: Register action → execute by name → get result
- [ ] 2.5.1.3 Test: Register tool → execute by name → get result
- [ ] 2.5.1.4 Test: Mixed actions and tools in registry

### 2.5.2 ReqLLM Integration

Test tool integration with ReqLLM (calling ReqLLM directly).

- [ ] 2.5.2.1 Test: Registry.to_reqllm_tools → ReqLLM.stream_text with tools
- [ ] 2.5.2.2 Test: Parse tool call from ReqLLM response
- [ ] 2.5.2.3 Test: Execute tool → format result → add to conversation

### 2.5.3 End-to-End Tool Calling

Test complete tool calling flow with ReqLLM.

- [ ] 2.5.3.1 Test: Full flow - prompt → ReqLLM → tool call → execute → result → ReqLLM
- [ ] 2.5.3.2 Test: Multiple sequential tool calls
- [ ] 2.5.3.3 Test: Error during tool execution handled gracefully
- [ ] 2.5.3.4 Test: Timeout during tool execution

---

## Phase 2 Success Criteria

1. **Tool Behavior**: Lightweight alternative to Jido.Action for simple tools
2. **Registry**: Unified management of Actions and Tools
3. **Executor**: Safe execution with validation, error handling, timeouts
4. **Direct ReqLLM**: All integration uses ReqLLM directly, no wrappers
5. **Test Coverage**: Minimum 80% for Phase 2 modules

---

## Phase 2 Critical Files

**New Files:**
- `lib/jido_ai/tools/tool.ex`
- `lib/jido_ai/tools/registry.ex`
- `lib/jido_ai/tools/executor.ex`
- `test/jido_ai/tools/tool_test.exs`
- `test/jido_ai/tools/registry_test.exs`
- `test/jido_ai/tools/executor_test.exs`
- `test/jido_ai/integration/tools_phase2_test.exs`

**Modified Files:**
- `lib/jido_ai/directive.ex` - Enhance ToolExec with registry integration
- `lib/jido_ai/tool_adapter.ex` - Ensure consistency with new Tool behavior
