# Advanced Generation Parameters

Advanced parameters give fine-grained control over AI model behavior, enabling optimization for specific use cases from creative writing to precise code generation.

## Overview

Advanced parameters control:
- **Temperature**: Randomness and creativity
- **Top-P/Top-K**: Token selection strategies
- **Frequency/Presence Penalties**: Reduce repetition
- **Logit Bias**: Control specific tokens
- **Response Format**: Structured output (JSON mode)
- **Provider Options**: Provider-specific features

## Core Parameters

### Temperature

Controls randomness (0.0-2.0):

```elixir
# Deterministic (code, facts, analysis)
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Write a function to calculate fibonacci",
  temperature: 0.0
)

# Balanced (general purpose)
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Explain quantum computing",
  temperature: 0.7  # Default
)

# Creative (stories, brainstorming)
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Write a creative sci-fi story",
  temperature: 1.5
)
```

**Guidelines:**
- `0.0-0.3`: Factual, deterministic (code, math, facts)
- `0.4-0.8`: Balanced (general chat, explanations)
- `0.9-1.5`: Creative (writing, brainstorming)
- `1.6-2.0`: Highly random (experimental)

### Top-P (Nucleus Sampling)

Controls diversity by probability mass (0.0-1.0):

```elixir
# More focused (better for factual tasks)
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "What is the capital of France?",
  top_p: 0.1  # Consider only top 10% probable tokens
)

# Balanced
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  prompt,
  top_p: 0.9  # Default
)

# More diverse
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Generate creative ideas",
  top_p: 0.95  # Consider wider range
)
```

**Note:** Use either `top_p` OR `temperature`, not both. Top-P is often more predictable.

### Max Tokens

Limit response length:

```elixir
# Short response
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Summarize this in one sentence",
  max_tokens: 50
)

# Medium response
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Explain the concept",
  max_tokens: 500
)

# Long response
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Write a detailed analysis",
  max_tokens: 2000
)
```

**Cost Optimization:** Lower `max_tokens` reduces costs and latency.

## Repetition Control

### Frequency Penalty

Reduces repetition of frequent tokens (-2.0 to 2.0):

```elixir
# No penalty (may repeat)
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  prompt,
  frequency_penalty: 0.0  # Default
)

# Moderate penalty (reduce repetition)
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  prompt,
  frequency_penalty: 0.5
)

# Strong penalty (avoid repetition)
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Generate diverse examples",
  frequency_penalty: 1.0
)
```

### Presence Penalty

Reduces repetition of any token (-2.0 to 2.0):

```elixir
# Encourage new topics
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Brainstorm ideas",
  presence_penalty: 0.6  # Encourages new concepts
)

# Strong topic diversity
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "List diverse alternatives",
  presence_penalty: 1.0
)
```

**Difference:**
- **Frequency**: Penalizes based on how often a token has appeared
- **Presence**: Penalizes any token that has appeared, regardless of frequency

## Advanced Features

### Logit Bias

Control specific token probabilities (OpenAI/compatible):

```elixir
# Suppress specific tokens
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Write a story",
  logit_bias: %{
    1234 => -100,  # Never use token 1234
    5678 => -50    # Discourage token 5678
  }
)

# Encourage specific tokens
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Technical explanation",
  logit_bias: %{
    9012 => 100  # Strongly prefer token 9012
  }
)
```

**Use Cases:**
- Prevent profanity (ban specific tokens)
- Enforce terminology (encourage technical terms)
- Control formatting (ban/require specific characters)

### JSON Mode

Guarantee valid JSON output (OpenAI/Groq/compatible):

```elixir
# Enable JSON mode
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Extract entities from text as JSON",
  response_format: %{type: "json_object"}
)

# Response is guaranteed valid JSON
data = Jason.decode!(response.content)
```

**Requirements:**
- Prompt must explicitly request JSON
- Works with OpenAI, Groq, Together, and compatible providers

### Provider-Specific Options

#### OpenAI - Log Probabilities

```elixir
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Analyze sentiment",
  provider_options: [
    logprobs: true,
    top_logprobs: 5  # Top 5 alternative tokens
  ]
)
```

#### Groq - Reasoning Effort

```elixir
{:ok, response} = Jido.AI.chat(
  "groq:llama-3.1-70b",
  "Solve this complex problem",
  provider_options: [
    reasoning_effort: "high"  # More deliberate reasoning
  ]
)
```

