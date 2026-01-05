# TRM Module Integration - Feature Plan

**Branch**: `feature/trm-module-integration`
**Started**: 2026-01-05
**Status**: COMPLETED

## Problem Statement

The TRM (Tiny-Recursive-Model) strategy has three well-designed support modules:
- `Jido.AI.TRM.Reasoning` - Structured prompt building and response parsing for reasoning
- `Jido.AI.TRM.Supervision` - Structured prompt building and feedback parsing for supervision
- `Jido.AI.TRM.ACT` - Adaptive Computational Time for sophisticated early stopping

However, these modules are **not integrated** into the actual strategy/machine code:
1. The TRM Strategy builds prompts inline instead of delegating to Reasoning/Supervision modules
2. The Machine uses a simple threshold check instead of the full ACT decision logic
3. Response parsing (extracting insights, issues, quality scores) is not using the structured parsers

This means ~1500 lines of well-designed code with sophisticated algorithms is unused.

## Solution Overview

Properly integrate all three modules:

1. **Reasoning Module Integration**
   - Strategy uses `Reasoning.build_reasoning_prompt/1` for prompt construction
   - Machine can use `Reasoning.parse_reasoning_result/1` for response parsing
   - Use structured insight extraction instead of raw text handling

2. **Supervision Module Integration**
   - Strategy uses `Supervision.build_supervision_prompt/1` for supervision prompts
   - Strategy uses `Supervision.build_improvement_prompt/3` for improvement prompts
   - Machine uses `Supervision.parse_supervision_result/1` for feedback parsing
   - Use `Supervision.calculate_quality_score/1` instead of inline regex

3. **ACT Module Integration**
   - Machine maintains ACT state alongside main state
   - Use `ACT.make_decision/2` for early stopping decisions (not just threshold check)
   - Leverage convergence detection and expected improvement calculations
   - Store ACT history for analysis

## Implementation Plan

### Step 1: Integrate ACT Module into Machine
**Status**: COMPLETED

**Changes to `lib/jido_ai/trm/machine.ex`**:
- [x] Add `act_state` field to machine struct (stores ACT.new() state)
- [x] Replace `check_act_condition/1` with `ACT.make_decision/2`
- [x] Update `handle_improvement_result/2` to use ACT decision logic
- [x] Store confidence history for convergence detection
- [x] Add termination reason `:convergence_detected`

**Key code changes**:
```elixir
# In struct definition, add:
act_state: %{threshold: 0.9, current_confidence: 0.0, history: []}

# Replace check_act_condition with:
defp check_act_decision(machine) do
  ACT.make_decision(machine.act_state, machine.latent_state)
end
```

### Step 2: Integrate Supervision Module Parsing
**Status**: COMPLETED

**Changes to `lib/jido_ai/trm/machine.ex`**:
- [x] Replace `extract_quality_score/1` with `Supervision.parse_supervision_result/1`
- [x] Store parsed feedback structure instead of raw text
- [x] Extract issues and suggestions for structured feedback

**Key code changes**:
```elixir
# In handle_supervision_result, replace:
quality_score = extract_quality_score(feedback_text)

# With:
parsed_feedback = Supervision.parse_supervision_result(feedback_text)
quality_score = parsed_feedback.quality_score
```

### Step 3: Integrate Reasoning Module Prompts
**Status**: COMPLETED

**Changes to `lib/jido_ai/strategies/trm.ex`**:
- [x] Replace inline `build_reasoning_directive/4` prompts with `Reasoning.build_reasoning_prompt/1`
- [x] Use `Reasoning.format_reasoning_trace/1` instead of inline implementation
- [x] Remove duplicate `format_reasoning_trace/1` function

