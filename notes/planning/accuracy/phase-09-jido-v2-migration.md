# Phase 9: Jido V2 Migration

This phase migrates Jido.AI to adopt the new Jido V2 patterns including StateOps for state management, enhanced Skills with lifecycle callbacks, and Zoi schemas for validation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Jido V2 Migration                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Old Pattern                    New Pattern                            │
│   ────────────                    ────────────                            │
│   Effects                        → StateOps                              │
│   NimbleOptions schemas          → Zoi schemas                           │
│   Basic Skills                   → Skills with lifecycle callbacks        │
│   Direct state mutation          → Explicit state operations             │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| StateOps Migration | Convert state mutations to explicit StateOp operations |
| Zoi Schema Migration | Convert NimbleOptions schemas to Zoi schemas |
| Skill Lifecycle | Add router, handle_signal, transform_result callbacks |
| Accuracy Pipeline StateOps | Migrate pipeline to use StateOps for state mutations |

---

## 9.1 StateOps Migration for Strategies

Update strategies to use the new StateOps pattern for explicit state mutations.

### 9.1.1 Strategy StateOps Integration

Update strategies to use StateOps instead of direct state manipulation.

- [x] 9.1.1.1 Update `lib/jido_ai/strategy/react.ex` to use StateOps
- [x] 9.1.1.2 Import `Jido.Agent.StateOp` for state operation constructors
- [x] 9.1.1.3 Replace direct state mutations with `StateOp.SetState`
- [x] 9.1.1.4 Use `StateOp.SetPath` for nested state updates
- [x] 9.1.1.5 Return `{:ok, result, state_ops}` tuples from strategy commands
- [x] 9.1.1.6 Apply state ops via `Jido.Agent.StateOps.apply_state_ops/2`

### 9.1.2 Strategy StateOps Patterns

Define common state operation patterns for strategies.

- [x] 9.1.2.1 Create `lib/jido_ai/strategy/state_ops_helpers.ex`
- [x] 9.1.2.2 Implement `update_strategy_state/2` helper
- [x] 9.1.2.3 Implement `set_iteration_status/2` helper
- [x] 9.1.2.4 Implement `append_conversation/2` helper
- [x] 9.1.2.5 Implement `set_pending_tools/2` helper
- [x] 9.1.2.6 Implement `clear_pending_tools/1` helper

### 9.1.3 Unit Tests for StateOps Migration

- [x] Test StateOp.SetState updates strategy state correctly
- [x] Test StateOp.SetPath updates nested state values
- [x] Test state ops are applied in order
- [x] Test helpers produce correct state operations
- [x] Test strategy returns correct state ops from commands
- [x] Test multiple state ops compose correctly

**Section 9.1 Status: Complete (79 tests passing, 0 failures)**

---

## 9.2 Zoi Schema Migration for Skills

Convert skill actions from NimbleOptions-style schemas to Zoi schemas for consistency with Jido V2.

**Status**: Complete (2025-01-17)
**Summary**: All 15 skill actions migrated to Zoi schemas. See `notes/summaries/accuracy-phase-9-2-zoi-schemas.md` for details.

### 9.2.1 LLM Skill Schema Migration

Update LLM skill actions to use Zoi schemas.

- [x] 9.2.1.1 Update `lib/jido_ai/skills/llm/actions/chat.ex`
- [x] 9.2.1.2 Replace NimbleOptions schema with `@schema Zoi.struct(...)`
- [x] 9.2.1.3 Add `@type t()` and `@enforce_keys` from Zoi schema
- [x] 9.2.1.4 Update `lib/jido_ai/skills/llm/actions/complete.ex`
- [x] 9.2.1.5 Replace NimbleOptions schema with Zoi schema
- [x] 9.2.1.6 Update `lib/jido_ai/skills/llm/actions/embed.ex`
- [x] 9.2.1.7 Replace NimbleOptions schema with Zoi schema

### 9.2.2 Planning Skill Schema Migration

Update planning skill actions to use Zoi schemas.

- [x] 9.2.2.1 Update `lib/jido_ai/skills/planning/actions/decompose.ex`
- [x] 9.2.2.2 Replace schema with Zoi struct
- [x] 9.2.2.3 Update `lib/jido_ai/skills/planning/actions/plan.ex`
- [x] 9.2.2.4 Replace schema with Zoi struct
- [x] 9.2.2.5 Update `lib/jido_ai/skills/planning/actions/prioritize.ex`
- [x] 9.2.2.6 Replace schema with Zoi struct

