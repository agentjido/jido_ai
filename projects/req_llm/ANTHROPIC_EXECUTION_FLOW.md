# ReqLLM Anthropic Provider - Execution Flow Analysis

## Overview
This document maps the complete execution flow of the ReqLLM Anthropic provider from initial `attach/3` call through request processing and response handling, including both streaming and non-streaming paths.

## Legend
- `[BOX]` = Process / function call  
- `<DIAMOND?>` = Decision / branch  
- `(DATA)` = Data artifact / payload  
- `---->` = Normal flow  
- `-X->` = Error flow / raise  

---

## Complete Execution Flow

```
            ┌──────────────────────────────────────────────────┐
            │  CALL SITE (eg. ReqLLM.generate_text/stream_text)│
            └──────────────────────────────────────────────────┘
                                   │
                                   │ passes Req.Request, model, opts
                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [attach/3] ReqLLM.Providers.Anthropic.attach/3                      │
│  ▸ Receives %Req.Request{}, model_input, user_opts                  │
└──────────────────────────────────────────────────────────────────────┘
                                   │
                                   │
              ┌────────────────────┴────────────────────┐
              │                                         │
     <DIAMOND?> model.provider == :anthropic ?          │
              │                                         │
         ┌────┴─────┐                              -X-> RAISE
         │  YES      │                                   Invalid.Provider
         └────┬─────┘
              │
     <DIAMOND?> Registry.model_exists? ?               │
              │                                         │
         ┌────┴─────┐                              -X-> RAISE
         │  YES      │                                   Invalid.Parameter (model)
         └────┬─────┘
              │
     <DIAMOND?> API-key present in JidoKeys ?          │
              │                                         │
         ┌────┴─────┐                              -X-> RAISE
         │  YES      │                                   Invalid.Parameter (api_key)
         └────┬─────┘
              │
┌─────────────▼────────────────────────────────────────────────────────┐
│ [prepare_options]                                                   │
│  ▸ Merge defaults + user_opts                                       │
│  ▸ Validate unknown / invalid keys                                  │
│  ▸ Returns generation opts                                          │
└──────────────────────────────────────────────────────────────────────┘
              │                                         -X-> RAISE
              │                                               Validation.Error /
              │                                               Unsupported options
              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [attach/3] continues                                                │
│  ▸ Req.Request.register_options/merge_options                       │
│  ▸ Put headers: x-api-key, anthropic-version                        │
│  ▸ append_request_steps :anthropic_body → body_step/1               │
│  ▸ maybe_install_stream_steps(stream?)                              │
│        ├─ if true ➜ ReqLLM.Plugins.Stream.attach/1                  │
│  ▸ append_response_steps :decode_response → parse_step/1            │
└──────────────────────────────────────────────────────────────────────┘
              │
              ▼
      ( UPDATED Req.Request )  ──► Req.run/Req.request/1
                                  (Req executes its pipeline)
```

---

## Request Pipeline

```
========================  REQUEST PIPELINE  ==========================
              │
              ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [body_step/1] (anthropic_body request step)                         │
│  ▸ Build message list                                               │
│      • opts[:messages] -or- context.messages                        │
│  ▸ Build body map {model, messages, …, stream?, system?}            │
│  ▸ Jason.encode! ➜ (JSON body)                                      │
└──────────────────────────────────────────────────────────────────────┘
              │                                         -X-> RAISE
              │                                               Encoding error
              ▼
        (HTTP POST) ──► https://api.anthropic.com/v1/messages
```

---

## Response Pipeline

```
========================  RESPONSE PIPELINE ==========================
              │    Raw HTTP Response
              ▼
<DIAMOND?> stream? option true AND
           Content-Type == "text/event-stream" ? 
         ┌───────┴────────┐
         │       YES       │
         └───────┬────────┘
                 │
┌────────────────▼────────────────────────────────────────────────────┐
│ [ReqLLM.Plugins.Stream.process_sse_response]                        │
│  ▸ parse_sse_stream/1                                               │
│      • Binary & chunk accumulator                                   │
│      • ServerSentEvents.parse                                       │
│  ▸ Returns Stream of %{event, data, …}                              │
└──────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
         (resp.body = Stream)                   (Non-stream path skips)
                 │
                 ▼
┌──────────────────────────────────────────────────────────────────────┐
│ [parse_step/1] decode_response response step                        │
│  <DIAMOND?> resp.status == 200 ?                                    │
│        │           │                                                │
│        │           └──NO─ -X-> ReqLLM.Error.API.Response            │
│        │                                                         (propagated)
│        │
│        └─YES                                                     │
│            ├─ if resp.body is binary → Jason.decode/1             │
│            └─ else pass-through                                   │
│  ▸ parse_response_body(body, stream?)                             │
│      • stream? false → map %{id, content, usage}                  │
│      • stream? true  → pass Stream through                        │
│  ▸ Update resp.body with parsed structure                         │
└──────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
        (Pipeline ends) → %Req.Response{}
```

