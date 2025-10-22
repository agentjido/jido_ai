# Context Window Management

Context windows define how much text (measured in tokens) a model can process at once. Proper management ensures prompts fit within model limits and enables efficient use of long-context models.

## Overview

Context window management provides:
- **Automatic Detection**: Extract context limits from model metadata
- **Validation**: Check if messages fit within limits
- **Truncation**: Intelligent strategies to fit content
- **Optimization**: Utilities for extended context models (128K-2M tokens)

## Context Window Sizes

| Model | Context Window | Best For |
|-------|----------------|----------|
| GPT-3.5 Turbo | 16K | Short conversations |
| GPT-4 | 8K / 32K | Standard tasks |
| GPT-4 Turbo | 128K | Long documents |
| Claude 3 | 200K | Very long documents |
| Gemini 1.5 Pro | 2M | Massive documents, codebases |
| Llama 3.1 70B | 128K | Open source long context |

## Quick Start

```elixir
alias Jido.AI.ContextWindow

# Get context limits for a model
{:ok, model} = Jido.AI.Model.from("openai:gpt-4-turbo")
{:ok, limits} = ContextWindow.get_limits(model)

IO.inspect limits
# %Limits{
#   total: 128000,
#   completion: 4096,
#   prompt: 123904
# }

# Check if prompt fits
{:ok, info} = ContextWindow.check_fit(prompt, model)
# %{tokens: 1250, limit: 128000, fits: true}

# Ensure prompt fits (truncate if needed)
{:ok, truncated_prompt} = ContextWindow.ensure_fit(
  prompt,
  model,
  strategy: :keep_recent,
  count: 20
)
```

## Detection and Validation

### Get Context Limits

```elixir
# For any model
{:ok, model} = Jido.AI.Model.from("anthropic:claude-3-sonnet")
{:ok, limits} = ContextWindow.get_limits(model)

limits.total       # 200000 (total context)
limits.completion  # 4096 (max output)
limits.prompt      # 195904 (max input)
```

### Check if Content Fits

```elixir
# Check before sending
case ContextWindow.check_fit(long_prompt, model) do
  {:ok, %{fits: true, tokens: count}} ->
    IO.puts "Fits! Uses #{count} tokens"

  {:ok, %{fits: false, tokens: count, limit: limit}} ->
    IO.puts "Too large: #{count} tokens, limit is #{limit}"
end
```

### Validate and Raise

```elixir
# Raise if doesn't fit
try do
  :ok = ContextWindow.ensure_fit!(prompt, model)
  # Continue with API call
rescue
  ContextWindow.ContextExceededError ->
    IO.puts "Prompt too large!"
end
```

## Truncation Strategies

### Keep Recent Messages

Keeps the N most recent messages:

```elixir
{:ok, truncated} = ContextWindow.ensure_fit(
  prompt,
  model,
  strategy: :keep_recent,
  count: 10  # Keep last 10 messages
)
```

### Keep Bookends

Preserves system message + N recent messages:

```elixir
{:ok, truncated} = ContextWindow.ensure_fit(
  prompt,
  model,
  strategy: :keep_bookends,
  count: 15  # System + 15 recent
)
```

### Sliding Window

Maintains continuity with overlapping windows:

```elixir
{:ok, truncated} = ContextWindow.ensure_fit(
  prompt,
  model,
  strategy: :sliding_window,
  window_size: 20,
  overlap: 5
)
```

### Smart Truncate

Intelligently preserves important context:

```elixir
{:ok, truncated} = ContextWindow.ensure_fit(
  prompt,
  model,
  strategy: :smart_truncate  # Default
)

# Smart truncate preserves:
# - System messages
# - First user message
# - Recent conversation
```

## Reserve Completion Tokens

Reserve space for model's response:

```elixir
{:ok, truncated} = ContextWindow.ensure_fit(
  prompt,
  model,
  reserve_completion: 2000,  # Reserve 2K tokens for response
  strategy: :keep_recent
)
```

## Advanced Patterns

### Automatic Context Management

