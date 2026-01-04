# Phase 4.1 ReAct Strategy Enhancements

**Branch**: `feature/phase4-react-enhancements`
**Status**: Complete
**Created**: 2026-01-04
**Completed**: 2026-01-04

## Problem Statement

The existing ReAct strategy is functional but lacks several features needed for production use:
1. No model alias support - must use full model specs instead of `:fast`, `:capable`
2. No usage metadata extraction - can't track token counts from LLM responses
3. No telemetry for iteration tracking - hard to monitor agent performance
4. No dynamic tool registration - tools must be passed at init time

## Solution Overview

Enhance the existing ReAct strategy with:
1. Model alias resolution via `Jido.AI.Config.resolve_model/1`
2. Usage metadata extraction and storage in machine state
3. Telemetry emission for start/stop/iteration events
4. Dynamic tool registration via Phase 2 Registry integration

---

## Implementation Plan

### Phase 1: Model Alias Support

- [x] 1.1 Update `build_config/2` to resolve model aliases
- [x] 1.2 Handle both atom aliases and string specs
- [x] 1.3 Add tests for model alias resolution

### Phase 2: Usage Metadata Extraction

- [x] 2.1 Update Machine to store usage metadata in state
- [x] 2.2 Extract usage from LLM result in `handle_llm_response/3`
- [x] 2.3 Include usage in snapshot details
- [x] 2.4 Add tests for usage extraction

### Phase 3: Telemetry Integration

- [x] 3.1 Define telemetry events:
  - `[:jido, :ai, :react, :start]` - Conversation started
  - `[:jido, :ai, :react, :iteration]` - Iteration completed
  - `[:jido, :ai, :react, :complete]` - Conversation complete
- [x] 3.2 Emit telemetry from Machine on state transitions
- [x] 3.3 Include metadata: iteration, status, duration, usage
- [x] 3.4 Add tests for telemetry emission

### Phase 4: Dynamic Tool Registration

- [x] 4.1 Add `register_tool/2` and `unregister_tool/2` instructions
- [x] 4.2 Update config to support Registry-based tool lookup (`use_registry` option)
- [x] 4.3 Merge static and dynamic tools in `lift_directives/2`
- [x] 4.4 Add tests for dynamic tool registration

---

## Success Criteria

1. [x] Model aliases resolve to full specs
2. [x] Usage metadata available in agent state
3. [x] Telemetry events emitted for monitoring
4. [x] Tools can be added/removed at runtime
5. [x] All tests pass (612 tests, 0 failures)

## Current Status

**What Works**: All enhancements implemented and tested
**Completed**: 2026-01-04
**How to Run**: `mix test test/jido_ai/react/ test/jido_ai/strategy/`

---

## Changes Made

### Modified Files
- `lib/jido_ai/strategy/react.ex` - Strategy enhancements (model alias, tool registration, use_registry)
- `lib/jido_ai/react/machine.ex` - Machine state updates (usage, started_at, telemetry)

### New Files
- `test/jido_ai/react/machine_test.exs` - Machine unit tests (21 tests)
- `test/jido_ai/strategy/react_test.exs` - Strategy integration tests (24 tests)

---

## Key Features Added

### Model Alias Support

```elixir
# Now you can use aliases
use Jido.Agent,
  strategy: {Jido.AI.Strategy.ReAct,
    tools: [MyTool],
    model: :fast  # Resolves to "anthropic:claude-haiku-4-5"
  }
```

### Usage Metadata

Usage is automatically extracted from LLM responses and accumulated:

```elixir
snapshot = ReAct.snapshot(agent, %{})
snapshot.details[:usage]
# => %{input_tokens: 150, output_tokens: 75}
```

### Telemetry Events

```elixir
# Events emitted:
[:jido, :ai, :react, :start]     # When conversation starts
[:jido, :ai, :react, :iteration] # After each iteration
[:jido, :ai, :react, :complete]  # When conversation completes

# Attach handler:
:telemetry.attach("my-handler", [:jido, :ai, :react, :complete], fn _, measurements, metadata, _ ->
  IO.inspect({measurements.duration, metadata.usage})
end, nil)
```

### Dynamic Tool Registration

```elixir
# Register tool at runtime
instruction = %Jido.Instruction{
  action: :react_register_tool,
  params: %{tool_module: MyNewTool}
}
{agent, _} = ReAct.cmd(agent, [instruction], %{})

# Unregister tool
instruction = %Jido.Instruction{
  action: :react_unregister_tool,
  params: %{tool_name: "my_tool"}
}
{agent, _} = ReAct.cmd(agent, [instruction], %{})

# List current tools
ReAct.list_tools(agent)
```
