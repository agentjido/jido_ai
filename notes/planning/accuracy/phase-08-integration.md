# Phase 8: Complete Accuracy Stack Integration

This phase integrates all components into an end-to-end accuracy pipeline. The complete stack orchestrates difficulty estimation, RAG with correction, multi-candidate generation, verification, search, reflection, and calibration into a unified system.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                 Complete Accuracy Stack                                  │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Query                                                                  │
│     │                                                                    │
│     ▼                                                                    │
│   ┌──────────────────┐                                                   │
│   │ Difficulty       │ ──→ Easy: N=3, no PRM                            │
│   │ Estimation       │ ──→ Medium: N=5, PRM                              │
│   └────────┬─────────┘ ──→ Hard: N=10, PRM + search                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ RAG with         │ ──→ See phase-05-crag-reference.md                │
│   │ Correction       │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Multi-Candidate  │ ──→ See phase-01-self-consistency.md             │
│   │ Generation       │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Verification     │ ──→ See phase-02-verifier.md                      │
│   │ (Outcome/PRM)    │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Search /         │ ──→ See phase-03-search.md                        │
│   │ Selection        │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Reflection       │ ──→ See phase-04-reflection.md                    │
│   │ (if needed)      │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│   ┌──────────────────┐                                                   │
│   │ Calibration      │ ──→ See phase-06-calibration.md                   │
│   │    Gate          │                                                     │
│   └────────┬─────────┘                                                     │
│            │                                                              │
│            ▼                                                              │
│        Response                                                            │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| AccuracyPipeline | Orchestrates complete accuracy stack |
| StrategyPresets | Pre-configured strategies for common use cases |
| AccuracyTelemetry | Emits telemetry for pipeline operations |
| StrategyAdapter | Integrates with Jido.AI strategies |

---

## 8.1 Accuracy Pipeline

Create the end-to-end accuracy pipeline.

### 8.1.1 Pipeline Module

Create the main pipeline orchestrator.

- [ ] 8.1.1.1 Create `lib/jido_ai/accuracy/pipeline.ex`
- [ ] 8.1.1.2 Add `@moduledoc` explaining complete pipeline
- [ ] 8.1.1.3 Define configuration schema with Zoi:
  - `:stages` - List of enabled stages
  - `:difficulty_estimator` - Module for difficulty estimation
  - `:rag_config` - Configuration for RAG stage
  - `:generation_config` - Configuration for candidate generation
  - `:verifier_config` - Configuration for verification
  - `:search_config` - Configuration for search
  - `:reflection_config` - Configuration for reflection
  - `:calibration_config` - Configuration for calibration
  - `:budget_limit` - Overall budget limit
- [ ] 8.1.1.4 Implement `run/3` with query and config
- [ ] 8.1.1.5 Implement with all stages in order
- [ ] 8.1.1.6 Return result with full trace
- [ ] 8.1.1.7 Support streaming intermediate results
- [ ] 8.1.1.8 Implement `run_stream/3` for streaming

### 8.1.2 Pipeline Stages

Implement individual pipeline stages.

- [ ] 8.1.2.1 Implement `stage_difficulty_estimation/3`
  - Estimate task difficulty
  - Return difficulty for downstream use
- [ ] 8.1.2.2 Implement `stage_rag/4`
  - Optional RAG with correction
  - Return retrieved context
- [ ] 8.1.2.3 Implement `stage_generation/4`
  - Multi-candidate generation
  - Use adaptive N based on difficulty
- [ ] 8.1.2.4 Implement `stage_verification/4`
  - Verify all candidates
  - Return scored candidates
- [ ] 8.1.2.5 Implement `stage_search/4`
  - Optional search for better selection
  - Return best candidate
- [ ] 8.1.2.6 Implement `stage_reflection/4`
  - Optional reflection if score low
  - Return improved candidate
- [ ] 8.1.2.7 Implement `stage_calibration/4`
  - Estimate confidence
  - Route based on confidence
  - Return final response

### 8.1.3 Pipeline Configuration

Define and validate pipeline configuration.

- [ ] 8.1.3.1 Implement `validate_config/1`
- [ ] 8.1.3.2 Implement `default_config/0`
- [ ] 8.1.3.3 Implement `merge_config/2`
- [ ] 8.1.3.4 Support component enable/disable
- [ ] 8.1.3.5 Support custom parameters per stage

### 8.1.4 Pipeline Execution

Execute pipeline with proper error handling and state management.

- [ ] 8.1.4.1 Implement `execute_stage/4`
- [ ] 8.1.4.2 Implement `handle_stage_error/3`
- [ ] 8.1.4.3 Implement `build_trace/2`
- [ ] 8.1.4.4 Implement `emit_stage_event/3`

### 8.1.5 Unit Tests for Pipeline

- [ ] Test `run/3` executes all stages
- [ ] Test configuration validation
- [ ] Test stage can be disabled
- [ ] Test result includes trace
- [ ] Test streaming returns intermediate results
- [ ] Test error handling per stage
- [ ] Test state management across stages

---

## 8.2 Strategy Presets

Define common strategy presets.

### 8.2.1 Presets Module