---

## Provider Callbacks

```
=======================  PROVIDER CALLBACKS ==========================
              │                        (Called by ReqLLM higher layer)
              ▼
<DIAMOND?> stream? option true ?
         ┌───────┴────────┐
         │                │
         │       NO       │
         │  (blocking)    │
         │                │
         └───────┬────────┘
                 │
┌────────────────▼────────────────────────────────────────────────────┐
│ [parse_response/2]                                                 │
│  <DIAMOND?> status 200 ?                                           │
│        │           │                                               │
│        │           └──NO─► {:error, to_error(...)}                 │
│        │                                                        -X-> caller
│        │                                                         │
│        └─YES                                                     │
│            ▸ ReqLLM.Context.Codec.decode()                        │
│              ➜ list of stream chunks                              │
│            ▸ Return {:ok, chunks}                                 │
└──────────────────────────────────────────────────────────────────────┘

         STREAMING PATH (YES branch)  
         ───────────────────────────  
                 │
┌────────────────▼────────────────────────────────────────────────────┐
│ [parse_stream/2]                                                   │
│  <DIAMOND?> resp.status == 200 AND body is Stream ?                │
│        │           │                                               │
│        │           └──NO─► {:error, to_error(...)}                 │
│        │                                                        -X-> caller
│        │                                                         │
│        └─YES                                                     │
│            ▸ Stream.map(&to_stream_chunk/1)                       │
│            ▸ Stream.filter(& &1)                                  │
│            ▸ Return {:ok, stream}                                 │
└──────────────────────────────────────────────────────────────────────┘
                 │
                 ▼
        (caller consumes chunks)
```

---

## Error Handling Paths

### Error Nodes:
- **Invalid.Provider / Invalid.Parameter (model)** - Early validation in `attach/3`
- **Missing/blank API key** - JidoKeys validation  
- **Unknown/invalid generation options** - Options validation
- **Jason.encode! failure** - In body_step during JSON encoding
- **HTTP status ≠ 200** - Handled in parse_step → ReqLLM.Error.API.Response  
- **Streaming: unexpected binary body** - Stream processing fallback → {:error, to_error(...)}  
- **parse_stream with non-Stream body** - Type mismatch error  

---

## Req Pipeline Steps Summary

### Request Steps (execution order):
1. *(caller inserted steps …)*  
2. **anthropic_body** (body_step/1) ⇐ added by attach/3  

### Response Steps (execution order):  
1. **stream_sse** (ReqLLM.Plugins.Stream) ⇐ added only when stream? true  
2. **decode_response** (parse_step/1) ⇐ always added by attach/3  
3. *(Req default decode_body, etc.)*  

---

## Key Architectural Decisions

### Separation of Concerns
- **Stream Plugin**: Handles transport-level SSE parsing using `server_sent_events` library
- **Provider**: Focuses on business logic - converting SSE events to ReqLLM chunks

### Step Ordering Critical
- Stream step must run **before** provider decode step
- This ensures raw SSE data is parsed before business logic transformation

### Dual Response Support
- **Non-streaming**: Standard JSON response → structured map
- **Streaming**: SSE events → Stream of parsed chunks

### Robust Error Handling
- Early validation prevents invalid requests
- Multiple error paths with appropriate exception types
- Graceful fallbacks for edge cases

---

## Performance & Optimization Opportunities

1. **Options validation**: Could be cached or simplified
2. **Message conversion**: Currently rebuilds message structure each time
3. **Stream processing**: Uses robust library but could optimize for common cases
4. **Error handling**: Some paths create multiple error objects

## Usage Guide

This flowchart helps with:
- **Debugging**: Trace execution path for issues
- **Performance analysis**: Identify bottlenecks and optimization targets  
- **Feature development**: Understand integration points for new features
- **Code review**: Evaluate architectural decisions and edge cases
- **Testing**: Ensure all paths and error conditions are covered
