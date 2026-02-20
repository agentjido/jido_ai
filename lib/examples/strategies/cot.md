# CoT Weather Example

Canonical weather module: `lib/examples/weather/cot_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## CoT Delegation Flow

1. Caller submits with `think/3` or `think_sync/3` (`ai.cot.query`).
2. `Jido.AI.Reasoning.ChainOfThought.Strategy` validates request lifecycle state and enforces `request_policy: :reject`.
3. Strategy lazily starts the delegated worker and emits `ai.cot.worker.start`.
4. Worker forwards runtime envelopes as `ai.cot.worker.event`.
5. Strategy applies event transitions for:
   - `request_started`
   - `llm_started`, `llm_delta`, `llm_completed`
   - terminal: `request_completed`, `request_failed`, `request_cancelled`
6. Terminal events finalize request state, preserve trace summaries, and mark the worker ready for the next request.

## Request Lifecycle Contract

- `think/3` returns `{:ok, %Jido.AI.Request.Handle{}}` immediately.
- `await/2` resolves a specific request handle to `{:ok, result}` or `{:error, reason}`.
- `think_sync/3` wraps `think/3 + await/2`.
- Rejected concurrent requests emit `ai.request.error` with `reason: :busy`.
- Request correlation stays request-id based across agent state, worker envelopes, and lifecycle signals.

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.CoTAgent.cli_adapter/0` returns `Jido.AI.Reasoning.ChainOfThought.CLIAdapter`, the canonical `mix jido_ai` adapter path for CoT weather usage.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.CoTAgent "How should I decide between biking and transit in rainy weather?"
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.CoTAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.CoTAgent.weather_decision_sync(
    pid,
    "Should I run outdoors or at the gym if rain is likely?"
  )
```
