# Feature Planning Document: Phase 4.4 - Self-Refine Strategy

**Status:** Completed
**Section:** 4.4 - Self-Refine Strategy
**Dependencies:** Phase 4.1 (Critique Component), Phase 4.2 (Revision Component)
**Branch:** `feature/accuracy-phase-4-4-self-refine`

## Problem Statement

The accuracy improvement system currently has:
- Full ReflectionLoop with multiple iterations (4.3)
- Critique capabilities (LLMCritiquer, ToolCritiquer)
- Revision capabilities (LLMReviser, TargetedReviser)

However, there's a need for a **lighter-weight single-pass refinement** strategy:
1. Not all tasks require multiple iterations
2. Single refinement can be sufficient for many use cases
3. Lower latency/cost compared to full reflection loop
4. Simpler API for basic self-improvement

**Impact**: Without a simpler self-refine option, users must either use the heavy reflection loop or implement custom single-pass refinement.

## Solution Overview

Implement SelfRefine as a simpler generate-feedback-refine strategy:

1. **SelfRefine Strategy** - Single-pass refinement module
2. **Feedback Generation** - Self-critique prompt
3. **Refinement Application** - Apply feedback to improve response
4. **Comparison** - Track improvement from original to refined

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Refinement style | Single-pass only | Lower latency, simpler API |
| Feedback generation | Built-in prompt | No separate critiquer needed |
| Comparison tracking | Before/after metrics | Shows improvement value |
| Strategy pattern | Follow existing strategy pattern | Consistency with codebase |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/strategies/
└── self_refine.ex                    # Single-pass refinement strategy

test/jido_ai/accuracy/strategies/
└── self_refine_test.exs              # Self-refine tests
```

### Dependencies

- **Existing**: `Candidate` from Phase 1
- **Existing**: `CritiqueResult` from Phase 4.1
- **Existing**: LLM generation via `ReqLLM`
- **Optional**: Integration with existing critiquers/revisers

### File Locations

| File | Purpose |
|------|---------|
| `lib/jido_ai/accuracy/strategies/self_refine.ex` | Self-refine strategy |
| `test/jido_ai/accuracy/strategies/self_refine_test.exs` | Tests |

## Success Criteria

1. **SelfRefine Module**: Executes generate-feedback-refine in single pass
2. **Feedback Generation**: Produces actionable self-feedback
3. **Refinement**: Improves original response based on feedback
4. **Comparison**: Tracks before/after quality metrics
5. **Test Coverage**: Minimum 85% for self-refine module
6. **Integration**: Works standalone or with existing critiquers

## Implementation Plan

### Step 1: SelfRefine Module (4.4.1)

**Purpose**: Single-pass refinement strategy

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/strategies/self_refine.ex`
- [x] Add `@moduledoc` explaining self-refine pattern
- [x] Define configuration struct:
  ```elixir
  defstruct [
    model: "anthropic:claude-haiku-4-5",
    feedback_prompt: nil,  # Optional custom prompt
    temperature: 0.7,
    timeout: 30000
  ]
  ```
- [x] Implement `run/2` with prompt
- [x] Implement `generate_feedback/2` for self-critique
- [x] Implement `apply_feedback/3` for refinement
- [x] Implement `compare_original_refined/3` for improvement tracking
- [x] Write tests

### Step 2: Self-Refine Operations (4.4.2)

**Purpose**: Core operations for self-refine

**Tasks**:
- [x] Implement `generate_feedback/2`:
  - Create self-feedback prompt
  - Generate critique of initial response
  - Return structured feedback
- [x] Implement `apply_feedback/3`:
  - Combine original + feedback
  - Generate refined response
  - Track what changed
- [x] Implement `compare_original_refined/3`:
  - Compare quality metrics
  - Calculate improvement score
  - Return comparison result

### Step 3: Unit Tests (4.4.3)

**Tests to write**:

- [x] `self_refine_test.exs`:
  - Test `run/2` improves initial response
  - Test feedback generation produces actionable critique
  - Test refinement incorporates feedback
  - Test comparison shows improvement
  - Test with custom feedback prompt
  - Test error handling

## Current Status

**Status**: Completed

**Completed**:
- Created feature branch `feature/accuracy-phase-4-4-self-refine`
- Created planning document
- Implemented SelfRefine module with full workflow
- Implemented all self-refine operations (feedback, apply, compare)
- All 26 tests passing

**What Works**:
- `SelfRefine.run/3` executes single-pass refinement (generate-feedback-refine)
- `generate_feedback/4` produces self-critique using configurable prompt template
- `apply_feedback/5` generates refined response incorporating feedback
- `compare_original_refined/2` tracks improvement metrics
- Custom prompt templates for both feedback and refinement steps
- Options to skip initial generation or feedback generation with provided values

**How to Run**:
```bash
# Run self-refine tests
mix test test/jido_ai/accuracy/strategies/self_refine_test.exs
```

**Known Limitations**:
- Comparison metrics are simple (length-based, could add semantic comparison)
- Built-in prompts only (no integration with existing critiquers yet)
- No parallel batch refinement (could add for multiple candidates)

## Notes/Considerations

### Self-Refine vs ReflectionLoop

| Aspect | SelfRefine | ReflectionLoop |
|--------|-----------|----------------|
| Iterations | 1 (single-pass) | Multiple (configurable) |
| Complexity | Low | High |
| Latency | Low | Higher |
| Cost | Lower | Higher |
| Use case | Quick improvement | Deep refinement |

### Built-in vs External Critiquer

SelfRefine can either:
1. Use built-in feedback generation (simpler, single LLM call pattern)
2. Integrate with existing critiquers (more consistent with architecture)

Start with built-in for simplicity, can add critiquer integration later.

### Feedback Prompt Template

Default feedback prompt should:
- Ask model to review its own response
- Identify specific issues or weaknesses
- Suggest concrete improvements
- Remain actionable for refinement step

### Comparison Metrics

Track improvement through:
- Length change (longer = more detail)
- Structural improvements (better organization)
- Self-assigned confidence scores
- Explicit quality ratings

### Integration with Existing Components

SelfRefine uses:
- **Candidate** (from 1.x): Response wrapping
- **CritiqueResult** (from 4.1): Optional feedback format
- **ReqLLM**: LLM generation

### Future Enhancements

1. **Critiquer integration**: Use existing LLMCritiquer for feedback
2. **Reviser integration**: Use existing LLMReviser for refinement
3. **Batch self-refine**: Refine multiple candidates in parallel
4. **Confidence scoring**: Track model confidence in refinement
5. **Selective refinement**: Only refine when confidence is low
