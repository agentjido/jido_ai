# AI Observability Event Spec

## Event Names
- `[:jido, :ai, :request, :start]`
- `[:jido, :ai, :request, :complete]`
- `[:jido, :ai, :request, :failed]`
- `[:jido, :ai, :request, :rejected]`
- `[:jido, :ai, :request, :cancelled]`
- `[:jido, :ai, :llm, :start]`
- `[:jido, :ai, :llm, :delta]`
- `[:jido, :ai, :llm, :complete]`
- `[:jido, :ai, :llm, :error]`
- `[:jido, :ai, :tool, :start]`
- `[:jido, :ai, :tool, :retry]`
- `[:jido, :ai, :tool, :complete]`
- `[:jido, :ai, :tool, :error]`
- `[:jido, :ai, :tool, :timeout]`
- `[:jido, :ai, :strategy, :react, :start]`
- `[:jido, :ai, :strategy, :react, :iteration]`
- `[:jido, :ai, :strategy, :react, :complete]`
- `[:jido, :ai, :strategy, :react, :error]`

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
- Metadata and measurements are normalized in `Jido.AI.Observability.Events`.
- Emission is centralized in `Jido.AI.Observability.Emitter`.
- Request/LLM/tool events are strategy-agnostic and shared across strategies.