Create the presets module.

- [x] 8.2.1.1 Create `lib/jido_ai/accuracy/presets.ex`
- [x] 8.2.1.2 Add `@moduledoc` explaining preset concept
- [x] 8.2.1.3 Define `@type preset/0`:
  - `:fast` - Minimal compute, basic verification
  - `:balanced` - Moderate compute, full verification
  - `:accurate` - Maximum compute, all features
  - `:coding` - Optimized for code correctness
  - `:research` - Optimized for factual QA

### 8.2.2 Preset Definitions

Define each preset configuration.

- [x] 8.2.2.1 Implement `fast/0` preset
  - num_candidates: 3
  - use_prm: false
  - use_search: false
  - use_reflection: false
  - use_rag: selective
- [x] 8.2.2.2 Implement `balanced/0` preset
  - num_candidates: 5
  - use_prm: true
  - use_search: false
  - use_reflection: false
  - use_rag: selective
- [x] 8.2.2.3 Implement `accurate/0` preset
  - num_candidates: 10
  - use_prm: true
  - use_search: true
  - use_reflection: true
  - use_rag: selective
  - search_iterations: 50
- [x] 8.2.2.4 Implement `coding/0` preset
  - num_candidates: 5
  - use_prm: true
  - use_search: false
  - use_reflection: true
  - use_rag: true
  - verifiers: [:code_execution, :unit_test]
- [x] 8.2.2.5 Implement `research/0` preset
  - num_candidates: 5
  - use_prm: true
  - use_search: false
  - use_reflection: false
  - use_rag: true
  - calibration: strict

### 8.2.3 Preset Operations

Implement preset utilities.

- [x] 8.2.3.1 Implement `get/1` for preset retrieval
- [x] 8.2.3.2 Implement `list/0` for available presets
- [x] 8.2.3.3 Implement `customize/2` for preset modification
- [x] 8.2.3.4 Implement `validate/1` for preset validation

### 8.2.4 Unit Tests for Presets

- [x] Test each preset loads correct config
- [x] Test presets can be customized
- [x] Test `get/1` returns preset or error
- [x] Test `list/0` returns all presets
- [x] Test preset validation

---

## 8.3 Telemetry and Observability

Add comprehensive telemetry.

### 8.3.1 Telemetry Module

Create telemetry for accuracy operations.

- [ ] 8.3.1.1 Create `lib/jido_ai/accuracy/telemetry.ex`
- [ ] 8.3.1.2 Add `@moduledoc` explaining telemetry approach
- [ ] 8.3.1.3 Define event names:
  - `[:jido, :accuracy, :pipeline, :start]`
  - `[:jido, :accuracy, :pipeline, :stop]`
  - `[:jido, :accuracy, :pipeline, :exception]`
  - `[:jido, :accuracy, :stage, :start]`
  - `[:jido, :accuracy, :stage, :stop]`
- [ ] 8.3.1.4 Implement `emit_pipeline_start/2`
- [ ] 8.3.1.5 Implement `emit_pipeline_stop/2`
- [ ] 8.3.1.6 Implement `emit_stage_start/3`
- [ ] 8.3.1.7 Implement `emit_stage_stop/3`
- [ ] 8.3.1.8 Implement `emit_exception/3`

### 8.3.2 Telemetry Measurements

Define measurements to attach.

- [ ] 8.3.2.1 Include timing information
  - Duration: pipeline total, each stage
- [ ] 8.3.2.2 Include token usage
  - Total tokens per LLM call
  - Breakdown by stage
- [ ] 8.3.2.3 Include quality metrics
  - Confidence scores
  - Verification scores
  - Candidate counts

### 8.3.3 Span Creation

Create spans for distributed tracing.

- [ ] 8.3.3.1 Create spans for pipeline execution
- [ ] 8.3.3.2 Nest spans for sub-stages
- [ ] 8.3.3.3 Include trace context in telemetry

### 8.3.4 Unit Tests for Telemetry

- [ ] Test events are emitted
- [ ] Test spans are created
- [ ] Test measurements are attached
- [ ] Test timing is accurate
- [ ] Test token counts are correct

---

## 8.4 Integration with Jido.AI Strategies

Integrate accuracy pipeline with existing strategies.

### 8.4.1 Strategy Adapter Module

Create adapter for using accuracy pipeline with strategies.

- [ ] 8.4.1.1 Create `lib/jido_ai/accuracy/strategy_adapter.ex`
- [ ] 8.4.1.2 Add `@moduledoc` explaining integration approach
- [ ] 8.4.1.3 Implement `wrap_pipeline/2`
  - Wraps accuracy pipeline for strategy use
- [ ] 8.4.1.4 Implement `to_directive/2`
  - Converts pipeline config to directive
- [ ] 8.4.1.5 Implement `from_signal/2`
  - Extracts query from signal

### 8.4.2 ReAct Strategy Integration

Integrate with ReAct strategy.

- [ ] 8.4.2.1 Implement `react_adapter/2`
  - Adapts pipeline for ReAct pattern
- [ ] 8.4.2.2 Support tool calls within pipeline
- [ ] 8.4.2.3 Emit ReAct-compatible signals

