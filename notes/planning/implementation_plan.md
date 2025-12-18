
# Phase 01 — Jido AI → ReqLLM Refactor Plan

> **Objective:** Replace all direct LLM provider integrations inside **Jido AI** with **ReqLLM**, while preserving Jido AI’s public API and existing (opt‑in) logging behavior, and exposing *all* ReqLLM-supported providers/models through Jido AI.

---

## 1) Context & Rationale

Jido AI currently implements provider‑specific clients (OpenAI, Anthropic/Claude, OpenRouter, Cloudflare, Google, etc.) using bespoke HTTP calls or third‑party SDKs. This increases surface area for bugs and makes it harder to add new providers. **ReqLLM** offers a unified, Req‑based, plugin architecture that normalizes request/response handling, streaming, tools, and key management across many providers. Migrating Jido AI’s internals to ReqLLM simplifies maintenance and expands model coverage without changing Jido AI’s public API. citeturn0search1turn0search0turn0search2

**Must‑haves (from requirements):**
- Keep **public API 100% backward compatible** (function signatures, return shapes). Internal modules may change.
- Use **only public ReqLLM APIs/behaviours**.
- **Preserve logging** where it exists today (no new noisy logs; keep it opt‑in).
- **Support all models in ReqLLM**, and migrate all existing Jido AI providers to the ReqLLM path.

---

## 2) Scope / Non‑Goals

### In‑Scope
- Replace Jido AI provider/action internals with ReqLLM calls (text chat/completions, streaming, embeddings).
- Map Jido AI model/provider selection to ReqLLM’s `"provider:model"` identifiers.
- Preserve tool/function‑calling via ReqLLM tooling where feasible.
- Keep key management compatible with existing Jido Keys & ENV usage, delegating to ReqLLM where appropriate. citeturn0search1
- Extend Jido AI to accept **any** provider/model supported by ReqLLM (auto‑exposure). citeturn0search6

### Out‑of‑Scope (Phase 01)
- UI/docs overhaul beyond necessary API notes.
- New Jido AI public APIs.
- Provider‑specific, advanced features not yet covered by ReqLLM (e.g., niche media types) — these will be evaluated and scheduled for Phase 02 if needed.

---

## 3) Success Criteria & KPIs

- **Compatibility:** Existing Jido AI examples/tests pass unchanged.
- **Coverage:** Every provider/model available in ReqLLM can be addressed through Jido AI with zero extra adapter code.
- **Parity:** Streaming, tools, embeddings continue to work across providers with same calling conventions.
- **Stability:** Error semantics preserved (same `{:ok, ...} | {:error, ...}` shapes). No log verbosity regressions.
- **DX:** Adding a new provider or model requires *no* Jido AI code changes (provided ReqLLM supports it).

---

## 4) High‑Level Design

### 4.1 Internal Architecture Changes

**A. Model Abstraction**
- Keep `%Jido.AI.Model{}` as the public façade. Internally, enrich it with:
  - `provider :: atom()` (e.g., `:openai`, `:anthropic`)
  - `model :: String.t()` (e.g., `"gpt-4o"`, `"claude-3-5-haiku"`)
  - `reqllm_id :: String.t()` **computed** as `"#{provider}:#{model}"` (e.g., `"openai:gpt-4o"`).
  - Optional: `caps`, `limits`, `context_window` cached from ReqLLM’s registry (if needed later).

**B. Provider Registry & Model Listing**
- Replace Jido’s provider‑specific listing logic with ReqLLM’s registry sync (models.dev). Expose the same Jido APIs but fetch from ReqLLM. If Jido previously had a `mix` task to refresh models, have it call ReqLLM’s sync task under the hood. citeturn0search6