```elixir
defmodule MyApp.ManagedChat do
  alias Jido.AI.ContextWindow

  def chat(model, messages, opts \\ []) do
    # Automatic truncation if needed
    {:ok, fitted_messages} = ContextWindow.ensure_fit(
      messages,
      model,
      Keyword.merge([
        strategy: :smart_truncate,
        reserve_completion: 1000
      ], opts)
    )

    Jido.AI.chat(model, fitted_messages)
  end
end
```

### Long Document Processing

```elixir
defmodule MyApp.DocumentProcessor do
  def process_long_document(document, model) do
    # Check document size
    {:ok, limits} = ContextWindow.get_limits(model)

    if document_too_large?(document, limits) do
      # Use chunking strategy
      process_in_chunks(document, model, limits)
    else
      # Process normally
      Jido.AI.chat(model, document)
    end
  end

  defp document_too_large?(doc, limits) do
    # Estimate tokens (rough: 4 chars = 1 token)
    estimated_tokens = String.length(doc) / 4
    estimated_tokens > limits.prompt * 0.8  # 80% threshold
  end

  defp process_in_chunks(document, model, limits) do
    chunk_size = round(limits.prompt * 0.7)  # 70% of limit

    document
    |> chunk_text(chunk_size)
    |> Enum.map(fn chunk ->
      {:ok, response} = Jido.AI.chat(model, chunk)
      response.content
    end)
    |> summarize_chunks(model)
  end

  defp chunk_text(text, chunk_size) do
    # Split into chunks (simplified)
    text
    |> String.graphemes()
    |> Enum.chunk_every(chunk_size * 4)  # 4 chars ≈ 1 token
    |> Enum.map(&Enum.join/1)
  end

  defp summarize_chunks(chunks, model) do
    summary_prompt = """
    Summarize these processed chunks:

    #{Enum.join(chunks, "\n\n---\n\n")}
    """

    {:ok, response} = Jido.AI.chat(model, summary_prompt)
    response
  end
end
```

### Conversation Management

```elixir
defmodule MyApp.Conversation do
  use GenServer

  defstruct [:model, :messages, :max_messages]

  def start_link(model, opts \\ []) do
    GenServer.start_link(__MODULE__, {model, opts})
  end

  def add_message(pid, role, content) do
    GenServer.call(pid, {:add_message, role, content})
  end

  def chat(pid, message) do
    GenServer.call(pid, {:chat, message})
  end

  # GenServer callbacks

  def init({model, opts}) do
    max_messages = Keyword.get(opts, :max_messages, 50)
    {:ok, %__MODULE__{model: model, messages: [], max_messages: max_messages}}
  end

  def handle_call({:add_message, role, content}, _from, state) do
    message = %{role: role, content: content}
    messages = trim_messages([message | state.messages], state)
    {:reply, :ok, %{state | messages: messages}}
  end

  def handle_call({:chat, user_message}, _from, state) do
    # Add user message
    messages = [%{role: "user", content: user_message} | state.messages]

    # Ensure fits
    {:ok, fitted} = ContextWindow.ensure_fit(
      Enum.reverse(messages),
      state.model,
      strategy: :keep_recent,
      reserve_completion: 500
    )

    # Get response
    {:ok, response} = Jido.AI.chat(state.model, fitted)

    # Add assistant message
    messages = [
      %{role: "assistant", content: response.content} | messages
    ]

    new_state = %{state | messages: trim_messages(messages, state)}

    {:reply, {:ok, response}, new_state}
  end

  defp trim_messages(messages, state) do
    Enum.take(messages, state.max_messages)
  end
end
```

### Dynamic Model Selection

