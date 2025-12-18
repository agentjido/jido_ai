# Breaking Changes

This guide documents breaking changes across versions to help you migrate your code safely.

## Version 2.0.0 (ReqLLM Integration)

### Overview

Version 2.0.0 represents a major architectural shift, migrating from provider-specific implementations to a unified ReqLLM-based system. While we've maintained backward compatibility for most public APIs, some breaking changes were necessary.

### Summary of Changes

| Change | Impact | Migration Effort |
|--------|--------|------------------|
| Internal implementation (ReqLLM) | None (transparent) | ✅ No changes needed |
| Unified API (`Jido.AI.chat/3`) | New feature | ✅ Optional upgrade |
| Provider format (`provider:model`) | Medium | ⚠️ Update model strings |
| Keyring system | Low | ℹ️ Update key management |
| Response format | Low | ℹ️ Minor field changes |
| Module deprecations | Low | ⚠️ Update imports |

### Breaking Changes

#### 1. Provider:Model Format Required

**What Changed:**
The unified API requires `provider:model` format instead of just model names.

**Before:**
```elixir
# This only worked with specific action modules
Jido.AI.Actions.OpenaiEx.run(%{model: "gpt-4", ...})
```

**After:**
```elixir
# Unified API requires provider prefix
Jido.AI.chat("openai:gpt-4", prompt)  # ✅ Correct
Jido.AI.chat("gpt-4", prompt)         # ❌ Error: missing provider
```

**Migration:**
```elixir
# Add provider prefix to all model references
"gpt-4" -> "openai:gpt-4"
"claude-3-sonnet" -> "anthropic:claude-3-sonnet"
"llama-3.1-70b" -> "groq:llama-3.1-70b"
```

**Impact:** Medium - Required for new unified API, but legacy action modules still work.

#### 2. Response Structure Changes

**What Changed:**
Response format has been normalized across all providers.

**Before:**
```elixir
# Provider-specific response formats
{:ok, %{
  "choices" => [%{"message" => %{"content" => "..."}}],  # OpenAI format
  "usage" => %{"total_tokens" => 123}
}}
```

**After:**
```elixir
# Unified response structure
{:ok, %Jido.AI.Response{
  content: "...",
  provider: :openai,
  model: "gpt-4",
  usage: %{
    prompt_tokens: 10,
    completion_tokens: 20,
    total_tokens: 30
  },
  finish_reason: :stop,
  tool_calls: nil,
  raw: %{...}  # Original provider response
}}
```

**Migration:**
```elixir
# Update response access patterns
# Before
content = get_in(response, ["choices", 0, "message", "content"])
tokens = get_in(response, ["usage", "total_tokens"])

# After
content = response.content
tokens = response.usage.total_tokens

# If you need original format
original = response.raw
```

**Impact:** Low - Response struct provides easier access, raw format still available.

#### 3. Error Response Format

**What Changed:**
Error responses are now normalized with a consistent structure.

**Before:**
```elixir
# Provider-specific error formats
{:error, %HTTPoison.Error{reason: :timeout}}
{:error, %{"error" => %{"message" => "Rate limit"}}}
```

**After:**
```elixir
# Normalized error format
{:error, %Jido.AI.Error{
  type: :timeout,
  message: "Request timed out",
  provider: :openai,
  status: nil,
  details: %{...}
}}

{:error, %Jido.AI.Error{
  type: :rate_limit,
  message: "Rate limit exceeded",
  provider: :openai,
  status: 429,
  details: %{...}
}}
```

**Migration:**
```elixir
# Update error handling
case Jido.AI.chat(provider, prompt) do
  {:ok, response} -> handle_success(response)

  # Before
  {:error, %HTTPoison.Error{reason: :timeout}} ->
    handle_timeout()
  {:error, %{"error" => %{"message" => msg}}} ->
    handle_api_error(msg)

  # After
  {:error, %{type: :timeout}} ->
    handle_timeout()
  {:error, %{type: :rate_limit}} ->
    handle_rate_limit()
  {:error, %{type: :api_error, message: msg}} ->
    handle_api_error(msg)
end
```

**Impact:** Medium - Consistent error handling is easier but requires code updates.

#### 4. API Key Management

**What Changed:**
Unified Keyring system replaces per-provider key passing.

**Before:**
```elixir
# Pass API key with every call
OpenaiEx.run(params, api_key: System.get_env("OPENAI_API_KEY"))
```

