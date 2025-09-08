# ReqLLM Client Architecture Research Report

## Executive Summary

This report outlines a best-practice architecture for ReqLLM that follows Req ecosystem patterns, inspired by the `req_embed` plugin. The goal is to achieve a clean API: `Req.new() |> ReqLLM.attach("anthropic:claude-3-sonnet")` while handling LLM-specific complexities transparently using existing ReqLLM.Model specs and Splode error handling.

## Problems We're Addressing

### 1. Provider Diversity
Every LLM vendor (OpenAI, Anthropic, Together, Fireworks) has different:
- Request/response formats
- Authentication methods
- Streaming protocols  
- Error envelopes
- Rate limiting headers
- Token accounting formats

### 2. AI-Specific Semantics
LLM APIs have unique concerns not found in typical REST APIs:
- **Reasoning tokens**: OpenAI `reasoning` field, Anthropic `thinking` blocks
- **Tool/Function calls**: Structured output with function execution
- **Streaming formats**: Server-Sent Events with delta updates
- **Token accounting**: Input/output/reasoning token costs
- **JSON-only modes**: Structured output constraints
- **Multi-modal content**: Text, images, files in messages

### 3. Current Architecture Issues

**✅ What's Working:**
- Well-factored micro-plugins (`Stream`, `TokenUsage`, `Kagi`) using proper Req step API
- Clear separation between streaming and non-streaming parsing
- Usage & cost telemetry infrastructure

**🟥 Current Gaps:**
1. No single "attach" point - callers must manually wire multiple plugins
2. Provider details scattered across codebase - no unified Provider abstraction
3. Stream parsing returns lists instead of `Stream` - loses back-pressure
4. Tool/function call payloads ignored in streaming
5. Missing retry/rate-limit handling for 429, 5xx responses
6. Parser returns decorated strings (🧠 emojis) - unsuitable as library primitives
7. No JSON-only mode, system fingerprint, response_format support

## Research: Req Plugin Best Practices

### Lessons from `req_embed`

The `req_embed` plugin demonstrates canonical Req extension patterns:

```elixir
# Single attach point
ReqEmbed.attach(req, url, opts)

# Keeps state in req.private only
# Uses prepend_request_steps for outgoing transformation
# Uses append_response_steps for response processing  
# Provides convenience wrapper: ReqEmbed.new(url)
```

**Key Principles:**
- Public surface is `attach/2` returning plain `Req.Request`
- No state outside `req.private`
- Provider logic encapsulated in request/response steps
- Composable with other Req plugins

### Proposed ReqLLM Architecture

```
                    ┌─────────────────────────┐
                    │   ReqLLM.attach/2       │  (public)
                    └────────────┬────────────┘
                                 │ returns Req.Request
                                 ▼
     ┌─────────────── request steps ───────────────┐
     │ 0. set_model_private                         │
     │ 1. Provider.request_defaults/2               │
     │ 2. AuthPlugin (Kagi, ENV, explicit)          │
     │ 3. Req.retry (vendor backoff)                │
     └──────────────────────────────────────────────┘
     ┌────────────── response steps ────────────────┐
     │ a. StreamPlugin (content-type detection)     │
     │ b. Provider.parse_stream/1 (if streaming)    │
     │ c. Provider.parse_response/1 (JSON)          │
     │ d. TokenUsagePlugin                          │
     └──────────────────────────────────────────────┘
```

## Core Design Components

### 1. ReqLLM.attach/2 - Single Entry Point

```elixir
@spec attach(Req.Request.t() | nil, ReqLLM.Model.spec(), keyword()) :: Req.Request.t()
def attach(req \\ Req.new(), model_spec, opts \\ []) do
  model = ReqLLM.Model.from!(model_spec)  # Reuse existing Model.from!/1
  provider = ReqLLM.Provider.for!(model.provider)
  
  req
  |> Req.Request.put_private(:req_llm_model, model)
  |> provider.attach(model, opts)          # injects provider-specific steps
  |> ReqLLM.Plugins.TokenUsage.attach(model)
  |> ReqLLM.Plugins.Stream.attach()        # generic SSE parsing
end
```

