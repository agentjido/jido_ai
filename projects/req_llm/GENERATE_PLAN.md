# ReqLLM Provider prepare_request/4 Implementation Plan

## Overview

Extend the ReqLLM provider system to add a higher-level `prepare_request/4` method implemented on each provider. This method will encapsulate Req request creation, endpoint path configuration, and provider attachment using idiomatic Elixir operation-first dispatch, simplifying the top-level API and making provider-specific differences more manageable.

## Current Architecture Issues

Currently, `ReqLLM.Generation.generate_text/3` follows this pattern:

```elixir
# Create generic request
request = Req.new(method: :post, receive_timeout: 30_000)

# Let provider configure it
configured_request <- provider_module.attach(request, model, request_options)

# Make request
{:ok, response} <- Req.request(configured_request)
```

**Problems:**
1. **Missing endpoint paths**: Providers need different API endpoints (`/messages` for Anthropic, `/chat/completions` for OpenAI)
2. **Generic request creation**: Top-level API creates generic requests without provider-specific context
3. **Scattered provider logic**: Endpoint paths and provider-specific defaults are not centralized
4. **No unified approach for different operations**: Chat, embeddings, moderation would need separate methods

## Proposed Solution: Provider-Level prepare_request/4

Add a new `prepare_request/4` callback to the `ReqLLM.Provider` behavior that:
- Takes operation type (`:chat`, `:embed`, `:moderate`) as first argument (idiomatic Elixir dispatch)
- Takes model, input (context/text/etc), and options
- Creates provider-specific Req request with correct endpoint for the operation
- Calls existing `attach/3` method internally
- Returns fully configured request ready for execution

## Implementation Plan

### 1. Update Provider Behavior

Add new callback to `lib/req_llm/provider.ex`:

```elixir
@typedoc "High-level operation recognised by ReqLLM"
@type operation :: :chat | :embed | :moderate | atom()

@doc """
Prepares a fully configured Req request for the specified operation.

This high-level method encapsulates endpoint path selection, request creation,
and provider configuration using idiomatic Elixir operation-first dispatch.
It builds on top of attach/3 but handles provider-specific routing and defaults.

## Parameters

  * `operation` - The operation type (:chat, :embed, :moderate, etc.)
  * `model` - The ReqLLM.Model struct or model specification  
  * `input` - Operation-specific input (Context for :chat, text/list for :embed)
  * `opts` - Provider options (temperature, max_tokens, etc.)

## Returns

  * `Req.Request.t()` - Fully configured request ready for Req.request/1

## Examples

      # Chat completion
      req = provider.prepare_request(:chat, model, context, opts)
      
      # Text embedding
      req = provider.prepare_request(:embed, model, ["hello", "world"], opts)
      
      # Single text embedding  
      req = provider.prepare_request(:embed, model, "hello", opts)

"""
@callback prepare_request(
            operation(),
            ReqLLM.Model.t() | term(),
            term(),
            keyword()
          ) :: Req.Request.t()

@optional_callbacks [extract_usage: 2, default_env_key: 0]
```

### 2. Implement prepare_request/4 in Anthropic Provider

Update `lib/req_llm/providers/anthropic.ex`:

```elixir
@impl ReqLLM.Provider
def prepare_request(:chat, model_input, %ReqLLM.Context{} = context, opts \\ []) do
  model = ReqLLM.Model.from!(model_input)
  
  # Extract HTTP-specific options
  http_opts = Keyword.get(opts, :req_http_options, [])
  
  # Create request with Anthropic-specific chat endpoint and defaults
  base_request = Req.new([
    url: "/messages", 
    method: :post,
    receive_timeout: 30_000
  ] ++ http_opts)
  
  # Add context to options and configure via existing attach/3
  request_options = Keyword.put(opts, :context, context)
  attach(base_request, model, request_options)
end

# Anthropic doesn't support embeddings, so we return error for unsupported operations
def prepare_request(operation, _model, _input, _opts) do
  {:error, ReqLLM.Error.Invalid.Parameter.exception(
    parameter: "operation: #{inspect(operation)} not supported by Anthropic provider"
  )}
end
```

