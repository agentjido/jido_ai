# Feature: Accuracy Phase 1.2 - Candidate Generator

## Problem Statement

Jido.AI needs a candidate generator system to support self-consistency and other test-time compute scaling algorithms. The generator must:

1. Generate multiple candidate responses from a single prompt
2. Support varied sampling via temperature randomization
3. Enable parallel generation for efficiency
4. Support Chain-of-Thought (CoT) prompts with separate reasoning traces
5. Track token usage for cost management
6. Handle API errors and rate limiting gracefully

**Impact**: Without a candidate generator, self-consistency and other accuracy improvement techniques cannot be implemented.

## Solution Overview

Create a behavior-based generator system with a standard LLM implementation:

1. **`Jido.AI.Accuracy.Generator`** - Behavior defining the generator interface
2. **`Jido.AI.Accuracy.Generators.LLMGenerator`** - LLM-based implementation using ReqLLM

**Key Design Decisions**:
- Use `@behaviour` pattern for extensibility (other generators can be added later)
- Use `ReqLLM.Generation.generate_text/3` directly (not through directives)
- Support parallel generation via `Task.async_stream` with configurable max_concurrency
- Temperature randomization within a specified range for diversity
- Track per-candidate token usage from ReqLLM response metadata

## Agent Consultations Performed

**Codebase Research**:
- Reviewed `Jido.AI.Algorithms.Algorithm` behavior pattern
- Reviewed existing ReqLLM usage patterns in `Jido.AI.Helpers`
- Reviewed `Jido.AI.Config` for model resolution
- Reviewed `Jido.AI.Accuracy.Candidate` for target data structure

No external research needed - this follows established patterns in the codebase.

## Technical Details

### File Locations

**New Files**:
- `lib/jido_ai/accuracy/generator.ex` - Behavior definition
- `lib/jido_ai/accuracy/generators/llm_generator.ex` - LLM implementation
- `test/jido_ai/accuracy/generator_test.exs` - Behavior tests
- `test/jido_ai/accuracy/generators/llm_generator_test.exs` - Implementation tests

### Dependencies

- **Existing**: `req_llm` (already in mix.exs)
- **Existing**: `Jido.AI.Accuracy.Candidate` (from Phase 1.1)
- **Existing**: `Jido.AI.Config` for model resolution

### Generator Behavior Definition

```elixir
@callback generate_candidates(
  generator :: term(),
  prompt :: String.t(),
  opts :: keyword()
) :: {:ok, [Jido.AI.Accuracy.Candidate.t()]} | {:error, term()}

@callback generate_candidates_async(
  generator :: term(),
  prompt :: String.t(),
  opts :: keyword()
) :: Task.t()

@callback generate_with_reasoning(
  generator :: term(),
  prompt :: String.t(),
  opts :: keyword()
) :: {:ok, [Jido.AI.Accuracy.Candidate.t()]} | {:error, term()}
```

### LLMGenerator Configuration Schema

```elixir
@schema %{
  model: Zoi.string() |> Zoi.default("anthropic:claude-haiku-4-5"),
  num_candidates: Zoi.positive_integer() |> Zoi.default(5),
  temperature_range: Zoi.tuple({Zoi.number(), Zoi.number()}) |> Zoi.default({0.0, 1.0}),
  timeout: Zoi.positive_integer() |> Zoi.default(30_000),
  max_concurrency: Zoi.positive_integer() |> Zoi.default(3),
  system_prompt: Zoi.string() |> Zoi.default(nil),
  include_reasoning: Zoi.boolean() |> Zoi.default(false)
}
```

### Usage Example

```elixir
# Basic usage
generator = LLMGenerator.new!(%{
  model: :fast,
  num_candidates: 5,
  temperature_range: {0.5, 1.0}
})

{:ok, candidates} = Generator.generate_candidates(generator, "What is 2+2?")

# With Chain-of-Thought
{:ok, candidates} = Generator.generate_with_reasoning(
  generator,
  "Solve step by step: 15 * 23 + 7"
)
```

## Success Criteria

1. `Generator` behavior defined with all required callbacks
2. `LLMGenerator` implements behavior correctly
3. `generate_candidates/2` returns N candidates with unique content
4. `temperature_range` produces diverse outputs
5. Parallel generation completes faster than sequential
6. Token counting is accurate from ReqLLM metadata
7. Error handling for API failures returns proper errors
8. `generate_candidates_async/2` returns Task that completes to candidates
9. `generate_with_reasoning/2` preserves reasoning traces in candidates
10. All tests pass (minimum 90% coverage)

