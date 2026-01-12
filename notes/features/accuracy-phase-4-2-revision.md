# Feature Planning Document: Phase 4.2 - Revision Component

**Status:** Completed
**Section:** 4.2 - Revision Component
**Dependencies:** Phase 4.1 (Critique Component)
**Branch:** `feature/accuracy-phase-4-2-revision`

## Problem Statement

The accuracy improvement system currently has:
- Critique capabilities (LLMCritiquer, ToolCritiquer)
- Structured critique feedback with issues and suggestions

However, it lacks **revision capabilities** that enable:
1. Response improvement based on critique feedback
2. Automated correction of identified issues
3. Iterative refinement through critique-revise cycles
4. Tracking changes between revision iterations

**Impact**: Without revision, the critique system can identify problems but cannot automatically fix them, missing the core benefit of self-reflection loops.

## Solution Overview

Implement revision components that improve candidate responses based on critique feedback:

1. **Revision Behavior** - Interface for revision implementations
2. **LLMReviser** - LLM-based revision that incorporates critique feedback
3. **TargetedReviser** - Specialized revision for specific issue types (code, reasoning, format)

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Revision interface | Behavior pattern | Allows pluggable revision strategies |
| LLM revision | Structured prompt with critique | Ensures feedback is incorporated |
| Change tracking | Diff-like metadata | Enables auditing of improvements |
| Targeted revision | Type-specific handlers | More efficient than full rewrites |
| Preservation option | Configurable | Allows keeping correct parts |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/
├── revision.ex                    # Behavior definition
└── revisers/
    ├── llm_reviser.ex             # LLM-based revision
    └── targeted_reviser.ex        # Type-specific revision
```

### Dependencies

- **Existing**: `Candidate`, `CritiqueResult` from Phase 4.1
- **Existing**: LLM generation via `ReqLLM`
- **Existing**: Critique behavior and critiquers

### File Locations

| File | Purpose |
|------|---------|
| `lib/jido_ai/accuracy/revision.ex` | Revision behavior |
| `lib/jido_ai/accuracy/revisers/llm_reviser.ex` | LLM revision implementation |
| `lib/jido_ai/accuracy/revisers/targeted_reviser.ex` | Targeted revision implementation |
| `test/jido_ai/accuracy/revision_test.exs` | Behavior tests |
| `test/jido_ai/accuracy/revisers/llm_reviser_test.exs` | LLM reviser tests |
| `test/jido_ai/accuracy/revisers/targeted_reviser_test.exs` | Targeted reviser tests |

## Success Criteria

1. **Revision Behavior**: Well-defined interface for revision generation
2. **LLMReviser**: Incorporates critique feedback into revisions
3. **TargetedReviser**: Handles code, reasoning, and format revisions
4. **Change Tracking**: Tracks what was changed between revisions
5. **Test Coverage**: Minimum 85% for all revision components
6. **Integration**: Works with existing CritiqueResult and Candidate types

## Implementation Plan

### Step 1: Revision Behavior (4.2.1)

**Purpose**: Define the interface for revision implementations

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/revision.ex`
- [x] Add `@moduledoc` explaining revision concept
- [x] Define `@callback revise/3`:
  ```elixir
  @callback revise(
    candidate :: Candidate.t(),
    critique :: CritiqueResult.t(),
    context :: map()
  ) :: {:ok, Candidate.t()} | {:error, term()}
  ```
- [x] Add helper `reviser?/1` to check if module implements behavior
- [x] Document revision patterns and usage
- [x] Write tests for behavior module

### Step 2: LLMReviser (4.2.2)

**Purpose**: Use LLM to revise based on critique feedback

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/revisers/llm_reviser.ex`
- [x] Adopt Revision behavior
- [x] Define configuration struct with:
  - `:model` - Model for revision
  - `:prompt_template` - Custom revision prompt
  - `:preserve_correct` - Whether to preserve correct parts
  - `:temperature` - Temperature for LLM calls
- [x] Implement `revise/3`:
  - Build revision prompt with candidate and critique
  - Call LLM with structured output request
  - Parse response into revised candidate
- [x] Include critique issues and suggestions in prompt
- [x] Implement `diff/2` to show changes between versions
- [x] Track revision metadata (iteration count, changes made)
- [x] Write tests

### Step 3: TargetedReviser (4.2.3)

**Purpose**: Implement specialized revision for specific issue types

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/revisers/targeted_reviser.ex`
- [x] Adopt Revision behavior
- [x] Implement `revise_code/3` for code-specific revision
  - Handle syntax errors
  - Fix logic issues
  - Apply linting suggestions
- [x] Implement `revise_reasoning/3` for reasoning revision
  - Fix logical inconsistencies
  - Add missing steps
  - Correct factual errors
- [x] Implement `revise_format/3` for format fixes
  - Fix structure issues
  - Improve readability
  - Standardize output
- [x] Write tests

### Step 4: Unit Tests (4.2.4)

**Tests to write**:
- [x] `revision_test.exs`:
  - Test behavior interface
  - Test `reviser?/1` helper

- [x] `llm_reviser_test.exs`:
  - Test `revise/3` improves candidate
  - Test critique feedback is incorporated
  - Test no new errors introduced
  - Test `diff/2` shows changes
  - Test preservation of correct parts

- [x] `targeted_reviser_test.exs`:
  - Test code revision
  - Test reasoning revision
  - Test format revision
  - Test type detection and routing

## Current Status

**Status**: Completed

**Completed**:
- Created feature branch `feature/accuracy-phase-4-2-revision`
- Created planning document
- Implemented Revision behavior interface (16 tests passing)
- Implemented LLMReviser with EEx templates and domain guidelines (20 tests passing)
- Implemented TargetedReviser for code/reasoning/format fixes (16 tests passing)
- All 52 revision tests passing

**Test Results**:
- `revision_test.exs`: 16 tests passing
- `llm_reviser_test.exs`: 20 tests passing
- `targeted_reviser_test.exs`: 16 tests passing
- **Total: 52 tests, 0 failures**

**In Progress**:
- None

**Next**:
- Create summary document
- Ask user for permission to commit and merge

## Notes/Considerations

### Revision Prompt Design

The LLM revision prompt should:
1. Include the original candidate content
2. Include the critique (issues, suggestions, severity)
3. Request improvements for identified issues
4. Ask to preserve correct parts
5. Request structured output showing what changed

Example prompt structure:
```
Original Response:
{candidate.content}

Critique:
Issues: {critique.issues}
Suggestions: {critique.suggestions}

Please revise the response to address these issues.
Preserve parts that are already correct.
Explain what you changed and why.
```

### Change Tracking

Track revisions through:
- Revision iteration number
- List of changes made
- Previous version reference
- Diff between versions

### Preservation Strategy

When `preserve_correct` is enabled:
- Identify correct parts (no issues raised)
- Only modify sections with issues
- Maintain structure and style of correct parts

### Future Enhancements

1. **Multi-step revision**: Break complex revisions into steps
2. **Confidence scoring**: LLM confidence in revision quality
3. **Rollback**: Revert to previous version if revision degrades quality
4. **Revision templates**: Domain-specific revision patterns
