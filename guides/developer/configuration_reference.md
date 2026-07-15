# Configuration Reference

This is the copy-paste reference for common `jido_ai` configuration and defaults.

## Application Config

```elixir
# config/config.exs
config :jido_ai,
  model_aliases: %{
    fast: "provider:fast-model",
    capable: "provider:capable-model",
    reasoning: "provider:reasoning-model",
    planning: "provider:planning-model"
  }
```

Package defaults are built into `Jido.AI`; `model_aliases` is merged on top for overrides.

## Strategy/Macro Defaults

- ReAct (`Jido.AI.Agent`)
  - `model`: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)
  - `max_iterations`: `10`
  - `max_tokens`: `4096`
  - `request_policy`: `:reject`
  - `tool_timeout_ms`: `15_000`
  - `tool_max_retries`: `1`
  - `tool_retry_backoff_ms`: `200`
  - `stream_timeout_ms`: `0` (0 = auto-derive the runner's inter-event idle
    timeout from `tool_timeout_ms + 60_000`; `stream_receive_timeout_ms` is
    accepted as a compatibility alias)
  - `tool_heartbeat_ms`: `0` (0 = off). When `> 0`, the runner emits a
    `:keepalive` runtime event every interval *while tools execute*. Tools
    produce no stream events while running, which would otherwise starve a
    consumer that set a short `stream_event_timeout_ms` on
    `Jido.AI.Request.Stream.events/2` (or a short `stream_timeout_ms` on the
    runner) and abort the run mid-tool. The heartbeat keeps both idle layers
    alive; truly-dead streams (no tool, no heartbeat) still time out normally.
  - `req_http_options`: `[]`
  - `llm_opts`: `[]`
  - `request_transformer`: `nil`
  - `agent_skills`: `false` (explicit opt-in trust boundary). Use `true` for
    standard `.agents/skills` roots, a list of trusted roots, or keyword options
    with `paths`, an explicit `trust` policy, `max_depth`, `max_directories`, and
    `exclude_directories`. Discovery and strict validation run when each agent
    instance initializes.
  - `signal_routes`: `[]` (agent-level routes merged with ReAct strategy routes)

- CoT (`Jido.AI.CoTAgent`)
  - `model`: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)

- CoD (`Jido.AI.CoDAgent`)
  - `model`: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)
  - default system prompt encourages concise drafts and final answer after `####`

- AoT (`Jido.AI.AoTAgent`)
  - `model`: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)
  - `profile`: `:standard`
  - `search_style`: `:dfs`
  - `temperature`: `0.0`
  - `max_tokens`: `2048`
  - `require_explicit_answer`: `true`

- ToT (`Jido.AI.ToTAgent`)
  - `model`: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)
  - `branching_factor`: `3`
  - `max_depth`: `3`
  - `traversal_strategy`: `:best_first`

- GoT (`Jido.AI.GoTAgent`)
  - `model`: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)
  - `max_nodes`: `20`
  - `max_depth`: `5`
  - `aggregation_strategy`: `:synthesis`

- TRM (`Jido.AI.TRMAgent`)
  - `model`: `:fast` (resolved at runtime via `Jido.AI.resolve_model/1`)
  - `max_supervision_steps`: `5`
  - `act_threshold`: `0.9`

- Adaptive (`Jido.AI.AdaptiveAgent`)
  - `default_strategy`: `:react`
  - `available_strategies`: `[:cod, :cot, :react, :tot, :got, :trm]`
  - add AoT explicitly when desired: `available_strategies: [:cod, :cot, :react, :aot, :tot, :got, :trm]`

## Request Defaults

- await timeout: `30_000ms`
- max retained requests per agent state: `100`
- request-scoped ReAct overrides: `tools`, `allowed_tools`, `request_transformer`, `max_iterations`, `stream_timeout_ms`, `tool_heartbeat_ms`, `tool_context`, `req_http_options`, `llm_opts`

## Security Defaults

- hard max turns cap: `50`
- callback timeout: `5_000ms`

## CLI Defaults (`mix jido_ai`)

- `--type`: `react`
- supported types: `react | aot | cod | cot | tot | got | trm | adaptive`
- `--timeout`: `60_000`
- `--format`: `text`

## Failure Mode: Conflicting Defaults Across Layers

Symptom:
- behavior differs between CLI, runtime calls, and tests

Fix:
- define explicit model and timeout at the call-site for critical paths
- use one shared config module for environment-specific settings

## Next

- [Getting Started](../user/getting_started.md)
- [Error Model And Recovery](error_model_and_recovery.md)
