# Jido AI Req Plugin Investigation

## Executive Summary

Investigation of refactoring the Jido AI LLM client code to leverage Req plugins for easier LLM calls. The current architecture uses a custom middleware pipeline for cost management and token counting that could be streamlined using Req's native plugin system.

**Key Finding**: The existing architecture is well-suited for plugin conversion, with clear separation between business logic and HTTP concerns. A Req plugin would eliminate ~300-500 lines of custom middleware framework code while maintaining all current functionality.

## Current Architecture Analysis

### Core Components

The LLM client architecture consists of three main layers:

1. **Provider Layer**: Handles provider-specific implementations (OpenAI, Anthropic, Google, etc.)
2. **Middleware Pipeline**: Custom framework for request/response processing
3. **HTTP Transport**: Uses Req as low-level HTTP client

### Middleware Chain Structure

```elixir
# Current pipeline in Provider.Request.HTTP
middlewares = [TokenCounter, CostCalculator, Transport]
context = Context.new(:request, model, request_body, opts)
result_context = Middleware.run(middlewares, context, &switch_to_response_phase/1)
```

The middleware follows a **phase-based processing model**:
- **Request Phase**: Validation, input token counting, setup
- **Transport**: HTTP execution with Req
- **Response Phase**: Response processing, output token counting, cost calculation

### Data Flow Through Context

```elixir
# Context struct carries all request/response data
%Context{
  phase: :request | :response,
  model: %Model{},           # Model configuration with pricing
  body: map(),               # Request/response payload
  opts: keyword(),           # API keys, URLs, timeouts
  meta: %{                   # Token counts, costs, usage data
    request_tokens: 1000,
    response_tokens: 500,
    cost: %{input_cost: 0.003, output_cost: 0.0015, total_cost: 0.0045},
    usage: %{}               # Raw provider usage data
  },
  private: map()             # Internal middleware state
}
```

### Return Contract

The current API returns enhanced responses with metadata:

```elixir
{:ok, enhanced_response} = Provider.Request.HTTP.do_http_request(...)
enhanced_response.jido_meta # => %{usage: ..., cost: ..., model: ...}
```

## Token Counting Implementation

### Core Algorithm

**Simple Estimation Approach**:
- ~4 characters per token (fallback when exact counting unavailable)
- Message overhead: 4 tokens per message + 10 token base
- Handles different content types (text, structured objects, streams)

```elixir
# Key functions in TokenCounter
count_request_tokens/1   # Full request with overhead
count_response_tokens/1  # Extract from API response
count_stream_tokens/1    # Real-time streaming accumulation
```

### Provider Integration

**Multi-source Priority**:
1. **Exact usage** from API response `usage` field (preferred)
2. **Estimated tokens** from TokenCounter middleware
3. **Fallback estimation** re-parsing request/response bodies

## Cost Calculation System

### Pricing Model

**Per-Million Token Rates** stored in Model structs:
```elixir
%Model{
  cost: %{
    input: 1.5,    # $1.50 per million input tokens
    output: 6.0,   # $6.00 per million output tokens
    cache_read: 0.375,
    cache_write: 0.75
  }
}
```

**Calculation Formula**:
```elixir
input_cost = input_tokens * input_rate / 1_000_000
output_cost = output_tokens * output_rate / 1_000_000
total_cost = input_cost + output_cost
```

### Provider Usage Format Support

**Normalized Usage Extraction**:
- **OpenAI/Mistral**: `usage.prompt_tokens`, `usage.completion_tokens`
- **Google**: `usageMetadata.promptTokenCount`, `usageMetadata.candidatesTokenCount`
- **Anthropic**: `usage.input_tokens`, `usage.output_tokens`

## Streaming Architecture

### Current Implementation

**Three-Layer Streaming**:
1. **API Layer**: `stream_text/3`, `stream_object/4` - unified interface
2. **Provider Layer**: SSE parsing and provider-specific handling
3. **Transport Layer**: `Stream.resource/3` with custom HTTP handling

### Streaming Token Counting

**Real-time Accumulation**:
```elixir
# Per-chunk token counting during streaming
tokens = TokenCounter.count_stream_tokens(chunk_content)
total_tokens = accumulated_tokens + tokens
```

**Post-Stream Cost Calculation**:
- Input tokens counted upfront
- Output tokens accumulated during streaming  
- Cost calculated after stream completion

### Streaming Limitations

- Cost calculation happens after stream completion (not real-time)
- No per-chunk cost visibility during streaming
- Tight integration with custom middleware pipeline

## Req Plugin Design Proposal

### Plugin Architecture

```elixir
defmodule Req.Plugin.JidoLLM do
  @behaviour Req.Steps

  def attach(%Req.Request{} = req, opts) do
    model = Keyword.fetch!(opts, :model)
    
    req
    |> Req.Request.put_private(:jido_model, model)
    |> Req.Request.append_request_steps(jido_token_count: &count_request_tokens/1)
    |> Req.Request.append_response_steps(jido_cost: &calc_cost/1)
  end

  defp count_request_tokens(%{body: body} = req) do
    tokens = TokenCounter.count_request_tokens(body || %{})
    {:cont, Req.Request.put_private(req, :jido_request_tokens, tokens)}
  end

  defp calc_cost({req, resp}) do
    model = Req.Request.get_private(req, :jido_model)
    req_tokens = Req.Request.get_private(req, :jido_request_tokens, 0)
    
    # Extract usage from response or fallback to token counting
    usage = resp.body["usage"]
    resp_tokens = if usage do
      usage["completion_tokens"] || usage["candidatesTokenCount"] || usage["output_tokens"]
    else
      TokenCounter.count_response_tokens(resp.body)
    end

    # Calculate cost using existing logic
    cost = if usage do
      CostCalculator.calculate_cost_from_usage(model, usage)
    else
      CostCalculator.calculate_cost(model, req_tokens, resp_tokens)
    end

    # Attach metadata to response
    resp = Req.Response.put_private(resp, :jido, %{
      input_tokens: req_tokens,
      output_tokens: resp_tokens,
      cost: cost
    })

    {:cont, resp}
  end
end
```

