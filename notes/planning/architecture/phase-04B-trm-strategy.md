# Phase 4B: TRM Strategy Implementation

This phase implements the TRM (Tiny-Recursive-Model) strategy for efficient recursive reasoning. TRM uses a tiny network applied recursively to iteratively improve answers, achieving remarkable parameter efficiency (7M parameters) while outperforming larger models on complex reasoning tasks.

## Design Principle

**Follow the established Strategy + Machine + Directives pattern.**

```
Strategy (thin adapter)     → Signal routing, config, directive lifting
    ↓
Machine (pure Fsmx FSM)     → State transitions, returns directives (no side effects)
    ↓
Directives                  → ReqLLMStream (executed by runtime)
```

**TRM-specific considerations:**
1. Recursive reasoning loop with iterative answer improvement
2. Deep supervision with multiple feedback steps
3. Adaptive Computational Time (ACT) for early stopping
4. Latent state management across recursion steps

## Module Structure

```
lib/jido_ai/
├── strategies/
│   └── trm.ex                  # TRM strategy adapter
├── trm/
│   ├── machine.ex              # Pure state machine
│   ├── reasoning.ex            # Recursive reasoning engine
│   ├── supervision.ex          # Deep supervision module
│   └── act.ex                  # Adaptive Computational Time
```

## Dependencies

- Phase 1: ReqLLM Integration Layer
- Phase 4: Strategy Implementations (ReAct, CoT, ToT, GoT patterns)

---

## 4B.1 TRM Machine

**Status**: COMPLETED (2026-01-04) - 43 tests passing

The TRM Machine is the pure state machine that manages the recursive reasoning loop. It maintains latent state, tracks answer history, and orchestrates the reason-supervise-improve cycle without side effects.

### 4B.1.1 State Struct Definition

Define the core state structure for the TRM machine.

- [x] 4B.1.1.1 Create `Jido.AI.TRM.Machine` module at `lib/jido_ai/trm/machine.ex`
- [x] 4B.1.1.2 Add `use Fsmx.Struct` with state_field: `:status` and transition map
- [x] 4B.1.1.3 Define telemetry prefix `[:jido, :ai, :trm]`
- [x] 4B.1.1.4 Define `@type status :: :idle | :reasoning | :supervising | :improving | :completed | :error`
- [x] 4B.1.1.5 Define `@type latent_state` struct with fields: `question_context`, `answer_context`, `reasoning_trace`, `confidence_score`, `step_count`
- [x] 4B.1.1.6 Define main struct with fields: `status`, `question`, `current_answer`, `answer_history`, `latent_state`, `supervision_step`, `max_supervision_steps`, `act_threshold`, `act_triggered`, `best_answer`, `best_score`, `result`, `current_call_id`, `termination_reason`, `streaming_text`, `usage`, `started_at`

### 4B.1.2 State Transitions

Define the Fsmx transition map for the TRM recursive loop.

- [x] 4B.1.2.1 Define transitions map: idle→reasoning→supervising→improving→reasoning (loop) or →completed
- [x] 4B.1.2.2 Implement `new/1` with keyword options for `max_supervision_steps`, `act_threshold`
- [x] 4B.1.2.3 Implement `update/3` main dispatcher function with pattern matching on status and message type
- [x] 4B.1.2.4 Implement `:start` message handler (idle → reasoning): Initialize with question and initial answer
- [x] 4B.1.2.5 Implement `:reasoning_result` message handler (reasoning → supervising): Update latent state
- [x] 4B.1.2.6 Implement `:supervision_result` message handler (supervising → improving): Store feedback
- [x] 4B.1.2.7 Implement `:improvement_result` message handler (improving → reasoning or completed): Update answer
- [x] 4B.1.2.8 Implement `:llm_partial` message handler for streaming text accumulation
- [x] 4B.1.2.9 Implement `with_transition/3` helper following existing pattern

### 4B.1.3 Latent State Management

Implement latent state tracking across recursion steps.

- [x] 4B.1.3.1 Implement `initialize_latent_state/2` from question and initial answer
- [x] 4B.1.3.2 Implement `update_latent_state/3` incorporating new reasoning insights
- [x] 4B.1.3.3 Implement `extract_confidence/1` from latent state
- [x] 4B.1.3.4 Implement `merge_reasoning_trace/2` to accumulate reasoning history

