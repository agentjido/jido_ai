# ReAct Observability Walkthrough

This guide shows how to run a ReAct agent with production lifecycle and observability defaults.

## 1. Configure a ReAct Agent

```elixir
defmodule MyApp.WeatherAgent do
  use Jido.AI.ReActAgent,
    name: "weather_agent",
    tools: [Jido.Tools.Weather],
    request_policy: :reject,
    tool_timeout_ms: 15_000,
    tool_max_retries: 1,
    tool_retry_backoff_ms: 200,
    observability: %{
      emit_telemetry?: true,
      emit_lifecycle_signals?: true,
      redact_tool_args?: true,
      emit_llm_deltas?: true
    }
end
```

## 2. Run with CLI Tracing

```bash
mix jido_ai --agent MyApp.WeatherAgent --trace "Will it rain in Seattle today?"
```

The trace output includes request lifecycle, LLM lifecycle, tool start/retry/timeout/error, and token usage signals.

## 3. Attach Telemetry Handlers

```elixir
:telemetry.attach_many(
  "react-observe",
  [
    [:jido, :ai, :request, :start],
    [:jido, :ai, :request, :complete],
    [:jido, :ai, :request, :failed],
    [:jido, :ai, :llm, :start],
    [:jido, :ai, :llm, :complete],
    [:jido, :ai, :tool, :start],
    [:jido, :ai, :tool, :complete],
    [:jido, :ai, :tool, :error]
  ],
  fn event, measurements, metadata, _ ->
    IO.inspect({event, measurements, metadata}, label: "react.telemetry")
  end,
  nil
)
```

## 4. Optional OpenTelemetry Integration

ReAct now emits through upstream `Jido.Observe`. To enable tracing, configure
`config :jido, :observability, tracer: ...` with a `Jido.Observe.Tracer`
implementation (default is `Jido.Observe.NoopTracer`).

## 5. Request Lifecycle Guarantees

- Busy requests are rejected deterministically (`ai.request.error`).
- Tool execution has bounded retries and per-attempt timeout.
- Cancellation is request-scoped and results in `{:cancelled, reason}` failure.
- `ask_sync/await` return deterministic success/error/timeout tuples.
