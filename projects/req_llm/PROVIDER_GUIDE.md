# ReqLLM Provider Implementation Guide

*Based on the refined Anthropic provider architecture - the "gold standard" approach*

## Table of Contents

1. [Overview & Guiding Principles](#1-overview--guiding-principles)
2. [Anatomy of `attach/3` – The 4-Step Pattern](#2-anatomy-of-attach3--the-4-step-pattern)
3. [API Key Handling & JidoKeys Best Practices](#3-api-key-handling--jidokeys-best-practices)
4. [Provider Option System – Declaration, Merge & Validation](#4-provider-option-system--declaration-merge--validation)
5. [Error Handling with Splode – Patterns & Guidelines](#5-error-handling-with-splode--patterns--guidelines)
6. [Step Naming, Ordering & Pipeline Design](#6-step-naming-ordering--pipeline-design)
7. [Base URL Handling & Multi-Environment Configuration](#7-base-url-handling--multi-environment-configuration)
8. [Request/Response Step Implementation Patterns](#8-requestresponse-step-implementation-patterns)
9. [Architectural Checklist for New Providers](#9-architectural-checklist-for-new-providers)

---

## 1. Overview & Guiding Principles

Each ReqLLM provider is implemented as a **native Req plugin** generated with the `ReqLLM.Provider.DSL`. This approach emphasizes simplicity, directness, and composability.

### Core Architecture Goals

1. **Stateless & Functional** – No module attributes mutated after compile time
2. **Single Responsibility** – `attach/3` only *prepares* the request; network I/O handled by Req
3. **Consistent Option Surface** – Generation options declared once, validated early
4. **Deterministic Error Semantics** – Only structured Splode errors, never bare exceptions
5. **Readable Step Names** – Self-documenting pipeline with clear verb-object naming

### Required Public Callbacks

The primary callback that providers must implement is:

- `attach(request, model_input, opts \\ [])` – Configure the request pipeline

*Note: `parse_response` and `parse_stream` callbacks are still being iterated upon and may not be required in the final architecture.*

---

## 2. Anatomy of `attach/3` – The 4-Step Pattern

The Anthropic provider's `attach/3` method represents the canonical implementation pattern. All providers should follow this exact structure with numbered comment blocks:

```elixir
@impl ReqLLM.Provider
def attach(%Req.Request{} = request, model_input, user_opts \\ []) do
  %ReqLLM.Model{} = model = ReqLLM.Model.from!(model_input)

  unless model.provider == provider_id() do
    raise ReqLLM.Error.Invalid.Provider.exception(provider: model.provider)
  end

  unless ReqLLM.Provider.Registry.model_exists?("#{provider_id()}:#{model.model}") do
    raise ReqLLM.Error.Invalid.Parameter.exception(parameter: "model: #{model.model}")
  end

  api_key = get_env_var_name() |> JidoKeys.get()
  unless api_key && api_key != "" do
    raise ReqLLM.Error.Invalid.Parameter.exception(
      parameter: "api_key (set via JidoKeys.put(#{inspect(api_key_env)}, key))"
    )
  end

  opts = prepare_options(model, user_opts)
  base_url = Keyword.get(user_opts, :base_url, default_base_url())

  request
  |> Req.Request.register_options(__MODULE__.supported_provider_options())
  |> Req.Request.merge_options(opts ++ [base_url: base_url])
  |> Req.Request.put_header("x-api-key", api_key)
  |> Req.Request.put_header("anthropic-version", user_opts[:api_version] || @default_api_version)
  |> Req.Request.append_request_steps(encode_body: &__MODULE__.body_step/1)
  |> Req.Request.append_response_steps(decode_response: &__MODULE__.parse_step/1)
end
```

### Why This Pattern Matters

- **Early Validation** – Bad models, missing keys, and invalid options fail *before* any HTTP call
- **Declarative Pipeline** – The Req pipeline remains composable and introspectable
- **Centralized Configuration** – Headers and base URL are set once, no repetition elsewhere
- **Consistent Structure** – Code reviews become trivial across providers

---

## 3. API Key Handling & JidoKeys Best Practices

### The Metadata-Driven Approach

1. **Provider Metadata** declares canonical environment variables:
   ```json
   {
     "provider": {
       "env": ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"]
     }
   }
   ```

2. **Dynamic Key Resolution** via `get_env_var_name/0`:
   ```elixir
   defp get_env_var_name do
     with {:ok, metadata} <- ReqLLM.Provider.Registry.get_provider_metadata(:anthropic),
          [env_var | _] <-
            get_in(metadata, ["provider", "env"]) || get_in(metadata, [:provider, :env]) do
       env_var
     else
       _ -> "ANTHROPIC_API_KEY"  # Fallback
     end
   end
   ```

3. **JidoKeys Integration** for runtime flexibility:
   ```elixir
   api_key_env = get_env_var_name()
   api_key = JidoKeys.get(api_key_env)
   ```

### Key Validation Guidelines

- **Always validate** that the key exists and is non-empty
- **Never store** keys in module attributes or persistent state
- **Never use `String.to_atom`** - JidoKeys.get accepts environment variable names directly
- **Provide clear error messages** showing the exact JidoKeys command to set the key
- **Support metadata-driven** key names for flexibility across environments

---

## 4. Provider Option System – Declaration, Merge & Validation

### DSL Declaration

Providers declare their supported options and defaults via the DSL:

```elixir
use ReqLLM.Provider.DSL,
  id: :anthropic,
  base_url: "https://api.anthropic.com/v1",
  provider_options: ~a[temperature max_tokens top_p top_k stream? stop_sequences system],
  provider_defaults: [temperature: 0.7, max_tokens: 1024, stream?: false]
```

### Option Processing Pattern

The `prepare_options/2` function follows this exact pattern:

```elixir
defp prepare_options(model, user_opts) do
  sup_keys = __MODULE__.supported_provider_options()
  defaults = __MODULE__.default_provider_opts()

  # Extract generation options from user input
  {gen_opts, rest} = ReqLLM.Provider.Options.extract_provider_options(user_opts)

  # Early validation for unknown keys
  unknown = Keyword.keys(gen_opts) -- sup_keys
  if unknown != [] do
    raise ReqLLM.Error.Invalid.Parameter.exception(
      parameter: "unsupported options: #{inspect(unknown)}"
    )
  end

  # Filter to supported keys and validate
  gen_opts = ReqLLM.Provider.Options.filter_generation_options(gen_opts, sup_keys)

  case ReqLLM.Provider.Options.validate_generation_options(gen_opts, only: sup_keys) do
    {:ok, _} -> :ok
    {:error, err} ->
      raise ReqLLM.Error.Validation.Error.exception(
        tag: :invalid_generation_options,
        reason: Exception.message(err)
      )
  end

  # Build provider defaults and merge
  provider_defaults = [
    provider: [
      id: provider_id(),
      base_url: default_base_url(),
      env: [get_env_var_name()],
      timeout: 30_000
    ],
    generation: Keyword.merge([model: model.model], defaults),
    capabilities: [id: model.model]
  ]

  merged = ReqLLM.Provider.Options.merge_with_defaults(rest, provider_defaults)
           |> Keyword.update!(:generation, &Keyword.merge(&1, gen_opts))

  # Final validation
  case ReqLLM.Provider.Options.complete_options_schema()
       |> NimbleOptions.validate(merged) do
    {:ok, valid} -> flatten_options(valid)
    {:error, err} ->
      raise ReqLLM.Error.Validation.Error.exception(
        tag: :invalid_options,
        reason: Exception.message(err)
      )
  end
end
```

### Guidelines for New Providers

- **Keep validation inside** `attach/3`, never in request steps
- **Provide reasonable defaults** so simple calls work with zero options
- **Expose all generation options** even if your API ignores some (forward compatibility)
- **Use the `~a` sigil** for clean option lists: `~a[temperature max_tokens top_p]`

---

## 5. Error Handling with Splode – Patterns & Guidelines

ReqLLM uses structured errors via Splode for consistent, serializable error handling.

### Common Error Patterns

```elixir
# Invalid parameters
raise ReqLLM.Error.Invalid.Parameter.exception(parameter: "max_tokens must be > 0")

# Provider mismatches
raise ReqLLM.Error.Invalid.Provider.exception(provider: actual_provider)

# API failures
raise ReqLLM.Error.API.Response.exception(
  reason: "Provider API error",
  status: status,
  response_body: resp.body
)

# Validation failures
raise ReqLLM.Error.Validation.Error.exception(
  tag: :invalid_options,
  reason: Exception.message(err)
)
```

### Error Handling Rules

1. **Never raise `ArgumentError`, `RuntimeError`, or other generic exceptions**
2. **Use the most specific error type** available (`Invalid.*`, `API.*`, `Validation.*`)
3. **Always provide context fields** – they're automatically included in error messages
4. **Wrap lower-level exceptions** when appropriate: `raise ..., cause: original_error`

---

## 6. Step Naming, Ordering & Pipeline Design

### Naming Convention

Use clear **verb-object** naming without provider prefixes for simplicity:

- **Request steps**: `encode_body`
- **Response steps**: `decode_response`
- **Stream handlers**: Use callback `parse_stream/2` plus helpers like `parse_sse_events/1`

### Example

```elixir
|> Req.Request.append_request_steps(encode_body: &__MODULE__.body_step/1)
|> Req.Request.append_response_steps(decode_response: &__MODULE__.parse_step/1)
```

### Pipeline Flow

The request pipeline should follow this order:

```
User Input → attach/3 → Headers → encode → HTTP → decode → parse_response/parse_stream
```

### Benefits of This Naming

- **Self-documenting** – immediately clear what each step does
- **Simple** – no unnecessary prefixes cluttering the pipeline
- **Symmetrical** – encode/decode pairs make pipeline flow obvious
- **Debuggable** – step names appear clearly in Req pipeline introspection

---

## 7. Base URL Handling & Multi-Environment Configuration

### Pattern

```elixir
# In attach/3
base_url = Keyword.get(user_opts, :base_url, default_base_url())

# Apply to request (combine with other options)
|> Req.Request.merge_options(opts ++ [base_url: base_url])
```

### Configuration Flexibility

This enables runtime base URL override:

```elixir
# Production
ReqLLM.generate_text(model, "hello")

# Development/testing
ReqLLM.generate_text(model, "hello", base_url: "http://localhost:8080")

# Different API regions
ReqLLM.generate_text(model, "hello", base_url: "https://eu.api.anthropic.com/v1")
```

### Guidelines

- **Never hard-code URLs** anywhere except the DSL declaration
- **Support version headers** when providers have multiple API versions
- **Use interpolation** for dynamic URL construction when needed

---

## 8. Request/Response Step Implementation Patterns

### Request Body Builder Pattern (`body_step/1`)

```elixir
def body_step(request) do
  body = %{
    model: request.options[:model] || request.options[:id],
    messages: request.options[:messages],
    temperature: request.options[:temperature],
    max_tokens: request.options[:max_tokens],
    stream: request.options[:stream?]
  }
  |> maybe_put(:system, request.options[:system])

  request
  |> Req.Request.put_header("content-type", "application/json")
  |> Map.put(:body, Jason.encode!(body))
end

# Helper to avoid nil values in JSON
defp maybe_put(map, _key, nil), do: map
defp maybe_put(map, key, value), do: Map.put(map, key, value)
```

### Response Decoder Pattern (`parse_step/1`)

```elixir
def parse_step({req, resp}) do
  case resp.status do
    200 ->
      {:ok, body} = Jason.decode(resp.body)
      parsed = parse_response_body(body, req.options[:stream?])
      {req, %{resp | body: parsed}}

    status ->
      err = ReqLLM.Error.API.Response.exception(
        reason: "Provider API error",
        status: status,
        response_body: resp.body
      )
      {req, err}
  end
end
```

### Streaming Response Pattern

```elixir
defp parse_sse_events(body) when is_binary(body) do
  body
  |> String.split("\n\n")
  |> Enum.map(&parse_sse_event/1)
  |> Enum.reject(&is_nil/1)
end

defp convert_to_stream_chunk(%{data: data}) do
  case data do
    %{"type" => "content_block_delta", "delta" => %{"text" => text}} ->
      ReqLLM.StreamChunk.text(text)

    %{"type" => "message_stop"} ->
      ReqLLM.StreamChunk.meta(%{finish_reason: "stop"})

    _ ->
      nil  # Filtered out
  end
end
```

### Helper Function Guidelines

- **Keep helpers `defp`** – only callbacks should be `def`
- **Use descriptive names** – `maybe_put/3`, `to_error/3`, `parse_response_body/2`
- **Keep functions pure** – no side effects, predictable outputs
- **Extract common patterns** – avoid repetition in main step functions

---

## 9. Architectural Checklist for New Providers

Use this checklist to ensure your provider follows the established patterns:

### ✅ DSL & Metadata Setup
- [ ] `use ReqLLM.Provider.DSL` with `:id`, `:base_url`, `:provider_options`, `:provider_defaults`
- [ ] Create `priv/models_dev/<id>.json` with models, context lengths, pricing, env vars
- [ ] Implement required `@behaviour ReqLLM.Provider` callbacks

### ✅ Core Implementation
- [ ] Implement `attach/3` with the 4-step pattern and numbered comments
- [ ] Fetch API key via metadata→JidoKeys pattern, validate non-empty
- [ ] Validate model ID against `Provider.Registry.model_exists?/1`
- [ ] Extract, merge, validate options via `ReqLLM.Provider.Options`

### ✅ Pipeline Configuration
- [ ] Build Req pipeline with headers, base URL, request & response steps
- [ ] Use descriptive step names: `<provider>_encode_body`, `<provider>_decode_response`
- [ ] Implement `body_step/1` for request encoding
- [ ] Implement `parse_step/1` for response decoding

### ✅ Error Handling
- [ ] Convert all failures to structured Splode errors (never `ArgumentError`)
- [ ] Provide helpful error messages with context
- [ ] Handle both success and error HTTP status codes appropriately

### ✅ Response Parsing
- [ ] Implement `parse_response/2` for non-streaming responses
- [ ] Implement `parse_stream/2` for SSE/chunked responses
- [ ] Convert provider responses to `ReqLLM.StreamChunk` format for streams

### ✅ Quality & Documentation
- [ ] Provide helper functions (`maybe_put`, `to_error`, SSE parsing) – keep pure
- [ ] Write integration tests for text generation and streaming
- [ ] Update README with environment variable setup and example usage
- [ ] Add comprehensive `@moduledoc` with examples

### ✅ Architecture Compliance
- [ ] Compare implementation diff-by-diff with Anthropic provider
- [ ] Verify step names and pipeline structure match established patterns
- [ ] Ensure error messages are clear and actionable
- [ ] Test with various model inputs and option combinations

---

## Conclusion

This guide represents the distilled wisdom from iteratively refining the ReqLLM provider architecture. The Anthropic provider serves as the gold standard implementation that balances simplicity, reliability, and extensibility.

**Key Takeaway**: Keep providers simple, direct, and focused on their single responsibility – configuring Req requests for specific AI providers. Let Req handle the HTTP complexity, Splode handle error semantics, and the Provider.Options system handle configuration validation.

Follow this guide closely, and your provider will integrate seamlessly into the ReqLLM ecosystem while maintaining the architectural consistency that makes the system maintainable and reliable.
