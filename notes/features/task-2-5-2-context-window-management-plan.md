# Task 2.5.2: Context Window Management - Planning Document

**Branch:** `feature/task-2-5-2-context-window-management`
**Status:** Planning Complete
**Date:** 2025-10-03
**Planner:** feature-planner agent

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Agent Consultations](#agent-consultations)
4. [Technical Architecture](#technical-architecture)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Success Criteria](#success-criteria)
8. [Risk Mitigation](#risk-mitigation)

---

## Problem Statement

### Why Context Window Management Is Needed

Modern LLMs have vastly different context window sizes, ranging from 4K tokens (older GPT-3.5) to over 1 million tokens (Gemini 1.5 Pro). Current Jido AI implementation:

1. **No automatic detection**: Users must manually track model context limits
2. **No validation**: Prompts can exceed limits, causing API errors
3. **No truncation**: When limits are exceeded, entire request fails
4. **No optimization**: Users can't leverage extended context models effectively

### Current State Analysis

**Existing Components:**
- `Jido.AI.Model.Endpoint` has `context_length`, `max_completion_tokens`, `max_prompt_tokens`
- `Jido.AI.Tokenizer` exists but is a placeholder (splits on spaces)
- `Jido.AI.Prompt.Splitter` exists for chunking large documents
- Model metadata from ReqLLM registry includes context window info

**Pain Points:**
- Token counting is inaccurate (word-based split)
- No way to check if messages fit in context
- No intelligent truncation strategies
- Users must implement their own context management

**Example Context Window Sizes:**
- GPT-3.5-turbo: 4K-16K tokens
- GPT-4: 8K-128K tokens (varies by model)
- Claude 3: 200K tokens
- Gemini 1.5 Pro: 1M+ tokens
- Local models (Ollama): 2K-32K tokens

### User Impact

Without context window management:
- **Developers**: Must manually count tokens and truncate messages
- **Applications**: Can fail unexpectedly when limits exceeded
- **Costs**: Unnecessary token usage when context not optimized
- **Quality**: Important context may be lost with naive truncation

---

## Solution Overview

### High-Level Approach

Implement intelligent context window management system that:

1. **Automatic Detection**: Extract context limits from model metadata
2. **Token Counting**: Accurate token estimation using provider-specific strategies
3. **Validation**: Check if messages fit within context before API calls
4. **Truncation**: Intelligent strategies (sliding window, keep recent, keep bookends)
5. **Optimization**: Utilities for working with extended context models

### Design Principles

1. **Pure Elixir**: No external NIF dependencies for easier deployment
2. **Non-Breaking**: All features optional, existing APIs unchanged
3. **Explicit**: Users should know when context is truncated
4. **Extensible**: Easy to add custom truncation strategies
5. **Future-Proof**: Designed for Phase 3 multimodal support

### Module Architecture

```
lib/jido_ai/
├── context_window.ex              # Main API module
├── context_window/
│   ├── strategy.ex                # Truncation strategies
│   └── analyzer.ex                # Context analysis utilities (optional)
└── tokenizer.ex                   # Enhanced with estimation

test/jido_ai/
├── context_window_test.exs
├── context_window/
│   └── strategy_test.exs
└── actions/
    └── instructor_context_window_test.exs
```

---

## Agent Consultations

### Elixir Expert Consultation

**Topic:** Idiomatic Elixir patterns for context window management

**Key Recommendations:**

1. **Token Counting**: Hybrid approach with provider-specific estimation
   - Pure Elixir word-based estimation (0.75 tokens per word)
   - Provider-specific strategies (OpenAI, Anthropic, etc.)
   - Process-local caching for performance

2. **Module Design**: Single module with TypedStruct for type safety
   - Not protocol-based (overkill for this use case)
   - All operations in one place
   - Clear, simple API

3. **Truncation Strategies**: Function-based (not behaviors/protocols)
   - Functions are first-class in Elixir
   - Easy to add custom strategies
   - Clear, testable

4. **Integration**: Separate utility, integrate at action layer
   - Separation of concerns
   - Prompt focuses on messages
   - Context window is infrastructure

5. **Caching**: Process dictionary for per-request caching
   - No global state management
   - Automatic cleanup
   - Good for single-request optimization

**Pattern Examples:**

```elixir
# Token estimation
Tokenizer.estimate_tokens(text, model)

# Context management
ContextWindow.get_limits(model)
ContextWindow.check_fit(messages, model)
ContextWindow.truncate(messages, strategy: &Strategy.keep_recent/2)
```

### Senior Engineer Architectural Review

**Topic:** Architectural decisions and trade-offs

**Key Decisions:**

1. **Backwards Compatibility**: Keep existing `Prompt.Splitter` unchanged
   - No breaking changes
   - Soft deprecation in docs
   - Gradual migration in Phase 3

2. **Model Metadata**: Use first endpoint with safe fallbacks
   - First endpoint typically primary
   - Default to 4096 tokens if missing
   - Can optimize later if needed

3. **Error Handling**: Explicit check, user decides
   - `check_fit/2` returns `{:ok, count} | {:error, :exceeds_limit, details}`
   - `ensure_fit/3` convenience function for auto-truncation
   - Follows Elixir `{:ok, _} | {:error, _}` pattern

4. **Extended Context Models**: No special handling initially
   - O(n) word splitting fast enough for 1M tokens
   - Focus on correctness first
   - Optimize in Phase 2.5.3 if benchmarks show issues

5. **Integration Points**: Actions layer, opt-in
   - Add `check_context_window: true` option to Instructor
   - Optional = no breaking changes
   - Can make default in Phase 3

6. **Testing**: Comprehensive approach
   - Unit tests for each component
   - Strategy-specific tests
   - Integration tests with Instructor
   - Property tests for invariants

7. **Future-Proofing**: Design for multimodal extension
   - Accept map content (even if only handling strings now)
   - Phase 3 will add image/audio token counting
   - API won't need to change

**Architecture Approval:** ✅ PROCEED WITH IMPLEMENTATION

---

## Technical Architecture

### 1. Enhanced Tokenizer

**File:** `lib/jido_ai/tokenizer.ex`

**Current State:**
```elixir
defmodule Jido.AI.Tokenizer do
  # Placeholder: splits on spaces
  def encode(input, _model), do: String.split(input, " ")
  def decode(tokens, _model), do: Enum.join(tokens, " ")
end
```

**Enhanced Implementation:**
```elixir
defmodule Jido.AI.Tokenizer do
  @moduledoc """
  Token estimation for LLM context window management.
  Uses provider-specific strategies with word-based fallback.
  """

  @doc """
  Estimates token count for the given text and model.

  Uses provider-specific estimation when available, falls back
  to word-based estimation (0.75 tokens per word).

  ## Examples

      iex> Tokenizer.estimate_tokens("Hello world", model)
      2
  """
  @spec estimate_tokens(String.t(), Jido.AI.Model.t()) :: non_neg_integer()
  def estimate_tokens(text, model) when is_binary(text) do
    strategy = get_tokenizer_strategy(model)
    do_estimate_tokens(text, strategy)
  end

  @doc """
  Estimates token count with process-local caching.
  """
  @spec estimate_tokens_cached(String.t(), Jido.AI.Model.t()) :: non_neg_integer()
  def estimate_tokens_cached(text, model) do
    cache_key = :erlang.phash2({text, model.id})

    case Process.get({:token_cache, cache_key}) do
      nil ->
        count = estimate_tokens(text, model)
        Process.put({:token_cache, cache_key}, count)
        count
      count ->
        count
    end
  end

  # Private functions

  defp get_tokenizer_strategy(%{provider: :openai}), do: :openai
  defp get_tokenizer_strategy(%{provider: :anthropic}), do: :anthropic
  defp get_tokenizer_strategy(_), do: :fallback

  defp do_estimate_tokens(text, :openai) do
    # OpenAI: ~0.75 tokens per word, but more conservative
    # Accounts for subword tokenization
    text
    |> String.split(~r/\s+/)
    |> length()
    |> Kernel.*(0.75)
    |> ceil()
  end

  defp do_estimate_tokens(text, :anthropic) do
    # Claude: similar to OpenAI tokenization
    text
    |> String.split(~r/\s+/)
    |> length()
    |> Kernel.*(0.75)
    |> ceil()
  end

  defp do_estimate_tokens(text, :fallback) do
    # Conservative estimate: 1 token per word
    text
    |> String.split(~r/\s+/)
    |> length()
  end

  # Keep existing encode/decode for Prompt.Splitter compatibility
  @deprecated "Use estimate_tokens/2 instead"
  def encode(input, model), do: String.split(input, " ")

  @deprecated "Use estimate_tokens/2 instead"
  def decode(tokens, model), do: Enum.join(tokens, " ")
end
```

### 2. Context Window Main Module

**File:** `lib/jido_ai/context_window.ex`

```elixir
defmodule Jido.AI.ContextWindow do
  @moduledoc """
  Intelligent context window management for LLM interactions.

  Provides automatic context limit detection, token counting, validation,
  and intelligent truncation strategies for models with varying context sizes.

  ## Features

  - Automatic context limit detection from model metadata
  - Accurate token estimation using provider-specific strategies
  - Validation to check if messages fit within context
  - Multiple truncation strategies (keep recent, bookends, sliding window)
  - Support for extended context models (100K+ tokens)

  ## Usage

      # Check if messages fit
      case ContextWindow.check_fit(messages, model) do
        {:ok, token_count} ->
          # Proceed
        {:error, :exceeds_limit, %{current: current, limit: limit}} ->
          # Handle overflow
      end

      # Auto-truncate with strategy
      messages = ContextWindow.ensure_fit(messages, model,
        strategy: &Strategy.keep_bookends/2,
        count: 10
      )

      # Get model limits
      limits = ContextWindow.get_limits(model)
  """

  use TypedStruct
  alias Jido.AI.{Model, Tokenizer}
  alias Jido.AI.ContextWindow.Strategy

  typedstruct module: Limits do
    @moduledoc "Context window limits for a model"
    field :context_length, non_neg_integer()
    field :max_completion_tokens, non_neg_integer()
    field :max_prompt_tokens, non_neg_integer() | nil
    field :available_prompt_tokens, non_neg_integer()
  end

  @default_context_length 4096
  @default_completion_tokens 2048

  @doc """
  Extracts context window limits from model metadata.

  Uses the first endpoint's limits with safe fallbacks.
  Calculates available prompt tokens accounting for completion tokens.
  """
  @spec get_limits(Model.t(), keyword()) :: Limits.t()
  def get_limits(%Model{endpoints: [endpoint | _]} = model, opts \\ []) do
    context_length = endpoint.context_length || @default_context_length
    max_completion = endpoint.max_completion_tokens || @default_completion_tokens
    max_prompt = endpoint.max_prompt_tokens

    # Calculate available tokens for prompt
    available_prompt = max_prompt || (context_length - max_completion)

    %Limits{
      context_length: context_length,
      max_completion_tokens: max_completion,
      max_prompt_tokens: max_prompt,
      available_prompt_tokens: max(0, available_prompt)
    }
  end

  def get_limits(%Model{endpoints: []} = model, opts \\ []) do
    # Fallback for models without endpoint data
    %Limits{
      context_length: @default_context_length,
      max_completion_tokens: @default_completion_tokens,
      max_prompt_tokens: nil,
      available_prompt_tokens: @default_context_length - @default_completion_tokens
    }
  end

  @doc """
  Counts total tokens across all messages.

  Uses cached token counting for efficiency.
  """
  @spec count_tokens(list(map()), Model.t()) :: non_neg_integer()
  def count_tokens(messages, model) when is_list(messages) do
    messages
    |> Enum.map(&count_message_tokens(&1, model))
    |> Enum.sum()
  end

  @doc """
  Checks if messages fit within the model's context window.

  Returns {:ok, token_count} if messages fit, or
  {:error, :exceeds_limit, details} if they exceed the limit.
  """
  @spec check_fit(list(map()), Model.t(), keyword()) ::
    {:ok, non_neg_integer()} |
    {:error, :exceeds_limit, map()}
  def check_fit(messages, model, opts \\ []) do
    limits = get_limits(model, opts)
    token_count = count_tokens(messages, model)

    if token_count <= limits.available_prompt_tokens do
      {:ok, token_count}
    else
      {:error, :exceeds_limit, %{
        current: token_count,
        limit: limits.available_prompt_tokens,
        overflow: token_count - limits.available_prompt_tokens,
        context_length: limits.context_length,
        reserved_for_completion: limits.max_completion_tokens
      }}
    end
  end

  @doc """
  Ensures messages fit by truncating with the given strategy.

  This is a convenience function that automatically truncates
  if messages exceed the context window.

  ## Options

  - `:strategy` - Truncation strategy function (default: keep_bookends)
  - Other options are passed to the strategy function

  ## Examples

      messages = ContextWindow.ensure_fit(messages, model,
        strategy: &Strategy.keep_recent/2,
        count: 15
      )
  """
  @spec ensure_fit(list(map()), Model.t(), keyword()) :: list(map())
  def ensure_fit(messages, model, opts \\ []) do
    case check_fit(messages, model, opts) do
      {:ok, _count} ->
        messages

      {:error, :exceeds_limit, _details} ->
        strategy = Keyword.get(opts, :strategy, &Strategy.keep_bookends/2)
        truncate(messages, model, opts)
    end
  end

  @doc """
  Truncates messages using the specified strategy.

  ## Options

  - `:strategy` - Truncation strategy function (required)
  - Other options are passed to the strategy function
  """
  @spec truncate(list(map()), Model.t(), keyword()) :: list(map())
  def truncate(messages, model, opts) do
    strategy = Keyword.fetch!(opts, :strategy)
    limits = get_limits(model, opts)

    # Pass limits to strategy for intelligent truncation
    strategy_opts = Keyword.put(opts, :limits, limits)
    strategy.(messages, strategy_opts)
  end

  # Private helpers

  defp count_message_tokens(%{content: content}, model) when is_binary(content) do
    # Add overhead for message formatting (role, etc.)
    Tokenizer.estimate_tokens_cached(content, model) + 4
  end

  defp count_message_tokens(%{content: content}, model) when is_map(content) do
    # Future: Phase 3 multimodal support
    # For now, return 0 for non-text content
    0
  end

  defp count_message_tokens(_message, _model), do: 0
end
```

### 3. Truncation Strategies Module

**File:** `lib/jido_ai/context_window/strategy.ex`

```elixir
defmodule Jido.AI.ContextWindow.Strategy do
  @moduledoc """
  Truncation strategies for context window management.

  Provides built-in strategies and allows custom strategies.
  All strategies are functions that take messages and options.

  ## Built-in Strategies

  - `keep_recent/2` - Keep only N most recent messages
  - `keep_bookends/2` - Keep system message and N recent messages
  - `sliding_window/2` - Sliding window with overlap
  - `smart_truncate/2` - Intelligent truncation preserving important messages

  ## Custom Strategies

  You can define custom strategies:

      def my_strategy(messages, opts) do
        # Your logic here
        truncated_messages
      end

      ContextWindow.truncate(messages, model, strategy: &my_strategy/2)
  """

  @type message :: %{role: atom(), content: String.t()}
  @type strategy_opts :: keyword()
  @type strategy_fun :: (list(message()), strategy_opts() -> list(message()))

  @doc """
  Keeps only the N most recent messages.

  ## Options

  - `:count` - Number of messages to keep (default: 10)

  ## Example

      Strategy.keep_recent(messages, count: 15)
  """
  @spec keep_recent(list(message()), strategy_opts()) :: list(message())
  def keep_recent(messages, opts) do
    count = Keyword.get(opts, :count, 10)
    Enum.take(messages, -count)
  end

  @doc """
  Keeps system message (if present) and N most recent messages.

  This is useful for maintaining system instructions while
  truncating conversation history.

  ## Options

  - `:count` - Number of recent messages to keep (default: 10)

  ## Example

      Strategy.keep_bookends(messages, count: 10)
  """
  @spec keep_bookends(list(message()), strategy_opts()) :: list(message())
  def keep_bookends(messages, opts) do
    count = Keyword.get(opts, :count, 10)

    case messages do
      [%{role: :system} = sys | rest] ->
        recent = Enum.take(rest, -count)
        [sys | recent]

      _ ->
        Enum.take(messages, -count)
    end
  end

  @doc """
  Sliding window with overlap.

  Creates a window of messages with configurable overlap
  to maintain context continuity.

  ## Options

  - `:window_size` - Size of the window (default: 10)
  - `:overlap` - Number of overlapping messages (default: 2)

  ## Example

      Strategy.sliding_window(messages, window_size: 10, overlap: 2)
  """
  @spec sliding_window(list(message()), strategy_opts()) :: list(message())
  def sliding_window(messages, opts) do
    window_size = Keyword.get(opts, :window_size, 10)
    overlap = Keyword.get(opts, :overlap, 2)

    # Take window_size messages, but ensure overlap with previous
    # For first window, this is just the first window_size messages
    # For subsequent calls, caller would maintain state
    Enum.take(messages, -window_size)
  end

  @doc """
  Smart truncation preserving important messages.

  Keeps:
  - System message (if present)
  - First user message (sets context)
  - Most recent N messages

  ## Options

  - `:count` - Number of recent messages to keep (default: 8)

  ## Example

      Strategy.smart_truncate(messages, count: 8)
  """
  @spec smart_truncate(list(message()), strategy_opts()) :: list(message())
  def smart_truncate(messages, opts) do
    count = Keyword.get(opts, :count, 8)

    {system, rest} = extract_system(messages)
    {first_user, middle, recent} = extract_parts(rest, count)

    # Build result: system + first_user + recent
    []
    |> maybe_add(system)
    |> maybe_add(first_user)
    |> Kernel.++(recent)
  end

  # Private helpers

  defp extract_system([%{role: :system} = sys | rest]), do: {sys, rest}
  defp extract_system(messages), do: {nil, messages}

  defp extract_parts([], _count), do: {nil, [], []}
  defp extract_parts([first | rest], count) do
    recent = Enum.take(rest, -count)
    middle_count = length(rest) - length(recent)
    middle = if middle_count > 0, do: Enum.take(rest, middle_count), else: []
    {first, middle, recent}
  end

  defp maybe_add(list, nil), do: list
  defp maybe_add(list, item), do: list ++ [item]
end
```

---

## Implementation Plan

### Subtask 2.5.2.1: Automatic Context Window Detection

**Goal:** Add automatic context limit detection from model metadata

**Implementation:**

1. Enhance `Jido.AI.ContextWindow` module:
   - Create `Limits` struct with TypedStruct
   - Implement `get_limits/2` function
   - Handle models with/without endpoint data
   - Add safe fallback defaults

2. Extract context information:
   - `context_length` from `Model.Endpoint`
   - `max_completion_tokens` from endpoint
   - `max_prompt_tokens` (if available)
   - Calculate `available_prompt_tokens`

3. Add tests:
   - Test with models having endpoints
   - Test with models without endpoints
   - Test fallback to defaults
   - Test calculation of available tokens

**Files:**
- `lib/jido_ai/context_window.ex` (create)
- `test/jido_ai/context_window_test.exs` (create)

**Success Criteria:**
- All model types return valid limits
- Defaults prevent crashes
- Available tokens correctly calculated

---

### Subtask 2.5.2.2: Intelligent Context Truncation Strategies

**Goal:** Implement multiple truncation strategies

**Implementation:**

1. Create `Jido.AI.ContextWindow.Strategy` module:
   - Define strategy function type
   - Implement `keep_recent/2`
   - Implement `keep_bookends/2`
   - Implement `sliding_window/2`
   - Implement `smart_truncate/2`

2. Strategy characteristics:
   - Take messages and options
   - Return truncated message list
   - Preserve message structure
   - Handle edge cases (empty, single message)

3. Add truncation to main module:
   - Implement `truncate/3` function
   - Pass limits to strategies
   - Allow custom strategy functions

4. Add tests:
   - Test each strategy independently
   - Test with various message counts
   - Test system message preservation
   - Test edge cases

**Files:**
- `lib/jido_ai/context_window/strategy.ex` (create)
- `test/jido_ai/context_window/strategy_test.exs` (create)

**Success Criteria:**
- Each strategy works correctly
- System messages preserved when appropriate
- Strategies handle edge cases
- Easy to add custom strategies

---

### Subtask 2.5.2.3: Extended Context Model Support

**Goal:** Add support for extended context models (100K+ tokens)

**Implementation:**

1. Enhance token counting:
   - Ensure efficient handling of large texts
   - Test with 100K+ token messages
   - Benchmark performance

2. Document best practices:
   - When to use extended context
   - Cost implications
   - Performance considerations
   - Optimal truncation strategies

3. Add analyzer utilities (optional):
   - Context utilization percentage
   - Token distribution analysis
   - Optimization recommendations

4. Add tests:
   - Test with large context models (Claude, Gemini)
   - Performance benchmarks
   - Memory usage validation

**Files:**
- `lib/jido_ai/context_window.ex` (enhance)
- `lib/jido_ai/context_window/analyzer.ex` (optional, create)
- `test/jido_ai/context_window_test.exs` (enhance)

**Success Criteria:**
- Handles 100K+ tokens efficiently (< 100ms)
- No memory issues with large contexts
- Clear documentation for best practices

---

### Subtask 2.5.2.4: Context Window Optimization Utilities

**Goal:** Create utilities for context window optimization

**Implementation:**

1. Enhance Tokenizer:
   - Provider-specific estimation
   - Cached token counting
   - Accurate word-based fallback

2. Add validation functions:
   - `count_tokens/2` - Count tokens in messages
   - `check_fit/3` - Validate messages fit in context
   - `ensure_fit/3` - Auto-truncate convenience function

3. Integrate with Instructor action:
   - Add `check_context_window` option
   - Add `truncation_strategy` option
   - Add `truncation_count` option
   - Validate before API calls (opt-in)

4. Add documentation:
   - Usage examples
   - Strategy comparison
   - Best practices guide
   - API reference

5. Add tests:
   - Test token counting accuracy
   - Test check_fit validation
   - Test ensure_fit truncation
   - Integration test with Instructor

**Files:**
- `lib/jido_ai/tokenizer.ex` (enhance)
- `lib/jido_ai/context_window.ex` (enhance)
- `lib/jido_ai/actions/instructor.ex` (enhance)
- `test/jido_ai/tokenizer_test.exs` (enhance)
- `test/jido_ai/actions/instructor_context_window_test.exs` (create)

**Success Criteria:**
- Token estimates within 10% of actual
- Validation catches overflow
- Integration works seamlessly
- Clear, comprehensive documentation

---

## Testing Strategy

### Unit Tests

**File:** `test/jido_ai/context_window_test.exs`

```elixir
defmodule Jido.AI.ContextWindowTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{ContextWindow, Model}

  describe "get_limits/2" do
    test "extracts limits from model with endpoints"
    test "returns defaults for model without endpoints"
    test "calculates available prompt tokens"
    test "handles nil values in endpoints"
  end

  describe "count_tokens/2" do
    test "counts tokens across multiple messages"
    test "handles empty message list"
    test "includes message overhead"
    test "uses cached counting"
  end

  describe "check_fit/3" do
    test "returns ok when messages fit"
    test "returns error when messages exceed limit"
    test "includes overflow information in error"
  end

  describe "ensure_fit/3" do
    test "returns messages unchanged when they fit"
    test "truncates when messages exceed limit"
    test "applies specified strategy"
  end
end
```

**File:** `test/jido_ai/context_window/strategy_test.exs`

```elixir
defmodule Jido.AI.ContextWindow.StrategyTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ContextWindow.Strategy

  describe "keep_recent/2" do
    test "keeps N most recent messages"
    test "handles count larger than message list"
    test "handles empty messages"
  end

  describe "keep_bookends/2" do
    test "preserves system message and recent messages"
    test "works without system message"
    test "handles count parameter"
  end

  describe "sliding_window/2" do
    test "creates window of specified size"
    test "handles overlap parameter"
  end

  describe "smart_truncate/2" do
    test "preserves system, first user, and recent"
    test "handles various message patterns"
  end
end
```

**File:** `test/jido_ai/tokenizer_test.exs`

```elixir
defmodule Jido.AI.TokenizerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Tokenizer

  describe "estimate_tokens/2" do
    test "estimates OpenAI tokens"
    test "estimates Anthropic tokens"
    test "falls back to word count"
    test "handles empty strings"
    test "handles multi-line text"
  end

  describe "estimate_tokens_cached/2" do
    test "caches token count"
    test "uses cached value on subsequent calls"
    test "cache is process-local"
  end
end
```

### Integration Tests

**File:** `test/jido_ai/actions/instructor_context_window_test.exs`

```elixir
defmodule Jido.AI.Actions.InstructorContextWindowTest do
  use ExUnit.Case

  alias Jido.AI.Actions.Instructor
  alias Jido.AI.{Model, Prompt}

  describe "context window checking" do
    test "runs normally when context fits"
    test "truncates when check_context_window enabled"
    test "uses specified truncation strategy"
    test "respects truncation_count option"
  end

  describe "error handling" do
    test "fails gracefully when context exceeded and no strategy"
    test "includes helpful error message"
  end
end
```

### Property Tests (Optional)

If using StreamData:

```elixir
property "truncation never increases message count" do
  check all messages <- list_of(message_generator()),
            strategy <- strategy_generator() do
    truncated = strategy.(messages, count: 10)
    assert length(truncated) <= length(messages)
  end
end

property "system message always preserved by keep_bookends" do
  check all messages <- list_of(message_generator(), min_length: 1) do
    with_system = [%{role: :system, content: "sys"} | messages]
    truncated = Strategy.keep_bookends(with_system, count: 5)
    assert hd(truncated).role == :system
  end
end
```

### Test Coverage Goals

- **Unit Tests**: 95%+ coverage
- **Integration Tests**: All main workflows
- **Edge Cases**: Empty lists, single messages, all system messages
- **Performance**: Benchmarks for 10K, 100K, 1M token contexts

---

## Success Criteria

### Functional Requirements

1. **Automatic Detection** ✅
   - Extract context limits from any model
   - Handle missing/incomplete metadata
   - Provide safe defaults

2. **Token Counting** ✅
   - Estimate within 10% of actual
   - Handle all text content
   - Cache for performance

3. **Validation** ✅
   - Check if messages fit
   - Provide detailed error info
   - Work with all model sizes

4. **Truncation** ✅
   - Multiple built-in strategies
   - Easy custom strategies
   - Preserve important context

5. **Extended Context** ✅
   - Support 100K+ tokens
   - Efficient performance
   - Clear best practices

### Non-Functional Requirements

1. **Performance**
   - Count 10K tokens: < 10ms
   - Count 100K tokens: < 100ms
   - Count 1M tokens: < 1000ms

2. **Usability**
   - 5 lines of code for basic usage
   - Clear error messages
   - Comprehensive documentation

3. **Reliability**
   - No crashes on invalid input
   - Graceful degradation
   - Safe defaults

4. **Maintainability**
   - Well-documented code
   - Clear module boundaries
   - Easy to extend

### Integration Requirements

1. **Backward Compatibility**
   - No breaking changes
   - Existing APIs unchanged
   - Optional features

2. **Future Compatibility**
   - Design for multimodal (Phase 3)
   - Extensible architecture
   - Clear upgrade path

### Documentation Requirements

1. **API Documentation**
   - All public functions
   - Clear examples
   - Type specifications

2. **Usage Guide**
   - Quick start
   - Strategy comparison
   - Best practices

3. **Integration Guide**
   - Using with Instructor
   - Custom strategies
   - Advanced patterns

---

## Risk Mitigation

### Technical Risks

1. **Token Estimation Accuracy**
   - **Risk**: Word-based estimation too inaccurate
   - **Mitigation**: Conservative estimates (overestimate)
   - **Fallback**: Add NIF-based tokenizer in Phase 2.5.3 if needed

2. **Performance with Large Contexts**
   - **Risk**: Slow with 1M+ token contexts
   - **Mitigation**: Use O(n) algorithms, benchmark early
   - **Fallback**: Add streaming token counter if needed

3. **Breaking Changes**
   - **Risk**: Integration breaks existing code
   - **Mitigation**: All features optional, explicit opt-in
   - **Verification**: Run all existing tests

### Integration Risks

1. **Prompt.Splitter Conflict**
   - **Risk**: Confusion between Splitter and ContextWindow
   - **Mitigation**: Clear documentation of use cases
   - **Resolution**: Keep both, different purposes

2. **Action Layer Complexity**
   - **Risk**: Too complex to use correctly
   - **Mitigation**: Simple defaults, clear examples
   - **Validation**: User testing before release

### Operational Risks

1. **Model Metadata Missing**
   - **Risk**: Some models lack context info
   - **Mitigation**: Safe defaults (4096 tokens)
   - **Monitoring**: Log when defaults used

2. **Strategy Selection**
   - **Risk**: Users pick wrong strategy
   - **Mitigation**: Document strategy trade-offs
   - **Guidance**: Recommend defaults for common cases

---

## Implementation Checklist

### Phase 1: Core Infrastructure (Subtasks 2.5.2.1 & 2.5.2.4)

- [ ] Create `Jido.AI.ContextWindow` module
  - [ ] Define `Limits` struct
  - [ ] Implement `get_limits/2`
  - [ ] Add safe defaults
- [ ] Enhance `Jido.AI.Tokenizer`
  - [ ] Provider-specific estimation
  - [ ] Cached counting
  - [ ] Deprecate old functions
- [ ] Add validation functions
  - [ ] `count_tokens/2`
  - [ ] `check_fit/3`
  - [ ] `ensure_fit/3`
- [ ] Write unit tests
  - [ ] Context window tests
  - [ ] Tokenizer tests
  - [ ] Edge cases

### Phase 2: Truncation Strategies (Subtask 2.5.2.2)

- [ ] Create `Jido.AI.ContextWindow.Strategy` module
  - [ ] `keep_recent/2`
  - [ ] `keep_bookends/2`
  - [ ] `sliding_window/2`
  - [ ] `smart_truncate/2`
- [ ] Add truncation to main module
  - [ ] `truncate/3` function
  - [ ] Strategy invocation
- [ ] Write strategy tests
  - [ ] Each strategy
  - [ ] Edge cases
  - [ ] System message handling

### Phase 3: Extended Context & Integration (Subtasks 2.5.2.3)

- [ ] Document extended context best practices
- [ ] Add analyzer utilities (optional)
- [ ] Integrate with Instructor action
  - [ ] `check_context_window` option
  - [ ] `truncation_strategy` option
  - [ ] `truncation_count` option
- [ ] Write integration tests
  - [ ] Instructor integration
  - [ ] Error handling
  - [ ] Strategy application
- [ ] Performance testing
  - [ ] Benchmark large contexts
  - [ ] Memory profiling

### Phase 4: Documentation & Polish

- [ ] Write comprehensive module docs
- [ ] Create usage guide
- [ ] Document each strategy
- [ ] Add code examples
- [ ] Write integration guide
- [ ] Update CHANGELOG
- [ ] Update phase-02.md progress

---

## Next Steps

After planning approval:

1. **Create branch**: `feature/task-2-5-2-context-window-management`
2. **Start with Subtask 2.5.2.1**: Core infrastructure
3. **Test-driven development**: Write tests first
4. **Incremental commits**: One subtask at a time
5. **Continuous validation**: Run tests frequently

## Related Documentation

- **Phase 02 Plan**: `/planning/phase-02.md`
- **Task 2.5.1 Summary**: `/notes/features/task-2-5-1-advanced-generation-summary.md`
- **Model Structure**: `/lib/jido_ai/model.ex`
- **Prompt Structure**: `/lib/jido_ai/prompt.ex`

---

**Planning Complete** ✅

Ready for implementation with clear architecture, comprehensive plan, and strong testing strategy.
