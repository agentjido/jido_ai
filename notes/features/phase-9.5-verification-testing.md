# Feature: Verification and Testing - Fix All Remaining Warnings (Section 9.5)

## Status: In Progress

## Problem Statement

Section 9.5 is the "Verification and Testing" phase, but to achieve zero warnings as required by the Phase 9 success criteria, we need to first fix all ~37 remaining compiler warnings.

### Current Warnings Breakdown

| Category | Count | Status |
|----------|-------|--------|
| Unreachable Clauses | 6 | Pending |
| Unused Variables | 10 | Pending |
| Unused Aliases | 4 | Pending |
| Unused Imports | 2 | Pending |
| Unused Functions | 3 | Pending |
| Code Style Issues | 2 | Pending |
| Other Issues (@impl, @doc, etc) | 3 | Pending |
| ReqLLM API Issue | 1 | Pending |

**Total: 31 unique warnings (some with multiple occurrences)**

## Specific Issues to Fix

### 1. Unreachable Clauses (6 warnings)

- `lib/jido_ai/accuracy/stages/calibration_stage.ex:145` - CalibrationStage.apply_calibration/3
- `lib/jido_ai/accuracy/revisers/targeted_reviser.ex:66` - TargetedReviser.new!/1
- `lib/jido_ai/accuracy/stages/verification_stage.ex:145` - VerificationStage.verify_candidates/3
- `lib/jido_ai/accuracy/verifiers/code_execution_verifier.ex:319` - CodeExecutionVerifier.verify_batch/3
- `lib/jido_ai/accuracy/search/beam_search.ex:207` - BeamSearch.run_iterations/7
- `lib/jido_ai/accuracy/search/beam_search.ex:232` - BeamSearch.expand_beam/7

### 2. Unused Variables (10 warnings)

- `model` - `lib/jido_ai/accuracy/generators/llm_generator.ex:352`
- `opts` - `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex:208`
- `count` - `lib/jido_ai/accuracy/verifiers/llm_outcome_verifier.ex:452`
- `mid_score` - `lib/jido_ai/accuracy/verifiers/llm_outcome_verifier.ex:454`
- `count` - `lib/jido_ai/accuracy/verifiers/llm_outcome_verifier.ex:503`
- `best_score` - `lib/jido_ai/accuracy/search/diverse_decoding.ex:308`
- `e` - `lib/jido_ai/accuracy/verification_runner.ex:479`
- `context` - `lib/jido_ai/accuracy/revisers/targeted_reviser.ex:142`
- `context` - `lib/jido_ai/accuracy/revisers/targeted_reviser.ex:182`
- `candidate` - `lib/jido_ai/accuracy/verifiers/code_execution_verifier.ex:357`

### 3. Unused Aliases (4 warnings)

- `VerificationResult` - `lib/jido_ai/accuracy/stages/verification_stage.ex:32`
- `CritiqueResult` - `lib/jido_ai/accuracy/stages/reflection_stage.ex:32`
- `Candidate` - `lib/jido_ai/accuracy/verification_result.ex:63`
- `BeamSearch` - `lib/jido_ai/accuracy/search/beam_search.ex:81`
- `BaseActionHelpers` - `lib/jido_ai/skills/llm/actions/embed.ex:66`

### 4. Unused Imports (2 warnings)

- `get_attr: 2` in `lib/jido_ai/accuracy/estimators/attention_confidence.ex:69`
- `get_attr: 2` in `lib/jido_ai/accuracy/compute_budgeter.ex:66`

### 5. Unused Functions (3 warnings)

- `error_result/2` - `lib/jido_ai/accuracy/verifiers/static_analysis_verifier.ex` (and others)
- `get_attr/2` - `lib/jido_ai/accuracy/calibration_gate.ex:396`
- `on_error?/1` - `lib/jido_ai/accuracy/verification_runner.ex:639`

### 6. Code Style Issues (2 warnings)

- `pass?/2` - `lib/jido_ai/accuracy/verification_result.ex:170` - Multiple clauses with defaults
- `allocate/3` - `lib/jido_ai/accuracy/compute_budgeter.ex:190` - Multiple clauses with defaults
- Heredoc indentation - `lib/jido_ai/accuracy/compute_budgeter.ex:357`

### 7. Other Issues (4 warnings)

- `ReqLLM.Tool.name/1` undefined - `lib/jido_ai/skills/tool_calling/actions/call_with_tools.ex:119`
- `@impl` not set - `lib/jido_ai/examples/react_demo_agent.ex:18`
- `@doc` redefinition - `lib/jido_ai/accuracy/signal.ex:267`
- `@default_num_candidates` unused - `lib/jido_ai/accuracy/compute_budget.ex:101`
- Underscored variable used - `_content` in `lib/jido_ai/accuracy/revisers/targeted_reviser.ex:274`
- Underscored variable used - `_stream_id` in `lib/jido_ai/skills/streaming/actions/start_stream.ex:244,247`
- Underscored variable used - `_text` in `lib/jido_ai/skills/streaming/actions/start_stream.ex:247`

## Solution Overview

Fix all remaining warnings systematically by category:
1. Remove unreachable error clauses
2. Prefix unused variables with underscore
3. Remove unused aliases and imports
4. Remove unused functions or prefix with underscore
5. Fix code style issues (default values, heredoc)
6. Fix other issues (@impl, @doc, API usage)

## Implementation Plan

### Step 1: Fix Unreachable Clauses

Remove all unreachable `{:error, _}` pattern matches.

### Step 2: Fix Unused Variables

Prefix all unused variables with underscore.

### Step 3: Fix Unused Aliases and Imports

Remove unused alias and import statements.

### Step 4: Fix Code Style Issues

Fix `pass?/2` and `allocate/3` default values, fix heredoc indentation.

### Step 5: Fix Other Issues

Fix @impl annotation, remove duplicate @doc, remove unused module attributes.

### Step 6: Verification

Run `mix compile` to verify zero warnings, then run tests.

## Success Criteria

1. `mix compile` produces zero warnings
2. `mix format` passes
3. `mix test` passes
4. `mix credo` passes

## Current Status

- **Step 1:** Pending
- **Step 2:** Pending
- **Step 3:** Pending
- **Step 4:** Pending
- **Step 5:** Pending
- **Step 6:** Pending