**C. Actions**
- Chat/completions → `ReqLLM.generate_text/3` (and `stream_text/3` if `stream: true`). citeturn0search1
- Embeddings → `ReqLLM.embed_many/3` (or `embed/2` for single input). citeturn0search1
- Tools/Function calling → Pass `tools: [...]` using ReqLLM’s tool API; wrap each Jido Action as a ReqLLM tool callback to preserve behaviour. citeturn0search1

**D. Keys & Auth**
- Delegate to ReqLLM’s key precedence (per‑request, in‑memory, app config, ENV). Continue to surface Jido Keys ergonomics (session/env helpers) but implement them via `ReqLLM` key APIs so both systems remain in sync. citeturn0search1

**E. Logging**
- Preserve existing log sites (and levels) in Jido AI action callbacks (`on_after_run/1`, `on_error/4`, etc.). Do **not** add new HTTP‑level logs unless an env flag is set. Optionally, document how to enable Req/ReqLLM debug/tracing for deeper diagnostics.

**F. Error/Retry Semantics**
- Standardize error mapping from ReqLLM into Jido AI’s existing `{:error, reason}` shapes.
- Retain any existing retry policy (if present) around the ReqLLM call boundary.

### 4.2 Data Flow (Chat Completion)

```
Caller → Jido.AI.Action.run(params, ctx)
  → Jido.AI.Model (ensure reqllm_id)
    → ReqLLM.generate_text(reqllm_id, prompt/messages, opts)
      → Provider plugin (auth, param mapping, HTTP)
        → Provider API
      ← ReqLLM.Response (text, usage, tool calls?)
  → (Optional) Tool loop via ReqLLM callbacks
  → Map to Jido’s public return struct/tuple
← Caller
```

---

## 5) Detailed Work Plan

### 5.1 Module Inventory & Changes

| Area | Current (typical) | Change |
|---|---|---|
| **Model** | `Jido.AI.Model` building provider‑specific structs | Keep API; add `reqllm_id` field & converter; drop provider HTTP details |
| **Providers** | `Jido.AI.Provider.*` for OpenAI, Anthropic, etc. | Make them thin facades over ReqLLM provider registry; optionally keep std name mapping |
| **Actions — Chat** | e.g., `Jido.AI.Actions.OpenaiEx.run/2` | Delegate to `ReqLLM.generate_text/3` (build messages, pass opts) |
| **Actions — Streaming** | provider‑specific streams | Delegate to `ReqLLM.stream_text/3`; preserve stream type/contract |
| **Actions — Embeddings** | provider SDK call | Use `ReqLLM.embed_many/3` |
| **Tools/Functions** | Jido loop & ToolHelper | Wrap Jido actions as `ReqLLM.tool/1` callbacks; feed results back into the chat chain |
| **Keys** | Jido Keys ring + ENV | Bridge to ReqLLM key APIs; preserve Jido helpers |
| **Mix Tasks** | Model list refresh | Call ReqLLM sync (models/dev) and expose through existing Jido task names |
| **Errors/Logging** | Jido shapes & optional logs | Keep identical shapes; keep existing logs only |

### 5.2 Concrete Implementation Steps

1. **Dependency Wire‑up**
   - Add `{:req_llm, "~> 1.0.0-rc"}` to `mix.exs`; ensure `:req` is included. citeturn0search1
   - Introduce an integration module `Jido.AI.ReqLLM` for thin wrappers (helpers, conversions).

2. **Model Conversion**
   - Implement `Jido.AI.Model.reqllm_id(%Model{}) :: String.t()`.
   - Implement `from({provider, opts})` to compute and store `reqllm_id` (validate provider/model present; error if missing).

3. **Key Management Bridge**
   - Implement `Jido.AI.Keys.get/1 | put/2` to delegate to ReqLLM’s key store, keeping Jido’s current API intact (ENV and session still work). citeturn0search1

