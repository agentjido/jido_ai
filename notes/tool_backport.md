# Tool System Backport Analysis

**Date:** 2026-01-29  
**Scope:** Evaluate whether `jido_ai` tool components should remain LLM-specific or be generalized to `jido_action`/`jido` core.

## Executive Summary

| Component | Recommendation | Rationale |
|-----------|---------------|-----------|
| `Jido.AI.Tools.Registry` | **DELETE** | Redundant with `Jido.Discovery` + minor enhancements |
| `Jido.AI.Tools.Executor` | **PARTIAL BACKPORT** | Parameter normalization is generic; result formatting is LLM-specific |
| `Jido.AI.ToolAdapter` | **KEEP IN jido_ai** | ReqLLM dependency makes this inherently LLM-specific |

---

## 1. Jido.AI.Tools.Registry

**Location:** `lib/jido_ai/tools/registry.ex`  
**Recommendation:** ❌ **DELETE** (replace with `Jido.Discovery`)

### Current Functionality

| Feature | Registry | Discovery |
|---------|----------|-----------|
| Storage mechanism | Agent (mutable) | persistent_term (immutable) |
| Population | Manual `register/1` | Automatic at startup |
| Lookup by name | ✅ `get("calculator")` | ❌ (only by slug) |
| Lookup by slug | ❌ | ✅ `get_action_by_slug/1` |
| List all | ✅ `list_all/0` | ✅ `list_actions/1` |
| Filter by category/tag | ❌ | ✅ Built-in |
| Convert to ReqLLM | ✅ `to_reqllm_tools/0` | ❌ |

### Why Registry is Redundant

1. **Discovery already exists** - `Jido.Discovery.list_actions/1` returns all actions with filtering
2. **Name lookup is trivial** - Actions have `.name()` callback; Discovery returns module refs
3. **"Curated" exposure is a design smell** - If you don't want an action exposed to LLMs, don't give it a tool schema or use a filter

### Migration Path

```elixir
# OLD: Registry-based
Registry.register(MyApp.Calculator)
tools = Registry.to_reqllm_tools()

# NEW: Discovery + ToolAdapter
actions = Jido.Discovery.list_actions(category: :tool)
          |> Enum.map(& &1.module)
tools = ToolAdapter.from_actions(actions)
```

### Required Changes to Discovery

Add to `jido` core:

```elixir
# In Jido.Discovery
def get_action_by_name(name) when is_binary(name) do
  list_actions()
  |> Enum.find(fn %{module: mod} -> mod.name() == name end)
end
```

**Effort:** ~1 hour  
**Breaking change:** Yes (update 5 files that use Registry)

---

## 2. Jido.AI.Tools.Executor

**Location:** `lib/jido_ai/tools/executor.ex`  
**Recommendation:** ⚡ **PARTIAL BACKPORT**

### Feature Analysis

| Feature | LLM-Specific? | Backport? | Notes |
|---------|---------------|-----------|-------|
| Registry lookup | No | ❌ | Use Discovery instead |
| Parameter normalization | **No** | ✅ | Already in `Jido.Action.Tool.convert_params_using_schema/2` |
| Integer→float coercion | No | ✅ | Missing from jido_action |
| Result truncation (10KB) | **Yes** | ❌ | LLMs have token limits |
| Binary→base64 encoding | **Yes** | ❌ | LLMs need text representation |
| Error formatting | Partially | Split | Generic error struct vs LLM-friendly message |
| Credential redaction | **No** | ✅ | Should be in core telemetry |
| Telemetry events | No | ✅ | Already exists in `Jido.Exec.Telemetry` |

### Backport to jido_action

**1. Integer→float coercion** (missing from `Jido.Action.Tool.convert_params_using_schema/2`)

```elixir
# Add to Jido.Action.Tool
defp coerce_to_schema_type(value, :float) when is_integer(value), do: value * 1.0
```

**2. Credential redaction in telemetry**

This is a security concern for ALL action execution, not just LLM tools. Move to `Jido.Exec.Telemetry`:

```elixir
# Move these patterns to Jido.Exec.Telemetry
@sensitive_key_patterns [
  ~r/^api_?key$/i,
  ~r/^password$/i,
  ~r/^secret$/i,
  ~r/^token$/i,
  # ...
]
```

### Keep in jido_ai

