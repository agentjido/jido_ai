# Feature Planning Document: Phase 6.2 - Calibration Gate

**Status:** Completed
**Section:** 6.2 - Calibration Gate
**Phase:** 6 - Uncertainty Estimation and Calibration Gates
**Branch:** `feature/accuracy-phase-6-2-calibration-gate`

## Problem Statement

The accuracy improvement system needs a way to route responses based on confidence levels. A calibration gate prevents wrong answers by:

1. **High confidence (≥0.7)** - Return answer directly without modification
2. **Medium confidence (0.4-0.7)** - Add verification, citations, or disclaimers
3. **Low confidence (<0.4)** - Abstain from answering or escalate to human

Currently, the system has confidence estimates (from Phase 6.1) but no mechanism to act on them.

## Solution Overview

Implement a CalibrationGate module that:

1. Takes a Candidate and ConfidenceEstimate as input
2. Routes the candidate based on confidence thresholds
3. Applies routing strategies (direct, with citations, abstain, escalate)
4. Emits telemetry for monitoring and analysis

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Threshold defaults | high: 0.7, low: 0.4 | Matches confidence levels from Phase 6.1 |
| Routing result | Struct with action and modified content | Type-safe, extensible |
| Telemetry | Optional, using :telemetry event | Zero overhead when disabled |
| Strategy pattern | Separate functions for each action | Easy to extend with new strategies |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/
├── calibration_gate.ex              # Main gate module
└── routing/
    └── routing_strategy.ex           # Behavior for routing strategies
```

### Dependencies

- **Existing**: `ConfidenceEstimate` from Phase 6.1
- **Existing**: `Candidate` struct for routing
- **Existing**: `:telemetry` for event emission

### CalibrationGate Fields

| Field | Type | Description |
|-------|------|-------------|
| `:high_threshold` | `float()` | Threshold for high confidence (default: 0.7) |
| `:low_threshold` | `float()` | Threshold for low confidence (default: 0.4) |
| `:medium_action` | `atom()` | Action for medium confidence (default: `:with_verification`) |
| `:low_action` | `atom()` | Action for low confidence (default: `:abstain`) |

### Routing Actions

| Action | Description |
|--------|-------------|
| `:direct` | Return candidate unchanged |
| `:with_verification` | Add verification suggestions |
| `:with_citations` | Add source citations |
| `:abstain` | Return abstention message |
| `:escalate` - Format escalation for human review |

### RoutingResult Struct

```elixir
defstruct [
  :action,           # The action taken
  :candidate,        # The (possibly modified) candidate
  :original_score,   # Original confidence score
  :reasoning,        # Human-readable explanation
  :metadata          # Additional metadata
]
```

## Implementation Plan

### 6.2.1 Calibration Gate Module

**File:** `lib/jido_ai/accuracy/calibration_gate.ex`

- Define CalibrationGate struct with thresholds and actions
- Implement `new/1` with validation
- Implement `route/3` with candidate and estimate
- Implement `should_route?/2` for pre-flight checks
- Add telemetry emission for decisions

### 6.2.2 Routing Strategies

**File:** `lib/jido_ai/accuracy/routing/routing_strategy.ex`

- Define RoutingStrategy behavior
- Implement `direct_answer/1`
- Implement `answer_with_verification/1`
- Implement `answer_with_citations/1`
- Implement `abstain/1`
- Implement `escalate/1`

### 6.2.3 RoutingResult Struct

**File:** `lib/jido_ai/accuracy/routing_result.ex`

- Define struct with action, candidate, score, reasoning
- Implement `new/1` constructor
- Add helper functions:
  - `direct?/1`
  - `abstained?/1`
  - `escalated?/1`
  - `with_verification?/1`

### 6.2.4 Unit Tests

**File:** `test/jido_ai/accuracy/calibration_gate_test.exs`
- Test routing with high confidence
- Test routing with medium confidence
- Test routing with low confidence
- Test custom thresholds
- Test telemetry emission

**File:** `test/jido_ai/accuracy/routing_result_test.exs`
- Test struct creation
- Test helper functions

## Success Criteria

1. **Module created**: CalibrationGate with proper struct and validation
2. **Routing working**: All confidence levels route correctly
3. **Strategies implemented**: Direct, verification, citations, abstain, escalate
4. **Tests passing**: All unit tests with >85% coverage
5. **Documentation**: Complete moduledocs and examples

## Current Status

**Status:** Completed

### Implementation Summary

All components have been implemented and tested:

| Component | File | Tests | Status |
|-----------|------|-------|--------|
| RoutingResult struct | `lib/jido_ai/accuracy/routing_result.ex` | 28 passing | Complete |
| CalibrationGate module | `lib/jido_ai/accuracy/calibration_gate.ex` | 32 passing | Complete |

### Test Results

```
RoutingResult:     28 tests, 0 failures
CalibrationGate:   32 tests, 0 failures
Total:             60 tests, 0 failures
```

### What Works

1. **RoutingResult struct** with action helpers:
   - `direct?/1`, `with_verification?/1`, `with_citations?/1`
   - `abstained?/1`, `escalated?/1`
   - `unmodified?/1` and `modified?/1`
   - `to_map/1` and `from_map/1` for serialization

2. **CalibrationGate** routing:
   - High confidence (≥0.7) → direct answer
   - Medium confidence (0.4-0.7) → verification/citations
   - Low confidence (<0.4) → abstain/escalate
   - Custom thresholds and actions supported

3. **Routing strategies**:
   - `:direct` - Returns candidate unchanged
   - `:with_verification` - Adds verification suffix
   - `:with_citations` - Adds citation suggestion
   - `:abstain` - Generates helpful abstention message
   - `:escalate` - Generates escalation message

4. **Telemetry**:
   - Optional event emission via `:telemetry`
   - Event: `[:jido, :accuracy, :calibration, :route]`
   - Measurements: duration
   - Metadata: action, confidence_level, score

### Known Limitations

1. **Candidate content required** - Strategies assume binary content; nil content is passed through
2. **Single routing pass** - No iterative routing or re-evaluation
3. **Metadata keys** - Nested metadata maps keep original key types (atoms vs strings)

### How to Run

```bash
# Run calibration gate tests
mix test test/jido_ai/accuracy/routing_result_test.exs
mix test test/jido_ai/accuracy/calibration_gate_test.exs

# Run all calibration tests together
mix test test/jido_ai/accuracy/routing_result_test.exs test/jido_ai/accuracy/calibration_gate_test.exs
```

### Next Steps (Future Work)

1. **6.3 Selective Generation** - Implement expected value calculation
2. **6.4 Uncertainty Quantification** - Distinguish aleatoric vs epistemic uncertainty
3. **Enhanced strategies**:
   - Configurable verification messages
   - Multi-language abstention messages
   - Custom strategy definitions

## Notes/Considerations

### Threshold Validation

High threshold must be greater than low threshold:
- Invalid: high_threshold: 0.3, low_threshold: 0.5
- Valid: high_threshold: 0.7, low_threshold: 0.4

### Telemetry Events

Event name: `[:jido, :accuracy, :calibration, :route]`

Measurements:
- `:duration` - Time taken for routing

Metadata:
- `:action` - Action taken
- `:confidence_level` - :high, :medium, :low
- `:score` - Actual confidence score

### Integration with Verification

When medium confidence triggers `:with_verification`, the gate can:
1. Add verification suggestions to response
2. Include confidence disclaimer
3. Suggest additional verification steps

### Abstention Messages

The abstain strategy should:
1. Explain why the system is abstaining
2. Suggest how the user can rephrase their question
3. Be helpful rather than just refusing to answer