4. **Action: Chat / Completions**
   - Replace HTTP calls with:
     ```elixir
     ReqLLM.generate_text(model.reqllm_id, messages_or_prompt, opts)
     ```
     - Message shaping: map `%{role, content}` to `[ReqLLM.Message.system/1 | user/1 | assistant/1]` or a string prompt as needed. citeturn0search1
     - Options passthrough: `temperature`, `max_tokens`, `top_p`, `stop`, etc.
     - Return mapping: convert `ReqLLM.Response` to Jido’s expected output struct/tuple.

5. **Action: Streaming**
   - If `opts[:stream]`, call `ReqLLM.stream_text/3` and return the stream (or an adapter stream) that yields the same chunk structure the current API expects. citeturn0search1

6. **Action: Embeddings**
   - Implement `embed/2` via `ReqLLM.embed_many(model.reqllm_id, inputs, opts)`; map to existing return type.

7. **Tools / Function Calling**
   - Add a translator that wraps a `Jido.Action` module as a `ReqLLM.tool/1` with a `callback` that invokes the action’s `run/2` (or suitable function) and returns JSON‑serializable output. citeturn0search1
   - Pass the tools list to `generate_text`; collect tool results (if any) and return them in Jido’s existing `tool_response` shape.

8. **Provider & Model Listing**
   - Implement `Jido.AI.Provider.available/0` and `available_models/1` to read from ReqLLM’s registry (synced via its mix task). Reuse Jido’s current function names.

9. **Error Handling & Retries**
   - Wrap ReqLLM calls to map errors into Jido’s error structs. Re‑apply any Jido retry policy (if present) around the ReqLLM call.

10. **Logging**
    - Preserve existing log statements and levels; no new logs by default.
    - Optionally document enabling Req/ReqLLM trace for debugging.

11. **Mix Tasks**
    - Re‑implement Jido’s model sync task to internally run ReqLLM’s models sync and store/print as before. citeturn0search6

12. **Test Suite Updates**
    - Keep all existing tests. Add new matrix tests across a sample of ReqLLM providers to ensure plug‑in routing works and API contracts hold.

### 5.3 Milestones

- **M0 – Scaffolding (½ day)**: deps, `Jido.AI.ReqLLM`, reqllm_id plumbing, smoke compile.
- **M1 – Chat Path (1–2 days)**: non‑streaming chat for OpenAI/Anthropic via ReqLLM, golden tests pass.
- **M2 – Streaming (1 day)**: streaming parity across providers.
- **M3 – Embeddings (½–1 day)**: embeddings parity.
- **M4 – Tools (1–2 days)**: tool bridging via ReqLLM callbacks; end‑to‑end agent example passes unchanged.
- **M5 – Providers & Models (½ day)**: provider/model listing via ReqLLM registry + mix task.
- **M6 – Hardening (1–2 days)**: error mapping, retries, key precedence tests, docs notes.

---

## 6) Compatibility Matrix (Phase 01 Target)

| Capability | OpenAI | Anthropic | Google | OpenRouter | Cloudflare | + Other ReqLLM providers |
|---|---:|---:|---:|---:|---:|---:|
| Chat (non‑stream) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Streaming | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Tools/Functions | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Embeddings | ✅ | ✅* | ✅* | ✅* | ✅* | ✅ |
| Key mgmt (ENV/session) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |

\* If a provider doesn’t support embeddings natively, Jido AI will still expose `embed*` but return a clear error for those specific models/providers.

---

## 7) Risks & Mitigations

- **Provider Quirks:** Some providers diverge on parameters or tool semantics. *Mitigation:* rely on ReqLLM’s provider plugins to normalize; add per‑provider integration tests. citeturn0search1
- **Name/Alias Mismatches:** Jido aliases (e.g., “gpt‑4o”) vs ReqLLM’s canonical names. *Mitigation:* keep a small alias map; prefer passing through exact strings users provide.
- **Streaming Shapes:** Ensure streamed chunk shapes are identical to today’s consumer expectations. *Mitigation:* add adapter function to reshape chunks if needed.
- **Image/Multimodal Gaps:** If a given modality isn’t exposed yet in ReqLLM, we may need Phase 02 work. *Mitigation:* feature‑flag and document temporary limitations.

