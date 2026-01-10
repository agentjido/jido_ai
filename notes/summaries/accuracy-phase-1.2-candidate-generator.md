# Summary: Accuracy Phase 1.2 - Candidate Generator

**Date**: 2025-01-10
**Feature Branch**: `feature/accuracy-phase-1-2-candidate-generator`
**Target Branch**: `feature/accuracy`

## Overview

Implemented the candidate generator system for the Jido.AI accuracy improvement system. This provides the foundation for self-consistency and other test-time compute scaling techniques by generating multiple diverse candidate responses from a single prompt.

## Files Created

### Implementation Files

1. **`lib/jido_ai/accuracy/generator.ex`** (143 lines)
   - Behavior defining the generator interface
   - Callbacks: `generate_candidates/3`, `generate_candidates_async/3`, `generate_with_reasoning/3`
   - Type definitions: `t/0`, `opts/0`, `generate_result/0`
   - Includes comprehensive documentation and usage examples

2. **`lib/jido_ai/accuracy/generators/llm_generator.ex`** (360 lines)
   - LLM-based implementation using ReqLLM directly
   - Struct with fields: `model`, `num_candidates`, `temperature_range`, `timeout`, `max_concurrency`, `system_prompt`
   - Functions: `new/1`, `new!/1`, `generate_candidates/3`, `generate_candidates_async/3`, `generate_with_reasoning/3`
   - Private helpers: temperature randomization, CoT parsing, token counting, message building

### Test Files

3. **`test/jido_ai/accuracy/generator_test.exs`** (35 lines)
   - 5 tests covering behavior contract verification
   - Tests: function_exported checks for all three callbacks

4. **`test/jido_ai/accuracy/generators/llm_generator_test.exs`** (211 lines)
   - 24 tests covering LLMGenerator functionality
   - Tests: constructor with all options, temperature validation, async generation, CoT parsing

## Test Results

```
mix test test/jido_ai/accuracy/generator_test.exs test/jido_ai/accuracy/generators/llm_generator_test.exs
Running ExUnit with seed: 508007, max_cases: 40
Excluding tags: [:flaky]

.....
.........................
Finished in 0.1 seconds (0.1s async, 0.00s sync)
29 tests, 0 failures
```

## Code Quality

- **Credo**: No new warnings introduced
- **Style**: Follows existing Jido.AI code patterns
- **TypeSpecs**: Full @type and @spec annotations

## Key Design Decisions

1. **Behavior Pattern**: Used `@behaviour` for extensibility - other generators can be added later

2. **Callback Signature**: Callbacks take 3 parameters (generator, prompt, opts) with opts defaulting to empty list, making both 2-arity and 3-arity calls work

3. **ReqLLM Direct Calls**: Generator calls `ReqLLM.Generation.generate_text/3` directly without going through Jido's directive system for simplicity

4. **Parallel Generation**: Uses `Task.async_stream` with configurable `max_concurrency` to control parallel API calls

5. **Temperature Randomization**: Each candidate gets a random temperature within the configured range for diversity

6. **Chain-of-Thought Parsing**: Uses `String.split` with patterns like `\n\nFinal answer:` to separate reasoning from final answer

7. **Error Handling**: Catches exceptions and returns `{:error, reason}` tuples; filters out failed candidates from results

## Technical Notes

### CoT Pattern Matching
The `parse_reasoning_content/1` function tries multiple patterns to split reasoning from the final answer:
- `\n\nFinal answer:`
- `\n\nTherefore:`
- `\n\nThus:`
- `\n\nSo:`
- `\n\nThe answer is:`
- `\n\nResult:`

If no pattern matches, the full content is returned with empty reasoning.

### Temperature Validation
The `valid_temperature_range?/1` function validates:
- Must be a tuple `{min, max}`
- Both values must be numbers
- min must be >= 0
- max must be <= 2 (standard LLM range)
- min must be <= max

## Next Steps

1. Mark tasks as completed in `notes/planning/accuracy/phase-01-self-consistency.md`
2. Commit and merge to `feature/accuracy` branch
3. Proceed to Phase 1.3: Candidate Aggregation

## Notes

- The generators subdirectory structure is established for future generator implementations
- The `@behaviour` declaration was added to LLMGenerator after the behavior callbacks were finalized
- Test helpers were created to test private functions like `random_temperature/1` and `parse_reasoning_content/1`
