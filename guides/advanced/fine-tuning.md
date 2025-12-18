# Fine-Tuning

Fine-tuning allows you to customize foundation models with your own data, creating specialized models for specific tasks, domains, or writing styles.

## Overview

Fine-tuning enables:
- **Domain Specialization**: Train models on domain-specific data
- **Custom Behavior**: Match specific tone, style, or format
- **Improved Accuracy**: Better performance on specialized tasks
- **Cost Reduction**: Smaller fine-tuned models can replace larger ones

## Supported Providers

| Provider | Fine-Tuning Support | Model Format | Best For |
|----------|---------------------|--------------|----------|
| **OpenAI** | ✅ Full | `ft:gpt-4-0613:org:suffix:id` | General purpose |
| **Google** | ✅ Full | `projects/.../models/...` | Enterprise, Vertex AI |
| **Cohere** | ✅ Full | `custom-model-name` | RAG, embeddings |
| **Together** | ✅ Full | `org/model-name` | Open source models |

## Quick Start

### Detecting Fine-Tuned Models

```elixir
alias Jido.AI.Features.FineTuning

# Check if a model is fine-tuned
FineTuning.fine_tuned?("ft:gpt-4-0613:myorg:custom:abc123")
# => true

FineTuning.fine_tuned?("gpt-4")
# => false

# Parse fine-tuned model ID
{:ok, info} = FineTuning.parse_model_id("ft:gpt-4-0613:myorg:custom:abc123", :openai)

IO.inspect info
# %{
#   provider: :openai,
#   base_model: "gpt-4-0613",
#   organization: "myorg",
#   suffix: "custom",
#   fine_tune_id: "abc123"
# }
```

### Using Fine-Tuned Models

```elixir
# Use just like any other model
{:ok, response} = Jido.AI.chat(
  "openai:ft:gpt-4-0613:myorg:legal-assistant:abc123",
  "Review this contract for compliance issues"
)

# Fine-tuned models inherit base model capabilities
base_model = FineTuning.get_base_model(model)
# {:ok, "gpt-4-0613"}
```

## Provider-Specific Fine-Tuning

### OpenAI

OpenAI fine-tuned models use the `ft:` prefix:

```elixir
# Model ID format: ft:BASE_MODEL:ORG:SUFFIX:ID
fine_tuned_model = "openai:ft:gpt-4-0613:myorg:legal:ft-123"

# Parse components
{:ok, info} = FineTuning.parse_model_id(
  "ft:gpt-4-0613:myorg:legal:ft-123",
  :openai
)

%{
  base_model: "gpt-4-0613",
  organization: "myorg",
  suffix: "legal",
  fine_tune_id: "ft-123"
}

# Use in chat
{:ok, response} = Jido.AI.chat(
  fine_tuned_model,
  "Analyze this legal document"
)
```

### Google Vertex AI

Google fine-tuned models use full resource paths:

```elixir
# Model ID format: projects/PROJECT/locations/LOCATION/models/MODEL
vertex_model = "vertex:projects/my-project/locations/us-central1/models/custom-gemini-123"

# Parse components
{:ok, info} = FineTuning.parse_model_id(
  "projects/my-project/locations/us-central1/models/custom-gemini-123",
  :google
)

%{
  provider: :google,
  base_model: "gemini-pro",  # Detected from name
  organization: "my-project",
  fine_tune_id: "custom-gemini-123"
}

# Use in chat
{:ok, response} = Jido.AI.chat(vertex_model, "Specialized query")
```

### Cohere

Cohere fine-tuned models use custom names:

```elixir
# Model ID format: custom-MODEL_NAME
cohere_model = "cohere:custom-rag-assistant"

# Parse components
{:ok, info} = FineTuning.parse_model_id("custom-rag-assistant", :cohere)

%{
  provider: :cohere,
  base_model: "command",  # Default assumption
  fine_tune_id: "custom-rag-assistant"
}

# Use with RAG
alias Jido.AI.Features.RAG

documents = load_documents()
{:ok, opts} = RAG.build_rag_options(documents, %{}, :cohere)

{:ok, response} = Jido.AI.chat(cohere_model, "Query", opts)
```

### Together AI

Together fine-tuned models include organization prefix:

