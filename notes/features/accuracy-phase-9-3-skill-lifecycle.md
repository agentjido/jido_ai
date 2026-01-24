# Feature Planning: Enhanced Skill Lifecycle (Phase 9.3)

**Date**: 2025-01-18
**Feature Branch**: `feature/accuracy-phase-9-3-skill-lifecycle`
**Status**: In Progress

## Problem Statement

The current Jido.AI skill implementations have basic lifecycle support but are missing several Jido V2 lifecycle callbacks that provide better integration with the agent runtime:

1. **`router/1`** - No signal routing defined for actions
2. **`handle_signal/2`** - No pre-processing of incoming signals
3. **`transform_result/3`** - No post-processing of action results
4. **`signal_patterns/0`** - Relying on default empty implementation
5. **`schema/0`** - Relying on default nil implementation (no state schema)

Adding these callbacks provides:
- **Better signal routing** - Signals can be routed to appropriate actions
- **Signal interception** - Skills can pre-process or override signal handling
- **Result transformation** - Skills can modify results before returning to caller
- **Documentation** - signal_patterns document which signals the skill handles
- **Type safety** - schema/0 defines skill state structure with Zoi

## Solution Overview

Add the missing lifecycle callbacks to all 5 skills (LLM, Planning, Reasoning, Tool Calling, Streaming):

1. **`router/1`** - Map signal patterns to action modules
2. **`handle_signal/2`** - Optional pre-processing hook (default continue)
3. **`transform_result/3`** - Optional result formatting
4. **`signal_patterns/0`** - List of signal patterns the skill responds to
5. **`schema/0`** - Zoi schema for skill state defaults

### Skills to Enhance

| Skill | Actions | Signal Patterns |
|-------|---------|-----------------|
| LLM | Chat, Complete, Embed | `llm.chat`, `llm.complete`, `llm.embed` |
| Planning | Decompose, Plan, Prioritize | `planning.decompose`, `planning.plan`, `planning.prioritize` |
| Reasoning | Analyze, Explain, Infer | `reasoning.analyze`, `reasoning.explain`, `reasoning.infer` |
| Tool Calling | CallWithTools, ExecuteTool, ListTools | `tool.call`, `tool.execute`, `tool.list` |
| Streaming | StartStream, ProcessTokens, EndStream | `stream.start`, `stream.process`, `stream.end` |

## Agent Consultations Performed

- **Research**: Reviewed Jido.Skill module for lifecycle callback definitions
- **Research**: Examined existing skill implementations in jido_ai
- **Research**: Reviewed Jido.Skill behavior for @optional_callbacks

## Technical Details

### Lifecycle Callbacks (from Jido.Skill)

```elixir
# From Jido.Skill behavior
@callback router(config :: map()) :: term()
@callback handle_signal(signal :: term(), context :: map()) ::
            {:ok, term()} | {:ok, {:override, term()}} | {:error, term()}
@callback transform_result(action :: module() | String.t(), result :: term(), context :: map()) ::
            term()
```

### Optional Callbacks

```elixir
@optional_callbacks [
  mount: 2,
  router: 1,
  handle_signal: 2,
  transform_result: 3,
  child_spec: 1,
  subscriptions: 2
]
```

### Default Implementations

```elixir
# From Jido.Skill
def router(_config), do: nil
def handle_signal(_signal, _context), do: {:ok, nil}
def transform_result(_action, result, _context), do: result
def signal_patterns, do: @validated_opts[:signal_patterns] || []
```

### Router Pattern

The router should return a list of `{signal_pattern, action_module}` tuples:

```elixir
def router(_config) do
  [
    {"llm.chat", Jido.AI.Skills.LLM.Actions.Chat},
    {"llm.complete", Jido.AI.Skills.LLM.Actions.Complete},
    {"llm.embed", Jido.AI.Skills.LLM.Actions.Embed}
  ]
end
```

### Signal Patterns Pattern

```elixir
def signal_patterns do
  [
    "llm.chat",
    "llm.complete",
    "llm.embed"
  ]
end
```

### Schema Pattern

Define skill state schema using Zoi:

```elixir
def schema do
  Zoi.object(%{
    default_model:
      Zoi.atom(description: "Default model alias (:fast, :capable, :reasoning)")
      |> Zoi.default(:fast),
    default_max_tokens:
      Zoi.integer(description: "Default max tokens for generation")
      |> Zoi.default(1024),
    default_temperature:
      Zoi.float(description: "Default sampling temperature")
      |> Zoi.default(0.7)
  })
end
```

### Transform Result Pattern

