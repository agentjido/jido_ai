# TRM Weather Example

Canonical weather module: `lib/examples/weather/trm_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## TRM Recursive Loop

1. Caller submits through `reason/3` or `reason_sync/3` (`ai.trm.query`).
2. `Jido.AI.Reasoning.TRM.Strategy` routes the request to `:trm_start` and initializes `Jido.AI.Reasoning.TRM.Machine`.
3. The machine emits `{:reason, ...}` and strategy builds an `LLMStream` call with `metadata.phase == :reasoning`.
4. Streaming chunks arrive as `ai.llm.delta` and are applied by `:trm_llm_partial`.
5. Final responses arrive as `ai.llm.response` and `:trm_llm_result` advances the loop through:
   - reasoning -> supervising
   - supervising -> improving
   - improving -> reasoning (next recursive pass) or completed
6. Concurrent start requests are rejected with `ai.request.error` (`reason: :busy`) and handled through `:trm_request_error`.

## Request Lifecycle Contract

- `reason/3` returns `{:ok, %Jido.AI.Request.Handle{}}` immediately.
- `await/2` resolves one handle to `{:ok, result}` or `{:error, reason}`.
- `reason_sync/3` wraps `reason/3 + await/2`.
- `trm_request_error` updates request state as a lifecycle rejection (`{:rejected, reason, message}`).
- Completed runs update both request tracking and compatibility fields (`last_result`, `completed`).

## TRM Module Contracts

- `Jido.AI.Reasoning.TRM.Machine`: pure state transitions and loop directives (`:reason`, `:supervise`, `:improve`).
- `Jido.AI.Reasoning.TRM.Reasoning`: reasoning prompt construction and reasoning result parsing.
- `Jido.AI.Reasoning.TRM.Supervision`: supervision/improvement prompts and quality/feedback parsing.
- `Jido.AI.Reasoning.TRM.ACT`: confidence tracking, convergence detection, and halt/continue decisions.

## TRM Stopping Controls

Core controls:
- `max_supervision_steps` (default `5`)
- `act_threshold` (default `0.9`)

Halting paths:
- `:max_steps` when supervision step limit is reached.
- `:act_threshold` when confidence crosses threshold or ACT detects diminishing returns.
- `:convergence_detected` when confidence history plateaus.
- `:error` when a phase call fails.

These controls are the guardrails for the recursive reason/supervise/improve loop.

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.TRMAgent.cli_adapter/0` returns
`Jido.AI.Reasoning.TRM.CLIAdapter`, the canonical `mix jido_ai` adapter for TRM weather runs.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.TRMAgent "Improve my severe-weather emergency plan for a 2-day power outage."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.TRMAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.TRMAgent.storm_readiness_sync(
    pid,
    "Two-day winter storm with likely outages."
  )
```
