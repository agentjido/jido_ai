# Feature Planning Document: Phase 4.1 - Critique Component

**Status:** Complete
**Section:** 4.1 - Critique Component
**Dependencies:** Phase 1 (Self-Consistency), Phase 2 (Verifier System), Phase 3 (Search Controllers)
**Branch:** `feature/accuracy-phase-4-1-critique`

## Problem Statement

The accuracy improvement system currently has:
- Self-consistency with candidate generation and aggregation
- Multiple verification methods (outcome, PRM, deterministic, tool-based)
- Search algorithms (Beam Search, MCTS, Diverse Decoding)

However, it lacks **critique capabilities** that enable:
1. Self-reflection - the model cannot critique its own responses
2. Issue identification - no structured way to identify specific problems
3. Actionable feedback - critique isn't formatted for revision
4. Iterative refinement - cannot improve responses through critique-revise cycles

**Impact**: Without critique, we miss opportunities to:
- Enable reflection loops for iterative improvement
- Provide structured feedback for revision
- Support self-refine and Reflexion patterns
- Improve responses beyond initial generation

## Solution Overview

Implement critique components that analyze and identify issues in candidate responses:

1. **Critique Behavior** - Interface for critique generation
2. **CritiqueResult** - Structured critique data type
3. **LLMCritiquer** - LLM-based self-critique
4. **ToolCritiquer** - Tool-based verification critique

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Critique interface | Behavior pattern | Allows pluggable critique strategies |
| Result structure | Struct with severity | Enables convergence detection and revision decisions |
| LLM critique | Structured prompt + parsing | Ensures consistent critique format |
| Tool critique | Aggregate tool results | Leverages existing verification infrastructure |
| Severity scoring | 0.0-1.0 with levels | Quantifies improvement potential |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/
├── critique.ex                    # Behavior definition
├── critique_result.ex             # Result struct
└── critiquers/
    ├── llm_critiquer.ex           # LLM-based critique
    └── tool_critiquer.ex          # Tool-based critique
```

### Dependencies

- **Existing**: `Candidate`, `VerificationResult` from Phase 1
- **Existing**: LLM generation via `ReqLLM`
- **Existing**: Tool execution via `Jido.AI.Tools`

### File Locations

| File | Purpose |
|------|---------|
| `lib/jido_ai/accuracy/critique.ex` | Critique behavior |
| `lib/jido_ai/accuracy/critique_result.ex` | Critique result type |
| `lib/jido_ai/accuracy/critiquers/llm_critiquer.ex` | LLM critique implementation |
| `lib/jido_ai/accuracy/critiquers/tool_critiquer.ex` | Tool critique implementation |
| `test/jido_ai/accuracy/critique_test.exs` | Behavior tests |
| `test/jido_ai/accuracy/critique_result_test.exs` | Result type tests |
| `test/jido_ai/accuracy/critiquers/llm_critiquer_test.exs` | LLM critiquer tests |
| `test/jido_ai/accuracy/critiquers/tool_critiquer_test.exs` | Tool critiquer tests |

## Success Criteria

1. **Critique Behavior**: Well-defined interface for critique generation
2. **CritiqueResult**: Structured data with issues, suggestions, severity
3. **LLMCritiquer**: Generates structured critiques from LLM
4. **ToolCritiquer**: Aggregates tool results into critique format
5. **Test Coverage**: Minimum 85% for all critique components
6. **Integration**: Works with existing Candidate and VerificationResult types

## Implementation Plan

### Step 1: CritiqueResult (4.1.2) ✅

**Purpose**: Define the data structure for critique results

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/critique_result.ex`
- [x] Define defstruct with fields:
  - `:issues` - List of identified issues
  - `:suggestions` - List of improvement suggestions
  - `:severity` - Overall severity score (0.0-1.0)
  - `:feedback` - Natural language feedback
  - `:actionable` - Whether issues are actionable
  - `:metadata` - Additional metadata
- [x] Implement `new/1` constructor with validation
- [x] Implement `has_issues?/1` - Returns true if issues present
- [x] Implement `should_refine?/1` - Returns true if severity > threshold
- [x] Implement `add_issue/2` - Adds issue to result
- [x] Implement `severity_level/1` - Returns :low, :medium, or :high
- [x] Write tests (38 tests passing)

### Step 2: Critique Behavior (4.1.1) ✅