---

## 8) Testing Strategy

- **Regression:** Re‑run all current Jido AI tests (no API changes).
- **Provider Matrix:** For a small set of prompts, run OpenAI/Anthropic/Google/OpenRouter/Cloudflare via ReqLLM and compare high‑level shape (not content) of results.
- **Streaming:** Ensure chunking and termination behavior match prior implementation.
- **Tools:** Run tool‑calling sample with 2–3 tools (JSON args parsing, callback wiring, multi‑call loops).
- **Embeddings:** Validate dimensions and types for supported providers/models.
- **Keys:** Verify ENV + session precedence and overrides.

---

## 9) Rollout Plan

1. **Feature Branch**: Land incremental PRs per milestone (M1…M6).
2. **Dual Path (short‑lived)**: Keep old adapter code behind a compile flag for rapid rollback while we stabilize.
3. **Docs Note**: “Internals now powered by ReqLLM; public API unchanged.” Add a short “How to enable Req/ReqLLM debug” doc.
4. **Release**: Tag minor version (e.g., `0.x+1`).

---

## 10) Open Questions

- Do we need to expose ReqLLM’s usage/cost metadata in Jido AI return values (optional)?
- Any Jido‑specific image/multimodal paths to carry over in Phase 01 or defer to Phase 02?
- Should we add a `Jido.AI.Config` knob to force a specific Req middle‑ware (retry/backoff)?

---

## 11) Reference Implementation Sketches

> **Note:** Pseudocode — illustrates the internal changes only. Public Jido AI API stays the same.

### Model → ReqLLM mapping

```elixir
defmodule Jido.AI.Model do
  defstruct [:provider, :model, :reqllm_id, :opts]

  def from({provider, opts}) when is_atom(provider) do
    model = Keyword.fetch!(opts, :model)
    %__MODULE__{
      provider: provider,
      model: model,
      reqllm_id: "#{provider}:#{model}",
      opts: opts
    }
  end
end
```

### Chat (non‑stream)

```elixir
defmodule Jido.AI.Actions.Chat do
  @behaviour Jido.Action

  @impl true
  def run(%{model: %Jido.AI.Model{} = m, messages: messages} = params, _ctx) do
    req_opts = Map.take(params, [:temperature, :max_tokens, :top_p, :stop, :tools])

    # Map Jido message maps -> ReqLLM messages
    msgs = Enum.map(messages, fn
      %{role: "system", content: c}    -> ReqLLM.Message.system(c)
      %{role: "user", content: c}      -> ReqLLM.Message.user(c)
      %{role: "assistant", content: c} -> ReqLLM.Message.assistant(c)
    end)

    case ReqLLM.generate_text(m.reqllm_id, msgs, req_opts) do
      {:ok, resp} -> {:ok, %{content: resp.text, usage: resp.usage}}
      {:error, e} -> {:error, jido_error(e)}
    end
  end
end
```

### Streaming

```elixir
def run(%{model: m, messages: msgs, stream: true} = params, _ctx) do
  req_opts = Map.take(params, [:temperature, :max_tokens, :top_p, :stop, :tools])
  stream = ReqLLM.stream_text(m.reqllm_id, msgs, req_opts)
  {:ok, stream}
end
```

### Tools (wrapping a Jido Action)

```elixir
def to_reqllm_tool(action_mod) do
  ReqLLM.tool(
    name: action_mod.name(),
    description: action_mod.description(),
    parameter_schema: action_mod.schema(),
    callback: fn args -> action_mod.run(args, %{}) end
  )
end
```

---

## 12) References

- **ReqLLM** — unified Req‑based LLM library, providers, streaming, tools, keys. citeturn0search1turn0search6  
- **Jido AI** — current package & getting started docs; current provider approach. citeturn0search0turn0search5turn0search2

