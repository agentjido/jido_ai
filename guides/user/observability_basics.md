# Observability Basics

You need a stable telemetry contract for requests, LLM calls, and tool execution.

After this guide, you can emit normalized events and subscribe to key paths.

## Event Namespaces

`Jido.AI.Observe` exposes canonical telemetry paths:

- `Observe.llm(:span | :start | :delta | :complete | :error)` -> `[:jido, :ai, :llm, ...]`
- `Observe.tool(:span | :start | :retry | :complete | :error | :timeout)` -> `[:jido, :ai, :tool, ...]`
- `Observe.request(:start | :complete | :failed | :rejected | :cancelled)` -> `[:jido, :ai, :request, ...]`
- `Observe.strategy(:react, :step)` -> `[:jido, :ai, :strategy, :react, :step]`
- `Observe.tool_execute(:start | :stop | :exception)` -> `[:jido, :ai, :tool, :execute, ...]`

## Emit With Normalization

```elixir
alias Jido.AI.Observe

obs_cfg = %{emit_telemetry?: true, emit_llm_deltas?: false}

:ok =
  Observe.emit(
    obs_cfg,
    Observe.request(:start),
    %{duration_ms: 18},
    %{agent_id: "weather_agent", request_id: "req-1", run_id: "run-1"}
  )
```

`Observe` normalizes required metadata/measurement keys before emit.

Required metadata keys:
`agent_id`, `request_id`, `run_id`, `iteration`, `llm_call_id`, `tool_call_id`, `tool_name`, `model`, `termination_reason`, `error_type`.

Required measurement keys:
`duration_ms`, `input_tokens`, `output_tokens`, `total_tokens`, `retry_count`, `queue_ms`.

## Subscribe Example

```elixir
:telemetry.attach(
  "jido-ai-request-complete",
  Jido.AI.Observe.request(:complete),
  fn event, measurements, metadata, _config ->
    IO.inspect({event, measurements.duration_ms, metadata.request_id})
  end,
  nil
)
```

## Telemetry + Signal Example

```elixir
alias Jido.AI.Observe
alias Jido.AI.Signal.RequestStarted

signal =
  RequestStarted.new!(%{
    request_id: "req-42",
    query: "weather in Austin"
  })

metadata =
  Observe.sanitize_sensitive(%{
    request_id: signal.data.request_id,
    agent_id: "weather_agent",
    api_key: "secret"
  })

:ok = Observe.emit(%{emit_telemetry?: true}, Observe.request(:start), %{duration_ms: 0}, metadata)
```

Use `Observe.sanitize_sensitive/1` before attaching user/tool payloads to telemetry metadata.

## Enable/Disable Behavior

- `emit_telemetry?` defaults to `true`; when set to `false`, `Observe.emit/5` and span wrappers become no-ops.
- `emit_llm_deltas?` defaults to `true`; it only applies when emitting with `feature_gate: :llm_deltas`.
- `Observe.start_span/3` returns `:noop` when telemetry is disabled or event prefixes are invalid.

## Failure Mode: Inconsistent Metadata Fields

Symptom:
- dashboards fail because events have inconsistent maps

Fix:
- emit via `Jido.AI.Observe.emit/4`
- keep custom keys additive; do not rely on ad-hoc required fields

## Defaults You Should Know

- telemetry emission defaults on (`emit_telemetry?` true)
- delta telemetry defaults on (`emit_llm_deltas?` true)
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
