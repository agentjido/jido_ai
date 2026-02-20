# AoT Weather Example

Canonical weather module: `lib/examples/weather/aot_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## AoT Execution Flow

1. Caller submits with `explore/3` or `explore_sync/3` (`ai.aot.query`).
2. `Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy` maps the request to `:aot_start` and starts the AoT machine.
3. Strategy emits `Jido.AI.Directive.LLMStream` for the active request id.
4. Streaming deltas arrive as `ai.llm.delta` and update partial text via `:aot_llm_partial`.
5. Final output arrives as `ai.llm.response` and is parsed by `:aot_llm_result` into the structured AoT result contract.
6. Concurrent start attempts are rejected with `ai.request.error` (`reason: :busy`) for request lifecycle parity.

## Request Lifecycle Contract

- `explore/3` returns `{:ok, %Jido.AI.Request.Handle{}}` immediately.
- `await/2` resolves a specific request handle to `{:ok, result}` or `{:error, reason}`.
- `explore_sync/3` wraps `explore/3 + await/2`.
- `aot_request_error` is treated as a request lifecycle rejection and recorded on agent request state.
- Successful completion stores the structured AoT result (including `answer`, `usage`, and diagnostics) in strategy/agent state.

## AoT Agent Macro Contract

`use Jido.AI.AoTAgent` wires the canonical strategy module and exposes request helpers.

Default strategy options:
- `model: "anthropic:claude-haiku-4-5"`
- `profile: :standard`
- `search_style: :dfs`
- `temperature: 0.0`
- `max_tokens: 2048`
- `require_explicit_answer: true`

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.AoTAgent.cli_adapter/0` returns `Jido.AI.Reasoning.AlgorithmOfThoughts.CLIAdapter`, the canonical `mix jido_ai` adapter for AoT weather runs.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.AoTAgent "Find the best weather-safe weekend option with one backup."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.AoTAgent)

{:ok, result} =
  Jido.AI.Examples.Weather.AoTAgent.weekend_options_sync(
    pid,
    "Find the best weather-safe weekend option with one fallback."
  )
```