### Plugin Usage

```elixir
# Simple usage - replaces entire middleware pipeline
resp = Req.new(base_url: "https://api.openai.com/v1")
  |> Req.plugin(Req.Plugin.JidoLLM, model: model)
  |> Req.post(json: request_body, auth: {:bearer, api_key})

# Access metadata
jido_meta = resp.private.jido
IO.inspect(jido_meta.cost)
```

## Migration Strategy

### Phase 1: Plugin Development

1. **Create `Req.Plugin.JidoLLM`** with request/response steps
2. **Preserve existing modules**: Keep TokenCounter and CostCalculator as-is
3. **Unit test** plugin with OpenAI and Anthropic providers
4. **Maintain compatibility** with current return format

### Phase 2: HTTP Client Migration

**Replace Provider.Request.HTTP**:
```elixir
# Before: Custom middleware pipeline
def do_http_request(_provider_module, model, request_body, opts) do
  context = Context.new(:request, model, request_body, opts)
  middlewares = [TokenCounter, CostCalculator, Transport]
  Middleware.run(middlewares, context, &switch_to_response_phase/1)
end

# After: Req plugin
def do_http_request(_provider_module, model, request_body, opts) do
  resp = Req.new(base_url: get_base_url(opts))
    |> Req.plugin(Req.Plugin.JidoLLM, model: model)  
    |> Req.post(json: request_body, auth: get_auth(opts))
  
  # Wrap response to maintain compatibility
  enhanced_response = Map.put(resp, :jido_meta, resp.private.jido)
  {:ok, enhanced_response}
end
```

### Phase 3: Middleware Deprecation

1. **Remove Context struct** where no longer needed
2. **Deprecate middleware modules** for non-streaming use cases
3. **Simplify provider implementations** - less glue code needed

### Phase 4: Streaming Integration

**Challenge**: Req plugins work at request/response level, streaming needs per-chunk processing

**Solution Options**:
1. **Keep current streaming** implementation unchanged (hybrid approach)
2. **Custom `:into` handler** that integrates with plugin metadata
3. **Wait for Req streaming plugin support** (future enhancement)

## Benefits Analysis

### Code Reduction

- **~300-500 lines removed**: Context, middleware framework, pipeline logic
- **Simplified providers**: Less boilerplate, direct Req usage
- **Better testability**: Standard Req plugin testing patterns

### Architecture Improvements

- **Single interception mechanism**: Req plugins instead of custom middleware
- **Ecosystem compatibility**: Leverage existing Req plugin ecosystem
- **Future-proof**: Req handles retries, metrics, telemetry, compression
- **Cleaner interfaces**: Remove Context struct abstraction layer

### Feature Preservation

- **All current functionality maintained**: Token counting, cost calculation, usage extraction
- **Provider compatibility**: All existing providers work unchanged
- **Return format**: Existing `jido_meta` structure preserved
- **Error handling**: Structured errors maintained

## Challenges & Limitations

### Streaming Considerations

**Current Req Limitations**:
- No per-chunk hooks in plugin system
- Streaming state management complex
- Real-time cost tracking challenging

**Recommended Approach**:
- Keep existing streaming implementation
- Apply plugin only to non-streaming requests
- Future migration when Req adds streaming plugin support

### Backward Compatibility

**Preservation Requirements**:
- Maintain `enhanced_response.jido_meta` format
- Keep provider API contracts unchanged
- Support all current provider formats
- Preserve error handling patterns

### Migration Risk

**Low Risk Assessment**:
- Core logic (TokenCounter, CostCalculator) unchanged
- Provider interfaces remain stable  
- Gradual migration possible (non-streaming first)
- Easy rollback path available

## Recommendations

### Immediate Actions

1. **Start with non-streaming requests**: Lower risk, immediate benefits
2. **Preserve existing modules**: TokenCounter and CostCalculator are solid
3. **Maintain compatibility**: Wrap plugin responses to match current format
4. **Test thoroughly**: Unit test plugin with all provider formats

### Long-term Strategy

1. **Hybrid approach**: Plugin for simple requests, middleware for streaming
2. **Monitor Req development**: Watch for streaming plugin support
3. **Gradual cleanup**: Remove middleware framework as plugin matures
4. **Ecosystem leverage**: Add retries, metrics, other Req plugins over time

### Success Metrics

- **Code reduction**: 20-30% reduction in HTTP client code
- **Maintainability**: Simpler provider implementations
- **Feature parity**: All current functionality preserved
- **Performance**: No degradation in request/response times

## Conclusion

The Jido AI LLM architecture is well-structured for Req plugin migration. The clear separation between business logic (TokenCounter, CostCalculator) and transport concerns makes this refactoring straightforward.

**Key Success Factors**:
- Existing Req usage provides solid foundation
- Isolated token/cost logic can be reused as-is
- Gradual migration path reduces risk
- Plugin approach aligns with Req ecosystem patterns

The proposed Req plugin would eliminate significant custom framework code while maintaining all current functionality and enabling future extensibility through the Req plugin ecosystem.
