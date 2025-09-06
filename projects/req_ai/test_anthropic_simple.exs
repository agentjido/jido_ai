# Test script for ReqAI Anthropic integration

IO.puts("=== Testing ReqAI Anthropic Integration ===")

# Step 1: Check API key availability through Kagi
case Kagi.get(:anthropic_api_key) do
  nil ->
    IO.puts("✗ No Anthropic API key found in Kagi")
    IO.puts("Please set ANTHROPIC_API_KEY environment variable")
    
  api_key when is_binary(api_key) ->
    IO.puts("✓ Found API key via Kagi (#{String.slice(api_key, 0, 12)}...)")
    IO.puts("✓ Kagi configuration system working")
end

# Step 2: Test provider registry
IO.puts("\n=== Testing Provider Registry ===")
case ReqAI.provider(:anthropic) do
  {:ok, ReqAI.Providers.Anthropic} ->
    IO.puts("✓ Provider registry working")
  
  {:ok, other_module} ->
    IO.puts("✗ Expected ReqAI.Providers.Anthropic, got #{inspect(other_module)}")
  
  {:error, :not_found} ->
    IO.puts("✗ Anthropic provider not registered")
end

# Step 3: Test model creation
IO.puts("\n=== Testing Model Creation ===")
case ReqAI.model("anthropic:claude-3-sonnet-20241022") do
  {:ok, model} ->
    IO.puts("✓ Model created: #{inspect(model)}")
  
  {:error, error} ->
    IO.puts("✗ Failed to create model: #{inspect(error)}")
end

# Step 4: Test basic generate_text call
IO.puts("\n=== Testing Basic Generate Text ===")
case Kagi.get(:anthropic_api_key) do
  nil ->
    IO.puts("⚠ Skipping actual API call (no API key)")

  _api_key ->
    case ReqAI.generate_text("anthropic:claude-3-sonnet-20241022", "Write a haiku about Elixir") do
      {:ok, text} when is_binary(text) ->
        IO.puts("✓ Generated text successfully:")
        IO.puts("#{text}")
      
      {:error, error} ->
        IO.puts("✗ Failed to generate text: #{inspect(error)}")
    end
end

IO.puts("\n=== Test Complete ===")
