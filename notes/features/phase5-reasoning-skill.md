# Feature: Phase 5 Section 5.2 - Reasoning Skill

**Branch**: `feature/phase5-reasoning-skill`
**Status**: Implementation Complete
**Priority**: High

## Problem Statement

Jido.AI currently provides basic LLM capabilities through the LLM Skill (Chat, Complete, Embed actions), but lacks a composable `Jido.Skill` for higher-level reasoning operations. This creates several gaps:

1. **No dedicated reasoning interface** - Agents cannot easily add analytical and inference capabilities as a skill
2. **No structured reasoning actions** - Common reasoning patterns like analysis, inference, and explanation aren't available as discrete actions
3. **Inconsistent prompt engineering** - Developers must build custom prompts for reasoning tasks, leading to inconsistent results
4. **No standardized output format** - Reasoning results come in various formats without a common structure

**Impact**: Developers must build custom solutions for analytical tasks, or are forced to use more complex ReAct agents when simple reasoning operations would suffice.

## Solution Overview

Create `Jido.AI.Skills.Reasoning` - a Jido.Skill that provides Analyze, Infer, and Explain actions with specialized system prompts for each reasoning task.

## Technical Details

### File Structure

```
lib/jido_ai/skills/reasoning/
├── reasoning.ex               # Main skill definition
├── actions/
│   ├── analyze.ex             # Analyze action
│   ├── infer.ex               # Infer action
│   └── explain.ex             # Explain action
test/jido_ai/skills/reasoning/
├── reasoning_skill_test.exs   # Skill tests
└── actions/
    ├── analyze_action_test.exs
    ├── infer_action_test.exs
    └── explain_action_test.exs
```

### Dependencies

- **Existing**: `jido` (>= 2.0.0), `req_llm`, `jido_ai`, `nimble_options`
- **None required** - Uses existing dependencies

### Key Design Decisions

1. **Direct ReqLLM Calls** - No adapter layer, call ReqLLM functions directly
2. **Config Integration** - Use `Jido.AI.Config.resolve_model/1` for model aliases (default to `:reasoning`)
3. **NimbleOptions Schemas** - Follow existing Jido.Action patterns
4. **Specialized System Prompts** - Each action has a carefully crafted system prompt
5. **No State** - Skill is stateless
6. **Error Handling** - Return `{:ok, result}` | `{:error, reason}` tuples

## Implementation Plan

### 5.2.1 Skill Definition

- [x] 5.2.1.1 Create `lib/jido_ai/skills/reasoning/reasoning.ex`
- [x] 5.2.1.2 Define `use Jido.Skill` with proper configuration
- [x] 5.2.1.3 Add module documentation with examples
- [x] 5.2.1.4 Implement `skill_spec/1` for configuration
- [x] 5.2.1.5 Implement `mount/2` callback

### 5.2.2 Analyze Action

- [x] 5.2.2.1 Create `lib/jido_ai/skills/reasoning/actions/analyze.ex`
- [x] 5.2.2.2 Define `use Jido.Action` with name "reasoning_analyze"
- [x] 5.2.2.3 Define NimbleOptions schema with fields:
  - model (optional, default: :reasoning)
  - input (required, string)
  - analysis_type (optional, enum: [:sentiment, :topics, :entities, :summary, :custom], default: :summary)
  - custom_prompt (optional, string, for custom analysis)
  - max_tokens (optional, default: 2048)
  - temperature (optional, default: 0.3)
  - timeout (optional)
- [x] 5.2.2.4 Implement `run/2` with specialized system prompts
- [x] 5.2.2.5 Add comprehensive documentation

### 5.2.3 Infer Action

- [x] 5.2.3.1 Create `lib/jido_ai/skills/reasoning/actions/infer.ex`
- [x] 5.2.3.2 Define `use Jido.Action` with name "reasoning_infer"
- [x] 5.2.3.3 Define NimbleOptions schema with fields:
  - model (optional, default: :reasoning)
  - premises (required, string)
  - question (required, string)
  - context (optional, string)
  - max_tokens (optional, default: 2048)
  - temperature (optional, default: 0.3)
  - timeout (optional)