**Model Spec Formats** (via existing `ReqLLM.Model.from/1`):
- String: `"anthropic:claude-3-sonnet"`
- Tuple: `{:anthropic, model: "claude-3-sonnet", temperature: 0.7}`
- Struct: `%ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet"}`

### 2. Provider Behaviour - Vendor Abstraction

```elixir
@callback attach(Req.Request.t(), ReqLLM.Model.t(), keyword()) :: Req.Request.t()
@callback build_body(messages :: list(), opts :: keyword()) :: map()
@callback parse_response(map()) :: {:ok, ReqLLM.Message.t()} | {:error, term()}
@callback parse_stream(enum()) :: Stream.t()
@callback extract_usage(map()) :: {:ok, map()} | :error
@callback auth_spec() :: {:header, header, :bearer | :plain | function()}
```

Each provider implements:
- Base URL & path defaults
- Model name mapping (`"gpt-4o"` vs vendor internal names)
- Message/tool encoding for their API format
- Error envelope parsing → `%ReqLLM.Error.API{}`
- Auth specification for Kagi plugin

### 3. Model Registry - Compile-time Configuration

```elixir
%{
  "openai:gpt-4o" => %ReqLLM.Model{
    id: "openai:gpt-4o",
    provider: :openai,
    context: 128_000,
    cost: %{input: 0.00001, output: 0.00003},
    streaming?: true,
    json_mode?: true
  }
}
```

### 4. StreamChunk-Based Streaming - Unified Format

```elixir
# Streaming returns unified chunk stream via ReqLLM.StreamChunk struct
%ReqLLM.StreamChunk{type: :content, text: "Hello"}
%ReqLLM.StreamChunk{type: :thinking, text: "I should be helpful"}  
%ReqLLM.StreamChunk{type: :tool_call, name: "weather", arguments: %{}}

# Helpers for consumers
stream
|> Stream.each(fn
     %ReqLLM.StreamChunk{type: :tool_call} = chunk -> dispatch_tool(chunk)
     %ReqLLM.StreamChunk{text: txt} -> IO.write(txt)
   end)
|> Stream.run()
```

## LLM-Specific Integration Points

### Request-Side Transformations
- **Multi-auth sources**: Kagi → ENV → explicit API keys
- **Streaming headers**: Automatic `Accept: text/event-stream`
- **JSON mode**: Safe `response_format: %{type: "json_object"}`
- **Tool injection**: Automatic `function_call: "auto"` with tools

### Response-Side Processing  
- **SSE handling**: Seamless HTTP/2 chunks or raw JSON
- **Delta merging**: Convert streaming deltas to lazy `Stream`
- **Tool completion**: Parse `%{tool_name: ..., arguments: map}`
- **Extended usage**: Reasoning tokens, completion token details
- **Error coercion**: Robust mapping to `ReqLLM.Error.API`

### Cross-Cutting Concerns
- **Telemetry Events**: 
  - `[:req_llm, :request, :start]` - Request initiated
  - `[:req_llm, :request, :stop]` - Non-streaming response complete (success/failure, token usage, cost)
  - `[:req_llm, :stream, :start]` - Streaming response started  
  - `[:req_llm, :stream, :stop]` - Streaming response complete (total tokens, cost)
  - `[:req_llm, :retry]` - Retry attempt
- **Error Handling**: All errors MUST use Splode error types (`ReqLLM.Error.*`)
- **Rate limiting**: Exponential backoff with vendor-specific headers
- **Configuration**: Override via `Application.put_env(:req_llm, ...)`

## Provider Integration Patterns

### OpenAI/OpenRouter
```json
// Request
{"model": "gpt-4o", "messages": [...], "stream": true}

// Streaming deltas
{"choices":[{"delta":{"reasoning":"I should help"}}]}
{"choices":[{"delta":{"content":"Hello!"}}]}
{"choices":[{"delta":{"tool_calls":[{"function":{"name":"weather"}}]}}]}
```

### Anthropic (Primary Implementation Target)
```json  
// Request to https://api.anthropic.com/v1/messages
{"model": "claude-3-5-sonnet", "messages": [...], "stream": true, "max_tokens": 4096}

// Non-streaming response
{"content": [{"type": "thinking", "thinking": "I should help"}, {"type": "text", "text": "Hello!"}], "usage": {...}}

// Streaming deltas  
{"type":"content_block_start","index":0,"content_block":{"type":"thinking"}}
{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"I should help"}}
{"type":"content_block_start","index":1,"content_block":{"type":"text"}}
{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello!"}}
{"type":"message_stop"}
```