### 9.2.3 Reasoning Skill Schema Migration

Update reasoning skill actions to use Zoi schemas.

- [x] 9.2.3.1 Update `lib/jido_ai/skills/reasoning/actions/analyze.ex`
- [x] 9.2.3.2 Replace schema with Zoi struct
- [x] 9.2.3.3 Update `lib/jido_ai/skills/reasoning/actions/explain.ex`
- [x] 9.2.3.4 Replace schema with Zoi struct
- [x] 9.2.3.5 Update `lib/jido_ai/skills/reasoning/actions/infer.ex`
- [x] 9.2.3.6 Replace schema with Zoi struct

### 9.2.4 Tool Calling Skill Schema Migration

Update tool calling skill actions to use Zoi schemas.

- [x] 9.2.4.1 Update `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex`
- [x] 9.2.4.2 Replace schema with Zoi struct
- [x] 9.2.4.3 Update `lib/jido_ai/skills/tool_calling/actions/execute_tool.ex`
- [x] 9.2.4.4 Replace schema with Zoi struct
- [x] 9.2.4.5 Update `lib/jido_ai/skills/tool_calling/actions/list_tools.ex`
- [x] 9.2.4.6 Replace schema with Zoi struct

### 9.2.5 Streaming Skill Schema Migration

Update streaming skill actions to use Zoi schemas.

- [x] 9.2.5.1 Update `lib/jido_ai/skills/streaming/actions/start_stream.ex`
- [x] 9.2.5.2 Replace schema with Zoi struct
- [x] 9.2.5.3 Update `lib/jido_ai/skills/streaming/actions/process_tokens.ex`
- [x] 9.2.5.4 Replace schema with Zoi struct
- [x] 9.2.5.5 Update `lib/jido_ai/skills/streaming/actions/end_stream.ex`
- [x] 9.2.5.6 Replace schema with Zoi struct

### 9.2.6 Unit Tests for Schema Migration

- [x] Test Zoi schema validation accepts valid inputs
- [x] Test Zoi schema validation rejects invalid inputs
- [x] Test schema coercion works correctly
- [x] Test default values are applied
- [x] Test required field validation
- [x] Test type validation for each field

---

## 9.3 Enhanced Skill Lifecycle

Add new lifecycle callbacks to skills for better integration with Jido V2.

**Status**: Complete (2025-01-18)
**Summary**: All 5 skills now implement lifecycle callbacks. See `notes/summaries/accuracy-phase-9-3-skill-lifecycle.md` for details.

### 9.3.1 LLM Skill Lifecycle Enhancement

Add lifecycle callbacks to LLM skill.

- [x] 9.3.1.1 Update `lib/jido_ai/skills/llm/llm.ex`
- [x] 9.3.1.2 Implement `router/1` callback for signal routing
  - Map "llm.chat" → Chat action
  - Map "llm.complete" → Complete action
  - Map "llm.embed" → Embed action
- [x] 9.3.1.3 Add `transform_result/3` for response formatting
- [x] 9.3.1.4 Add schema for skill state defaults
- [x] 9.3.1.5 Add signal_patterns for LLM signals

### 9.3.2 Planning Skill Lifecycle Enhancement

Add lifecycle callbacks to planning skill.

- [x] 9.3.2.1 Update `lib/jido_ai/skills/planning/planning.ex`
- [x] 9.3.2.2 Implement `router/1` callback
- [x] 9.3.2.3 Add `handle_signal/2` for planning-specific signals
- [x] 9.3.2.4 Add schema for plan state tracking
- [x] 9.3.2.5 Add signal_patterns for planning signals

### 9.3.3 Reasoning Skill Lifecycle Enhancement

Add lifecycle callbacks to reasoning skill.

- [x] 9.3.3.1 Update `lib/jido_ai/skills/reasoning/reasoning.ex`
- [x] 9.3.3.2 Implement `router/1` callback
- [x] 9.3.3.3 Add `transform_result/3` for reasoning results
- [x] 9.3.3.4 Add schema for reasoning state
- [x] 9.3.3.5 Add signal_patterns for reasoning signals