#### Anthropic - Top-K Sampling

```elixir
{:ok, response} = Jido.AI.chat(
  "anthropic:claude-3-sonnet",
  prompt,
  provider_options: [
    anthropic_top_k: 40  # Nucleus sampling parameter
  ]
)
```

#### OpenRouter - Fallback Models

```elixir
{:ok, response} = Jido.AI.chat(
  "openrouter:anthropic/claude-3-sonnet",
  prompt,
  provider_options: [
    openrouter_models: ["openai/gpt-4", "anthropic/claude-3-opus"]  # Fallbacks
  ]
)
```

## Advanced Patterns

### Task-Specific Presets

```elixir
defmodule MyApp.Presets do
  def code_generation do
    [
      temperature: 0.2,
      max_tokens: 1000,
      frequency_penalty: 0.3
    ]
  end

  def creative_writing do
    [
      temperature: 1.2,
      max_tokens: 2000,
      presence_penalty: 0.6,
      frequency_penalty: 0.4
    ]
  end

  def fact_extraction do
    [
      temperature: 0.0,
      max_tokens: 500,
      response_format: %{type: "json_object"}
    ]
  end

  def chat_assistant do
    [
      temperature: 0.7,
      max_tokens: 500,
      presence_penalty: 0.2
    ]
  end
end

# Usage
{:ok, response} = Jido.AI.chat(
  "openai:gpt-4",
  "Write a function...",
  MyApp.Presets.code_generation()
)
```

### Dynamic Parameter Selection

```elixir
defmodule MyApp.DynamicParams do
  def chat(prompt, task_type) do
    params = select_params(task_type)

    Jido.AI.chat("openai:gpt-4", prompt, params)
  end

  defp select_params(:code) do
    [temperature: 0.2, frequency_penalty: 0.3]
  end

  defp select_params(:creative) do
    [temperature: 1.2, presence_penalty: 0.6]
  end

  defp select_params(:factual) do
    [temperature: 0.0, max_tokens: 300]
  end

  defp select_params(_) do
    [temperature: 0.7]  # Default
  end
end
```

### Parameter Optimization

```elixir
defmodule MyApp.ParamOptimizer do
  def find_best_temperature(prompt, test_cases) do
    temperatures = [0.0, 0.3, 0.5, 0.7, 0.9, 1.2]

    results = Enum.map(temperatures, fn temp ->
      {:ok, response} = Jido.AI.chat(
        "openai:gpt-4",
        prompt,
        temperature: temp
      )

      score = evaluate_response(response, test_cases)

      {temp, score, response}
    end)

    # Find best temperature
    {best_temp, best_score, _} = Enum.max_by(results, fn {_, score, _} -> score end)

    IO.puts "Best temperature: #{best_temp} (score: #{best_score})"
    best_temp
  end

  defp evaluate_response(response, test_cases) do
    # Implement scoring logic
    100
  end
end
```

### Response Quality Control

```elixir
defmodule MyApp.QualityControl do
  def chat_with_quality_check(prompt, quality_threshold \\ 0.8) do
    # Try multiple parameter sets
    param_sets = [
      [temperature: 0.3, presence_penalty: 0.3],
      [temperature: 0.5, frequency_penalty: 0.4],
      [temperature: 0.7, presence_penalty: 0.5]
    ]

    results = Enum.map(param_sets, fn params ->
      {:ok, response} = Jido.AI.chat("openai:gpt-4", prompt, params)
      quality = assess_quality(response)
      {response, quality, params}
    end)

    # Find response meeting quality threshold
    case Enum.find(results, fn {_, quality, _} -> quality >= quality_threshold end) do
      {response, quality, params} ->
        IO.puts "Quality: #{quality} with params: #{inspect(params)}"
        {:ok, response}

      nil ->
        # Return best attempt
        {response, quality, _} = Enum.max_by(results, fn {_, q, _} -> q end)
        IO.puts "Best quality: #{quality} (below threshold #{quality_threshold})"
        {:ok, response}
    end
  end

  defp assess_quality(response) do
    # Implement quality metrics
    # - Length appropriateness
    # - Coherence
    # - Completeness
    0.85
  end
end
```

### Cost vs. Quality Trade-off

