# Phase 8.1: Accuracy Pipeline

**Date:** 2026-01-15
**Feature Branch:** `feature/accuracy-phase-8-1-pipeline`
**Target Branch:** `feature/accuracy`
**Status:** 🚧 IN PROGRESS

---

## Overview

This feature implements the core **Accuracy Pipeline** that orchestrates all accuracy components into an end-to-end system. The pipeline integrates difficulty estimation, RAG with correction, multi-candidate generation, verification, search, reflection, and calibration into a unified, configurable flow.

This is the first sub-phase of Phase 8 (Complete Accuracy Stack Integration).

---

## Problem Statement

### Current State

Phase 7 (Adaptive Compute Budgeting) has been completed with:
- Difficulty estimation (Heuristic and LLM-based)
- Compute budgeting with difficulty-based allocation
- Adaptive self-consistency with early stopping
- Timeout protection and security hardening
- Review improvements (ensemble estimator, consensus checker)

### Missing Components

While individual components exist, there is no unified orchestration layer that:
1. Combines all components in a coherent pipeline
2. Manages state between stages
3. Provides configurable execution strategies
4. Returns trace information for debugging
5. Supports streaming intermediate results

### Impact

Without a pipeline:
- Users must manually orchestrate each component
- No unified configuration interface
- Difficult to trace execution flow
- Hard to add/remove components dynamically
- No support for streaming results

### Solution

Implement a comprehensive Accuracy Pipeline that:
1. Orchestrates all stages in proper order
2. Passes state between stages efficiently
3. Provides unified configuration schema
4. Returns full execution trace
5. Supports streaming intermediate results
6. Handles errors gracefully per stage

---

## Solution Overview

### Pipeline Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                    Accuracy Pipeline Execution                           │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│   Query ──► [Config] ──► Pipeline.run/3                                 │
│                                                                         │
│   Stages (executed in order):                                           │
│   ┌──────────────────────────────────────────────────────────────────┐  │
│   │ 1. Difficulty Estimation  ──► DifficultyEstimate                 │  │
│   │    └─ Determines compute budget based on query complexity        │  │
│   │                                                                   │  │
│   │ 2. RAG with Correction   ──► Context | nil                       │  │
│   │    └─ Optional: Retrieves and corrects context                   │  │
│   │                                                                   │  │
│   │ 3. Multi-Candidate       ──► [Candidate]                         │  │
│   │    └─ Generates N candidates based on difficulty                 │  │
│   │                                                                   │  │
│   │ 4. Verification          ──► [ScoredCandidate]                   │  │
│   │    └─ Scores all candidates with outcome/PRM verifiers          │  │
│   │                                                                   │  │
│   │ 5. Search/Selection     ──► BestCandidate | [ImprovedCandidates] │  │
│   │    └─ Optional: Beam search/MCTS for better selection           │  │
│   │                                                                   │  │
│   │ 6. Reflection            ──► ImprovedCandidate | nil             │  │
│   │    └─ Optional: Iterative improvement if score low              │  │
│   │                                                                   │  │
│   │ 7. Calibration Gate     ──► FinalResponse                        │  │
│   │    └─ Estimates confidence, routes based on threshold           │  │
│   └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
│   ──► PipelineResult                                                   │
│        - answer: Final answer or abstention                           │
│        - confidence: Confidence score                                  │
│        - trace: Stage-by-stage execution trace                        │
│        - metadata: Token counts, timing, etc.                         │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── pipeline.ex                           # Main pipeline orchestrator
├── pipeline_stage.ex                     # Stage behavior and execution
├── pipeline_result.ex                    # Result struct
├── pipeline_config.ex                    # Configuration schema
└── stages/                               # Individual stage implementations
    ├── difficulty_estimation_stage.ex
    ├── rag_stage.ex
    ├── generation_stage.ex
    ├── verification_stage.ex
    ├── search_stage.ex
    ├── reflection_stage.ex
    └── calibration_stage.ex