### 9.3.4 Tool Calling Skill Lifecycle Enhancement

Add lifecycle callbacks to tool calling skill.

- [x] 9.3.4.1 Update `lib/jido_ai/skills/tool_calling/tool_calling.ex`
- [x] 9.3.4.2 Implement `router/1` callback
- [x] 9.3.4.3 Add `handle_signal/2` for tool execution signals
- [x] 9.3.4.4 Add schema for tool registry state
- [x] 9.3.4.5 Add signal_patterns for tool signals

### 9.3.5 Streaming Skill Lifecycle Enhancement

Add lifecycle callbacks to streaming skill.

- [x] 9.3.5.1 Update `lib/jido_ai/skills/streaming/streaming.ex`
- [x] 9.3.5.2 Implement `router/1` callback
- [x] 9.3.5.3 Add `handle_signal/2` for stream signals
- [x] 9.3.5.4 Add schema for stream state tracking
- [x] 9.3.5.5 Add signal_patterns for streaming signals

### 9.3.6 Unit Tests for Skill Lifecycle

- [x] Test router/1 returns correct route mappings
- [x] Test handle_signal/2 processes signals correctly
- [x] Test transform_result/3 modifies results appropriately
- [x] Test skill schema provides correct defaults
- [x] Test signal_patterns match expected signals
- [x] Test mount/2 initializes skill state correctly

---

## 9.4 Accuracy Pipeline StateOps Migration

Migrate the accuracy pipeline to use StateOps for state mutations.

### 9.4.1 Pipeline StateOps Integration

Update pipeline to use StateOps instead of direct state manipulation.

- [ ] 9.4.1.1 Update `lib/jido_ai/accuracy/pipeline.ex`
- [ ] 9.4.1.2 Import `Jido.Agent.StateOp` for state operations
- [ ] 9.4.1.3 Replace direct result struct updates with StateOp.SetState
- [ ] 9.4.1.4 Use StateOp.SetPath for nested metadata updates
- [ ] 9.4.1.5 Update `run/3` to apply state operations
- [ ] 9.4.1.6 Ensure trace updates use state operations

### 9.4.2 Pipeline Stage StateOps

Update pipeline stages to use StateOps.

- [ ] 9.4.2.1 Update `lib/jido_ai/accuracy/generation_result.ex`
- [ ] 9.4.2.2 Add StateOps helpers for result updates
- [ ] 9.4.2.3 Update `lib/jido_ai/accuracy/pipeline_result.ex`
- [ ] 9.4.2.4 Add StateOps helpers for pipeline result updates
- [ ] 9.4.2.5 Update stage execution to return state operations
- [ ] 9.4.2.6 Compose state operations across stages

### 9.4.3 Calibration Gate StateOps

Update calibration gate to use StateOps.

- [ ] 9.4.3.1 Update `lib/jido_ai/accuracy/calibration_gate.ex`
- [ ] 9.4.3.2 Replace direct state updates with state operations
- [ ] 9.4.3.3 Use StateOp.SetPath for confidence updates
- [ ] 9.4.3.4 Add StateOps for action decision storage
- [ ] 9.4.3.5 Update calibration result handling

### 9.4.4 Unit Tests for Pipeline StateOps

- [ ] Test pipeline applies state operations correctly
- [ ] Test stage state operations compose
- [ ] Test calibration gate uses state operations
- [ ] Test state operations preserve pipeline integrity
- [ ] Test metadata updates via StateOp.SetPath
- [ ] Test trace updates via state operations

---

## 9.5 Phase 9 Integration Tests

Comprehensive integration tests for Jido V2 migration.

### 9.5.1 Strategy StateOps Integration Tests

- [ ] 9.5.1.1 Create `test/jido_ai/strategy/stateops_integration_test.exs`
- [ ] 9.5.1.2 Test: ReAct strategy uses StateOps correctly
  - Run ReAct conversation
  - Verify state ops are returned
  - Verify state is updated correctly
- [ ] 9.5.1.3 Test: Multiple state ops compose correctly
  - Generate multiple state updates
  - Verify all updates applied
- [ ] 9.5.1.4 Test: State ops isolation between strategies
  - Run multiple strategies concurrently
  - Verify state isolation