## Anthropic Provider Implementation (Detailed)

```elixir
defmodule ReqLLM.Provider.Anthropic do
  @behaviour ReqLLM.Provider
  @endpoint "https://api.anthropic.com/v1/messages"

  def attach(req, model, opts) do
    req
    |> Req.merge(
         base_url: @endpoint,
         headers: [
           {"content-type", "application/json"},
           {"anthropic-version", "2023-06-01"}
         ]
       )
    |> Req.Request.put_private(:req_llm_provider_spec, auth_spec())
    |> Req.Request.prepend_request_steps(body_builder: &apply_body(&1, model, opts))
    |> Req.Request.append_response_steps(parse_anthropic: &parse_response/1)
    |> attach_telemetry()
  end

  def auth_spec(), do: {:header, "x-api-key", :plain}
  
  defp apply_body(req, model, opts) do
    body = build_anthropic_body(opts[:messages], model, opts)
    Req.update_options(req, json: body)
  end

  defp parse_response({req, %{status: 200, body: body} = resp}) do
  # Parse non-streaming response into ReqLLM.StreamChunk structs
  # Emit [:req_llm, :request, :stop] telemetry with usage/cost
  end

  defp parse_response({req, %{status: status} = resp}) when status >= 400 do
    # Convert to Splode error
    error = ReqLLM.Error.API.Request.exception(
      reason: extract_anthropic_error(resp.body),
      status: status
    )
    {req, error}
  end
end
```

## Proposed API Usage

### Basic Text Generation
```elixir
req = Req.new() |> ReqLLM.attach("openai:gpt-4o", messages: msgs)
{:ok, response} = Req.post!(req)
```

### Streaming
```elixir
stream = 
  Req.new()
  |> ReqLLM.attach("anthropic:claude-3-sonnet", messages: msgs, stream?: true)
  |> Req.post!()
  |> Map.fetch!(:body)

stream |> Stream.each(&IO.puts(&1.text)) |> Stream.run()
```

### Tool Calling
```elixir
events =
  Req.new()
  |> ReqLLM.attach("openai:gpt-4o", messages: msgs, tools: tools, stream?: true)  
  |> Req.post!()
  |> Map.fetch!(:body)
```

## Testing Architecture & Strategy

### Core Testing Approach

**Philosophy**: 100% HTTP traffic stays within BEAM during `mix test`, zero network calls, full concurrent test execution (`async: true`).

### Req.Test Integration

ReqLLM leverages Req.Test's plug registry for HTTP mocking:

```elixir
# Production: Real HTTP
req = Req.new() |> ReqLLM.attach("anthropic:claude-3-sonnet")

# Testing: Mocked responses  
req = Req.new() 
|> ReqLLM.attach("anthropic:claude-3-sonnet", 
                 req_opts: [plug: {Req.Test, ReqLLM.Provider.Anthropic.Stub}])
```

### Generic Fixture-Based Stub

Single generic stub that loads fixtures from provider directories:

```elixir
# config/test.exs  
config :req_llm, :test_mode, :fixtures
config :req_llm, :fixtures_path, "test/support/fixtures"

# Directory structure:
# test/support/fixtures/
# ├── anthropic/
# │   ├── completion_success.json
# │   ├── completion_streaming.json  
# │   ├── completion_error_429.json
# │   └── completion_error_401.json
# ├── openai/
# │   ├── completion_success.json
# │   └── completion_streaming.json
# └── together/
#     └── completion_success.json
```

### Fixture Recording & Replay System

**Recording Fixtures (Easy!):**

```bash
# Record real API responses to fixtures
mix req_llm.record anthropic completion_success "Hello world"
mix req_llm.record anthropic completion_streaming "Tell me a story" --stream
mix req_llm.record openai completion_success "What is 2+2?"

# Records to: test/support/fixtures/anthropic/completion_success.json
```

**Using Fixtures in Tests:**

