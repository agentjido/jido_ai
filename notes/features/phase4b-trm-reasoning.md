# Phase 4B.3 TRM Recursive Reasoning Engine - Feature Plan

**Branch**: `feature/phase4b-trm-integration`
**Started**: 2026-01-04
**Status**: COMPLETED

## Problem Statement

The TRM Machine and Strategy are implemented, but they rely on the TRM Strategy's inline prompt construction. Section 4B.3 calls for a dedicated Reasoning module that:
- Provides structured prompt templates for recursive reasoning
- Parses LLM reasoning responses to extract insights
- Calculates reasoning confidence scores
- Formats reasoning traces for inclusion in prompts

## Solution Overview

Create a `Jido.AI.TRM.Reasoning` module that provides:
1. Prompt construction for the reasoning phase
2. Result parsing to extract insights from LLM responses
3. Confidence calculation from response quality
4. Reasoning trace formatting

This module will be used by the TRM Strategy to build reasoning-phase directives.

## Implementation Plan

### 4B.3.1 Reasoning Module Setup
**Status**: COMPLETED

- [x] Create `Jido.AI.TRM.Reasoning` module at `lib/jido_ai/trm/reasoning.ex`
- [x] Define `@type reasoning_context :: %{question: String.t(), current_answer: String.t(), latent_state: map()}`
- [x] Define `@type reasoning_result` for parsed responses
- [x] Define `@type parsed_insight` for structured insights

### 4B.3.2 Reasoning Prompt Templates
**Status**: COMPLETED

- [x] Implement `build_reasoning_prompt/1` taking context, returns {system, user} tuple
- [x] Define `default_reasoning_system_prompt/0` with structured format markers (INSIGHT, ISSUE, MISSING, SUGGESTION, CONFIDENCE)
- [x] Implement `build_latent_update_prompt/3` for updating latent state from reasoning
- [x] Implement `format_reasoning_trace/1` for including history in prompts (handles list, string, nil)

### 4B.3.3 Reasoning Result Parsing
**Status**: COMPLETED

- [x] Implement `parse_reasoning_result/1` extracting insights, issues, suggestions, confidence
- [x] Implement `extract_key_insights/1` identifying important points with types and importance
- [x] Implement `calculate_reasoning_confidence/1` from response quality
- [x] Support explicit CONFIDENCE markers and heuristic calculation
- [x] Handle certainty/uncertainty language markers

### 4B.3.4 Unit Tests
**Status**: COMPLETED

- [x] Test `build_reasoning_prompt/1` for initial and subsequent reasoning
- [x] Test `default_reasoning_system_prompt/0` includes format markers
- [x] Test `build_latent_update_prompt/3` includes context
- [x] Test `format_reasoning_trace/1` handles various input types
- [x] Test `parse_reasoning_result/1` extracts all marker types
- [x] Test `extract_key_insights/1` assigns types and importance
- [x] Test `calculate_reasoning_confidence/1` from explicit and heuristic sources
- [x] Test integration scenarios for full reasoning cycle

## Test Results

- TRM Reasoning tests: 36 tests, 0 failures
- All TRM tests: 79 tests, 0 failures
- Full test suite: 991 tests, 0 failures

## Files Created/Modified

| File | Change |
|------|--------|
| `lib/jido_ai/trm/reasoning.ex` | Created (380 lines) |
| `test/jido_ai/trm/reasoning_test.exs` | Created (36 tests) |
| `notes/features/phase4b-trm-reasoning.md` | Updated to COMPLETED |

## Notes

- The Reasoning module uses structured format markers (INSIGHT:, ISSUE:, MISSING:, SUGGESTION:, CONFIDENCE:)
- These markers allow for reliable parsing of LLM responses
- Confidence is calculated from explicit markers or heuristics (certainty language, insight/issue ratio)
- The module can be integrated into TRM Strategy to replace inline prompt construction