### 9.5.2 Skill Schema Integration Tests

- [ ] 9.5.2.1 Create `test/jido_ai/skills/schema_integration_test.exs`
- [ ] 9.5.2.2 Test: All skill actions use Zoi schemas
  - Verify each action has @schema
  - Verify validation works
- [ ] 9.5.2.3 Test: Schema validation rejects invalid inputs
  - Test each skill with invalid params
  - Verify proper errors
- [ ] 9.5.2.4 Test: Schema coercion works correctly
  - Test type coercion
  - Test default value application

### 9.5.3 Skill Lifecycle Integration Tests

- [ ] 9.5.3.1 Create `test/jido_ai/skills/lifecycle_integration_test.exs`
- [ ] 9.5.3.2 Test: Router callbacks route signals correctly
  - Send signal to each skill
  - Verify correct action invoked
- [ ] 9.5.3.3 Test: Handle signal pre-processing works
  - Send signal through handle_signal
  - Verify processing occurs
- [ ] 9.5.3.4 Test: Transform result modifies output
  - Run action with transform_result
  - Verify result transformed
- [ ] 9.5.3.5 Test: Skill state isolation works
  - Mount multiple skills
  - Verify state separation

### 9.5.4 Pipeline StateOps Integration Tests

- [ ] 9.5.4.1 Create `test/jido_ai/accuracy/stateops_pipeline_test.exs`
- [ ] 9.5.4.2 Test: Pipeline runs with StateOps
  - Run full pipeline
  - Verify state ops applied
- [ ] 9.5.4.3 Test: Stage state operations compose
  - Run multi-stage pipeline
  - Verify all stage updates applied
- [ ] 9.5.4.4 Test: Calibration uses StateOps
  - Run pipeline with calibration
  - Verify state mutations via ops
- [ ] 9.5.4.5 Test: Error handling with StateOps
  - Cause stage error
  - Verify state consistency

### 9.5.5 Backward Compatibility Tests

- [ ] 9.5.5.1 Test: Existing agents still work
  - Run existing demo agents
  - Verify no breaking changes
- [ ] 9.5.5.2 Test: Direct action execution works
  - Execute actions directly
  - Verify results
- [ ] 9.5.5.3 Test: Strategy configuration works
  - Create agent with strategies
  - Verify proper initialization

---

## Phase 9 Success Criteria

1. **StateOps**: All strategies use StateOps for state mutations
2. **Zoi Schemas**: All skill actions use Zoi schemas
3. **Skill Lifecycle**: Skills implement relevant lifecycle callbacks
4. **Pipeline StateOps**: Accuracy pipeline uses StateOps
5. **Integration Tests**: All migration tests passing
6. **Backward Compatibility**: Existing code continues to work

---

## Phase 9 Critical Files

**New Files:**
- `lib/jido_ai/strategy/state_ops_helpers.ex`
- `test/jido_ai/strategy/stateops_integration_test.exs`
- `test/jido_ai/skills/schema_integration_test.exs`
- `test/jido_ai/skills/lifecycle_integration_test.exs`
- `test/jido_ai/accuracy/stateops_pipeline_test.exs`

**Modified Files:**
- `lib/jido_ai/strategy/react.ex`
- `lib/jido_ai/skills/llm/llm.ex`
- `lib/jido_ai/skills/llm/actions/chat.ex`
- `lib/jido_ai/skills/llm/actions/complete.ex`
- `lib/jido_ai/skills/llm/actions/embed.ex`
- `lib/jido_ai/skills/planning/planning.ex`
- `lib/jido_ai/skills/planning/actions/*.ex`
- `lib/jido_ai/skills/reasoning/reasoning.ex`
- `lib/jido_ai/skills/reasoning/actions/*.ex`
- `lib/jido_ai/skills/tool_calling/tool_calling.ex`
- `lib/jido_ai/skills/tool_calling/actions/*.ex`
- `lib/jido_ai/skills/streaming/streaming.ex`
- `lib/jido_ai/skills/streaming/actions/*.ex`
- `lib/jido_ai/accuracy/pipeline.ex`
- `lib/jido_ai/accuracy/pipeline_result.ex`
- `lib/jido_ai/accuracy/calibration_gate.ex`
