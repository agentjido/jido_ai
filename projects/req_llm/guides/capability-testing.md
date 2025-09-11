# Capability Testing Guide

This guide covers testing and verification workflows for ReqLLM, focusing on capability-driven testing patterns that ensure provider behavior matches advertised features.

## Overview

ReqLLM's testing system is built around two core principles:

1. **Capability-driven testing** - Tests verify that advertised capabilities actually work
2. **Fixture-based testing** - Tests can run against live APIs or cached fixtures

## Testing Modes

### Fixture Mode (Default)

By default, tests use cached fixtures for fast, reliable testing:

```bash
mix test                    # Uses fixtures
mix test --only anthropic   # Test specific provider with fixtures
```

### Live Mode

Set `LIVE=true` to test against real APIs and capture new fixtures:

```bash
LIVE=true mix test                    # Run all tests live
LIVE=true mix test --only anthropic   # Test specific provider live
LIVE=true mix test --only coverage    # Run coverage tests live
```

**Live mode will:**
- Make real API calls to providers
- Capture responses as JSON fixtures
- Overwrite existing fixtures with new responses
- Require valid API keys for each provider

## Test Organization

### Directory Structure

```
test/
├── coverage/              # Provider capability coverage tests
│   ├── anthropic/
│   │   ├── core_test.exs           # Basic generation
│   │   ├── streaming_test.exs      # Streaming responses
│   │   ├── tools_test.exs          # Tool calling
│   │   ├── thinking_tokens_test.exs # Reasoning capabilities
│   │   └── sampling_parameters_test.exs # Temperature, top-p, etc.
│   └── openai/            # Similar structure for each provider
├── support/
│   ├── fixtures/          # Cached API responses
│   │   ├── anthropic/
│   │   └── openai/
│   └── live_fixture.ex    # Test fixture system
└── req_llm_test.exs      # Core library tests
```

### Test Tags

Tests use ExUnit tags for organization:

```elixir
@moduletag :coverage       # Coverage test
@moduletag :anthropic      # Provider-specific
@moduletag :streaming      # Feature-specific
@moduletag :tools          # Capability-specific
```

Run specific test groups:
```bash
mix test --only coverage
mix test --only anthropic
mix test --only streaming
```

## Writing Capability Tests

### Basic Pattern

Use the `LiveFixture` module for capability testing:

```elixir
defmodule ReqLLM.Coverage.MyProvider.CoreTest do
  use ExUnit.Case, async: false
  
  import ReqLLM.Test.LiveFixture
  
  @moduletag :coverage
  @moduletag :my_provider
  
  @model "my_provider:my-model"
  
  test "basic text generation" do
    result = use_fixture(:my_provider, "basic_generation", fn ->
      ctx = ReqLLM.Context.new([ReqLLM.Context.user("Hello!")])
      ReqLLM.generate_text(@model, ctx, max_tokens: 50)
    end)
    
    {:ok, resp} = result
    assert is_binary(resp.body)
    assert resp.body != ""
    assert resp.status == 200
  end
end
```

### Capability-Driven Tests

Verify capabilities match metadata before testing:

```elixir
test "temperature parameter works as advertised" do
  # Check if model advertises temperature support
  supports_temp = ReqLLM.Capability.supports?(@model, :temperature)
  
  if supports_temp do
    result = use_fixture(:my_provider, "temperature_test", fn ->
      ctx = ReqLLM.Context.new([ReqLLM.Context.user("Be creative")])
      ReqLLM.generate_text(@model, ctx, temperature: 1.0, max_tokens: 50)
    end)
    
    {:ok, resp} = result
    assert resp.status == 200
  else
    skip("Model does not advertise temperature support")
  end
end

test "provider supports advertised capabilities" do
  # Get all capabilities from metadata
  capabilities = ReqLLM.Capability.for(@model)
  
  # Test each advertised capability
  if :tools in capabilities do
    # Test tool calling functionality
    use_fixture(:my_provider, "tool_test", fn ->
      # Tool calling test implementation
    end)
  end
  
  if :streaming in capabilities do
    # Test streaming functionality
    use_fixture(:my_provider, "streaming_test", fn ->
      # Streaming test implementation
    end)
  end
end
```

### Testing Tool Calling

Comprehensive tool calling tests:

