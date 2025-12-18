# Integrating ReqLLM into Jido AI: Plan and Considerations  
**Research report — 2025-09-22 06:31**

## Overview

This report explores what’s required to replace **direct model integrations** in **Jido AI** with the **ReqLLM** library while **preserving Jido AI’s public API** and **existing logging behavior (when present)**. The goal is to (1) migrate all currently supported Jido AI providers to use ReqLLM internally, and (2) make **every ReqLLM-supported model** available through Jido AI without changing Jido AI’s public function signatures or return shapes.

---

## Current Jido AI LLM Integration (as-is)

Jido AI exposes a provider-agnostic surface to application code but currently performs **provider‑specific HTTP calls** or uses **provider‑specific SDKs** under the hood:

- Providers typically include **OpenAI**, **Anthropic (Claude)**, **Google (Gemini)**, **OpenRouter**, and **Cloudflare Workers AI**.
- Each provider has custom **request building**, **transport**, and **response parsing** in dedicated action/adapter modules.
- **Streaming** and **function/tool-calling** are implemented per provider where supported.
- **Key management** is handled via environment variables and Jido Keys helpers.
- **Logging** is deliberately minimal and **opt-in** (e.g., only when a log level is configured); there is no default noisy logging.

**Implications:** Provider-specific code paths increase maintenance cost, create duplication (e.g., for message shaping and error handling), and slow the addition of new providers.

---

## ReqLLM in a Nutshell

**ReqLLM** is a unified, provider‑agnostic interface built on the `Req` HTTP client:

- **Core APIs:**
  - `generate_text/3` and `stream_text/3` for chat/completions (accept either a prompt or a list of role‑tagged messages).
  - Embedding helpers (e.g., `embed_many/3`).
  - Built‑in **tool/function-calling** support via tool descriptors + Elixir callbacks.
- **Model addressing:** Models are referenced by "provider:model" identifiers (e.g., "openai:gpt-4o").
- **Providers:** Broad coverage (OpenAI, Anthropic, Google, OpenRouter, Cloudflare, and many others) with a plugin architecture that normalizes parameters and responses per provider.
- **Key management:** Precedence across per-request overrides, in‑memory keys, application config, and environment variables; friendly to .env workflows.
- **Req-based:** Leverages middleware, timeouts, retries, and instrumentation patterns from the Req ecosystem.

**Implications:** Jido AI can delegate the heavy lifting (auth, param normalization, streaming, tool calls, and embeddings) to a single, consistent backend—**without altering Jido AI’s public API**.

---

## Refactoring Jido AI to Use ReqLLM

### 1) Keep Jido’s Public API Stable

- Preserve all public function names, arities, and return types (e.g., `{:ok, result}` / `{:error, reason}`).
- Continue to use the `%Jido.AI.Model{}` façade and `Jido.AI.Model.from/1` user entrypoints.

### 2) Add an Internal Model Mapping

Augment `%Jido.AI.Model{}` with a **computed** `reqllm_id :: String.t()`:

```elixir
%Jido.AI.Model{provider: :openai, model: "gpt-4o", reqllm_id: "openai:gpt-4o"}
```

- Keep any existing fields needed by callers.
- Optionally cache model metadata (caps/limits) if needed later.

### 3) Delegate Action Implementations to ReqLLM

- **Chat / non‑streaming:** call `ReqLLM.generate_text(model.reqllm_id, messages_or_prompt, opts)`.
- **Streaming:** call `ReqLLM.stream_text(model.reqllm_id, messages_or_prompt, opts)` and **preserve the existing stream contract** (wrap/reshape the chunks if necessary).
- **Embeddings:** call `ReqLLM.embed_many(model.reqllm_id, inputs, opts)` and map to the current embedding result shape.
- **Tools / function‑calling:** create ReqLLM **tool descriptors** that wrap Jido Action modules (callbacks invoke the Jido action and return JSON‑serializable values). Pass `tools: [...]` to `generate_text/3`. Aggregate tool invocations into the same `tool_response` shape Jido currently returns.