### 4B.1.4 Termination Conditions

Implement ACT-based early stopping and termination logic.

- [x] 4B.1.4.1 Implement `should_terminate_max_steps?/1` checking max_supervision_steps
- [x] 4B.1.4.2 Implement `check_act_condition/1` for confidence-based early stopping
- [x] 4B.1.4.3 Implement `complete_with_best/1` to finalize with best answer
- [x] 4B.1.4.4 Emit telemetry events for `:start`, `:step`, `:act_triggered`, `:complete`, `:error`

### 4B.1.5 Serialization

Implement to_map/from_map for strategy state storage.

- [x] 4B.1.5.1 Implement `to_map/1` converting struct to map with atom status
- [x] 4B.1.5.2 Implement `from_map/1` restoring struct from map
- [x] 4B.1.5.3 Implement `generate_call_id/0` with "trm_" prefix

### 4B.1.6 Unit Tests for TRM Machine

- [x] Test `new/0` creates machine in idle state with default config
- [x] Test `new/1` accepts custom max_supervision_steps, act_threshold
- [x] Test `:start` message transitions to reasoning and returns reasoning directive
- [x] Test `:reasoning_result` updates latent state and transitions to supervising
- [x] Test `:supervision_result` stores feedback and transitions to improving
- [x] Test `:improvement_result` updates answer and loops or completes
- [x] Test ACT early stopping when confidence exceeds threshold
- [x] Test termination on max_supervision_steps
- [x] Test answer_history accumulates across steps
- [x] Test `to_map/from_map` round-trip

---

## 4B.2 TRM Strategy

The TRM Strategy is the thin adapter that routes signals, manages configuration, and lifts machine directives into SDK-specific directive structs.

### 4B.2.1 Strategy Module Setup

Create the strategy module following established patterns.

- [ ] 4B.2.1.1 Create `Jido.AI.Strategies.TRM` module at `lib/jido_ai/strategies/trm.ex`
- [ ] 4B.2.1.2 Add `use Jido.Agent.Strategy`
- [ ] 4B.2.1.3 Define `@type config` with model, max_supervision_steps, act_threshold, reasoning_temperature, supervision_temperature
- [ ] 4B.2.1.4 Define `@default_model "anthropic:claude-haiku-4-5"`

### 4B.2.2 Action Atoms

Define the action atoms for TRM operations.

- [ ] 4B.2.2.1 Define `@start :trm_start`, `@llm_result :trm_llm_result`, `@llm_partial :trm_llm_partial`
- [ ] 4B.2.2.2 Implement accessor functions: `start_action/0`, `llm_result_action/0`, `llm_partial_action/0`
- [ ] 4B.2.2.3 Define `@action_specs` map with Zoi schemas for each action

### 4B.2.3 Signal Routing

Implement signal routing for TRM-specific signals.

- [ ] 4B.2.3.1 Implement `signal_routes/1` callback with routes for `trm.reason`, `reqllm.result`, `reqllm.partial`

### 4B.2.4 Strategy Callbacks

Implement required strategy callbacks.

- [ ] 4B.2.4.1 Implement `action_spec/1` returning spec from `@action_specs`
- [ ] 4B.2.4.2 Implement `init/2` building config and creating machine
- [ ] 4B.2.4.3 Implement `cmd/3` processing instructions through machine
- [ ] 4B.2.4.4 Implement `snapshot/2` returning `%Snapshot{}` with status, done?, result, details
- [ ] 4B.2.4.5 Implement `build_config/2` extracting options from ctx

### 4B.2.5 Directive Lifting

Implement conversion from machine directives to SDK directives.

- [ ] 4B.2.5.1 Implement `lift_directives/2` with pattern matching on directive types
- [ ] 4B.2.5.2 Handle `{:reason, id, context}` → `Directive.ReqLLMStream` with reasoning prompt
- [ ] 4B.2.5.3 Handle `{:supervise, id, context}` → `Directive.ReqLLMStream` with supervision prompt
- [ ] 4B.2.5.4 Handle `{:improve, id, context}` → `Directive.ReqLLMStream` with improvement prompt
- [ ] 4B.2.5.5 Implement `to_machine_msg/2` converting action/params to machine messages