```elixir
defmodule MyApp.SmartModelSelection do
  def chat(prompt) do
    # Estimate tokens needed
    estimated_tokens = estimate_tokens(prompt)

    # Select appropriate model
    model = select_model(estimated_tokens)

    Jido.AI.chat(model, prompt)
  end

  defp estimate_tokens(prompt) when is_binary(prompt) do
    # Rough estimate: 4 characters ≈ 1 token
    round(String.length(prompt) / 4)
  end

  defp estimate_tokens(messages) when is_list(messages) do
    messages
    |> Enum.map(& &1.content)
    |> Enum.join(" ")
    |> estimate_tokens()
  end

  defp select_model(tokens) when tokens < 4000 do
    # Short prompt - use fast model
    "groq:llama-3.1-8b-instant"
  end

  defp select_model(tokens) when tokens < 16000 do
    # Medium prompt - use standard model
    "openai:gpt-3.5-turbo"
  end

  defp select_model(tokens) when tokens < 100000 do
    # Long prompt - use extended context
    "openai:gpt-4-turbo"
  end

  defp select_model(_tokens) do
    # Very long - use maximum context
    "vertex:gemini-1.5-pro"  # 2M context
  end
end
```

## Best Practices

### 1. Always Check Before Sending

```elixir
# ✅ Good: Validate first
{:ok, _} = ContextWindow.check_fit(prompt, model)
Jido.AI.chat(model, prompt)

# ❌ Bad: Send without checking
Jido.AI.chat(model, very_long_prompt)
# May fail with context exceeded error
```

### 2. Reserve Completion Space

```elixir
# ✅ Good: Reserve space for response
{:ok, fitted} = ContextWindow.ensure_fit(
  prompt,
  model,
  reserve_completion: 1000  # Reserve 1K for response
)

# ❌ Bad: Use entire context for prompt
# Leaves no room for model response
```

### 3. Choose Appropriate Strategy

```elixir
# For customer support (need recent context)
strategy: :keep_recent

# For document analysis (need intro + recent)
strategy: :keep_bookends

# For long conversations (need continuity)
strategy: :sliding_window

# For general use (smart preservation)
strategy: :smart_truncate
```

### 4. Monitor Token Usage

```elixir
defmodule MyApp.TokenMonitor do
  def chat_with_monitoring(model, prompt) do
    {:ok, info} = ContextWindow.check_fit(prompt, model)

    Logger.info("Token usage", %{
      tokens: info.tokens,
      limit: info.limit,
      utilization: info.tokens / info.limit * 100
    })

    if info.tokens / info.limit > 0.9 do
      Logger.warning("High context utilization: #{info.tokens}/#{info.limit}")
    end

    Jido.AI.chat(model, prompt)
  end
end
```

### 5. Handle Truncation Gracefully

```elixir
defmodule MyApp.GracefulTruncation do
  require Logger

  def chat(model, messages) do
    case ContextWindow.ensure_fit(messages, model) do
      {:ok, ^messages} ->
        # No truncation needed
        Jido.AI.chat(model, messages)

      {:ok, truncated} ->
        # Truncation occurred
        original_count = length(messages)
        truncated_count = length(truncated)
        removed = original_count - truncated_count

        Logger.warning("Truncated #{removed} messages to fit context window")

        Jido.AI.chat(model, truncated)
    end
  end
end
```

## Troubleshooting

### Context Exceeded Error

```elixir
# Error: Prompt exceeds context window
{:error, %ContextWindow.ContextExceededError{}}

# Solution: Enable truncation
{:ok, fitted} = ContextWindow.ensure_fit(
  prompt,
  model,
  strategy: :smart_truncate
)
```

### Unexpected Truncation

```elixir
# Check token count
{:ok, info} = ContextWindow.check_fit(prompt, model)
IO.puts "Using #{info.tokens} of #{info.limit} tokens"

# Adjust max_tokens if needed
{:ok, fitted} = ContextWindow.ensure_fit(
  prompt,
  model,
  reserve_completion: 2000  # Increase reservation
)
```

### Choosing Right Model

```elixir
# Check if model supports needed context
{:ok, limits} = ContextWindow.get_limits(model)

if limits.total < needed_tokens do
  # Switch to model with larger context
  model = "vertex:gemini-1.5-pro"  # 2M tokens
end
```

## Next Steps

- [Advanced Parameters](advanced-parameters.md) - Fine-tune generation
- [RAG Integration](rag-integration.md) - Extend with documents
- [Fine-Tuning](fine-tuning.md) - Custom models
- [Provider Matrix](../providers/provider-matrix.md) - Compare context limits
