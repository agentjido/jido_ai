# Test script for ReqAI Model JSON loading

IO.puts("=== Testing ReqAI Model JSON Loading ===")

# Test 1: Check if models are loaded from JSON
IO.puts("\n=== Testing Model Loading ===")
models = ReqAI.Providers.Anthropic.models()
model_count = Enum.count(models)
IO.puts("✓ Loaded #{model_count} models from anthropic.json")

if model_count > 0 do
  # Show first few models
  models
  |> Enum.take(3)
  |> Enum.each(fn {model_id, model} ->
    IO.puts("  - #{model_id}: #{inspect(model.capabilities)}")
  end)
end

# Test 2: Test model retrieval
IO.puts("\n=== Testing Model Retrieval ===")
case ReqAI.Providers.Anthropic.get_model("claude-3-5-sonnet-20241022") do
  nil ->
    IO.puts("⚠ Claude 3.5 Sonnet not found in models")
  model ->
    IO.puts("✓ Retrieved model: #{model.model}")
    IO.puts("  - Capabilities: #{inspect(model.capabilities)}")
    IO.puts("  - Modalities: #{inspect(model.modalities)}")
    IO.puts("  - Cost: #{inspect(model.cost)}")
    IO.puts("  - Limit: #{inspect(model.limit)}")
end

# Test 3: Test model with metadata
IO.puts("\n=== Testing Model with Metadata ===")
case ReqAI.Model.from({:anthropic, [model: "claude-3-5-sonnet-20241022"]}) do
  {:ok, model} ->
    IO.puts("✓ Created model with metadata from JSON:")
    model_with_defaults = ReqAI.Model.with_defaults(model)
    IO.puts("  - Model: #{model.model}")
    IO.puts("  - Provider: #{model.provider}")
    IO.puts("  - Capabilities: #{inspect(model.capabilities)}")
    IO.puts("  - With defaults: #{inspect(model_with_defaults.capabilities)}")
  
  {:error, error} ->
    IO.puts("✗ Failed to create model: #{inspect(error)}")
end

IO.puts("\n=== Test Complete ===")