### 4B.2.6 Public API

Add helper functions for external access.

- [ ] 4B.2.6.1 Implement `get_answer_history/1` returning answer progression
- [ ] 4B.2.6.2 Implement `get_current_answer/1` returning latest answer
- [ ] 4B.2.6.3 Implement `get_confidence/1` returning current confidence score
- [ ] 4B.2.6.4 Implement `get_supervision_step/1` returning current step number

### 4B.2.7 Unit Tests for TRM Strategy

- [ ] Test `init/2` creates machine and sets config
- [ ] Test `signal_routes/1` returns correct routing
- [ ] Test `cmd/3` with start instruction creates reasoning directive
- [ ] Test `cmd/3` with llm_result processes through reasoning phases
- [ ] Test `snapshot/2` returns correct status for each phase
- [ ] Test `lift_directives/2` creates correct directive types for each phase
- [ ] Test public API functions return expected values

---

## 4B.3 Recursive Reasoning Engine

The Recursive Reasoning Engine generates reasoning prompts and parses results for iterative answer improvement.

### 4B.3.1 Reasoning Module Setup

- [ ] 4B.3.1.1 Create `Jido.AI.TRM.Reasoning` module at `lib/jido_ai/trm/reasoning.ex`
- [ ] 4B.3.1.2 Define `@type reasoning_context :: %{question: String.t(), current_answer: String.t(), latent_state: map()}`

### 4B.3.2 Reasoning Prompt Templates

Define prompts for recursive reasoning.

- [ ] 4B.3.2.1 Implement `build_reasoning_prompt/2` taking question, current_answer, and latent_state
- [ ] 4B.3.2.2 Define `default_reasoning_system_prompt/0` for guiding recursive reasoning
- [ ] 4B.3.2.3 Implement `build_latent_update_prompt/3` for updating latent state from reasoning
- [ ] 4B.3.2.4 Implement `format_reasoning_trace/1` for including history in prompts

### 4B.3.3 Reasoning Result Parsing

Parse LLM reasoning responses.

- [ ] 4B.3.3.1 Implement `parse_reasoning_result/1` extracting insights from LLM response
- [ ] 4B.3.3.2 Implement `extract_key_insights/1` identifying important reasoning steps
- [ ] 4B.3.3.3 Implement `calculate_reasoning_confidence/1` from response quality

### 4B.3.4 Unit Tests for Reasoning Module

- [ ] Test `build_reasoning_prompt/2` includes question and current answer
- [ ] Test `parse_reasoning_result/1` extracts structured insights
- [ ] Test `extract_key_insights/1` identifies important points
- [ ] Test `calculate_reasoning_confidence/1` returns valid confidence score

---

## 4B.4 Deep Supervision Module

The Deep Supervision Module provides feedback for answer improvement across multiple supervision steps.

### 4B.4.1 Supervision Module Setup

- [ ] 4B.4.1.1 Create `Jido.AI.TRM.Supervision` module at `lib/jido_ai/trm/supervision.ex`
- [ ] 4B.4.1.2 Define `@type feedback :: %{issues: [String.t()], suggestions: [String.t()], quality_score: float()}`

### 4B.4.2 Supervision Prompt Construction

Build prompts for generating supervision feedback.

- [ ] 4B.4.2.1 Implement `build_supervision_prompt/3` taking question, answer, and supervision_state
- [ ] 4B.4.2.2 Define `default_supervision_system_prompt/0` for critical analysis
- [ ] 4B.4.2.3 Implement `include_previous_feedback/2` for iterative improvement context
- [ ] 4B.4.2.4 Implement `format_quality_criteria/0` listing evaluation dimensions

### 4B.4.3 Feedback Parsing

Parse supervision feedback from LLM responses.

- [ ] 4B.4.3.1 Implement `parse_supervision_result/1` extracting structured feedback
- [ ] 4B.4.3.2 Implement `extract_issues/1` identifying problems in current answer
- [ ] 4B.4.3.3 Implement `extract_suggestions/1` getting improvement recommendations
- [ ] 4B.4.3.4 Implement `calculate_quality_score/1` from feedback analysis