- [x] 5.2.3.4 Implement `run/2` with inference system prompt
- [x] 5.2.3.5 Add comprehensive documentation

### 5.2.4 Explain Action

- [x] 5.2.4.1 Create `lib/jido_ai/skills/reasoning/actions/explain.ex`
- [x] 5.2.4.2 Define `use Jido.Action` with name "reasoning_explain"
- [x] 5.2.4.3 Define NimbleOptions schema with fields:
  - model (optional, default: :reasoning)
  - topic (required, string)
  - detail_level (optional, enum: [:basic, :intermediate, :advanced], default: :intermediate)
  - audience (optional, string)
  - include_examples (optional, boolean, default: true)
  - max_tokens (optional, default: 2048)
  - temperature (optional, default: 0.5)
  - timeout (optional)
- [x] 5.2.4.4 Implement `run/2` with explanation system prompts
- [x] 5.2.4.5 Add comprehensive documentation

### 5.2.5 Unit Tests

- [x] 5.2.5.1 Create test files for skill and actions
- [x] 5.2.5.2 Test skill definition and mount/2
- [x] 5.2.5.3 Test Analyze action with each analysis_type
- [x] 5.2.5.4 Test Infer action with premises and question
- [x] 5.2.5.5 Test Explain action with each detail_level
- [x] 5.2.5.6 Test error handling for all actions

## Success Criteria

1. Skill compiles without warnings
2. All three actions (Analyze, Infer, Explain) are defined and valid
3. Actions use NimbleOptions schemas for validation
4. Actions call ReqLLM directly
5. Model aliases work via `Jido.AI.Config.resolve_model/1`
6. Each action uses specialized system prompts
7. All tests pass
8. Documentation includes usage examples

## Usage Examples

### Analyze Action

```elixir
{:ok, result} = Jido.Exec.run(
  Jido.AI.Skills.Reasoning.Actions.Analyze,
  %{
    input: "I loved the product! Great quality.",
    analysis_type: :sentiment
  }
)
```

### Infer Action

```elixir
{:ok, result} = Jido.Exec.run(
  Jido.AI.Skills.Reasoning.Actions.Infer,
  %{
    premises: "All cats are mammals. Fluffy is a cat.",
    question: "Is Fluffy a mammal?"
  }
)
```

### Explain Action

```elixir
{:ok, result} = Jido.Exec.run(
  Jido.AI.Skills.Reasoning.Actions.Explain,
  %{
    topic: "GenServer",
    detail_level: :basic
  }
)
```

## Critical Files for Implementation

- `lib/jido_ai/skills/llm/llm.ex` - Skill pattern to follow
- `lib/jido_ai/skills/llm/actions/chat.ex` - Action pattern to follow
- `lib/jido_ai/helpers.ex` - Helper utilities
- `lib/jido_ai/config.ex` - Model resolution
- `test/jido_ai/skills/llm/llm_skill_test.exs` - Test pattern

## Current Status

**Status**: Implementation Complete
**Test Results**: All 23 tests passing
**Files Created**:
- `lib/jido_ai/skills/reasoning/reasoning.ex`
- `lib/jido_ai/skills/reasoning/actions/analyze.ex`
- `lib/jido_ai/skills/reasoning/actions/infer.ex`
- `lib/jido_ai/skills/reasoning/actions/explain.ex`
- `test/jido_ai/skills/reasoning/reasoning_skill_test.exs`
- `test/jido_ai/skills/reasoning/actions/analyze_action_test.exs`
- `test/jido_ai/skills/reasoning/actions/infer_action_test.exs`
- `test/jido_ai/skills/reasoning/actions/explain_action_test.exs`

**Next Steps**: Awaiting commit and merge approval
**Target Branch**: `feature/phase5-reasoning-skill`
**Merge Target**: `v2`