test/jido_ai/accuracy/
├── pipeline_test.exs                     # Pipeline unit tests
├── pipeline_config_test.exs              # Configuration tests
├── pipeline_stages_test.exs              # Stage tests
└── pipeline_integration_test.exs         # End-to-end tests
```

### Dependencies

**Existing Components (from Phases 1-7):**
- `DifficultyEstimator` - For difficulty estimation
- `HeuristicDifficulty`, `LLMDifficulty` - Estimator implementations
- `ComputeBudgeter` - For compute allocation
- `AdaptiveSelfConsistency` - For adaptive candidate generation
- `OutcomeVerifier`, `ProcessVerifier` - For candidate verification
- `BeamSearch`, `MCTS` - For candidate selection
- `Reflection` - For iterative improvement
- `CalibrationGate` - For confidence-based routing

**New Dependencies:**
- `:telemetry` - For event emission (already in project)

---

## Implementation Plan

### 8.1.1 Pipeline Module Creation

**File:** `lib/jido_ai/accuracy/pipeline.ex`

**Struct Definition:**
```elixir
defmodule Jido.AI.Accuracy.Pipeline do
  @moduledoc """
  End-to-end accuracy improvement pipeline.

  Orchestrates all accuracy components in a configurable flow:
  difficulty estimation → RAG → generation → verification → search → reflection → calibration
  """

  alias Jido.AI.Accuracy.{
    PipelineConfig,
    PipelineResult,
    PipelineStage,
    Stages
  }

  defstruct [
    :config,
    :telemetry_enabled,
    telemetry_enabled: true
  ]

  @type t :: %__MODULE__{
    config: PipelineConfig.t(),
    telemetry_enabled: boolean()
  }
end
```

**Public API:**
```elixir
# Create new pipeline
def new(attrs) :: {:ok, t()} | {:error, term()}
def new!(attrs) :: t()

# Run pipeline
def run(pipeline, query, opts) :: {:ok, PipelineResult.t()} | {:error, term()}

# Run pipeline with streaming
def run_stream(pipeline, query, opts) :: Enumerable.t()

# Get default configuration
def default_config() :: map()
```

### 8.1.2 Pipeline Stage Behavior

**File:** `lib/jido_ai/accuracy/pipeline_stage.ex`

**Behavior Definition:**
```elixir
defmodule Jido.AI.Accuracy.PipelineStage do
  @moduledoc """
  Behavior for pipeline stages.

  Each stage receives the accumulated state and returns
  an updated state with its results.
  """

  @callback name() :: atom()

  @callback execute(
    input :: map(),
    config :: map()
  ) :: {:ok, map(), metadata()} | {:error, term()}

  @callback required?() :: boolean()

  @optional_callbacks [required?: 0]
