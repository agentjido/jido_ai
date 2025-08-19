# Jido Eval Demo - Complete System Integration
# This demonstrates the full Jido Eval system working end-to-end

# Import required modules
alias Jido.Eval
alias Jido.Eval.Dataset.InMemory
alias Jido.Eval.Sample.SingleTurn

# Create sample data
samples = [
  %SingleTurn{
    id: "sample_1",
    user_input: "What is the capital of France?",
    retrieved_contexts: ["France's capital is Paris.", "Paris is located in northern France."],
    response: "Paris is the capital of France.",
    tags: %{"category" => "geography"}
  },
  %SingleTurn{
    id: "sample_2", 
    user_input: "What is 2+2?",
    retrieved_contexts: ["Basic arithmetic: 2+2=4", "Addition is a mathematical operation."],
    response: "2+2 equals 4.",
    tags: %{"category" => "math"}
  }
]

# Create dataset
{:ok, dataset} = InMemory.new(samples)

IO.puts("=== Jido Eval Demo ===")
IO.puts("Dataset created with #{Eval.Dataset.count(dataset)} samples")

# Simple evaluation with default metrics
IO.puts("\n1. Simple Ragas-compatible evaluation:")
{:ok, result} = Eval.evaluate(dataset, metrics: [:faithfulness])

IO.puts("   Evaluation completed!")
IO.puts("   Run ID: #{result.run_id}")
IO.puts("   Samples processed: #{result.metadata.samples_successful}/#{result.metadata.samples_total}")
IO.puts("   Duration: #{result.metadata.duration_ms}ms")

# Show available metrics
IO.puts("\n2. Available metrics:")
metrics = Eval.list_metrics()
Enum.each(metrics, fn metric -> IO.puts("   - #{metric}") end)

# Advanced configuration example
IO.puts("\n3. Advanced configuration with custom settings:")

{:ok, result2} = Eval.evaluate(dataset,
  metrics: [:faithfulness, :context_precision],
  llm: "test:mock",  # Using test model for demo
  run_config: %Eval.RunConfig{
    max_workers: 4,
    timeout: 30_000
  },
  tags: %{"experiment" => "demo_run", "version" => "1.0"}
)

IO.puts("   Advanced evaluation completed!")
IO.puts("   Metrics used: #{inspect(Map.keys(result2.summary))}")
IO.puts("   Tags: #{inspect(result2.metadata.config.tags)}")

# Async evaluation demonstration
IO.puts("\n4. Asynchronous evaluation with monitoring:")

{:ok, run_id} = Eval.evaluate(dataset, 
  metrics: [:faithfulness],
  sync: false
)

IO.puts("   Started async evaluation: #{run_id}")

# Monitor progress
case Eval.get_progress(run_id) do
  {:ok, progress} -> 
    IO.puts("   Progress: #{progress.completed}/#{progress.total} samples")
  {:error, _} -> 
    IO.puts("   Run completed before progress check")
end

# Wait for completion
case Eval.await_result(run_id, 10_000) do
  {:ok, async_result} ->
    IO.puts("   Async evaluation completed!")
    IO.puts("   Final progress: #{async_result.metadata.samples_successful} samples")
  {:error, :timeout} ->
    IO.puts("   Async evaluation still running...")
end

IO.puts("\n=== Demo Complete ===")
IO.puts("Jido Eval system is fully operational!")
