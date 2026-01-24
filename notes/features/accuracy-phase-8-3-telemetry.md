# Feature Planning: Telemetry and Observability (Phase 8.3)

## Status

**Status**: Complete
**Created**: 2025-01-15
**Completed**: 2025-01-15
**Branch**: `feature/accuracy-phase-8-3-telemetry`

---

## Problem Statement

The accuracy pipeline (Phase 8.1-8.2) is fully implemented but lacks observability. Without telemetry, it's difficult to:

1. Monitor pipeline performance in production
2. Debug issues when they occur
3. Understand bottlenecks in the pipeline
4. Track token usage and costs
5. Measure quality metrics over time

**Impact**:
- No visibility into pipeline execution
- Difficult to optimize performance
- Cannot track costs accurately
- No historical data for analysis

---

## Solution Overview

Implement comprehensive telemetry using the standard `:telemetry` library. This provides:

1. **Event Emission**: Standard events for pipeline lifecycle
2. **Measurements**: Timing, token usage, quality metrics
3. **Span Support**: Distributed tracing with OpenTelemetry compatibility
4. **Test Coverage**: Attach handlers for testing telemetry

**Key Design Decisions**:
1. Use `:telemetry` library (Elixir standard)
2. Event names follow `[:app, :component, :action, :status]` pattern
3. Measurements include monotonic time for accuracy
4. Metadata includes context for filtering
5. Span creation via `:telemetry_span` for nested operations

---

## Agent Consultations Performed

### Research: Telemetry Library Usage
**Consulted**: Standard Elixir telemetry patterns
**Findings**:
- `:telemetry` is the de-facto standard for Elixir observability
- Events are simple: `{event_name, measurements, metadata}`
- Use `:telemetry.execute/3` to emit events
- Use `:telemetry.attach/4` to handle events
- `:telemetry_span/3` provides automatic start/stop events
- No compile-time dependency on handlers

### Research: OpenTelemetry Integration
**Consulted**: OpenTelemetry Erlang/Ecosystem patterns
**Findings**:
- `:opentelemetry` package can bridge :telemetry to OTLP
- Use `:telemetry` events as source of truth
- Spans created via `:telemetry.attach` handlers in production
- Tests can verify events without OTel dependency

---

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
└── telemetry.ex                 # NEW - Main telemetry module

test/jido_ai/accuracy/
└── telemetry_test.exs           # NEW - Telemetry tests
```

### Dependencies

- **Optional**: `:telemetry` (already in :jido dependencies)
- **Optional**: `:opentelemetry` (for production, not for tests)

### Event Names

| Event Name | When Emitted | Measurements | Metadata |
|------------|--------------|--------------|----------|
| `[:jido, :accuracy, :pipeline, :start]` | Pipeline starts | `%{system_time: integer()}` | query, preset, config |
| `[:jido, :accuracy, :pipeline, :stop]` | Pipeline completes | `%{duration: integer()}` | query, preset, config, result |
| `[:jido, :accuracy, :pipeline, :exception]` | Pipeline errors | `%{duration: integer()}` | query, preset, kind, reason, stacktrace |
| `[:jido, :accuracy, :stage, :start]` | Stage starts | `%{system_time: integer()}` | stage_name, query |
| `[:jido, :accuracy, :stage, :stop]` | Stage completes | `%{duration: integer()}` | stage_name, query, stage_metadata |
| `[:jido, :accuracy, :stage, :exception]` | Stage errors | `%{duration: integer()}` | stage_name, kind, reason |

### Measurements Structure

```elixir
# Timing measurements
%{
  duration: native_time(),      # monotonic time difference
  system_time: system_time()    # system time at event start
}

# Token usage (in metadata for stop events)
%{
  input_tokens: non_neg_integer(),
  output_tokens: non_neg_integer(),
  total_tokens: non_neg_integer()
}