## Implementation Plan

### Step 1: Create Generator Behavior (1.2.1)

- [x] 1.2.1.1 Create `lib/jido_ai/accuracy/generator.ex`
- [x] 1.2.1.2 Add comprehensive `@moduledoc`
- [x] 1.2.1.3 Define `@callback generate_candidates/3`
- [x] 1.2.1.4 Define `@callback generate_candidates_async/3`
- [x] 1.2.1.5 Define `@callback generate_with_reasoning/3`
- [x] 1.2.1.6 Define `@type t/0` for generator configuration
- [x] 1.2.1.7 Define `@type opts/0` for generator options

### Step 2: Implement LLMGenerator (1.2.2)

- [x] 1.2.2.1 Create `lib/jido_ai/accuracy/generators/llm_generator.ex`
- [x] 1.2.2.2 Add `@moduledoc` explaining LLM sampling
- [x] 1.2.2.3 Define `defstruct` with configuration fields
- [x] 1.2.2.4 Add custom validation (not Zoi - using manual validation)
- [x] 1.2.2.5 Implement `new/1` constructor
- [x] 1.2.2.6 Implement `generate_candidates/3` with N samples
- [x] 1.2.2.7 Support temperature randomization via `temperature_range`
- [x] 1.2.2.8 Add parallel generation via `Task.async_stream`
- [x] 1.2.2.9 Extract token counts from ReqLLM response
- [x] 1.2.2.10 Handle errors and return proper `{:error, reason}`
- [x] 1.2.2.11 Implement `generate_with_reasoning/3`
- [x] 1.2.2.12 Implement `generate_candidates_async/3`

### Step 3: Create Generators Directory

- [x] Create `lib/jido_ai/accuracy/generators/` directory
- [x] Create `test/jido_ai/accuracy/generators/` directory

### Step 4: Write Unit Tests

- [x] Test `generate_candidates/3` returns N candidates
- [x] Test candidates have unique content with varied temperature
- [x] Test parallel generation completes successfully
- [x] Test token counting is accurate
- [x] Test error handling for API failures
- [x] Test `generate_candidates_async/3` returns Task
- [x] Test `generate_with_reasoning/3` preserves reasoning
- [x] Test `temperature_range` produces diverse outputs
- [x] Test timeout is enforced per candidate
- [x] Test configuration validation

### Step 5: Integration Tests

- [x] Test end-to-end generation with mocked ReqLLM
- [x] Test actual ReqLLM call (optional, with API key)
- [x] Test candidate quality and diversity

### Step 6: Verify and Quality Check

- [x] Run `mix test test/jido_ai/accuracy/generator*`
- [x] Run `mix test test/jido_ai/accuracy/generators/*`
- [x] Verify test coverage > 90%
- [x] Run `mix credo` - no warnings
- [x] Verify documentation completeness

## Current Status

**Status**: ✅ Complete - All 29 tests passing
**What works**:
- Generator behavior with 3 callbacks (generate_candidates/3, generate_candidates_async/3, generate_with_reasoning/3)
- LLMGenerator implementation using ReqLLM directly
- Parallel generation with configurable max_concurrency
- Temperature randomization for diverse sampling
- Token counting from ReqLLM response metadata
- Chain-of-Thought reasoning parsing with separate reasoning/content fields
- Comprehensive error handling

**What's next**: Commit and merge to feature/accuracy branch
**How to run tests**: `mix test test/jido_ai/accuracy/generator_test.exs test/jido_ai/accuracy/generators/llm_generator_test.exs`

## Notes/Considerations

- **ReqLLM Direct Calls**: Generator calls `ReqLLM.Generation.generate_text/3` directly without going through Jido's directive system
- **Temperature Randomization**: Uses `:rand.uniform()` to pick temperature within range for diversity
- **Parallel Execution**: `Task.async_stream` with `max_concurrency: n` limits parallel API calls
- **Token Tracking**: Extracted from `ReqLLM.Response.usage` map (input_tokens + output_tokens)
- **Error Handling**: Converts `ReqLLM.Error` to `{:error, reason}` tuples
- **Model Resolution**: Uses `Jido.AI.Config.resolve_model/1` to support model aliases like `:fast`
- **CoT Prompts**: `generate_with_reasoning/2` adds a "Think step by step" prefix and stores reasoning separately

## Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| API rate limiting | Configurable max_concurrency and timeout |
| Token cost tracking | Extract usage from every ReqLLM response |
| Diverse sampling | Temperature randomization within range |
| Timeout handling | Per-candidate timeout with Task.async_stream timeout |