```elixir
defmodule MyApp.CostOptimized do
  def chat(prompt, budget: :low) do
    # Minimize tokens, use cheaper model
    Jido.AI.chat(
      "groq:llama-3.1-8b-instant",
      prompt,
      max_tokens: 256,
      temperature: 0.3
    )
  end

  def chat(prompt, budget: :medium) do
    # Balance cost and quality
    Jido.AI.chat(
      "openai:gpt-3.5-turbo",
      prompt,
      max_tokens: 500,
      temperature: 0.7
    )
  end

  def chat(prompt, budget: :high) do
    # Maximize quality
    Jido.AI.chat(
      "openai:gpt-4",
      prompt,
      max_tokens: 2000,
      temperature: 0.7
    )
  end
end
```

## Best Practices

### 1. Parameter Combinations

```elixir
# ✅ Good combinations
# Code generation
[temperature: 0.2, frequency_penalty: 0.3]

# Creative writing
[temperature: 1.2, presence_penalty: 0.6]

# Factual Q&A
[temperature: 0.0, max_tokens: 300]

# ❌ Avoid
[top_p: 0.9, temperature: 1.5]  # Don't use both
[frequency_penalty: 2.0, presence_penalty: 2.0]  # Too aggressive
```

### 2. Start Conservative

```elixir
# Start with defaults
{:ok, response} = Jido.AI.chat(model, prompt)  # temperature: 0.7

# Adjust based on results
if too_random?(response) do
  # Lower temperature
  {:ok, response} = Jido.AI.chat(model, prompt, temperature: 0.5)
end
```

### 3. Monitor Token Usage

```elixir
defmodule MyApp.TokenMonitor do
  def chat_monitored(model, prompt, opts \\ []) do
    {:ok, response} = Jido.AI.chat(model, prompt, opts)

    Logger.info("Token usage", %{
      prompt_tokens: response.usage.prompt_tokens,
      completion_tokens: response.usage.completion_tokens,
      total_tokens: response.usage.total_tokens,
      max_tokens: Keyword.get(opts, :max_tokens, "unlimited")
    })

    {:ok, response}
  end
end
```

### 4. Document Your Settings

```elixir
# ✅ Good: Clear documentation
@code_params [
  temperature: 0.2,      # Low for deterministic code
  frequency_penalty: 0.3 # Reduce repetition
]

# ❌ Bad: Magic numbers
@params [temperature: 0.2, frequency_penalty: 0.3]
```

### 5. Test Parameter Changes

```elixir
# A/B test parameter changes
defmodule MyApp.ABTest do
  def test_parameters(prompt, params_a, params_b, n \\ 10) do
    results_a = run_tests(prompt, params_a, n)
    results_b = run_tests(prompt, params_b, n)

    compare_results(results_a, results_b)
  end

  defp run_tests(prompt, params, n) do
    1..n
    |> Enum.map(fn _ ->
      {:ok, response} = Jido.AI.chat("openai:gpt-4", prompt, params)
      response
    end)
  end

  defp compare_results(results_a, results_b) do
    %{
      a: analyze_results(results_a),
      b: analyze_results(results_b)
    }
  end

  defp analyze_results(results) do
    %{
      avg_length: avg_length(results),
      avg_tokens: avg_tokens(results),
      variety: measure_variety(results)
    }
  end

  # Analysis helpers...
  defp avg_length(results), do: 0
  defp avg_tokens(results), do: 0
  defp measure_variety(results), do: 0
end
```

## Troubleshooting

### Response Too Random

```elixir
# Lower temperature
[temperature: 0.3]  # Down from 0.7

# Or use top_p instead
[top_p: 0.5]  # More focused
```

### Response Too Repetitive

```elixir
# Add penalties
[
  frequency_penalty: 0.5,   # Reduce word repetition
  presence_penalty: 0.3     # Encourage new topics
]
```

### Invalid JSON Response

```elixir
# Use JSON mode (OpenAI/Groq)
[response_format: %{type: "json_object"}]

# Ensure prompt explicitly requests JSON
prompt = "Return the data as a JSON object: ..."
```

### Token Limit Errors

```elixir
# Reduce max_tokens
[max_tokens: 500]  # Down from 1000

# Or check context window
{:ok, info} = ContextWindow.check_fit(prompt, model)
```

## Next Steps

- [Context Windows](context-windows.md) - Manage long contexts
- [RAG Integration](rag-integration.md) - Enhance with documents
- [Code Execution](code-execution.md) - Enable code interpretation
- [Provider Matrix](../providers/provider-matrix.md) - Compare provider support