```elixir  
# Generic fixture stub
ReqLLM.TestHelpers.with_fixture("anthropic/completion_success") do
  result = ReqLLM.attach("anthropic:claude-3-sonnet", "hello") |> Req.request!()
  assert result.body["content"] == "Hello! How can I help you today?"
end

# Or inline fixture specification
test "successful completion" do
  stub = ReqLLM.TestHelpers.fixture_stub("anthropic/completion_success")  
  Req.Test.expect(ReqLLM.FixtureStub, stub)
  
  result = ReqLLM.attach("anthropic:claude-3-sonnet", "hello", 
                         req_opts: [plug: {Req.Test, ReqLLM.FixtureStub}])
end
```

### Streaming Test Patterns

Mock streaming responses with chunked plugs:

```elixir
stream_mock = fn conn ->
  {:ok, conn} = Plug.Conn.send_chunked(conn, 200)
  {:ok, conn} = Plug.Conn.chunk(conn, ~s|data: {"delta":"Hello"}\\n\\n|)
  {:ok, _} = Plug.Conn.chunk(conn, ~s|data: {"delta":"!"}\\n\\n|)
  conn
end

Req.Test.expect(ReqLLM.Provider.Anthropic.Stub, stream_mock)
chunks = ReqLLM.attach("hi", stream?: true) |> Enum.to_list()
assert [%StreamChunk{text: "Hello"}, %StreamChunk{text: "!"}] = chunks
```

### Error & Telemetry Testing

```elixir
# Test error handling  
Req.Test.expect(stub, &Plug.Conn.send_resp(&1, 429, "rate limited"))
assert {:error, %ReqLLM.Error.RateLimit{}} = ReqLLM.attach("hi")

# Test telemetry emissions
:ok = :telemetry.attach_many("test", [[:req_llm, :request, :stop]], &capture_telemetry/4)
ReqLLM.attach("hi") |> Req.request!()
assert_received {:telemetry, [:req_llm, :request, :stop], %{tokens: 150}, %{provider: :anthropic}}
```

### Test Helper Module

```elixir
defmodule ReqLLM.TestHelpers do
  @doc "Load fixture and setup generic stub"
  def with_fixture(fixture_path, test_fn)
  
  @doc "Create fixture-based plug for Req.Test.expect/2"
  def fixture_stub(fixture_path), do: load_fixture_plug(fixture_path)
  
  @doc "Collect streaming chunks for assertions"  
  def collect_chunks(stream), do: Enum.to_list(stream)
  
  @doc "Record live API response to fixture file"
  def record_fixture(provider, scenario, prompt, opts \\ [])
end

# Generic fixture stub implementation
defmodule ReqLLM.FixtureStub do
  @doc "Single stub namespace that loads any fixture by path"
  def load_response(fixture_path) do
    fixtures_dir = Application.get_env(:req_llm, :fixtures_path, "test/support/fixtures")
    file_path = Path.join(fixtures_dir, fixture_path <> ".json")
    
    case File.read(file_path) do
      {:ok, json} -> Jason.decode!(json)
      {:error, _} -> raise "Fixture not found: #{file_path}"
    end
  end
end
```

## Refined Implementation Plan: Anthropic Provider Focus

### Phase 1: Core Infrastructure (Week 1)
1. **Create ReqLLM.StreamChunk struct** 
   - Path: `lib/req_llm/stream_chunk.ex` (NOT response/event.ex)
   - Fields: `type` (`:content`, `:thinking`, `:tool_call`), `text`, `name`, `arguments`, `metadata`
   - TypedStruct with proper validation

2. **Create ReqLLM.Provider behaviour**
   - Path: `lib/req_llm/provider.ex`
   - Define callbacks: `attach/3`, `build_body/3`, `parse_response/1`, `parse_stream/1`, `auth_spec/0`

3. **Add ReqLLM.attach/2 function**
   - Add to main `lib/req_llm.ex` module
   - Use existing `ReqLLM.Model.from!/1` for model spec parsing
   - Wire up provider plugins automatically

### Phase 2: Anthropic Provider (Week 2) 
4. **Create ReqLLM.Provider.Anthropic module**
   - Path: `lib/req_llm/providers/anthropic.ex`
   - Implement all behaviour callbacks
   - Handle both streaming and non-streaming responses
   - Convert responses to `ReqLLM.StreamChunk` structs
   - Use Splode errors exclusively