```elixir
# Model ID format: ORG/MODEL_NAME
together_model = "together:myorg/fine-tuned-llama-70b"

# Parse components
{:ok, info} = FineTuning.parse_model_id("myorg/fine-tuned-llama-70b", :together)

%{
  provider: :together,
  base_model: "fine-tuned-llama-70b",
  organization: "myorg",
  fine_tune_id: "myorg/fine-tuned-llama-70b"
}

# Use in chat
{:ok, response} = Jido.AI.chat(together_model, "Specialized task")
```

## Advanced Patterns

### 1. Model Selection Based on Task

Route tasks to appropriate fine-tuned models:

```elixir
defmodule MyApp.ModelRouter do
  @models %{
    legal: "openai:ft:gpt-4:org:legal:id1",
    medical: "openai:ft:gpt-4:org:medical:id2",
    customer_service: "openai:ft:gpt-3.5:org:support:id3",
    general: "openai:gpt-4"
  }

  def chat(prompt, task_type \\ :general) do
    model = Map.get(@models, task_type, @models.general)
    Jido.AI.chat(model, prompt)
  end

  def classify_and_chat(prompt) do
    # Auto-detect task type
    task_type = classify_task(prompt)
    chat(prompt, task_type)
  end

  defp classify_task(prompt) do
    # Quick classification with fast model
    {:ok, response} = Jido.AI.chat(
      "groq:llama-3.1-8b-instant",
      "Classify this as legal/medical/support/general (one word): #{prompt}",
      max_tokens: 10
    )

    String.downcase(response.content)
    |> String.trim()
    |> String.to_atom()
  end
end
```

### 2. Fine-Tuned Model Fallback

Fallback to base model if fine-tuned fails:

```elixir
defmodule MyApp.SmartFallback do
  alias Jido.AI.Features.FineTuning

  def chat_with_fallback(model_id, prompt, opts \\ []) do
    case Jido.AI.chat(model_id, prompt, opts) do
      {:ok, response} ->
        {:ok, response}

      {:error, _reason} ->
        # Try base model
        case get_base_model(model_id) do
          {:ok, base_model_id} ->
            IO.puts "Falling back to base model: #{base_model_id}"
            Jido.AI.chat(base_model_id, prompt, opts)

          {:error, :not_fine_tuned} ->
            {:error, :all_failed}
        end
    end
  end

  defp get_base_model(model_id) do
    case Jido.AI.Model.from(model_id) do
      {:ok, model} ->
        FineTuning.get_base_model(model)

      {:error, _} ->
        {:error, :invalid_model}
    end
  end
end
```

### 3. A/B Testing Fine-Tuned Models

Compare fine-tuned model performance:

```elixir
defmodule MyApp.ABTesting do
  def compare_models(prompt, model_a, model_b) do
    # Run both models in parallel
    tasks = [
      Task.async(fn -> Jido.AI.chat(model_a, prompt) end),
      Task.async(fn -> Jido.AI.chat(model_b, prompt) end)
    ]

    [result_a, result_b] = Task.await_many(tasks)

    %{
      model_a: %{model: model_a, result: result_a},
      model_b: %{model: model_b, result: result_b},
      comparison: compare_results(result_a, result_b)
    }
  end

  def rolling_deployment(prompts, current_model, new_model, percentage \\ 10) do
    Enum.map(prompts, fn prompt ->
      model = if :rand.uniform(100) <= percentage do
        new_model
      else
        current_model
      end

      {model, Jido.AI.chat(model, prompt)}
    end)
  end

  defp compare_results({:ok, a}, {:ok, b}) do
    %{
      length_diff: String.length(a.content) - String.length(b.content),
      latency_diff: compare_latencies(a, b),
      tokens_diff: a.usage.total_tokens - b.usage.total_tokens
    }
  end

  defp compare_results(_, _), do: %{error: true}

  defp compare_latencies(_a, _b), do: 0  # Would need actual timing
end
```

### 4. Version Management

Manage multiple versions of fine-tuned models:

```elixir
defmodule MyApp.ModelVersions do
  @versions %{
    legal_assistant: [
      v3: "openai:ft:gpt-4:org:legal-v3:id3",
      v2: "openai:ft:gpt-4:org:legal-v2:id2",
      v1: "openai:ft:gpt-4:org:legal-v1:id1"
    ],
    customer_support: [
      v2: "openai:ft:gpt-3.5:org:support-v2:id2",
      v1: "openai:ft:gpt-3.5:org:support-v1:id1"
    ]
  }

  def get_model(model_name, version \\ :latest) do
    versions = Map.get(@versions, model_name, [])

    model_id = case version do
      :latest -> Keyword.values(versions) |> List.first()
      version -> Keyword.get(versions, version)
    end

    case model_id do
      nil -> {:error, :model_not_found}
      id -> {:ok, id}
    end
  end

  def chat(model_name, prompt, opts \\ []) do
    version = Keyword.get(opts, :version, :latest)

    case get_model(model_name, version) do
      {:ok, model_id} ->
        Jido.AI.chat(model_id, prompt, Keyword.delete(opts, :version))

      error -> error
    end
  end

  def rollback(model_name) do
    # Rollback to previous version
    versions = Map.get(@versions, model_name, [])

    case versions do
      [_current, previous | _] ->
        {:ok, Keyword.get(versions, previous)}

      _ ->
        {:error, :no_previous_version}
    end
  end
end
```

### 5. Performance Monitoring

Monitor fine-tuned model performance:

```elixir
defmodule MyApp.ModelMonitoring do
  use GenServer

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def chat_monitored(model_id, prompt, opts \\ []) do
    start_time = System.monotonic_time(:millisecond)

    result = Jido.AI.chat(model_id, prompt, opts)

    latency = System.monotonic_time(:millisecond) - start_time

    # Record metrics
    record_metrics(model_id, result, latency)

    result
  end

  defp record_metrics(model_id, result, latency) do
    metrics = %{
      model_id: model_id,
      latency: latency,
      success: match?({:ok, _}, result),
      timestamp: DateTime.utc_now()
    }

    case result do
      {:ok, response} ->
        metrics = Map.merge(metrics, %{
          tokens: response.usage.total_tokens,
          cost: estimate_cost(model_id, response.usage)
        })

      {:error, reason} ->
        metrics = Map.put(metrics, :error, inspect(reason))
    end

    GenServer.cast(__MODULE__, {:record, metrics})
  end

  def get_stats(model_id) do
    GenServer.call(__MODULE__, {:get_stats, model_id})
  end

  # GenServer callbacks
  def init(_), do: {:ok, %{stats: %{}}}

  def handle_cast({:record, metrics}, state) do
    model_id = metrics.model_id
    model_stats = Map.get(state.stats, model_id, [])
    updated_stats = [metrics | Enum.take(model_stats, 999)]  # Keep last 1000

    {:noreply, put_in(state, [:stats, model_id], updated_stats)}
  end

  def handle_call({:get_stats, model_id}, _from, state) do
    stats = Map.get(state.stats, model_id, [])

    summary = %{
      total_requests: length(stats),
      success_rate: calculate_success_rate(stats),
      avg_latency: calculate_avg_latency(stats),
      total_tokens: calculate_total_tokens(stats),
      total_cost: calculate_total_cost(stats)
    }

    {:reply, summary, state}
  end

  defp estimate_cost(_model_id, _usage), do: 0.0  # Implement cost calculation
  defp calculate_success_rate(stats) do
    successful = Enum.count(stats, & &1.success)
    successful / max(length(stats), 1) * 100
  end
  defp calculate_avg_latency(stats) do
    Enum.map(stats, & &1.latency) |> Enum.sum() / max(length(stats), 1)
  end
  defp calculate_total_tokens(stats) do
    Enum.map(stats, &Map.get(&1, :tokens, 0)) |> Enum.sum()
  end
  defp calculate_total_cost(stats) do
    Enum.map(stats, &Map.get(&1, :cost, 0)) |> Enum.sum()
  end
end
```

## Best Practices

### 1. Capability Inheritance

Fine-tuned models inherit base model capabilities:

```elixir
alias Jido.AI.Features.FineTuning

# Check if fine-tuned model supports a capability
fine_tuned = Jido.AI.Model.from("openai:ft:gpt-4:org:custom:id")

# Supports same capabilities as gpt-4
FineTuning.supports_capability?(fine_tuned, :streaming)  # true
FineTuning.supports_capability?(fine_tuned, :tools)      # true
FineTuning.supports_capability?(fine_tuned, :vision)     # true (if base supports)
```

### 2. Model Naming Conventions