### 4B.4.4 Improvement Prompt Construction

Build prompts for applying feedback to improve answers.

- [ ] 4B.4.4.1 Implement `build_improvement_prompt/3` taking question, answer, and feedback
- [ ] 4B.4.4.2 Define `default_improvement_system_prompt/0` for applying feedback
- [ ] 4B.4.4.3 Implement `prioritize_suggestions/1` ordering by impact

### 4B.4.5 Unit Tests for Supervision Module

- [ ] Test `build_supervision_prompt/3` includes answer and context
- [ ] Test `parse_supervision_result/1` extracts issues and suggestions
- [ ] Test `calculate_quality_score/1` returns valid score
- [ ] Test `build_improvement_prompt/3` incorporates feedback

---

## 4B.5 Adaptive Computational Time (ACT)

The ACT module implements early stopping based on confidence thresholds.

### 4B.5.1 ACT Module Setup

- [ ] 4B.5.1.1 Create `Jido.AI.TRM.ACT` module at `lib/jido_ai/trm/act.ex`
- [ ] 4B.5.1.2 Define `@type act_state :: %{threshold: float(), current_confidence: float(), history: [float()]}`

### 4B.5.2 Confidence Calculation

Implement confidence scoring for early stopping decisions.

- [ ] 4B.5.2.1 Implement `calculate_confidence/2` from latent_state and quality_score
- [ ] 4B.5.2.2 Implement `should_halt?/2` comparing confidence against threshold
- [ ] 4B.5.2.3 Implement `update_confidence_history/2` tracking confidence progression
- [ ] 4B.5.2.4 Implement `detect_convergence/1` checking if improvements have plateaued

### 4B.5.3 ACT Decision Logic

Implement the continue/halt decision process.

- [ ] 4B.5.3.1 Implement `make_decision/2` returning `:continue` or `:halt`
- [ ] 4B.5.3.2 Implement `calculate_expected_improvement/1` estimating benefit of continuing
- [ ] 4B.5.3.3 Implement `get_halt_reason/1` returning reason for early stopping

### 4B.5.4 Unit Tests for ACT Module

- [ ] Test `calculate_confidence/2` returns valid confidence
- [ ] Test `should_halt?/2` returns true when confidence exceeds threshold
- [ ] Test `should_halt?/2` returns false when confidence below threshold
- [ ] Test `detect_convergence/1` identifies plateaued improvements
- [ ] Test `make_decision/2` returns correct decision

---

## 4B.6 Adaptive Integration

Integrate TRM into the Adaptive strategy for automatic selection.

### 4B.6.1 Strategy Registration

Add TRM to available strategies in Adaptive.

- [ ] 4B.6.1.1 Update `@strategy_modules` map in `lib/jido_ai/strategies/adaptive.ex` to include `:trm`
- [ ] 4B.6.1.2 Update `@type strategy_type` to include `:trm`
- [ ] 4B.6.1.3 Update default `available_strategies` to include `:trm`

### 4B.6.2 Puzzle/Reasoning Keyword Detection

Add keyword detection for puzzle-solving and iterative reasoning tasks.

- [ ] 4B.6.2.1 Define `@puzzle_keywords ~w(puzzle solve step-by-step iterate improve refine recursive)`
- [ ] 4B.6.2.2 Implement `has_puzzle_keywords?/1` helper
- [ ] 4B.6.2.3 Add `:iterative_reasoning` to `detect_task_type/1` result types

### 4B.6.3 TRM-Specific Task Type Routing

Route puzzle/iterative reasoning tasks to TRM.

- [ ] 4B.6.3.1 Update `select_by_task_type/2` to handle `:iterative_reasoning` → `:trm`
- [ ] 4B.6.3.2 Update `detect_task_type/1` to check for puzzle keywords
- [ ] 4B.6.3.3 Add action mapping functions for TRM: `start_action_for(:trm)`, etc.

### 4B.6.4 Unit Tests for Adaptive Integration

