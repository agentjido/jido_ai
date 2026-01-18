# Feature Planning: Zoi Schema Migration for Skills (Phase 9.2)

**Date**: 2025-01-17
**Feature Branch**: `feature/accuracy-phase-9-2-zoi-schemas`
**Status**: In Progress

## Problem Statement

The current Jido.AI skill actions use NimbleOptions-style schemas for parameter validation. Jido V2 has standardized on Zoi schemas for better type safety, richer validation rules, and consistency with the rest of the ecosystem. Migrating to Zoi provides:

1. **Better type safety** - Zoi generates proper Elixir type specs
2. **Richer validation** - Custom validators, transforms, and complex type composition
3. **Consistency** - Aligned with Jido V2 patterns used in directives and strategies
4. **Better error messages** - More descriptive validation errors

## Solution Overview

Migrate all skill actions from NimbleOptions schemas to Zoi schemas. The Jido.Action macro already supports both formats transparently, so this is a straightforward schema replacement with no behavioral changes.

### Skills to Migrate

| Skill | Actions |
|-------|---------|
| LLM | Chat, Complete, Embed |
| Planning | Decompose, Plan, Prioritize |
| Reasoning | Analyze, Explain, Infer |
| Tool Calling | CallWithTools, ExecuteTool, ListTools |
| Streaming | StartStream, ProcessTokens, EndStream |

## Agent Consultations Performed

- **Explore Agent**: Researched current schema usage in skill actions
- **Explore Agent**: Found Zoi schema examples in directives and strategies
- **Explore Agent**: Verified Jido.Action supports both NimbleOptions and Zoi

## Technical Details

### Migration Pattern

**Before (NimbleOptions)**:
```elixir
schema: [
  prompt: [type: :string, required: true, doc: "The user prompt"],
  max_tokens: [type: :integer, default: 1024],
  temperature: [type: :float, default: 0.7]
]
```

**After (Zoi)**:
```elixir
schema: Zoi.object(%{
  prompt: Zoi.string(description: "The user prompt"),
  max_tokens: Zoi.integer(description: "Maximum tokens") |> Zoi.default(1024),
  temperature: Zoi.float(description: "Sampling temperature") |> Zoi.default(0.7)
})
```

### Type Mappings

| NimbleOptions | Zoi |
|---------------|-----|
| `type: :string` | `Zoi.string()` |
| `type: :integer` | `Zoi.integer()` |
| `type: :float` | `Zoi.float()` or `Zoi.number()` |
| `type: :boolean` | `Zoi.boolean()` |
| `type: {:list, :string}` | `Zoi.list(Zoi.string())` |
| `type: {:map, :string, :integer}` | `Zoi.map(Zoi.string(), Zoi.integer())` |
| `required: true` | `Zoi.string() |> Zoi.required()` (or implied by no default) |
| `required: false` | `Zoi.string() |> Zoi.optional()` |
| `default: value` | `Zoi.string() |> Zoi.default(value)` |
| `doc: "text"` | `Zoi.string(description: "text")` |

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_ai/skills/llm/actions/chat.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/llm/actions/complete.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/llm/actions/embed.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/planning/actions/decompose.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/planning/actions/plan.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/planning/actions/prioritize.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/reasoning/actions/analyze.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/reasoning/actions/explain.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/reasoning/actions/infer.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/tool_calling/actions/execute_tool.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/tool_calling/actions/list_tools.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/streaming/actions/start_stream.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/streaming/actions/process_tokens.ex` | Replace schema with Zoi |
| `lib/jido_ai/skills/streaming/actions/end_stream.ex` | Replace schema with Zoi |

### Test Files

| File | Purpose |
|------|---------|
| `test/jido_ai/skills/schema_migration_test.exs` | **NEW** - Verify schema validation works |

## Success Criteria

1. ✅ All 15 skill actions use Zoi schemas
2. ✅ All existing tests pass
3. ✅ Schema validation works correctly
4. ✅ No breaking changes to public API
5. ✅ Error messages are preserved or improved

## Implementation Plan

### Step 1: Migrate LLM Skill Actions (9.2.1)

**Files**:
- `lib/jido_ai/skills/llm/actions/chat.ex`
- `lib/jido_ai/skills/llm/actions/complete.ex`
- `lib/jido_ai/skills/llm/actions/embed.ex`

**Changes**:
- Replace `schema: [...]` with `schema: Zoi.object(%{...})`
- Update type mappings as per migration pattern
- Preserve all field descriptions in `description:` option

### Step 2: Migrate Planning Skill Actions (9.2.2)

**Files**:
- `lib/jido_ai/skills/planning/actions/decompose.ex`
- `lib/jido_ai/skills/planning/actions/plan.ex`
- `lib/jido_ai/skills/planning/actions/prioritize.ex`

### Step 3: Migrate Reasoning Skill Actions (9.2.3)

**Files**:
- `lib/jido_ai/skills/reasoning/actions/analyze.ex`
- `lib/jido_ai/skills/reasoning/actions/explain.ex`
- `lib/jido_ai/skills/reasoning/actions/infer.ex`

### Step 4: Migrate Tool Calling Skill Actions (9.2.4)

**Files**:
- `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex`
- `lib/jido_ai/skills/tool_calling/actions/execute_tool.ex`
- `lib/jido_ai/skills/tool_calling/actions/list_tools.ex`

### Step 5: Migrate Streaming Skill Actions (9.2.5)

**Files**:
- `lib/jido_ai/skills/streaming/actions/start_stream.ex`
- `lib/jido_ai/skills/streaming/actions/process_tokens.ex`
- `lib/jido_ai/skills/streaming/actions/end_stream.ex`

### Step 6: Write Integration Tests (9.2.6)

**File**: `test/jido_ai/skills/schema_migration_test.exs`

**Tests**:
- Verify each action accepts valid inputs
- Verify each action rejects invalid inputs
- Verify default values are applied
- Verify type validation works correctly

## Notes/Considerations

### Key Finding

**Jido.Action already supports both NimbleOptions and Zoi schemas**. The migration is a simple schema replacement with no behavioral changes required.

### Validation Behavior

The Jido.Action.Schema module provides unified validation for both schema types. No changes to action behavior are needed.

### Backward Compatibility

Since the validation behavior is the same, this is a drop-in replacement. Existing code using these actions will continue to work without modification.

## Status

### Completed ✅

- Feature branch created
- Research completed on NimbleOptions → Zoi migration

### In Progress 🔄

- Creating feature planning document

### Next Steps 📋

1. Migrate LLM skill actions
2. Migrate Planning skill actions
3. Migrate Reasoning skill actions
4. Migrate Tool Calling skill actions
5. Migrate Streaming skill actions
6. Write integration tests
7. Run all tests to verify
