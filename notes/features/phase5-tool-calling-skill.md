# Phase 5.5: Tool Calling Skill - Implementation Plan

## Overview

Implement the Tool Calling Skill for Jido.AI, providing LLM tool/function calling capabilities with automatic execution and multi-turn conversations.

## Requirements (from Phase 5 plan)

### 5.5.1 Skill Setup
- [x] Create `lib/jido_ai/skills/tool_calling.ex` with module documentation
- [x] Use `Jido.Skill` with name, state_key, and actions
- [x] Define schema with available_tools, auto_execute fields
- [x] List actions: CallWithTools, ExecuteTool, ListTools

### 5.5.2 Mount Callback
- [x] Implement `mount/2` callback
- [x] Load available tools from Registry
- [x] Configure auto-execution setting

### 5.5.3 CallWithTools Action
- [x] Create CallWithTools action module
- [x] Accept prompt, tools parameters
- [x] Call `ReqLLM.generate_text/3` with `tools:` option directly
- [x] Return response with tool calls

### 5.5.4 ExecuteTool Action
- [x] Create ExecuteTool action module
- [x] Accept tool_name, params parameters
- [x] Execute via Registry/Executor
- [x] Return tool result

### 5.5.5 ListTools Action
- [x] Create ListTools action module
- [x] Get tools from Registry
- [x] Return tool list with schemas

### 5.5.6 Auto-Execution
- [x] Implement auto-execution logic
- [x] Parse tool call from LLM response
- [x] Execute and return result to LLM
- [x] Support multi-turn tool conversations

### 5.5.7 Unit Tests
- [x] Test mount/2 loads available tools
- [x] Test CallWithTools action includes tools
- [x] Test ExecuteTool action runs tool
- [x] Test ListTools action returns tool list
- [x] Test auto-execution handles tool calls
- [x] Test multi-turn tool conversations
- [x] Test error handling during execution

## Design Decisions

1. **Registry Integration**: Uses existing `Jido.AI.Tools.Registry` for tool lookup
2. **Executor Integration**: Uses `Jido.AI.Tools.Executor.execute/4` for execution
3. **Tool Format**: Uses `Registry.to_reqllm_tools/0` to get ReqLLM-compatible tools
4. **Auto-Execution**: Optional multi-turn conversation loop for automatic tool execution
5. **Tool Selection**: Supports filtering tools by name pattern or explicit list

## Module Structure

```
lib/jido_ai/skills/tool_calling/
├── tool_calling.ex            # Main skill module
└── actions/
    ├── call_with_tools.ex     # LLM call with tool support
    ├── execute_tool.ex        # Direct tool execution
    └── list_tools.ex          # List available tools
```

## Dependencies

- `Jido.AI.Tools.Registry` - Tool storage and lookup
- `Jido.AI.Tools.Executor` - Tool execution
- `ReqLLM` - LLM with tool calling support
- `Jido.AI.Config` - Model resolution
- `Jido.AI.Helpers` - Message building

## Implementation Status

- [x] Skill setup
- [x] Mount callback
- [x] CallWithTools action
- [x] ExecuteTool action
- [x] ListTools action
- [x] Auto-execution logic
- [x] Unit tests

## Test Results

- **Total Tests:** 32 (30 passing, 2 skipped - require LLM API access)
- **Full Test Suite:** 1498 tests passing
- **Credo:** No issues

---

*Completed: 2025-01-06*