```elixir
def transform_result(_action, result, _context) do
  # Add metadata or normalize result format
  result
end
```

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_ai/skills/llm/llm.ex` | Add router, handle_signal, transform_result, signal_patterns, schema |
| `lib/jido_ai/skills/planning/planning.ex` | Add router, handle_signal, transform_result, signal_patterns, schema |
| `lib/jido_ai/skills/reasoning/reasoning.ex` | Add router, handle_signal, transform_result, signal_patterns, schema |
| `lib/jido_ai/skills/tool_calling/tool_calling.ex` | Add router, handle_signal, transform_result, signal_patterns, schema |
| `lib/jido_ai/skills/streaming/streaming.ex` | Add router, handle_signal, transform_result, signal_patterns, schema |

### Test Files

| File | Purpose |
|------|---------|
| `test/jido_ai/skills/llm/llm_skill_test.exs` | **NEW** - Test LLM skill lifecycle |
| `test/jido_ai/skills/planning/planning_skill_test.exs` | **NEW** - Test Planning skill lifecycle |
| `test/jido_ai/skills/reasoning/reasoning_skill_test.exs` | **NEW** - Test Reasoning skill lifecycle |
| `test/jido_ai/skills/tool_calling/tool_calling_skill_test.exs` | **NEW** - Test Tool Calling skill lifecycle |
| `test/jido_ai/skills/streaming/streaming_skill_test.exs` | **NEW** - Test Streaming skill lifecycle |

## Success Criteria

1. ✅ All 5 skills implement `router/1` callback
2. ✅ All 5 skills implement `handle_signal/2` callback
3. ✅ All 5 skills implement `transform_result/3` callback
4. ✅ All 5 skills implement `signal_patterns/0` function
5. ✅ All 5 skills implement `schema/0` function with Zoi schema
6. ✅ All new tests pass
7. ✅ No breaking changes to public API

## Implementation Plan

### Step 1: LLM Skill Lifecycle Enhancement (9.3.1)

**File**: `lib/jido_ai/skills/llm/llm.ex`

**Add**:
- `router/1` - Map llm.chat/complete/embed to actions
- `handle_signal/2` - Return `{:ok, :continue}` for now
- `transform_result/3` - Pass through result for now
- `signal_patterns/0` - List LLM signal patterns
- `schema/0` - Zoi schema for LLM skill state

### Step 2: Planning Skill Lifecycle Enhancement (9.3.2)

**File**: `lib/jido_ai/skills/planning/planning.ex`

**Add**:
- `router/1` - Map planning.* signals to actions
- `handle_signal/2` - Return `{:ok, :continue}`
- `transform_result/3` - Pass through result
- `signal_patterns/0` - List planning signal patterns
- `schema/0` - Zoi schema for planning skill state

### Step 3: Reasoning Skill Lifecycle Enhancement (9.3.3)

**File**: `lib/jido_ai/skills/reasoning/reasoning.ex`

**Add**:
- `router/1` - Map reasoning.* signals to actions
- `handle_signal/2` - Return `{:ok, :continue}`
- `transform_result/3` - Pass through result
- `signal_patterns/0` - List reasoning signal patterns
- `schema/0` - Zoi schema for reasoning skill state

### Step 4: Tool Calling Skill Lifecycle Enhancement (9.3.4)

**File**: `lib/jido_ai/skills/tool_calling/tool_calling.ex`

**Add**:
- `router/1` - Map tool.* signals to actions
- `handle_signal/2` - Return `{:ok, :continue}`
- `transform_result/3` - Pass through result
- `signal_patterns/0` - List tool signal patterns
- `schema/0` - Zoi schema for tool calling skill state

### Step 5: Streaming Skill Lifecycle Enhancement (9.3.5)

**File**: `lib/jido_ai/skills/streaming/streaming.ex`

**Add**:
- `router/1` - Map stream.* signals to actions
- `handle_signal/2` - Return `{:ok, :continue}`
- `transform_result/3` - Pass through result
- `signal_patterns/0` - List streaming signal patterns
- `schema/0` - Zoi schema for streaming skill state

### Step 6: Write Unit Tests (9.3.6)

**Files**: New test files for each skill

**Tests**:
- `router/1` returns correct route mappings
- `handle_signal/2` returns `{:ok, :continue}`
- `transform_result/3` returns result unchanged
- `signal_patterns/0` returns expected patterns
- `schema/0` returns valid Zoi schema
- `skill_spec/1` includes all lifecycle data

## Notes/Considerations

### Minimal Implementation

For this phase, we're implementing the callbacks with minimal behavior:
- `router/1` returns signal-to-action mappings
- `handle_signal/2` returns `{:ok, :continue}` (no interception)
- `transform_result/3` returns result unchanged

Future phases can add more sophisticated behavior like:
- Signal interception and overriding
- Result transformation and enrichment
- Error handling and recovery

### Backward Compatibility

Since these are `@optional_callbacks` in Jido.Skill, adding them is backward compatible. Existing code using these skills will continue to work.

### Signal Naming Convention

Using dot-notation for signal types:
- `llm.chat` - Chat action
- `llm.complete` - Complete action
- `planning.plan` - Plan action
- `reasoning.analyze` - Analyze action
- `tool.call` - Tool call action
- `stream.start` - Start stream action

## Status

### In Progress 🔄

- Feature branch created
- Research completed on Jido.Skill lifecycle callbacks
- Planning document created

### Next Steps 📋

1. Implement LLM skill lifecycle callbacks
2. Implement Planning skill lifecycle callbacks
3. Implement Reasoning skill lifecycle callbacks
4. Implement Tool Calling skill lifecycle callbacks
5. Implement Streaming skill lifecycle callbacks
6. Write unit tests for all skills
7. Run tests to verify
8. Create summary document
9. Mark tasks complete in phase 9 plan