### 4) Unify Provider/Model Discovery

- Replace bespoke provider listing and model catalog logic with ReqLLM’s provider/model registry.
- If Jido offers `mix` tasks to update model lists, re‑implement them to call ReqLLM’s sync/listing capabilities and surface the same Jido CLI entrypoints.

### 5) Bridge Key Management

- Keep Jido Keys helpers as the developer‑facing API.
- Under the hood, **delegate** to ReqLLM’s key store/precedence so that ENV variables, app config, and in‑memory/session values behave identically to today.

### 6) Preserve Logging & Error Semantics

- **Logging:** keep existing log sites and levels (no new default logs). Optionally document how to enable deeper Req/ReqLLM debug/trace if desired.
- **Errors:** map ReqLLM errors/exceptions to the **same** `{:error, reason}` shapes or error structs Jido currently uses.
- **Retries:** if Jido had a retry policy, re‑apply it around the ReqLLM call boundary (or configure Req middleware accordingly).

---

## Expected Benefits

- **Less code & duplication:** Reduced provider‑specific branches and custom HTTP plumbing.
- **More providers & models:** Immediate access to any provider/model supported by ReqLLM.
- **Consistency:** Common handling of streaming, tools, embeddings, and error shapes across providers.
- **Maintainability:** Faster onboarding for new providers/models as ReqLLM evolves.

---

## Risks & Mitigations

- **Provider parameter drift:** Different providers emphasize different knobs.  
  *Mitigation:* Rely on ReqLLM’s provider plugins for normalization; only add thin glue when absolutely necessary.

- **Streaming payload differences:** Stream chunk structure may differ.  
  *Mitigation:* Add a small adapter so downstream Jido consumers observe the **same** stream item shape.

- **Model name aliases:** Jido examples may use convenient aliases.  
  *Mitigation:* Keep a tiny alias map or pass original names verbatim where accepted by ReqLLM.

- **Modalities beyond text/embeddings:** If an image/audio modality isn’t yet exposed by ReqLLM, parity may lag.  
  *Mitigation:* Temporarily keep a thin direct call (feature‑flagged) and plan a Phase‑2 provider plugin or extension.

---

## Migration Checklist

1. Add `:req_llm` dependency and create `Jido.AI.ReqLLM` glue module (helpers, message conversion, error mapping).
2. Compute/store `reqllm_id` in `%Jido.AI.Model{}` when building from `{:provider, opts}`.
3. Replace chat/stream/embedding action internals with ReqLLM calls; preserve public contracts.
4. Implement tool wrappers as ReqLLM tools; return the **same** tool_response structure.
5. Bridge key management (Jido helpers → ReqLLM key store/precedence).
6. Rewire provider/model listing and related mix tasks to use ReqLLM’s registry.
7. Keep logging sites/levels; map errors and (if present) retries.
8. Extend tests to validate: (a) shape parity across providers, (b) streaming chunk contract, (c) tool‑calling loop, (d) embeddings shape/dimensions, (e) key precedence and overrides.

---

## Conclusion

Adopting **ReqLLM** as the unified backend for **Jido AI** yields broader provider/model coverage, reduces maintenance burden, and preserves the **unchanged public API** and **logging behavior** that users rely on. Internal complexity shifts to ReqLLM’s well‑factored provider plugins and standardized interfaces, enabling Jido AI to focus on agentic orchestration and developer ergonomics—while transparently supporting **all models available through ReqLLM**Great. I’ll analyze what’s required to replace the direct model integrations in Jido Ai with the Req LLM library while preserving Jido Ai’s public API and logging behavior where applicable. I’ll also ensure that all LLMs currently supported by Jido Ai are moved to Req LLM and that Jido Ai gains access to all models available through Req LLM, using only its public API.

.
