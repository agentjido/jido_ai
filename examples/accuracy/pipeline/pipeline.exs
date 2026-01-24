#!/usr/bin/env env elixir

# Accuracy Pipeline Example
#
# Run this example with:
#   mix run examples/accuracy/pipeline/pipeline.exs
#
# This example demonstrates the complete accuracy pipeline
# that orchestrates all accuracy improvement techniques.

Application.ensure_all_started(:jido_ai)

alias Jido.AI.Accuracy.{Pipeline, Presets}

IO.puts("\n=== Accuracy Pipeline Example ===\n")

# Example 1: Using presets
IO.puts("Example 1: Using preset configurations")
IO.puts("--------------------------------------")

IO.puts("""
Available presets:
  :fast      - Minimal compute, basic verification (1-3 candidates)
  :balanced  - Moderate compute, full verification (3-5 candidates)
  :accurate  - Maximum compute, all features (5-10 candidates)
  :coding    - Optimized for code correctness
  :research  - Optimized for factual QA
""")

IO.puts("Usage:")
preset_usage = """
# Get preset configuration
{:ok, config} = Presets.get(:balanced)

# Create pipeline with preset
{:ok, pipeline} = Pipeline.new(%{
  config: config,
  generator: fn query ->
    ReqLLM.Generation.generate_text(model, [
      %{role: :user, content: query}
    ])
  end
})

# Run pipeline
{:ok, result} = Pipeline.run(pipeline, "What is 15 * 23?")
"""

IO.puts(preset_usage)

# Example 2: Custom pipeline configuration
IO.puts("\n\nExample 2: Custom pipeline configuration")
IO.puts("---------------------------------------")

custom_pipeline = """
{:ok, pipeline} = Pipeline.new(%{
  stages: [
    {:generation, %{
      generator: &my_generator/1,
      num_candidates: 5
    }},
    {:verification, %{
      verifier: my_verifier,
      threshold: 0.6
    }},
    {:reflection, %{
      min_score_threshold: 0.7,
      max_iterations: 2
    }},
    {:calibration, %{
      method: :temperature_scaling,
      min_confidence: 0.8
    }}
  ],
  budget: %{
    max_tokens: 10_000,
    max_duration_ms: 30_000
  }
})
"""

IO.puts(custom_pipeline)

# Example 3: Pipeline stages explained
IO.puts("\n\nExample 3: Pipeline stages")
IO.puts("-------------------------")

IO.puts("""
┌─────────────────────────────────────────────────────────────┐
│                     Pipeline Flow                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Query                                                      │
│   │                                                         │
│   ▼                                                         │
│ ┌─────────────┐                                             │
│ │ Generation  │ → Generate N candidates                     │
│ └─────────────┘                                             │
│   │                                                         │
│   ▼                                                         │
│ ┌─────────────┐                                             │
│ │ Verification│ → Score each candidate                     │
│ └─────────────┘                                             │
│   │                                                         │
│   ├──────────┬──────────┐                                   │
│   ▼          ▼          ▼                                   │
│ Pass       Fail       Filter                                │
│   │          │          │                                   │
│   ▼          ▼          ▼                                   │
│ Keep    Reflect    Discard                                 │
│              │                                               │
│              ▼                                               │
│        ┌─────────┐                                           │
│        │Reflect  │ → Improve low-scoring candidates           │
│ └─────────────┘                                           │
│              │                                               │
│   ┌──────────┴──────────┐                                   │
│   ▼                     ▼                                   │
│ All candidates    Calibrate                                 │
│                         │                                   │
│                         ▼                                   │
│                   ┌─────────┐                                 │
│                   │Calibrate│ → Adjust confidence             │
│                   └─────────┘                                 │
│                         │                                   │
│                         ▼                                   │
│                   ┌─────────┐                                 │
│                   │ Select  │ → Choose best                 │
│                   └─────────┘                                 │
│                         │                                   │
│                         ▼                                   │
│                    Result                                    │
└─────────────────────────────────────────────────────────────┘
""")

# Example 4: Pipeline result structure
IO.puts("\n\nExample 4: Pipeline result")
IO.puts("-------------------------")

result_structure = """
{:ok, result} = Pipeline.run(pipeline, query)

# result.best_answer - The selected best answer
# result.confidence - Confidence score (0-1)
# result.metadata: %{
#   num_candidates: 5,
#   verification_passed: 3,
#   reflection_iterations: 1,
#   calibration_applied: true,
#   total_tokens: 1250,
#   duration_ms: 3500
# }
"""

IO.puts(result_structure)

# Example 5: Compute budgeting
IO.puts("\n\nExample 5: Compute budgeting")
IO.puts("-------------------------")

IO.puts("Control resource usage with budgets:\n")

budget_example = """
{:ok, pipeline} = Pipeline.new(%{
  stages: [:generation, :verification],
  budget: %{
    max_tokens: 5000,         # Stop after using this many tokens
    max_duration_ms: 10_000,   # Stop after this much time
    max_cost_usd: 0.10         # Stop after spending this much
  }
})
"""

IO.puts(budget_example)

IO.puts("""
If budget is exceeded:
  → Pipeline stops gracefully
  → Returns {:error, :budget_exceeded, metadata}
  → Can fall back to simpler method
""")

# Example 6: Telemetry
IO.puts("\n\nExample 6: Pipeline telemetry")
IO.puts("----------------------------")

IO.puts("Attach telemetry handler to monitor pipeline:\n")

telemetry_example = """
:telemetry.attach(
  "pipeline-monitor",
  [:jido, :ai, :pipeline, :complete],
  &handle_pipeline_event/4,
  nil
)

def handle_pipeline_event(_event, measurements, metadata, _config) do
  IO.puts(\"\"\"
  Pipeline completed in #{measurements.duration}ms
  Candidates: #{metadata.num_candidates}
  Final score: #{metadata.final_score}
  \"\"\")
end
"""

IO.puts(telemetry_example)

# Example 7: Complete service example
IO.puts("\n\nExample 7: Complete service wrapper")
IO.puts("----------------------------------")

service_example = """
defmodule MyApp.AccuracyService do
  alias Jido.AI.Accuracy.Pipeline

  def answer(query) do
    {:ok, pipeline} = Pipeline.new(%{
      stages: [:generation, :verification, :reflection],
      generator: &generate/1
    })

    case Pipeline.run(pipeline, query) do
      {:ok, result} ->
        {:ok, result.best_answer, result.metadata}

      {:error, :budget_exceeded, _metadata} ->
        # Fallback to direct generation
        {:ok, fallback} = generate_direct(query)
        {:ok, fallback, %{method: :direct}}
    end
  end

  defp generate(query) do
    ReqLLM.Generation.generate_text(model, [
      %{role: :user, content: query}
    ])
  end
end
"""

IO.puts(service_example)

# Summary
IO.puts("\n=== Summary ===")
IO.puts("-----------")
IO.puts("The pipeline provides:")
IO.puts("  • End-to-end accuracy improvement")
IO.puts("  • Configurable stages")
IO.puts("  • Resource budgeting")
IO.puts("  • Telemetry and monitoring")
IO.puts("  • Preset configurations")
IO.puts("\nBest practices:")
IO.puts("  1. Start with presets (balanced, fast, accurate)")
IO.puts("  2. Add stages incrementally as needed")
IO.puts("  3. Use budgets to control costs")
IO.puts("  4. Monitor with telemetry")
IO.puts("  5. Have fallback for budget failures")
IO.puts("\n")