end
```

### 8.1.3 Individual Stage Implementations

#### 8.1.3.1 DifficultyEstimationStage

**File:** `lib/jido_ai/accuracy/stages/difficulty_estimation_stage.ex`

**Responsibilities:**
- Estimate query difficulty using configured estimator
- Return difficulty estimate for downstream stages
- Include in trace

**Input:**
```elixir
%{
  query: String.t()
}
```

**Output:**
```elixir
%{
  query: String.t(),
  difficulty: DifficultyEstimate.t(),
  compute_budget: ComputeBudget.t()
}
```

#### 8.1.3.2 RAGStage

**File:** `lib/jido_ai/accuracy/stages/rag_stage.ex`

**Responsibilities:**
- Optional: Retrieve context using RAG
- Apply correction if retrieval quality is low
- Return context or nil

**Input:**
```elixir
%{
  query: String.t(),
  difficulty: DifficultyEstimate.t()
}
```

**Output:**
```elixir
%{
  query: String.t(),
  difficulty: DifficultyEstimate.t(),
  context: map() | nil
}
```

#### 8.1.3.3 GenerationStage

**File:** `lib/jido_ai/accuracy/stages/generation_stage.ex`

**Responsibilities:**
- Generate N candidates using AdaptiveSelfConsistency
- Use difficulty to determine N
- Return candidates

**Input:**
```elixir
%{
  query: String.t(),
  difficulty: DifficultyEstimate.t(),
  context: map() | nil
}
```

**Output:**
```elixir
%{
  query: String.t(),
  difficulty: DifficultyEstimate.t(),
  context: map() | nil,
  candidates: [Candidate.t()]
}
```

#### 8.1.3.4 VerificationStage

**File:** `lib/jido_ai/accuracy/stages/verification_stage.ex`

**Responsibilities:**
- Verify all candidates
- Score with outcome and process verifiers
- Return scored candidates

**Input:**
```elixir
%{
  query: String.t(),
  candidates: [Candidate.t()]
}
```

**Output:**
```elixir
%{
  query: String.t(),
  candidates: [ScoredCandidate.t()],
  best_candidate: ScoredCandidate.t()
}
```

#### 8.1.3.5 SearchStage

**File:** `lib/jido_ai/accuracy/stages/search_stage.ex`

**Responsibilities:**
- Optional: Run beam search or MCTS
- Find better candidate through search
- Return improved candidates

**Input:**
```elixir
%{
  query: String.t(),
  candidates: [ScoredCandidate.t()]
}
```

**Output:**
```elixir
%{
  query: String.t(),
  candidates: [ScoredCandidate.t()],
  best_candidate: ScoredCandidate.t()
}
```

#### 8.1.3.6 ReflectionStage

**File:** `lib/jido_ai/accuracy/stages/reflection_stage.ex`

**Responsibilities:**
- Optional: Run reflection if best score is low
- Iteratively improve the answer
- Return improved candidate or original

**Input:**
```elixir
%{
  query: String.t(),
  best_candidate: ScoredCandidate.t()
}
```

**Output:**
```elixir
%{
  query: String.t(),
  best_candidate: ScoredCandidate.t(),
  reflected: boolean()
}
```

#### 8.1.3.7 CalibrationStage

**File:** `lib/jido_ai/accuracy/stages/calibration_stage.ex`

**Responsibilities:**
- Estimate confidence in final answer
- Route based on confidence threshold
- Return final response or abstention

**Input:**
```elixir
%{
  query: String.t(),
  best_candidate: ScoredCandidate.t()
}
```

**Output:**
```elixir
%{
  query: String.t(),
  answer: String.t() | nil,
  confidence: float(),
  action: :direct | :with_verification | :abstain | :escalate
}
```

### 8.1.4 Pipeline Configuration

**File:** `lib/jido_ai/accuracy/pipeline_config.ex`

**Configuration Schema:**
```elixir
defmodule Jido.AI.Accuracy.PipelineConfig do
  @moduledoc """
  Pipeline configuration with Zoi validation.
  """

  alias Jido.AI.Accuracy.{Thresholds, DifficultyEstimate}

  # Stage enablement
  @stage_names [
    :difficulty_estimation,
    :rag,
    :generation,
    :verification,
    :search,
    :reflection,
    :calibration
  ]

  # Configuration structure
  defstruct [
    # Stage enablement
    :stages,

    # Difficulty estimation
    :difficulty_estimator,

    # RAG configuration
    :rag_config,

    # Generation configuration
    :generation_config,

    # Verification configuration
    :verifier_config,

    # Search configuration
    :search_config,

    # Reflection configuration
    :reflection_config,

    # Calibration configuration
    :calibration_config,

    # Budget limits
    :budget_limit,

    # Telemetry
    :telemetry_enabled
  ]

  @type t :: %__MODULE__{
    stages: [atom()],
    difficulty_estimator: module(),
    rag_config: map() | nil,
    generation_config: map(),
    verifier_config: map(),
    search_config: map() | nil,
    reflection_config: map() | nil,
    calibration_config: map(),
    budget_limit: float() | nil,
    telemetry_enabled: boolean()
  }

  # Builder functions
  def new(attrs) :: {:ok, t()} | {:error, term()}
  def new!(attrs) :: t()
  def with_stage(config, stage) :: t()
  def without_stage(config, stage) :: t()
  def validate(config) :: :ok | {:error, term()}
end
```

**Default Configuration:**
```elixir
%{
  stages: [
    :difficulty_estimation,
    :generation,
    :verification,
    :calibration
  ],
  difficulty_estimator: HeuristicDifficulty,
  generation_config: %{
    min_candidates: 3,
    max_candidates: 10
  },
  verifier_config: %{
    use_outcome: true,
    use_process: true
  },
  calibration_config: %{
    high_threshold: Thresholds.calibration_high_confidence(),
    low_threshold: Thresholds.calibration_medium_confidence()
  },
  telemetry_enabled: true
}
```

### 8.1.5 Pipeline Result

**File:** `lib/jido_ai/accuracy/pipeline_result.ex`

**Result Structure:**
```elixir
defmodule Jido.AI.Accuracy.PipelineResult do
  @moduledoc """
  Pipeline execution result with trace and metadata.
  """

  defstruct [
    :answer,
    :confidence,
    :action,
    :trace,
    :metadata
  ]

  @type t :: %__MODULE__{
    answer: String.t() | nil,
    confidence: float(),
    action: :direct | :with_verification | :abstain | :escalate,
    trace: [trace_entry()],
    metadata: metadata()
  }

  @type trace_entry :: %{
    stage: atom(),
    status: :ok | :skipped | :error,
    duration_ms: non_neg_integer(),
    result: map() | nil
  }

  @type metadata :: %{
    total_duration_ms: non_neg_integer(),
    total_tokens: non_neg_integer(),
    num_candidates: non_neg_integer(),
    difficulty: DifficultyEstimate.t() | nil
  }
