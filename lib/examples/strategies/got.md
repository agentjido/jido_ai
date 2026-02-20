# GoT Weather Example

Canonical weather module: `lib/examples/weather/got_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## GoT Execution Flow

1. Caller submits with `explore/3` or `explore_sync/3` (`ai.got.query`).
2. `Jido.AI.Reasoning.GraphOfThoughts.Strategy` maps the request into `:got_start` and starts graph exploration.
3. Strategy emits `Jido.AI.Directive.LLMStream` directives for generation/connection/aggregation turns.
4. Streaming deltas arrive as `ai.llm.delta` and update partial text via `:got_llm_partial`.
5. Final output arrives as `ai.llm.response` and is applied by `:got_llm_result` to node/edge state and synthesis output.
6. Concurrent start attempts are rejected with `ai.request.error` (`reason: :busy`) for request lifecycle parity.

## Request Lifecycle Contract

- `explore/3` returns `{:ok, %Jido.AI.Request.Handle{}}` immediately.
- `await/2` resolves a specific request handle to `{:ok, result}` or `{:error, reason}`.
- `explore_sync/3` wraps `explore/3 + await/2`.
- `got_request_error` is treated as a lifecycle rejection and recorded as `{:rejected, reason, message}` on request state.
- Successful completion records the final synthesis result in request state and macro compatibility fields (`last_result`, `completed`).

## GoT Agent Macro Contract

`use Jido.AI.GoTAgent` wires `Jido.AI.Reasoning.GraphOfThoughts.Strategy` and request helpers.

Default strategy options:
- `model: "anthropic:claude-haiku-4-5"`
- `max_nodes: 20`
- `max_depth: 5`
- `aggregation_strategy: :synthesis`

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.GoTAgent.cli_adapter/0` returns `Jido.AI.Reasoning.GraphOfThoughts.CLIAdapter`, the canonical `mix jido_ai` adapter for GoT weather runs.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.GoTAgent "Compare weather risks across NYC, Chicago, and Denver for a trip."
```

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.GoTAgent)

{:ok, result} =
  Jido.AI.Examples.Weather.GoTAgent.multi_city_sync(
    pid,
    ["NYC", "Chicago", "Denver"]
  )
```
