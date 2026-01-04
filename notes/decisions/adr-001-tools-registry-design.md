# ADR-001: Unified Tools Registry Design

**Date**: 2026-01-04
**Status**: Accepted
**Deciders**: Developer

## Context

Jido.AI needs to manage two types of callable tools for LLM interactions:

1. **Jido.Actions** - Heavyweight modules with lifecycle hooks, output schemas, and workflow integration
2. **Jido.AI.Tools.Tool** - Lightweight modules for simple LLM functions

When an LLM returns a tool call like `{"name": "calculator", "arguments": {...}}`, the system needs to:
1. Look up the corresponding module by name
2. Determine if it's an Action or Tool
3. Execute it appropriately

### Existing State

`Jido.AI.ToolAdapter` already has an Agent-based registry for Actions:
- `register_action/1`, `register_actions/1`
- `get_action/1`, `list_actions/0`
- `to_tools/0` for ReqLLM conversion

However, this registry only handles Actions, not the new lightweight Tools.

## Decision

Create a new `Jido.AI.Tools.Registry` module as the **unified registry** for both Actions and Tools.

### Design Choices

1. **Separate module from ToolAdapter**
   - `Tools.Registry` handles registration and lookup for both types
   - `ToolAdapter` remains focused on Action → ReqLLM.Tool conversion
   - Clear separation of concerns

2. **Agent-based runtime registry**
   - Uses Elixir Agent for runtime state management
   - Auto-starts when first accessed (like existing ToolAdapter pattern)
   - Suitable for dynamic tool registration in running systems

3. **Unified API with type discrimination**
   - `register/1` auto-detects Action vs Tool by checking behaviors
   - `register_action/1` and `register_tool/1` for explicit registration
   - `get/1` returns `{:ok, {type, module}}` where type is `:action` or `:tool`
   - `list_all/0`, `list_actions/0`, `list_tools/0` for filtered listing

4. **Validation on registration**
   - Validates that modules implement the correct behavior
   - Rejects modules that don't implement `Jido.Action` or `Jido.AI.Tools.Tool`

5. **ReqLLM conversion delegation**
   - `to_reqllm_tools/0` uses `ToolAdapter.from_action/1` for Actions
   - Uses `Tool.to_reqllm_tool/1` for Tools
   - Returns unified list of `ReqLLM.Tool` structs

## Consequences

### Positive

- **Single source of truth** for tool lookup during execution
- **Type-aware lookup** enables correct execution dispatch (Jido.Exec vs run/2)
- **Clean separation** - ToolAdapter stays focused on conversion, Registry handles management
- **Extensible** - Easy to add new tool types in the future

### Negative

- **Two registries** - ToolAdapter's registry becomes redundant (but remains for backwards compatibility)
- **Migration** - Existing code using ToolAdapter's registry still works but should migrate to Tools.Registry

### Neutral

- **No compile-time registration** - Plan mentioned `@tools` attribute pattern but runtime Agent is simpler and sufficient for current needs

## Alternatives Considered

### 1. Extend ToolAdapter to handle both types

**Rejected because:**
- ToolAdapter's name and purpose is specifically "adapting Actions"
- Adding Tool support would conflate conversion with registration
- Would require significant API changes

### 2. Keep separate registries

**Rejected because:**
- Lookup would require checking both registries
- No unified view of available tools
- Complicates executor implementation

### 3. Compile-time registry via module attributes

**Rejected because:**
- Less flexible for runtime tool registration
- More complex implementation
- Runtime Agent pattern already established in codebase

## Implementation Notes

```elixir
# Registration
Jido.AI.Tools.Registry.register(MyApp.Actions.Calculator)  # auto-detects Action
Jido.AI.Tools.Registry.register(MyApp.Tools.Search)        # auto-detects Tool

# Lookup
{:ok, {:action, MyApp.Actions.Calculator}} = Registry.get("calculator")
{:ok, {:tool, MyApp.Tools.Search}} = Registry.get("search")

# Listing
Registry.list_all()     # [{"calculator", :action, Module}, {"search", :tool, Module}]
Registry.list_actions() # [{"calculator", Module}]
Registry.list_tools()   # [{"search", Module}]

# Conversion for LLM
tools = Registry.to_reqllm_tools()  # [%ReqLLM.Tool{}, ...]
```

## Related

- Phase 2 Section 2.2: Tool Registry
- Phase 2 Section 2.3: Tool Executor (will use Registry for lookup)
- `lib/jido_ai/tool_adapter.ex` - Existing Action registry (to be superseded)