end
```

### 8.1.6 Pipeline Execution

**Execution Flow:**
```elixir
defp execute_pipeline(pipeline, query, opts) do
  start_time = System.monotonic_time(:millisecond)

  # Initialize state
  initial_state = %{
    query: query,
    opts: opts
  }

  # Get enabled stages from config
  stages = get_enabled_stages(pipeline.config)

  # Execute stages sequentially
  {final_state, trace_entries} =
    Enum.reduce(stages, {initial_state, []}, fn stage, {state, trace} ->
      {start_time, result} = execute_stage(stage, state, pipeline.config)
      new_state = merge_state(state, result)
      new_trace = [trace_entry(stage, start_time, result) | trace]
      {new_state, new_trace}
    end)

  # Build final result
  build_result(final_state, Enum.reverse(trace_entries), start_time)
end
```

---

## Success Criteria

1. ✅ Pipeline module created with all stages defined
2. ✅ Each stage implements PipelineStage behavior
3. ✅ Pipeline runs all enabled stages in order
4. ✅ State is passed correctly between stages
5. ✅ Result includes full execution trace
6. ✅ Configuration is validated on pipeline creation
7. ✅ Unit tests for all stages passing
8. ✅ Integration tests for end-to-end pipeline passing
9. ✅ Telemetry events emitted for each stage
10. ✅ Error handling works per stage

---

## Progress Tracking

### Phase 8.1.1: Pipeline Module
- [ ] 8.1.1.1 Create pipeline.ex
- [ ] 8.1.1.2 Define Pipeline struct
- [ ] 8.1.1.3 Implement new/1, new!/1
- [ ] 8.1.1.4 Implement run/3
- [ ] 8.1.1.5 Implement run_stream/3
- [ ] 8.1.1.6 Add telemetry hooks

### Phase 8.1.2: Pipeline Stages
- [ ] 8.1.2.1 Create pipeline_stage.ex behavior
- [ ] 8.1.2.2 Implement DifficultyEstimationStage
- [ ] 8.1.2.3 Implement RAGStage
- [ ] 8.1.2.4 Implement GenerationStage
- [ ] 8.1.2.5 Implement VerificationStage
- [ ] 8.1.2.6 Implement SearchStage
- [ ] 8.1.2.7 Implement ReflectionStage
- [ ] 8.1.2.8 Implement CalibrationStage

### Phase 8.1.3: Pipeline Configuration
- [ ] 8.1.3.1 Create pipeline_config.ex
- [ ] 8.1.3.2 Define config struct with defaults
- [ ] 8.1.3.3 Implement validation
- [ ] 8.1.3.4 Add stage enable/disable helpers

### Phase 8.1.4: Pipeline Result
- [ ] 8.1.4.1 Create pipeline_result.ex
- [ ] 8.1.4.2 Define result struct
- [ ] 8.1.4.3 Implement trace helpers
- [ ] 8.1.4.4 Implement metadata aggregation

### Phase 8.1.5: Tests
- [ ] 8.1.5.1 Test pipeline creation and validation
- [ ] 8.1.5.2 Test each stage individually
- [ ] 8.1.5.3 Test end-to-end pipeline execution
- [ ] 8.1.5.4 Test error handling per stage
- [ ] 8.1.5.5 Test trace generation
- [ ] 8.1.5.6 Test telemetry emission

---

## Notes and Considerations

### Breaking Changes
- None. This is a new module.

### Backward Compatibility
- All existing components remain unchanged
- Pipeline is an optional orchestration layer

### Trade-offs
- **Sequential vs Parallel**: Stages run sequentially for simplicity. Could parallelize some stages in future.
- **State Management**: Using a map accumulator is simple but less type-safe. Could use struct in future.
- **Error Handling**: Continue-on-error vs fail-fast. We use continue-on-error with trace for debugging.

### Future Enhancements
- Support for custom stages
- Parallel stage execution where possible
- State machine for complex workflows
- Caching at stage level

---

**Last Updated:** 2026-01-15
