# ReAct Weather Example

Canonical weather module: `lib/examples/weather/react_agent.ex`.

Related index docs:
- `README.md`
- `lib/examples/README.md`
- `lib/examples/weather/overview.ex`

## ReAct Tool Loop Flow

1. Caller submits with `ask/3` or `ask_sync/3` (`ai.react.query`).
2. `Jido.AI.Reasoning.ReAct.Strategy` builds runtime config/context for the request.
3. Strategy starts delegated worker execution via `ai.react.worker.start`.
4. Worker runs `Jido.AI.Reasoning.ReAct.stream/3` and forwards each runtime envelope as `ai.react.worker.event`.
5. Strategy applies runtime events and updates request state:
   - `request_started`
   - `llm_started`, `llm_delta`, `llm_completed`
   - `tool_started`, `tool_completed`
   - `checkpoint`
   - terminal: `request_completed`, `request_failed`, or `request_cancelled`
6. Terminal events finalize request state and release the worker for the next run.

## Request Lifecycle Contract

- `ask/3` returns `{:ok, %Jido.AI.Request.Handle{}}` immediately.
- `await/2` resolves that handle to `{:ok, result}` or `{:error, reason}`.
- `ask_sync/3` wraps `ask/3 + await/2`.
- `cancel/2` emits `ai.react.cancel` for advisory cancellation of the active request.
- Correlation is request-id based end-to-end (request handle, runtime events, lifecycle signals).
- Default concurrency policy is `request_policy: :reject` (second in-flight request emits `ai.request.error` with `:busy`).

## CLI Adapter Alignment

`Jido.AI.Examples.Weather.ReActAgent.cli_adapter/0` returns `Jido.AI.Reasoning.ReAct.CLIAdapter`, which is the default ReAct CLI path.

```bash
mix jido_ai --agent Jido.AI.Examples.Weather.ReActAgent "Should I bring an umbrella in Chicago this evening?"
```

## API Demo

```elixir
{:ok, pid} = Jido.AgentServer.start_link(agent: Jido.AI.Examples.Weather.ReActAgent)

{:ok, response} =
  Jido.AI.Examples.Weather.ReActAgent.commute_plan_sync(
    pid,
    "Seattle, WA"
  )
```

## Example Gate

```bash
mix run lib/examples/scripts/test_weather_agent.exs
```

If the environment cannot run live LLM/weather calls (missing provider credentials or sandboxed runtime), skip this script gate and rely on the ReAct test/docs gates for validation.