- [ ] Test `:trm` is in `@strategy_modules`
- [ ] Test `has_puzzle_keywords?/1` detects puzzle-solving prompts
- [ ] Test `detect_task_type/1` returns `:iterative_reasoning` for puzzle prompts
- [ ] Test `select_by_task_type(:iterative_reasoning, _)` returns `:trm`
- [ ] Test Adaptive delegates to TRM for iterative reasoning tasks

---

## 4B.7 Phase 4B Integration Tests

Comprehensive integration tests verifying all Phase 4B components work together.

### 4B.7.1 Basic Workflow Tests

Verify the complete TRM workflow.

- [ ] 4B.7.1.1 Create `test/jido_ai/integration/trm_phase4b_test.exs`
- [ ] 4B.7.1.2 Test: TRM strategy initialization with config
- [ ] 4B.7.1.3 Test: Start with question creates initial reasoning directive
- [ ] 4B.7.1.4 Test: Reasoning result triggers supervision phase
- [ ] 4B.7.1.5 Test: Supervision feedback triggers improvement phase
- [ ] 4B.7.1.6 Test: Improvement result loops back to reasoning
- [ ] 4B.7.1.7 Test: Multi-step recursive loop completes
- [ ] 4B.7.1.8 Test: Answer history accumulates correctly

### 4B.7.2 ACT Early Stopping Tests

Verify Adaptive Computational Time behavior.

- [ ] 4B.7.2.1 Test: ACT triggers early stopping when confidence exceeds threshold
- [ ] 4B.7.2.2 Test: ACT allows continuation when confidence below threshold
- [ ] 4B.7.2.3 Test: Convergence detection stops on plateaued improvements

### 4B.7.3 Termination Tests

Verify termination conditions.

- [ ] 4B.7.3.1 Test: Termination on max_supervision_steps
- [ ] 4B.7.3.2 Test: Termination on ACT threshold
- [ ] 4B.7.3.3 Test: Error handling and recovery
- [ ] 4B.7.3.4 Test: Snapshot returns correct state at each phase

### 4B.7.4 Adaptive Integration Tests

Verify TRM works through Adaptive strategy.

- [ ] 4B.7.4.1 Test: Adaptive selects TRM for "solve this puzzle step by step" query
- [ ] 4B.7.4.2 Test: Adaptive delegates correctly to TRM
- [ ] 4B.7.4.3 Test: TRM completion result is accessible through Adaptive

### 4B.7.5 Deep Supervision Tests

Verify deep supervision feedback loop.

- [ ] 4B.7.5.1 Test: Supervision feedback improves answer quality
- [ ] 4B.7.5.2 Test: Quality scores increase across supervision steps
- [ ] 4B.7.5.3 Test: Best answer is tracked and returned on completion

---

## Phase 4B Success Criteria

1. **Machine Pattern**: TRM Machine follows pure Fsmx state machine pattern with no side effects
2. **Directive Emission**: Strategy emits `ReqLLMStream` directives for reasoning, supervision, and improvement
3. **Signal Routing**: `signal_routes/1` auto-routes TRM signals to strategy commands
4. **Recursive Loop**: Answer improves iteratively through reason-supervise-improve cycle
5. **Deep Supervision**: Multiple supervision steps provide feedback for improvement
6. **ACT Early Stopping**: Confidence-based early stopping prevents unnecessary computation
7. **Adaptive Integration**: TRM is selectable through Adaptive strategy for puzzle/iterative tasks
8. **Test Coverage**: All components have unit tests; integration tests verify end-to-end workflow

---

## Phase 4B Critical Files

**New Files:**
- `lib/jido_ai/strategies/trm.ex`
- `lib/jido_ai/trm/machine.ex`
- `lib/jido_ai/trm/reasoning.ex`
- `lib/jido_ai/trm/supervision.ex`
- `lib/jido_ai/trm/act.ex`
- `test/jido_ai/trm/machine_test.exs`
- `test/jido_ai/strategies/trm_test.exs`
- `test/jido_ai/trm/reasoning_test.exs`
- `test/jido_ai/trm/supervision_test.exs`
- `test/jido_ai/trm/act_test.exs`
- `test/jido_ai/integration/trm_phase4b_test.exs`

**Existing Files (Enhance):**
- `lib/jido_ai/strategies/adaptive.ex` - Add TRM to strategy modules and puzzle keyword detection