**Purpose**: Define the interface for critique generators

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/critique.ex`
- [x] Add `@moduledoc` explaining critique concept
- [x] Define `@callback critique/2`
- [x] Add optional `@callback critique_batch/2` for multiple candidates
- [x] Document critique patterns and usage
- [x] Write tests for behavior module (12 tests passing)

### Step 3: LLMCritiquer (4.1.3) ✅

**Purpose**: Use LLM to generate structured critiques

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/critiquers/llm_critiquer.ex`
- [x] Adopt Critique behavior
- [x] Define configuration struct with:
  - `:model` - Model for critique
  - `:prompt_template` - Custom critique prompt
  - `:domain` - Optional domain for specialized critique
- [x] Implement `critique/2`:
  - Build critique prompt with candidate content
  - Call LLM with structured output request
  - Parse JSON response into CritiqueResult
- [x] Implement severity scoring from critique content
- [x] Handle LLM errors gracefully
- [x] Write tests (18 tests passing)

### Step 4: ToolCritiquer (4.1.4) ✅

**Purpose**: Use tool execution to generate critiques

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/critiquers/tool_critiquer.ex`
- [x] Adopt Critique behavior
- [x] Define configuration struct with:
  - `:tools` - List of tools to run
  - `:severity_map` - Mapping from tool results to severity
- [x] Implement `critique/2`:
  - Execute configured tools
  - Aggregate results
  - Convert to CritiqueResult format
- [x] Handle tool failures gracefully
- [x] Write tests (19 tests passing)

### Step 5: Unit Tests (4.1.5) ✅

**Tests completed**:
- [x] `critique_result_test.exs` (38 tests)
- [x] `critique_test.exs` (12 tests)
- [x] `llm_critiquer_test.exs` (18 tests)
- [x] `tool_critiquer_test.exs` (19 tests)

**Total**: 87 tests, 0 failures

## Current Status

**Status**: Complete ✅

**Completed**:
- [x] Created feature branch `feature/accuracy-phase-4-1-critique`
- [x] Created planning document
- [x] Implemented CritiqueResult struct (38 tests)
- [x] Implemented Critique behavior (12 tests)
- [x] Implemented LLMCritiquer (18 tests)
- [x] Implemented ToolCritiquer (19 tests)

**Test Summary**: 87 tests, 0 failures

**Files Created**:
- `lib/jido_ai/accuracy/critique.ex` - Critique behavior
- `lib/jido_ai/accuracy/critique_result.ex` - Critique result type
- `lib/jido_ai/accuracy/critiquers/llm_critiquer.ex` - LLM critique implementation
- `lib/jido_ai/accuracy/critiquers/tool_critiquer.ex` - Tool critique implementation
- `test/jido_ai/accuracy/critique_test.exs` - Behavior tests
- `test/jido_ai/accuracy/critique_result_test.exs` - Result type tests
- `test/jido_ai/accuracy/critiquers/llm_critiquer_test.exs` - LLM critiquer tests
- `test/jido_ai/accuracy/critiquers/tool_critiquer_test.exs` - Tool critiquer tests

## Notes/Considerations

### Critique Prompt Design

The LLM critique prompt should:
1. Request analysis of factual correctness
2. Check for logical consistency
3. Identify reasoning gaps
4. Suggest specific improvements
5. Rate overall severity

Example prompt structure:
```
Critique the following response for:
1. Factual errors
2. Logical inconsistencies
3. Missing reasoning steps
4. Areas for improvement

Response: {candidate.content}

Provide your critique as JSON:
{
  "issues": ["issue1", "issue2"],
  "suggestions": ["suggestion1"],
  "severity": 0.5
}
```

### Severity Scoring

- **Low (0.0-0.3)**: Minor issues, optional improvements
- **Medium (0.3-0.7)**: Notable issues, should address
- **High (0.7-1.0)**: Critical issues, must address

### Tool Critique Mapping

Tool results map to severity:
- Pass → Low severity (0.1)
- Warnings → Medium severity (0.5)
- Failures → High severity (0.8)

### Future Enhancements

1. **Few-shot learning**: Store successful critiques as examples
2. **Domain-specific critiquers**: Specialized prompts for code, math, etc.
3. **Meta-critique**: Critique of critique quality
4. **Confidence scores**: LLM confidence in critique accuracy