# Quality metrics (in metadata for stop events)
%{
  confidence: float(),
  verification_score: float(),
  num_candidates: pos_integer()
}
```

---

## Success Criteria

1. ✅ Telemetry module created with all event emission functions
2. ✅ Events emitted for pipeline start/stop/exception
3. ✅ Events emitted for stage start/stop/exception
4. ✅ Measurements include timing information
5. ✅ Metadata includes query, config, and results
6. ✅ Span creation helpers provided
7. ✅ All tests pass (minimum 95% coverage)
8. ✅ Test helpers for attaching handlers

---

## Implementation Plan

### Step 1: Create Telemetry Module (8.3.1)

**File**: `lib/jido_ai/accuracy/telemetry.ex`

**Tasks**:
- [ ] 1.1 Create module with @moduledoc explaining telemetry approach
- [ ] 1.2 Define event name constants
- [ ] 1.3 Implement `emit_pipeline_start/2`
- [ ] 1.4 Implement `emit_pipeline_stop/3`
- [ ] 1.5 Implement `emit_pipeline_exception/4`
- [ ] 1.6 Implement `emit_stage_start/3`
- [ ] 1.7 Implement `emit_stage_stop/4`
- [ ] 1.8 Implement `emit_stage_exception/4`

**Code Structure**:
```elixir
defmodule Jido.AI.Accuracy.Telemetry do
  @moduledoc """
  Telemetry for accuracy pipeline operations.
  """

  # Event names
  defp pipeline_start_event, do: [:jido, :accuracy, :pipeline, :start]
  defp pipeline_stop_event, do: [:jido, :accuracy, :pipeline, :stop]
  defp pipeline_exception_event, do: [:jido, :accuracy, :pipeline, :exception]
  defp stage_start_event, do: [:jido, :accuracy, :stage, :start]
  defp stage_stop_event, do: [:jido, :accuracy, :stage, :stop]
  defp stage_exception_event, do: [:jido, :accuracy, :stage, :exception]

  # Emission functions
  def emit_pipeline_start(query, config)
  def emit_pipeline_stop(start_time, query, result)
  def emit_pipeline_exception(start_time, query, kind, reason)
  def emit_stage_start(stage_name, query, context)
  def emit_stage_stop(stage_name, start_time, query, metadata)
  def emit_stage_exception(stage_name, start_time, kind, reason)
end
```

---

### Step 2: Implement Telemetry Measurements (8.3.2)

**File**: `lib/jido_ai/accuracy/telemetry.ex`

**Tasks**:
- [ ] 2.1 Add duration calculation helper
- [ ] 2.2 Add system_time helper
- [ ] 2.3 Include token usage extraction from result metadata
- [ ] 2.4 Include quality metrics extraction from result

**Implementation**:
```elixir
defp measure_duration(start_time) do
  System.monotonic_time() - start_time
end

defp extract_telemetry_metadata(result_or_context) do
  %{
    # Token usage from result metadata
    input_tokens: get_in(result_or_context, [:metadata, :input_tokens]),
    output_tokens: get_in(result_or_context, [:metadata, :output_tokens]),

    # Quality metrics
    confidence: get_in(result_or_context, [:metadata, :confidence]),
    num_candidates: get_in(result_or_context, [:metadata, :num_candidates])
  }
end
```

---

### Step 3: Implement Span Creation (8.3.3)

**File**: `lib/jido_ai/accuracy/telemetry.ex`

**Tasks**:
- [ ] 3.1 Add `pipeline_span/3` helper
- [ ] 3.2 Add `stage_span/3` helper
- [ ] 3.3 Support nested spans
- [ ] 3.4 Include trace context in metadata

**Implementation**:
```elixir
@doc """
Wraps pipeline execution in a telemetry span.
"""
def pipeline_span(query, config, fun) when is_function(fun, 0) do
  metadata = build_pipeline_metadata(query, config)

  :telemetry.span(
    pipeline_start_event(),
    metadata,
    fn ->
      result = fun.()
      {result, build_result_metadata(result)}
    end
  )
end

@doc """
Wraps stage execution in a telemetry span.
"""
def stage_span(stage_name, query, fun) when is_function(fun, 0) do
  metadata = %{stage_name: stage_name, query: query}

  :telemetry.span(
    stage_start_event(),
    metadata,
    fn ->
      result = fun.()
      {result, build_stage_metadata(result)}
    end
  )
