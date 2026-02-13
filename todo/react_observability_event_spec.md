# ReAct Observability Event Spec

## Event Names
- `[:jido, :ai, :react, :request, :start]`
- `[:jido, :ai, :react, :request, :complete]`
- `[:jido, :ai, :react, :request, :failed]`
- `[:jido, :ai, :react, :request, :rejected]`
- `[:jido, :ai, :react, :request, :cancelled]`
- `[:jido, :ai, :react, :llm, :start]`
- `[:jido, :ai, :react, :llm, :delta]`
- `[:jido, :ai, :react, :llm, :complete]`
- `[:jido, :ai, :react, :llm, :error]`
- `[:jido, :ai, :react, :tool, :start]`
- `[:jido, :ai, :react, :tool, :retry]`
- `[:jido, :ai, :react, :tool, :complete]`
- `[:jido, :ai, :react, :tool, :error]`
- `[:jido, :ai, :react, :tool, :timeout]`

## Required Metadata Keys
- `agent_id`
- `request_id`
- `run_id`
- `iteration`
- `llm_call_id`
- `tool_call_id`
- `tool_name`
- `model`
- `termination_reason`
- `error_type`

## Required Measurement Keys
- `duration_ms`
- `input_tokens`
- `output_tokens`
- `total_tokens`
- `retry_count`
- `queue_ms`

## Tool Error Envelope
```elixir
%{
  type: :timeout | :validation | :executor | :exception | :unknown_tool,
  message: String.t(),
  retryable?: boolean(),
  details: map()
}
```

## Notes
- Metadata and measurements are normalized to include required keys with defaults.
- OpenTelemetry bridge is optional and must be a no-op when OTel libraries are unavailable.
- Tool and LLM telemetry should include request/run correlation IDs whenever available.