```elixir
describe "tool calling capabilities" do
  @weather_tool %{
    name: "get_weather",
    description: "Get weather for a location",
    input_schema: %{
      type: "object",
      properties: %{
        location: %{type: "string", description: "City name"}
      },
      required: ["location"]
    }
  }

  test "basic tool calling" do
    use_fixture("tool_calling/basic", [], fn ->
      ctx = ReqLLM.Context.new([
        ReqLLM.Context.user("What's the weather in Paris?")
      ])
      
      ReqLLM.generate_text(@model, ctx, 
        tools: [@weather_tool],
        max_tokens: 200
      )
    end)
  end
  
  test "tool choice control" do
    if ReqLLM.Capability.supports?(@model, :tool_choice) do
      use_fixture("tool_calling/choice_specific", [], fn ->
        ctx = ReqLLM.Context.new([
          ReqLLM.Context.user("Tell me about weather")
        ])
        
        ReqLLM.generate_text(@model, ctx, 
          tools: [@weather_tool],
          tool_choice: %{type: "tool", name: "get_weather"}
        )
      end)
    else
      skip("Model does not support tool choice control")
    end
  end

  test "tool result handling" do
    use_fixture("tool_calling/with_result", [], fn ->
      ctx = ReqLLM.Context.new([
        ReqLLM.Context.user("What's the weather like?"),
        ReqLLM.Context.assistant("", tool_calls: [
          %{id: "call_1", name: "get_weather", arguments: %{"location" => "Paris"}}
        ]),
        ReqLLM.Context.tool_result("call_1", %{"weather" => "sunny", "temp" => 22})
      ])
      
      ReqLLM.generate_text(@model, ctx, tools: [@weather_tool])
    end)
  end
end
```

### Testing Streaming

Test streaming with proper chunk handling:

```elixir
test "streaming text generation" do
  if ReqLLM.Capability.supports?(@model, :streaming) do
    result = use_fixture(:my_provider, "streaming_test", fn ->
      ctx = ReqLLM.Context.new([ReqLLM.Context.user("Tell me a story")])
      
      {:ok, stream} = ReqLLM.stream_text(@model, ctx, max_tokens: 100)
      
      # Collect all chunks
      chunks = Enum.to_list(stream)
      
      # Verify streaming behavior
      assert length(chunks) > 1, "Should receive multiple chunks"
      
      # Last chunk should have finish_reason
      last_chunk = List.last(chunks)
      assert Map.has_key?(last_chunk, :finish_reason)
      
      # Return full response for fixture
      text = chunks |> Enum.map_join("", & &1.content)
      %{text: text, chunks: length(chunks)}
    end)
    
    assert result.chunks > 1
  else
    skip("Model does not support streaming")
  end
end
```

### Testing Multimodal Capabilities

Test image and other modality support:

```elixir
test "image input processing" do
  modalities = ReqLLM.Capability.modalities(@model)
  input_modalities = get_in(modalities, [:input]) || []
  
  if "image" in input_modalities do
    use_fixture(:my_provider, "image_input", fn ->
      # Base64 encoded test image
      image_data = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
      
      ctx = ReqLLM.Context.new([
        ReqLLM.Context.user([
          %{type: "text", text: "What do you see in this image?"},
          %{type: "image", source: %{
            type: "base64",
            media_type: "image/png", 
            data: image_data
          }}
        ])
      ])
      
      ReqLLM.generate_text(@model, ctx, max_tokens: 100)
    end)
  else
    skip("Model does not support image input")
  end
end
```

## Fixture Management

### Fixture Format

Fixtures are stored as JSON with metadata:

```json
{
  "captured_at": "2024-01-15T10:30:00Z",
  "provider": "anthropic",
  "result": {
    "type": "ok_response",
    "status": 200,
    "body": "Hello there! How can I assist you today?",
    "headers": {
      "content-type": "application/json",
      "anthropic-ratelimit-requests-remaining": "999"
    }
  }
}
```

### Fixture Organization

Organize fixtures by provider and capability:

```
test/support/fixtures/
├── anthropic/
│   ├── basic_completion.json
│   ├── system_prompt_completion.json
│   ├── temperature_test.json
│   ├── streaming/
│   │   ├── basic_streaming.json
│   │   └── streaming_with_tools.json
│   ├── tool_calling/
│   │   ├── choice_auto.json
│   │   ├── choice_specific.json
│   │   └── with_result.json
│   └── thinking_tokens/
│       ├── basic_reasoning.json
│       └── streaming_thinking.json
└── openai/
    ├── basic_completion.json
    └── tool_calling/
        └── function_call.json
```

### Fixture Best Practices

1. **Descriptive naming** - Use clear fixture names that indicate what they test
2. **Minimal responses** - Use `max_tokens` to keep fixtures small
3. **Deterministic content** - Use low temperature for reproducible responses
4. **Regular updates** - Refresh fixtures when APIs change

```elixir
# Good fixture usage
use_fixture("sampling/low_temperature", [], fn ->
  ReqLLM.generate_text(@model, ctx, 
    temperature: 0.1,  # Deterministic
    max_tokens: 20     # Minimal
  )
end)
```

## Provider Verification Workflows

### Adding a New Provider

1. **Create provider module** with DSL
2. **Add metadata file** in `priv/models_dev/`
3. **Create coverage tests** for each capability
4. **Run live tests** to capture fixtures
5. **Validate capabilities** match implementation

```bash
# Create provider tests
mix req_llm.gen.provider MyProvider

# Run live tests to capture fixtures
LIVE=true mix test --only coverage --only my_provider

# Validate capabilities
mix req_llm.validate_provider MyProvider
```

### Ongoing Verification

Regular verification workflows:

```bash
# Daily: Validate all providers with fixtures
mix test --only coverage

# Weekly: Refresh critical fixtures
LIVE=true mix test test/coverage/*/core_test.exs

# Release: Full live test suite
LIVE=true mix test --only coverage

# API Changes: Update specific provider
LIVE=true mix test --only anthropic --only coverage
```

## Models.dev Integration

### Metadata Synchronization

ReqLLM syncs with Models.dev for current model metadata:

```bash
# Sync all provider metadata
mix req_llm.sync_models

# Verify metadata consistency
mix req_llm.validate_metadata

# List models by capability
mix req_llm.models --capability tools
mix req_llm.models --provider anthropic
```

### Testing Against Metadata

Verify implementation matches Models.dev data:

```elixir
test "metadata matches implementation" do
  # Get Models.dev metadata
  {:ok, metadata} = ReqLLM.Provider.Registry.get_model_metadata(
    :anthropic, "claude-3-haiku-20240307"
  )
  
  # Test each advertised capability
  if metadata["tool_call"] do
    # Verify tool calling actually works
    use_fixture("metadata_verification/tools", [], fn ->
      # Tool calling test
    end)
  end
  
  if metadata["reasoning"] do
    # Verify reasoning/thinking tokens work
    use_fixture("metadata_verification/reasoning", [], fn ->
      # Reasoning test
    end)
  end
end
```

## Best Practices

### Test Organization

1. **Group by capability** - Organize tests around features, not just providers
2. **Use descriptive names** - Test names should explain what capability is tested
3. **Tag appropriately** - Use ExUnit tags for selective test execution
4. **Minimize dependencies** - Each test should be self-contained

### Fixture Management

1. **Keep fixtures small** - Use minimal token limits to reduce file size
2. **Use deterministic settings** - Low temperature for consistent responses  
3. **Version control fixtures** - Commit fixtures to track API changes over time
4. **Update regularly** - Refresh fixtures when provider APIs change

### Error Handling

1. **Test error conditions** - Verify proper error handling for invalid requests
2. **Check API limits** - Test behavior at rate limits and token limits
3. **Validate responses** - Ensure responses match expected format

```elixir
test "handles invalid model gracefully" do
  result = use_fixture(:anthropic, "invalid_model_error", fn ->
    ReqLLM.generate_text("anthropic:invalid-model", "Hello")
  end)
  
  {:error, error} = result
  assert %ReqLLM.Error.API{} = error
  assert error.status_code == 404
end
```

### Environment Management

Handle API keys and environment variables properly:

```elixir
# Skip tests if API key not available
setup do
  unless ReqLLM.get_key(:anthropic_api_key) do
    skip("ANTHROPIC_API_KEY not configured")
  end
  :ok
end
```

This capability testing approach ensures that ReqLLM providers work as advertised and helps maintain compatibility as APIs evolve.