**1. Result formatting** (`format_result/1`, `truncate_result/1`, `format_binary/1`)

These are inherently LLM-specific:
- LLMs have context limits → truncation
- LLMs can't process binary → base64 encoding
- LLMs need readable error messages → structured error maps

**2. LLM error formatting** (`format_error/2`, `format_exception/3`)

The error structure `%{error: ..., tool_name: ..., type: ...}` is designed for LLM consumption.

### Recommended Architecture

```
┌─────────────────────────────────────────┐
│            jido_action                  │
├─────────────────────────────────────────┤
│ Jido.Action.Tool                        │
│   - convert_params_using_schema/2  ✓    │
│   - coerce_to_schema_type/2        NEW  │
│   - execute_action/3               ✓    │
├─────────────────────────────────────────┤
│ Jido.Exec.Telemetry                     │
│   - sanitize_params/1              NEW  │
│   - sensitive_key?/1               NEW  │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│              jido_ai                    │
├─────────────────────────────────────────┤
│ Jido.AI.Tools.Executor                  │
│   - format_result/1           (LLM)     │
│   - truncate_result/1         (LLM)     │
│   - format_binary/1           (LLM)     │
│   - format_error/2            (LLM)     │
└─────────────────────────────────────────┘
```

**Effort:** ~3 hours  
**Breaking change:** No (Executor API unchanged)

---

## 3. Jido.AI.ToolAdapter

**Location:** `lib/jido_ai/tool_adapter.ex`  
**Recommendation:** ✅ **KEEP IN jido_ai**

### Why Keep It Here

1. **ReqLLM dependency** - Returns `ReqLLM.Tool.t()` structs, which are LLM-specific
2. **Noop callback pattern** - Tools don't execute via callback; Jido owns execution
3. **Already uses core** - Delegates to `Jido.Action.Schema.to_json_schema/1`

The adapter is pure glue code between Jido and ReqLLM. If `jido_action` had this, it would need to depend on `req_llm`, which violates separation of concerns.

### Alternative: Generic Tool Protocol

If you want tool adapters for multiple AI frameworks (LangChain, Instructor, etc.), consider:

```elixir
# In jido_action
defprotocol Jido.Action.ToolFormat do
  @doc "Convert action to external tool format"
  def to_external(action_module, opts)
end

# In jido_ai
defimpl Jido.Action.ToolFormat, for: Atom do
  def to_external(module, opts) do
    format = Keyword.get(opts, :format, :reqllm)
    case format do
      :reqllm -> Jido.AI.ToolAdapter.from_action(module, opts)
      :langchain -> Jido.AI.LangChainAdapter.from_action(module, opts)
    end
  end
end
```

**Effort:** N/A (keep as-is) or ~4 hours (protocol approach)

---

## Implementation Priority

1. **High Priority:** Backport credential redaction to `Jido.Exec.Telemetry`
   - Security improvement for all action execution
   - ~1 hour

2. **Medium Priority:** Add integer→float coercion to `Jido.Action.Tool`
   - Prevents common type errors from external callers
   - ~30 minutes

3. **Low Priority:** Delete Registry, add `get_action_by_name/1` to Discovery
   - Nice cleanup but Registry works fine
   - ~2 hours + migration

4. **Deferred:** Generic ToolFormat protocol
   - Only if supporting multiple AI frameworks
   - ~4 hours

---

## Files Affected by Registry Removal

If Registry is deleted, update these files:

| File | Change Required |
|------|-----------------|
| `lib/jido_ai/strategy/react.ex` | Use Discovery + ToolAdapter |
| `lib/jido_ai/tools/executor.ex` | Use Discovery.get_action_by_name |
| `lib/jido_ai/skills/tool_calling/tool_calling.ex` | Use Discovery |
| `lib/jido_ai/skills/tool_calling/actions/list_tools.ex` | Use Discovery.list_actions |
| `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex` | Use Discovery + ToolAdapter |

---

## Summary

The tool system has some **good separation** (ToolAdapter is correctly LLM-specific) and some **redundancy** (Registry duplicates Discovery). The main backport opportunities are:

1. **Credential redaction** → belongs in core for security
2. **Type coercion** → already partially done, needs completion
3. **Registry** → can be eliminated in favor of Discovery

The result formatting and LLM error handling should **stay in jido_ai** as they are inherently tied to LLM constraints (token limits, text-only I/O).