### 2b. Example OpenAI Provider Implementation

For comparison, OpenAI would support multiple operations:

```elixir
@impl ReqLLM.Provider
def prepare_request(:chat, model_input, %ReqLLM.Context{} = context, opts \\ []) do
  model = ReqLLM.Model.from!(model_input)
  http_opts = Keyword.get(opts, :req_http_options, [])
  
  Req.new([url: "/chat/completions", method: :post, receive_timeout: 30_000] ++ http_opts)
  |> attach(model, Keyword.put(opts, :context, context))
end

def prepare_request(:embed, model_input, input, opts) when is_binary(input) or is_list(input) do
  model = ReqLLM.Model.from!(model_input)
  http_opts = Keyword.get(opts, :req_http_options, [])
  
  Req.new([url: "/embeddings", method: :post, receive_timeout: 30_000] ++ http_opts)
  |> attach(model, Keyword.put(opts, :input, input))
end

def prepare_request(operation, _model, _input, _opts) do
  {:error, ReqLLM.Error.Invalid.Parameter.exception(
    parameter: "operation: #{inspect(operation)} not supported by OpenAI provider"
  )}
end
```

### 3. Refactor ReqLLM.Generation

Update `generate_text/3` and `stream_text/3` to use the new provider method:

**Before:**
```elixir
request = Req.new(method: :post, receive_timeout: 30_000)
configured_request <- provider_module.attach(request, model, request_options)
```

**After:**
```elixir
{:ok, configured_request} <- provider_module.prepare_request(:chat, model, context, validated_opts)
```

**Full refactored flow:**
```elixir
def generate_text(model_spec, messages, opts \\ []) do
  with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
       {:ok, model} <- Model.from(model_spec),
       {:ok, provider_module} <- ReqLLM.provider(model.provider),
       context <- build_context(messages, validated_opts),
       provider_opts <- prepare_provider_options(model, validated_opts),
       {:ok, configured_request} <- provider_module.prepare_request(:chat, model, context, provider_opts),
       {:ok, %Req.Response{body: raw_response_body}} <- Req.request(configured_request),
       {:ok, response} <- Response.decode_response(raw_response_body, model) do
    {:ok, response}
  end
end
```

**Critical Fix - Response Decoding:**
The `Req.request()` call returns a parsed response body, but our `prepare_request/4` method configures the provider's `decode_response/1` step which already processes it. We need to ensure we're not double-decoding the response.

### 4. Provider-Specific Endpoint Mapping

Different providers will implement different operations and endpoints:

| Provider | :chat | :embed | :moderate |
|----------|-------|--------|-----------|
| Anthropic | `/messages` | ❌ (raises) | ❌ (raises) |
| OpenAI | `/chat/completions` | `/embeddings` | `/moderations` |
| Google | `/generateContent` | ❌ (raises) | ❌ (raises) |

This approach allows each provider to:
- Support only the operations they implement
- Use their specific endpoint paths
- Raise clear errors for unsupported operations

### 5. Future Extensibility for New Operations

Adding new operations is as simple as:
1. Adding the operation atom to the `@type operation` definition
2. Implementing the operation in providers that support it
3. Creating a new top-level module (e.g., `ReqLLM.Moderation`) that calls `prepare_request(:moderate, ...)`

**Example new operation:**
```elixir
# In ReqLLM.Moderation
def moderate_text(model_spec, text, opts \\ []) do
  with {:ok, model} <- Model.from(model_spec),
       {:ok, provider_module} <- ReqLLM.provider(model.provider),
       configured_request <- provider_module.prepare_request(:moderate, model, text, opts),
       {:ok, %Req.Response{body: body}} <- Req.request(configured_request) do
    {:ok, decode_moderation_response(body)}
  end
end

# In providers that support it
def prepare_request(:moderate, model_input, text, opts) when is_binary(text) do
  # provider-specific implementation
end
```