**After:**
```elixir
# Set key once via Keyring
Jido.AI.Keyring.set(:openai, System.get_env("OPENAI_API_KEY"))

# Or use environment variables (automatic)
# export OPENAI_API_KEY="sk-..."

# No key needed in calls
Jido.AI.chat("openai:gpt-4", prompt)
```

**Migration:**
```elixir
# Option 1: Environment variables (recommended)
# Set these in your deployment configuration
export OPENAI_API_KEY="sk-..."
export ANTHROPIC_API_KEY="sk-..."

# Option 2: Programmatic setup
defmodule MyApp.Application do
  def start(_type, _args) do
    # Set keys on application start
    :ok = Jido.AI.Keyring.set(:openai, fetch_openai_key())
    :ok = Jido.AI.Keyring.set(:anthropic, fetch_anthropic_key())

    # ... rest of application setup
  end
end
```

**Impact:** Low - Cleaner API, but requires one-time setup change.

#### 5. Streaming Response Format

**What Changed:**
Streaming responses now emit structured chunks instead of raw provider data.

**Before:**
```elixir
# Provider-specific chunk format
stream
|> Stream.each(fn chunk ->
  # OpenAI format
  content = get_in(chunk, ["choices", 0, "delta", "content"])
  IO.write(content)
end)
```

**After:**
```elixir
# Unified chunk format
stream
|> Stream.each(fn %Jido.AI.StreamChunk{} = chunk ->
  IO.write(chunk.content)
end)
```

**Migration:**
```elixir
# Update streaming handlers
# Before
defp handle_stream_chunk(chunk) do
  case get_in(chunk, ["choices", 0, "delta", "content"]) do
    nil -> :skip
    content -> {:ok, content}
  end
end

# After
defp handle_stream_chunk(%Jido.AI.StreamChunk{content: content}) do
  {:ok, content}
end
```

**Impact:** Low - Simpler and more consistent across providers.

### Deprecations

#### 1. Direct Provider Module Usage (Soft Deprecation)

**Status:** Deprecated but still functional

**What Changed:**
Direct usage of provider modules is discouraged in favor of unified API.

```elixir
# Discouraged (still works)
alias Jido.AI.Actions.OpenaiEx
OpenaiEx.run(params, api_key: key)

# Recommended
Jido.AI.chat("openai:gpt-4", prompt)
```

**Timeline:**
- v2.0.0: Soft deprecation (warnings in logs)
- v2.1.0: Documentation removal
- v3.0.0: Hard deprecation (compile warnings)
- v4.0.0: Removal

**Migration:**
See [Migration from Legacy Providers](from-legacy-providers.md) guide.

#### 2. Manual HTTP Client Configuration

**Status:** Deprecated

**What Changed:**
Manual HTTP client configuration is replaced by ReqLLM's optimized defaults.

```elixir
# Deprecated
config :jido_ai,
  http_client: MyApp.CustomHTTPClient,
  timeout: 30_000

# Not needed - ReqLLM handles this
```

**Migration:**
```elixir
# Use per-request options instead
Jido.AI.chat(model, prompt, timeout: 30_000)
```

**Impact:** Low - Most users didn't customize this.

### New Features (Non-Breaking)

These features are available without breaking existing code:

#### 1. Model Registry and Discovery

```elixir
# Discover available models dynamically
{:ok, models} = Jido.AI.Model.Registry.discover_models(provider: :openai)

# Search for models by capability
{:ok, models} = Jido.AI.Model.Registry.search(
  capability: :vision,
  provider: :openai
)
```

#### 2. Capability Detection

```elixir
# Check model capabilities before use
alias Jido.AI.Features

model = Jido.AI.Model.from("openai:gpt-4")

if Features.supports?(model, :vision) do
  # Use vision features
  Jido.AI.chat(model, prompt, images: [image])
end
```

#### 3. Provider Fallback

```elixir
# Built-in fallback support
providers = ["groq:llama-3.1-70b", "openai:gpt-4", "anthropic:claude-3-sonnet"]

result = Enum.reduce_while(providers, {:error, :all_failed}, fn provider, _acc ->
  case Jido.AI.chat(provider, prompt) do
    {:ok, response} -> {:halt, {:ok, response}}
    {:error, _} -> {:cont, {:error, :all_failed}}
  end
end)
```