```elixir
# ✅ Good: Clear, descriptive names
"ft:gpt-4:myorg:legal-contract-review:v1"
"ft:gpt-3.5:myorg:customer-support-es:v2"

# ❌ Bad: Unclear names
"ft:gpt-4:myorg:model1:abc"
"ft:gpt-4:myorg:test:xyz"
```

### 3. Version Control

```elixir
# Track versions in configuration
config :my_app, :models,
  legal_assistant: [
    current: "ft:gpt-4:org:legal-v3:id3",
    previous: "ft:gpt-4:org:legal-v2:id2",
    stable: "ft:gpt-4:org:legal-v1:id1"
  ]

# Easy rollback
def rollback_model(model_name) do
  config = Application.get_env(:my_app, :models)
  models = config[model_name]

  # Swap current and previous
  updated = [
    current: models[:previous],
    previous: models[:current],
    stable: models[:stable]
  ]

  Application.put_env(:my_app, :models,
    Keyword.put(config, model_name, updated)
  )
end
```

### 4. Cost Optimization

```elixir
# Use smaller fine-tuned models for simple tasks
defmodule MyApp.CostOptimized do
  def chat(prompt, complexity: :simple) do
    # Fine-tuned GPT-3.5 is cheaper than base GPT-4
    Jido.AI.chat("openai:ft:gpt-3.5:org:simple:id", prompt)
  end

  def chat(prompt, complexity: :complex) do
    # Use fine-tuned GPT-4 for complex tasks
    Jido.AI.chat("openai:ft:gpt-4:org:complex:id", prompt)
  end
end
```

### 5. Testing Fine-Tuned Models

```elixir
defmodule MyApp.ModelTest do
  use ExUnit.Case

  @test_cases [
    %{input: "Test case 1", expected_pattern: ~r/pattern1/},
    %{input: "Test case 2", expected_pattern: ~r/pattern2/}
  ]

  test "fine-tuned model accuracy" do
    model = "openai:ft:gpt-4:org:custom:id"

    results = Enum.map(@test_cases, fn test_case ->
      {:ok, response} = Jido.AI.chat(model, test_case.input)
      matches = String.match?(response.content, test_case.expected_pattern)
      {test_case, matches}
    end)

    accuracy = Enum.count(results, fn {_, matches} -> matches end) / length(results)

    assert accuracy >= 0.90, "Model accuracy #{accuracy} below 90%"
  end
end
```

## Troubleshooting

### Model ID Parsing Errors

```elixir
# Error: Invalid format
{:error, :invalid_format}

# Check format for your provider:
# OpenAI: ft:BASE:ORG:SUFFIX:ID
# Google: projects/PROJ/locations/LOC/models/MODEL
# Cohere: custom-MODEL
# Together: ORG/MODEL
```

### Model Not Found

```elixir
# Verify model ID is correct
{:ok, info} = FineTuning.parse_model_id(model_id, provider)
IO.inspect info

# Check if model exists (would need API integration)
# FineTuning.discover(:openai, api_key)
```

### Capability Mismatches

```elixir
# Fine-tuned models inherit base capabilities
{:ok, base} = FineTuning.get_base_model(model)
IO.puts "Base model: #{base}"

# Check base model capabilities instead
base_model = Jido.AI.Model.from("openai:#{base}")
```

## Fine-Tuning Workflow

1. **Prepare Training Data**
   - Collect high-quality examples
   - Format according to provider requirements
   - Validate data quality

2. **Create Fine-Tune Job**
   - Upload training data
   - Configure training parameters
   - Start fine-tuning job

3. **Monitor Training**
   - Track training progress
   - Review validation metrics
   - Adjust if needed

4. **Deploy Model**
   - Test fine-tuned model
   - Compare with base model
   - Deploy to production

5. **Monitor Performance**
   - Track accuracy metrics
   - Monitor latency and costs
   - Gather user feedback

6. **Iterate**
   - Collect new training data
   - Create new fine-tune version
   - A/B test and deploy

## Next Steps

- [Advanced Parameters](advanced-parameters.md) - Optimize model behavior
- [Context Windows](context-windows.md) - Manage long contexts
- [RAG Integration](rag-integration.md) - Enhance with documents
- [Provider Matrix](../providers/provider-matrix.md) - Compare providers
