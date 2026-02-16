# Observability Basics

You need a stable telemetry contract for requests, LLM calls, and tool execution.

After this guide, you can emit normalized events and subscribe to key paths.

## Event Namespaces

`Jido.AI.Observability.Events` exposes canonical telemetry paths:

- `Events.llm(:start)` -> `[:jido, :ai, :llm, :start]`
- `Events.tool(:stop)` -> `[:jido, :ai, :tool, :stop]`
- `Events.request(:exception)` -> `[:jido, :ai, :request, :exception]`
- `Events.strategy(:react, :step)` -> `[:jido, :ai, :strategy, :react, :step]`

## Emit With Normalization

```elixir
alias Jido.AI.Observability.{Emitter, Events}

obs_cfg = %{emit_telemetry?: true}

:ok =
  Emitter.emit(
    obs_cfg,
    Events.request(:completed),
    %{duration_ms: 18},
    %{agent_id: "weather_agent", request_id: "req-1"}
  )
```

`Emitter` ensures required keys exist in metadata and measurements.

## Subscribe Example

```elixir
:telemetry.attach(
  "jido-ai-request-completed",
  [:jido, :ai, :request, :completed],
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements.duration_ms, metadata.request_id})
  end,
  nil
)
```

## Failure Mode: Inconsistent Metadata Fields

Symptom:
- dashboards fail because events have inconsistent maps

Fix:
- emit via `Jido.AI.Observability.Emitter`
- keep custom keys additive; do not rely on ad-hoc required fields

## Defaults You Should Know

- telemetry emission defaults on (`emit_telemetry?` true)
- required measurements/metadata keys are auto-filled (`0` or `nil`)

## When To Use / Not Use

Use this path when:
- you need stable metrics and traces across strategies

Do not use this path when:
- you are only debugging locally and can rely on direct inspection

## Next

- [Request Lifecycle And Concurrency](request_lifecycle_and_concurrency.md)
- [Signals, Namespaces, Contracts](../developer/signals_namespaces_contracts.md)
- [Architecture And Runtime Flow](../developer/architecture_and_runtime_flow.md)