### 8.4.3 Directive Integration

Support directive-based execution.

- [ ] 8.4.3.1 Implement `AccuracyDirective` module
- [ ] 8.4.3.2 Define directive schema
  - `:query` - Query to process
  - `:preset` - Preset to use
  - `:config` - Custom config overrides
- [ ] 8.4.3.3 Implement directive execution
- [ ] 8.4.3.4 Return result as signal

### 8.4.4 Unit Tests for StrategyAdapter

- [ ] Test ReAct integration
- [ ] Test CoT integration
- [ ] Test directive execution
- [ ] Test signal emission
- [ ] Test to_directive conversion

---

## 8.5 Phase 8 Integration Tests

Comprehensive integration tests for the complete pipeline.

### 8.5.1 End-to-End Pipeline Tests

- [ ] 8.5.1.1 Create `test/jido_ai/accuracy/pipeline_test.exs`
- [ ] 8.5.1.2 Test: Complete pipeline on math problem
  - Run full pipeline
  - Verify all stages execute
  - Verify correct answer
  - Check trace completeness
- [ ] 8.5.1.3 Test: Complete pipeline on coding problem
  - Code generation task
  - Verify tool-based verification
  - Verify compilation check
- [ ] 8.5.1.4 Test: Complete pipeline on research question
  - Factual QA task
  - Verify RAG with correction
  - Verify factuality improved
- [ ] 8.5.1.5 Test: Presets behave as expected
  - Test :fast preset
  - Test :balanced preset
  - Test :accurate preset
  - Compare cost vs accuracy

### 8.5.2 Accuracy Validation Tests

- [ ] 8.5.2.1 Test: Pipeline improves over baseline
  - Compare pipeline vs simple LLM call
  - Measure accuracy improvement on benchmark
- [ ] 8.5.2.2 Test: Each component contributes
  - Ablation study
  - Verify each stage adds value
- [ ] 8.5.2.3 Test: Presets match their intent
  - Fast is fastest
  - Accurate is most accurate
  - Balanced is best trade-off

### 8.5.3 Performance Tests

- [ ] 8.5.3.1 Test: Pipeline latency is acceptable
  - Measure end-to-end latency
  - Verify < 30 seconds for typical query
- [ ] 8.5.3.2 Test: Cost tracking is accurate
  - Verify total token count
  - Compare to expected
- [ ] 8.5.3.3 Test: Telemetry overhead is minimal
  - Measure telemetry impact
  - Verify < 5% overhead

### 8.5.4 Reliability Tests

- [ ] 8.5.4.1 Test: Pipeline handles errors gracefully
  - Mock failure at each stage
  - Verify fallback behavior
- [ ] 8.5.4.2 Test: Calibration prevents wrong answers
  - Questions LLM cannot answer
  - Verify abstention rate
- [ ] 8.5.4.3 Test: Budget limits are enforced
  - Set strict budget
  - Verify pipeline respects limit

### 8.5.5 Strategy Integration Tests

- [ ] 8.5.5.1 Create `test/jido_ai/accuracy/strategy_integration_test.exs`
- [ ] 8.5.5.2 Test: ReAct strategy with accuracy pipeline
  - Run ReAct agent with pipeline
  - Verify correct integration
- [ ] 8.5.5.3 Test: Directive execution
  - Execute AccuracyDirective
  - Verify result signal

---

## Phase 8 Success Criteria

1. **Complete pipeline**: All stages execute correctly
2. **Presets**: Common strategies work out of box
3. **Accuracy improvement**: Measurable gain over baseline
4. **Telemetry**: Full observability of pipeline execution
5. **Integration**: Works with existing Jido.AI strategies
6. **Test coverage**: Minimum 85% for Phase 8 modules

---

## Phase 8 Critical Files

**New Files:**
- `lib/jido_ai/accuracy/pipeline.ex`
- `lib/jido_ai/accuracy/presets.ex`
- `lib/jido_ai/accuracy/telemetry.ex`
- `lib/jido_ai/accuracy/strategy_adapter.ex`
- `lib/jido_ai/accuracy/directives/accuracy_directive.ex`

**Test Files:**
- `test/jido_ai/accuracy/pipeline_test.exs`
- `test/jido_ai/accuracy/presets_test.exs`
- `test/jido_ai/accuracy/telemetry_test.exs`
- `test/jido_ai/accuracy/strategy_adapter_test.exs`
- `test/jido_ai/accuracy/strategy_integration_test.exs`

---

## Overall Project Success Criteria

1. **Self-Consistency**: Generate and aggregate multiple candidate responses
2. **Verification**: Score candidates with outcome and process verifiers
3. **Search**: Beam search and MCTS for better candidate selection
4. **Reflection**: Iteratively improve responses through self-critique
5. **Self-Correcting RAG**: Evaluate and correct retrieval quality
6. **Calibration**: Confidence-based routing and selective answering
7. **Adaptive Compute**: Difficulty-based resource allocation
8. **Complete Pipeline**: End-to-end accuracy improvement system
9. **Integration**: Works with existing Jido.AI strategies
10. **Test Coverage**: Minimum 80% across all accuracy modules