**Key code changes**:
```elixir
defp build_reasoning_directive(id, context, model, _config) do
  # Use Reasoning module instead of inline prompt building
  {system, user} = Reasoning.build_reasoning_prompt(%{
    question: context[:question],
    current_answer: context[:current_answer],
    latent_state: context[:latent_state]
  })

  messages = [
    %{role: :system, content: system},
    %{role: :user, content: user}
  ]

  Directive.ReqLLMStream.new!(%{
    id: id,
    model: model,
    context: convert_to_reqllm_context(messages),
    tools: [],
    metadata: %{phase: :reasoning}
  })
end
```

### Step 4: Integrate Supervision Module Prompts
**Status**: COMPLETED

**Changes to `lib/jido_ai/strategies/trm.ex`**:
- [x] Replace inline `build_supervision_directive/4` with `Supervision.build_supervision_prompt/1`
- [x] Replace inline `build_improvement_directive/4` with `Supervision.build_improvement_prompt/3`
- [x] Pass previous feedback for iterative improvement context

**Key code changes**:
```elixir
defp build_supervision_directive(id, context, model, _config) do
  {system, user} = Supervision.build_supervision_prompt(%{
    question: context[:question],
    answer: context[:current_answer],
    step: context[:step],
    previous_feedback: context[:previous_feedback]
  })
  # ... create directive
end

defp build_improvement_directive(id, context, model, _config) do
  # Parse feedback for structured improvement prompt
  feedback = Supervision.parse_supervision_result(context[:feedback])

  {system, user} = Supervision.build_improvement_prompt(
    context[:question],
    context[:current_answer],
    feedback
  )
  # ... create directive
end
```

### Step 5: Update Default Prompts
**Status**: COMPLETED

**Changes to `lib/jido_ai/strategies/trm.ex`**:
- [x] Update `default_reasoning_prompt/0` to delegate to `Reasoning.default_reasoning_system_prompt/0`
- [x] Update `default_supervision_prompt/0` to delegate to `Supervision.default_supervision_system_prompt/0`
- [x] Update `default_improvement_prompt/0` to delegate to `Supervision.default_improvement_system_prompt/0`

### Step 6: Update Context Builders
**Status**: COMPLETED

**Changes to `lib/jido_ai/trm/machine.ex`**:
- [x] Machine directive context includes parsed_feedback for improvement phase
- [x] Context builders provide all required data for Reasoning/Supervision modules

### Step 7: Fix Signal Route Naming
**Status**: COMPLETED

**Changes to `lib/jido_ai/strategies/trm.ex`**:
- [x] Changed `"trm.reason"` to `"trm.query"` for consistency with other strategies

### Step 8: Update Tests
**Status**: COMPLETED

- [x] Updated machine tests to use SCORE: format for Supervision module parsing
- [x] Updated strategy tests for signal route naming change
- [x] All existing integration tests pass

### Step 9: Run Full Test Suite
**Status**: COMPLETED

- [x] Run `mix test` to verify no regressions
- [x] All 1115 tests pass

## Success Criteria

1. ✅ TRM Strategy delegates prompt building to Reasoning and Supervision modules
2. ✅ TRM Machine uses ACT.make_decision/2 for early stopping (not just threshold)
3. ✅ Machine uses Supervision.parse_supervision_result/1 for feedback parsing
4. ✅ Convergence detection works (stops when improvements plateau)
5. ✅ All existing tests continue to pass (1115 tests, 0 failures)
6. ✅ Signal route uses consistent naming ("trm.query")

## Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_ai/trm/machine.ex` | ACT integration, Supervision parsing |
| `lib/jido_ai/strategies/trm.ex` | Reasoning/Supervision prompt delegation |
| `test/jido_ai/trm/machine_test.exs` | Tests for ACT state management |
| `test/jido_ai/strategies/trm_test.exs` | Tests for prompt delegation |

## Notes

- Keep backward compatibility with existing tests
- The modules already have excellent documentation and type specs
- ACT module has more features than currently needed - integrate core functionality first
- Supervision module's `prioritize_suggestions/1` is nice-to-have for improvement prompts
