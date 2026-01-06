# Phase 5.3: Planning Skill Implementation

## Problem Statement

The Jido.AI framework needs a Planning Skill that provides goal decomposition, planning, and task prioritization capabilities. This skill will allow agents to break down complex goals into manageable steps, generate structured plans, and prioritize tasks based on given criteria.

## Solution Overview

Create a `Jido.AI.Skills.Planning` skill following the established pattern from LLM and Reasoning skills:
- Use `Jido.Skill` behavior
- Call ReqLLM directly (no adapter layer)
- Use `Jido.AI.Config` for model resolution
- Use `Jido.AI.Helpers` for common patterns
- Provide three actions: `Plan`, `Decompose`, `Prioritize`

## Technical Details

### File Structure

```
lib/jido_ai/skills/planning/
├── planning.ex          # Main skill module
└── actions/
    ├── plan.ex          # Plan action
    ├── decompose.ex     # Decompose action
    └── prioritize.ex    # Prioritize action
```

### Test Structure

```
test/jido_ai/skills/planning/
├── planning_skill_test.exs
└── actions/
    ├── plan_action_test.exs
    ├── decompose_action_test.exs
    └── prioritize_action_test.exs
```

### Dependencies

- `Jido.Skill` - Base skill behavior
- `Jido.Action` - Base action behavior
- `ReqLLM` - Direct LLM calls
- `Jido.AI.Config` - Model resolution
- `Jido.AI.Helpers` - Common patterns

## Success Criteria

- [ ] Planning skill module created with `Jido.Skill` behavior
- [ ] All three actions implemented (Plan, Decompose, Prioritize)
- [ ] Actions call ReqLLM directly
- [ ] Model aliases supported via `Jido.AI.Config`
- [ ] Comprehensive test coverage (unit tests for all actions)
- [ ] All tests passing
- [ ] Code formatted with `mix format`
- [ ] No Credo warnings

## Implementation Plan

### Step 1: Create Planning Skill Module
- [ ] Create `lib/jido_ai/skills/planning/planning.ex`
- [ ] Use `Jido.Skill` with name "planning"
- [ ] Define actions list (Plan, Decompose, Prioritize)
- [ ] Implement `mount/2` callback
- [ ] Implement `skill_spec/1` function

### Step 2: Create Plan Action
- [ ] Create `lib/jido_ai/skills/planning/actions/plan.ex`
- [ ] Accept `goal`, `constraints`, `resources` parameters
- [ ] Build specialized planning prompt
- [ ] Call `ReqLLM.Generation.generate_text/3`
- [ ] Return structured plan with steps and dependencies

### Step 3: Create Decompose Action
- [ ] Create `lib/jido_ai/skills/planning/actions/decompose.ex`
- [ ] Accept `goal`, `max_depth` parameters
- [ ] Build decomposition prompt
- [ ] Return hierarchical goal structure

### Step 4: Create Prioritize Action
- [ ] Create `lib/jido_ai/skills/planning/actions/prioritize.ex`
- [ ] Accept `tasks`, `criteria` parameters
- [ ] Build prioritization prompt
- [ ] Return ordered task list with priority scores

### Step 5: Create Tests
- [ ] Test planning skill module
- [ ] Test Plan action with various inputs
- [ ] Test Decompose action with different depths
- [ ] Test Prioritize action with different criteria
- [ ] Test error handling

## Status

**Current Status:** ✅ Complete

**What works:**
- All skill and action modules implemented
- All 33 tests passing (22 unit tests, 11 integration tests requiring LLM access)
- No Credo warnings for Planning Skill files
- `:planning` model alias added to Config

**What's next:** Ready for review and merge

**How to test:** Run `mix test test/jido_ai/skills/planning/`

---

*Last updated: 2025-01-06*