## Migration Checklist

### Phase 1: Assessment (1-2 hours)

- [ ] Review current provider usage (OpenAI, Anthropic, etc.)
- [ ] Identify all locations where AI calls are made
- [ ] Check if using provider-specific features
- [ ] Review API key management approach
- [ ] Assess error handling patterns

### Phase 2: Preparation (2-4 hours)

- [ ] Set up Keyring for all providers
- [ ] Test unified API with current use cases
- [ ] Update error handling to new format
- [ ] Review response structure changes
- [ ] Test streaming if used

### Phase 3: Migration (varies by codebase)

- [ ] Migrate simple chat completions first
- [ ] Update response access patterns
- [ ] Migrate streaming implementations
- [ ] Update error handling
- [ ] Migrate tool/function calling
- [ ] Update embeddings generation

### Phase 4: Testing (2-4 hours)

- [ ] Test all AI interactions
- [ ] Verify error handling works
- [ ] Test with actual API calls
- [ ] Check rate limiting behavior
- [ ] Verify logging and monitoring

### Phase 5: Deployment

- [ ] Deploy to staging
- [ ] Monitor for issues
- [ ] Deploy to production
- [ ] Monitor production metrics

## Version History

### v2.0.0 (Current) - ReqLLM Integration

**Release Date:** 2024-Q4

**Major Changes:**
- Unified ReqLLM integration (57+ providers)
- New `Jido.AI.chat/3` API
- Keyring credential management
- Normalized response format
- Enhanced error handling

**Migration Effort:** Low to Medium (2-8 hours depending on codebase size)

### v1.x.x (Legacy)

**Sunset Date:** v1.x will be maintained until v3.0.0

**Support:**
- Security fixes: Until v3.0.0
- Bug fixes: Until v2.2.0
- New features: None

## Getting Help

### Common Migration Issues

#### Issue: Model Not Found

```elixir
# Error
{:error, %{type: :model_not_found, message: "Model 'gpt-4' not found"}}

# Solution: Add provider prefix
Jido.AI.chat("openai:gpt-4", prompt)  # ✅
```

#### Issue: API Key Not Found

```elixir
# Error
{:error, %{type: :authentication_error, message: "API key not configured"}}

# Solution: Set up Keyring
Jido.AI.Keyring.set(:openai, "sk-...")
# Or: export OPENAI_API_KEY="sk-..."
```

#### Issue: Response Format Changed

```elixir
# Error: Response doesn't have expected fields

# Solution: Update to new response structure
# Before
content = response["choices"][0]["message"]["content"]

# After
content = response.content
```

### Resources

- [Migration Guide](from-legacy-providers.md) - Detailed migration scenarios
- [ReqLLM Integration](reqllm-integration.md) - Architecture deep-dive
- [Provider Matrix](../providers/provider-matrix.md) - All provider details
- [GitHub Issues](https://github.com/agentjido/jido_ai/issues) - Report problems

### Support Channels

- **GitHub Discussions:** General questions and community support
- **GitHub Issues:** Bug reports and feature requests
- **Documentation:** Complete guides and examples

## Future Breaking Changes (Planned)

### v3.0.0 (Planned for 2025-Q2)

**Potential Changes:**
- Remove deprecated provider modules
- Update minimum Elixir version to 1.16
- Consolidate configuration format
- Enhanced type specifications

**Migration Timeline:**
- v2.1.0: Deprecation warnings added
- v2.2.0: Migration guide published
- v3.0.0: Breaking changes implemented

### Staying Informed

Subscribe to release notifications:
- Watch the GitHub repository
- Follow release notes
- Review changelog with each update

## Summary

Version 2.0.0 represents a significant improvement in capability (4-5 providers → 57+ providers) while maintaining a smooth migration path. Most changes are additive, and the breaking changes are minimal and well-documented.

**Key Takeaways:**
- ✅ Public API names unchanged (backward compatible)
- ✅ New unified API is optional (gradual migration)
- ⚠️ Response format normalized (minor updates needed)
- ⚠️ Error handling improved (update error patterns)
- ✅ Keyring simplifies credential management
- ✅ 57+ providers available immediately

**Recommended Migration Path:**
1. Start with new code using `Jido.AI.chat/3`
2. Gradually migrate existing code
3. Leverage new providers and features
4. Enjoy unified interface across all providers
