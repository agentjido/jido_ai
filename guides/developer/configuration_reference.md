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
  - `request_policy`: `:reject`
  - `tool_timeout_ms`: `15_000`
  - `tool_max_retries`: `1`
  - `tool_retry_backoff_ms`: `200`

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