end
```

---

### Step 4: Unit Tests (8.3.4)

**File**: `test/jido_ai/accuracy/telemetry_test.exs`

**Test Cases**:
- [ ] 4.1 Test pipeline start event is emitted
- [ ] 4.2 Test pipeline stop event is emitted with duration
- [ ] 4.3 Test pipeline exception event is emitted
- [ ] 4.4 Test stage start event is emitted
- [ ] 4.5 Test stage stop event is emitted with duration
- [ ] 4.6 Test stage exception event is emitted
- [ ] 4.7 Test pipeline_span helper works
- [ ] 4.8 Test stage_span helper works
- [ ] 4.9 Test measurements are accurate
- [ ] 4.10 Test metadata includes expected fields

**Test Helper**:
```elixir
defmodule TelemetryTestHelper do
  def attach_handler(event_name) do
    {:ok, pid} = Agent.start_link(fn -> [] end)
    handler_id = make_ref()

    :telemetry.attach(
      handler_id,
      event_name,
      &handle_event(&1, &2, &3, pid),
      nil
    )

    {handler_id, pid}
  end

  defp handle_event(event, measurements, metadata, collector_pid) do
    Agent.update(collector_pid, fn events ->
      [{event, measurements, metadata} | events]
    end)
  end

  def collect_events(collector_pid) do
    Agent.get(collector_pid, &Enum.reverse/1)
  end
end
```

---

## Current Status

### What Works
- Feature branch created
- Research completed on telemetry patterns
- Planning document created

### What's Next
- Implement Telemetry module with all emission functions
- Write comprehensive unit tests
- Update planning document as implementation progresses

### How to Run Tests
```bash
# Test telemetry module
MIX_ENV=test mix test test/jido_ai/accuracy/telemetry_test.exs

# Test with pipeline
MIX_ENV=test mix test test/jido_ai/accuracy/pipeline_test.exs
```

---

## Notes and Considerations

### Design Decisions
1. **No Handler Implementation**: This module only emits events. Handlers are attached by the application using the pipeline.
2. **Span Support**: Using `:telemetry.span/3` for automatic start/stop events with proper exception handling.
3. **Monotonic Time**: Using `System.monotonic_time()` for duration to avoid system clock adjustments.

### Integration Points
- Pipeline module will call telemetry functions before/after stages
- Each stage will emit start/stop events via span helpers
- Exception handling will emit exception events

### Future Enhancements
1. OpenTelemetry bridge handler for production
2. Metrics aggregation dashboard
3. Alerting on unusual patterns (high latency, low confidence)
4. Cost tracking per query/preset

---

## Implementation Checklist

- [ ] Step 1: Create Telemetry module (8.3.1)
  - [ ] 1.1 Create module with @moduledoc
  - [ ] 1.2 Define event name constants
  - [ ] 1.3 Implement emit_pipeline_start/2
  - [ ] 1.4 Implement emit_pipeline_stop/3
  - [ ] 1.5 Implement emit_pipeline_exception/4
  - [ ] 1.6 Implement emit_stage_start/3
  - [ ] 1.7 Implement emit_stage_stop/4
  - [ ] 1.8 Implement emit_stage_exception/4

- [ ] Step 2: Implement telemetry measurements (8.3.2)
  - [ ] 2.1 Add duration calculation helper
  - [ ] 2.2 Add system_time helper
  - [ ] 2.3 Include token usage extraction
  - [ ] 2.4 Include quality metrics extraction

- [ ] Step 3: Implement span creation (8.3.3)
  - [ ] 3.1 Add pipeline_span/3 helper
  - [ ] 3.2 Add stage_span/3 helper
  - [ ] 3.3 Support nested spans
  - [ ] 3.4 Include trace context in metadata

- [ ] Step 4: Unit tests (8.3.4)
  - [ ] 4.1 Create test file
  - [ ] 4.2 Test pipeline events
  - [ ] 4.3 Test stage events
  - [ ] 4.4 Test span helpers
  - [ ] 4.5 Test measurements accuracy

- [ ] Step 5: Documentation
  - [ ] 5.1 Update feature planning document with ✅
  - [ ] 5.2 Create summary document in notes/summaries/
  - [ ] 5.3 Update phase-08-integration.md plan

---

## References

- **Phase 8 Plan**: `notes/planning/accuracy/phase-08-integration.md`
- **Telemetry Docs**: https://hexdocs.pm/telemetry/
- **OpenTelemetry**: https://opentelemetry.io/
