# Adaptive Weather Example

Canonical weather module: `lib/examples/weather/adaptive_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## Adaptive Selection Flow

1. Caller submits through `ask/3` or `ask_sync/3` (`ai.adaptive.query`).
2. `Jido.AI.Reasoning.Adaptive.Strategy` handles `:adaptive_start`, computes prompt complexity, and classifies task shape from keywords.
3. Adaptive maps lifecycle actions (`:adaptive_llm_result`, `:adaptive_llm_partial`, `:adaptive_request_error`) into the selected strategy action atoms.
4. Selected strategy processes `ai.llm.response` and `ai.llm.delta`, then returns normal directives and final result.
5. Strategy selection is re-evaluated only when a new start command arrives and the previous delegated run has reached `done?`.
6. Busy lifecycle conflicts are emitted as `ai.request.error` with `reason: :busy`.

## Strategy-Selection Constraints

Selection is deterministic and constrained by configured strategy availability:

- Manual `strategy` override bypasses analysis.
- Task-type priority applies before complexity fallback:
  - iterative reasoning -> `:trm` (fallback `:tot`)
  - synthesis/graph -> `:got` (fallback `:tot`)
  - tool use -> `:react`
  - exploration -> `:aot`, then `:tot`, then `:got`
- Complexity fallback applies when no task-type override matches:
  - score `< simple` -> `:cod`, then `:cot`
  - score `> complex` -> `:aot`, then `:tot`, then `:got`
  - otherwise -> `:react`
- Preference lists are filtered by `available_strategies`; if a preferred option is unavailable, Adaptive falls back to the first available strategy.

## Adaptive Agent Macro Contract

`use Jido.AI.AdaptiveAgent` wires `Jido.AI.Reasoning.Adaptive.Strategy` and request helpers.

Default strategy options:
- `model: "anthropic:claude-haiku-4-5"`
- `default_strategy: :react`
- `available_strategies: [:cod, :cot, :react, :tot, :got, :trm]`
- `complexity_thresholds: %{simple: 0.3, complex: 0.7}`

AoT support is opt-in for Adaptive:
- `available_strategies: [:cod, :cot, :react, :aot, :tot, :got, :trm]`

## Request Lifecycle Contract

- `ask/3` returns `{:ok, %Jido.AI.Request.Handle{}}` immediately.
- `await/2` resolves a specific request handle to `{:ok, result}` or `{:error, reason}`.
- `ask_sync/3` wraps `ask/3 + await/2`.
- `adaptive_request_error` is treated as a lifecycle rejection and recorded as `{:rejected, reason, message}`.
- Completed runs update request tracking and compatibility fields (`last_result`, `completed`, `selected_strategy`).

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.AdaptiveAgent.cli_adapter/0` returns
`Jido.AI.Reasoning.Adaptive.CLIAdapter`, the canonical `mix jido_ai` adapter for Adaptive weather runs.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.AdaptiveAgent "I need a weather-aware commute and backup plan for tomorrow."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.AdaptiveAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.AdaptiveAgent.coach_sync(
    pid,
    "Need a weather-aware commute and backup plan for tomorrow."
  )
```