5. **Update Stream plugin**
   - Modify to work with provider-specific stream parsers
   - Return `Stream` of `ReqLLM.StreamChunk` structs (not lists)
   - Handle Anthropic SSE format specifically

6. **Add comprehensive telemetry**
   - `[:req_llm, :request, :start]` with model metadata
   - `[:req_llm, :request, :stop]` with success/failure, tokens, cost
   - `[:req_llm, :stream, :start]` and `[:req_llm, :stream, :stop]`

### Phase 3: Testing & Integration (Week 3)
7. **Create fixture recording system**
   - Add `mix req_llm.record` task for capturing real API responses
   - Implement `ReqLLM.FixtureStub` generic stub that loads JSON fixtures
   - Create fixture directory structure: `test/support/fixtures/{provider}/{scenario}.json`
   - Support both streaming and non-streaming fixture recording

8. **Create ReqLLM.TestHelpers module**
   - `with_fixture/2` - load fixture and run test
   - `fixture_stub/1` - create Req.Test plug from fixture path
   - `record_fixture/4` - programmatic fixture recording
   - `collect_chunks/1` - streaming test utilities

9. **Comprehensive Req.Test integration**
   - Use single `ReqLLM.FixtureStub` for all providers
   - Test both streaming and non-streaming with fixture-based responses
   - Test error scenarios (429, 401) with error fixtures
   - Test telemetry emissions with :telemetry.attach_many

10. **Update TokenUsage plugin**
    - Use provider callbacks for usage extraction
    - Support Anthropic usage format
    - Emit enhanced telemetry with testable assertions

11. **Update existing APIs**
    - Modify `generate_text/3` to optionally use new attach pattern
    - Keep backward compatibility
    - Document migration path

## Implementation Requirements & Best Practices

### Critical Requirements
- ✅ **Splode errors only**: ALL errors must use `ReqLLM.Error.*` types - never raw exceptions
- ✅ **Model specs**: Use existing `ReqLLM.Model.from!/1` for all model spec parsing
- ✅ **ReqLLM.StreamChunk path**: StreamChunk struct at `lib/req_llm/stream_chunk.ex` (not in response/ subdir)
- ✅ **Telemetry mandatory**: All request/stream lifecycle events must emit telemetry
- ✅ **Stream back-pressure**: Return `Stream` not lists for proper memory management

### Implementation Best Practices  
- ✅ **Immutable requests**: Never mutate, always return new `Req.Request` struct
- ✅ **Provider encapsulation**: Keep ALL vendor knowledge in Provider modules
- ✅ **Primitive APIs**: Return `%Req.Response{}`, `%Stream{}` - no markdown decorations
- ✅ **Secret safety**: Read from Kagi/ENV, never log API keys  
- ✅ **Test-driven architecture**: Design all modules with `req_opts` injection for Req.Test
- ✅ **Zero network tests**: 100% HTTP traffic stays within BEAM during `mix test`
- ✅ **Fixture-based testing**: Single generic stub loads fixtures by provider/scenario path
- ✅ **Easy recording**: `mix req_llm.record provider scenario prompt` captures real responses
- ✅ **Clear documentation**: Document all `attach/2` options and telemetry events

### Anthropic-Specific Requirements
- ✅ **API version**: Include `"anthropic-version": "2023-06-01"` header
- ✅ **Max tokens**: Anthropic requires `max_tokens` in request body
- ✅ **Thinking blocks**: Parse `thinking` content blocks into `:thinking` events
- ✅ **Tool calls**: Support Anthropic tool calling format in streaming/non-streaming
- ✅ **Usage extraction**: Parse Anthropic-specific usage format for telemetry

## Conclusion

By following the `req_embed` pattern and introducing a Provider behaviour, `ReqLLM.attach/2` becomes a single entry point that encapsulates LLM vendor complexity. The architecture maintains Req's composability while providing LLM-specific capabilities like reasoning tokens, tool calls, streaming, and token accounting in a unified, type-safe interface.

This approach makes ReqLLM a true Req ecosystem citizen while handling the unique challenges of LLM API integration transparently and robustly.
