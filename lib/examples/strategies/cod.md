# CoD Weather Example

Canonical weather module: `lib/examples/weather/cod_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## CoD Runtime Flow

1. Caller submits through `draft/3` or `draft_sync/3` (`ai.cod.query`).
2. `Jido.AI.Reasoning.ChainOfDraft.Strategy` maps CoD instructions to delegated CoT worker actions.
3. Worker lifecycle envelopes arrive as `ai.cot.worker.event`.
4. Terminal events set request status to completed (`request_completed`) or error (`request_failed`).

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.CoDAgent.cli_adapter/0` returns `Jido.AI.Reasoning.ChainOfDraft.CLIAdapter`, which is the canonical `mix jido_ai` adapter for CoD agents.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.CoDAgent "Give me a fast weather-aware commute recommendation with one backup."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.CoDAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.CoDAgent.quick_plan_sync(
    pid,
    "Need a quick commute plan for rainy weather tomorrow morning."
  )
```