## Implementation Steps

### Phase 1: Core Infrastructure
1. **Add prepare_request/4 callback to Provider behavior**
2. **Implement prepare_request/4 in Anthropic provider with :chat operation** 
3. **Update ReqLLM.Generation to use prepare_request(:chat, ...)**
4. **Remove obsolete request creation code**

### Phase 2: Testing & Validation
5. **Update existing tests to verify operation dispatch and endpoint paths**
6. **Add unit tests for prepare_request/4 method**
7. **Test error cases for unsupported operations**
8. **Test demo scripts to ensure functionality**
9. **Run quality checks (formatter, dialyzer, credo)**

### Phase 3: Future Operations (Optional)
10. **Add ReqLLM.Embedding module using prepare_request(:embed, ...)**
11. **Add prepare_request(:embed, ...) to providers that support it**
12. **Consider ReqLLM.Moderation for content moderation APIs**

### Phase 4: Documentation & Cleanup
13. **Update provider behavior documentation**
14. **Add operation dispatch examples to provider guides**
15. **Update README with new architecture patterns**
16. **Remove obsolete code and comments**

## Benefits

1. **Idiomatic Elixir**: Operation-first dispatch using pattern matching
2. **Cleaner Architecture**: Provider-specific logic centralized in provider modules
3. **Easier Provider Development**: Clear pattern for implementing new providers and operations
4. **Better Endpoint Management**: No more hardcoded paths in generic code
5. **Explicit Operation Support**: Providers clearly define what operations they support
6. **Future-Proof**: Easy to add new operations without changing the behavior interface

## Design Considerations

### Error Handling
- `prepare_request/4` returns `{:ok, request}` or `{:error, exception}` tuples
- Unsupported operations return Splode error with clear message
- HTTP errors still handled at request execution level  
- Provider-specific validation in `prepare_request/4` before request creation

### Operation Dispatch Pattern
- Use pattern matching on the first argument for operation dispatch
- Guard clauses can validate input types per operation (e.g., `when is_binary(text)`)
- Fallback clause returns `{:error, exception}` for unsupported operations
- Clear error messages help developers understand provider capabilities

### Response Processing Fix
- `prepare_request/4` configures the provider's decode_response step via `attach/3`
- `Req.request()` returns already-processed response body from decode_response step
- No additional decoding needed in ReqLLM.Generation - response is ready to use

### Testing Strategy
- Unit tests verify correct endpoint paths per provider and operation
- Unit tests verify proper error handling for unsupported operations
- Integration tests ensure full request flow works for each operation
- Mock HTTP responses to test error conditions

### Performance Impact
- Minimal overhead (pattern matching is very fast in Elixir)
- Same underlying Req request/response cycle
- No additional allocations or processing

## Implementation Example

**Complete Anthropic Provider Pattern:**
```elixir
defmodule ReqLLM.Providers.Anthropic do
  @behaviour ReqLLM.Provider
  
  # Chat completion - supported
  @impl ReqLLM.Provider 
  def prepare_request(:chat, model_input, %ReqLLM.Context{} = context, opts) do
    with {:ok, model} <- ReqLLM.Model.from(model_input) do
      http_opts = Keyword.get(opts, :req_http_options, [])
      
      request = Req.new([url: "/messages", method: :post, receive_timeout: 30_000] ++ http_opts)
                |> attach(model, Keyword.put(opts, :context, context))
      
      {:ok, request}
    end
  end
  
  # Unsupported operations - clear error message
  def prepare_request(operation, _model, _input, _opts) do
    {:error, ReqLLM.Error.Invalid.Parameter.exception(
      parameter: "operation: #{inspect(operation)} not supported by Anthropic provider. Supported operations: [:chat]"
    )}
  end
end
```
