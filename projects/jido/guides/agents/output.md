# Agent Signal Output Guide

## Overview

Agent signal output provides a comprehensive event and error emission system for tracking agent execution, state changes, and instruction results. The output system ensures consistent monitoring and traceability across your agent-based applications.

## Output Types

### 1. Event Signals

Event signals track lifecycle and state transition events within the agent system. Events follow the pattern `jido.agent.event.<category>.<action>`.

Common event categories include:

#### Process Events

```elixir
# Process lifecycle events
"jido.agent.event.process.started"     # Process started successfully
"jido.agent.event.process.terminated"  # Process terminated normally
"jido.agent.event.process.failed"      # Process failed to start/execute
"jido.agent.event.process.restarted"   # Process was restarted
```

#### State Transition Events

```elixir
"jido.agent.event.transition.succeeded"  # State transition completed
"jido.agent.event.transition.failed"     # State transition failed
```

#### Queue Management Events

```elixir
"jido.agent.event.queue.overflow"  # Queue size exceeded maximum
"jido.agent.event.queue.cleared"   # Queue was emptied
```

### 2. Error Signals

Error signals provide detailed error reporting when operations fail. They follow the pattern `jido.agent.err.<category>.<type>`.

```elixir
# Common error signal types
"jido.agent.err.execution.error"    # Runtime execution errors
"jido.agent.err.validation.error"   # State/parameter validation errors
"jido.agent.err.directive.error"    # Directive application errors
```

Error signals include:

- Detailed error message
- Error context and metadata
- Stack trace when available
- Related entity IDs (agent, process, etc.)

### 3. Signal Output

Signal output represents the results of processing incoming signals. These follow the pattern `jido.agent.out.signal.<result>`.

```elixir
# Signal output types
"jido.agent.out.signal.result"     # Final signal processing result
"jido.agent.out.signal.processed"  # Signal successfully processed
"jido.agent.out.signal.rejected"   # Signal rejected/invalid
```

### 4. Instruction Output

Instruction output tracks the execution results of individual instructions. These follow the pattern `jido.agent.out.instruction.<result>`.

```elixir
# Instruction output example
"jido.agent.out.instruction.result"  # Individual instruction result
```

Important: When a signal triggers multiple instructions, each instruction generates its own output signal. This provides granular visibility into the execution flow.

## Output Structure

All output signals contain consistent base fields:

```elixir
%{
  id: "sig_abc123",           # Unique signal ID
  type: "jido.agent.<type>",  # Signal type
  source: "agent:worker_1",   # Signal origin
  subject: "jido://agent/worker_1/abc123",  # Subject URI
  time: "2024-02-11T12:00:00Z",  # ISO 8601 timestamp
  data: %{                    # Signal-specific payload
    result: "success",
    details: %{...}
  }
}
```

### Signal Subject Format

The `subject` field follows a specific URI format for signals emitted by Jido agents:

```elixir
"jido://agent/<agent_name>/<agent_id>"
```

For example:

- Named agent: `"jido://agent/data_processor/abc123"`
- Anonymous agent: `"jido://agent/abc123"` (when no name is specified)

This subject field is automatically set by the agent when emitting signals, ensuring consistent identification and routing. The agent's name and ID are preserved across all signals it emits, making it easier to:

- Track signal chains through the system
- Filter and route signals by agent
- Associate related events and outputs
- Debug issues across distributed deployments

## Example Flow

Here's how different output types work together during execution:

```elixir
# 1. Agent receives signal with multiple instructions
signal = %Signal{
  type: "process.data",
  data: %{items: [1, 2, 3]}
}

# 2. Event signals emitted for processing
"jido.agent.event.started"              # Agent starts processing
"jido.agent.event.transition.succeeded" # State transition to :running

# 3. Individual instruction outputs
"jido.agent.out.instruction.result"     # ValidateData result
"jido.agent.out.instruction.result"     # ProcessItems result
"jido.agent.out.instruction.result"     # SaveResults result

# 4. Final signal output
"jido.agent.out.signal.result"          # Overall processing result

# 5. Completion events
"jido.agent.event.transition.succeeded" # State transition to :idle
```

## Best Practices

### 1. Output Handling

- Subscribe to relevant output types based on monitoring needs
- Implement proper error handling for each output type
- Consider output persistence for audit trails
- Use structured logging for output signals

### 2. Signal Design

- Keep payloads focused and relevant
- Include necessary context in metadata
- Use consistent naming conventions
- Follow type-specific patterns

### 3. Monitoring

- Track error rates by type
- Monitor queue sizes and overflow events
- Alert on critical state transitions
- Analyze instruction completion patterns
- Set up dashboards for key metrics

### 4. Error Handling

```elixir
# Implement comprehensive error handling
case handle_signal(signal) do
  {:ok, result} ->
    # Normal output handling
    emit_output("jido.agent.out.signal.result", result)

  {:error, reason} ->
    # Error output handling
    emit_error("jido.agent.err.execution.error", %{
      reason: reason,
      signal_id: signal.id,
      context: get_error_context()
    })
end
```

## Testing Output

```elixir
defmodule OutputTest do
  use ExUnit.Case

  test "emits instruction results" do
    {:ok, agent} = MyAgent.new()

    # Execute multi-instruction signal
    {:ok, _result} = MyAgent.process([
      ValidateAction,
      ProcessAction,
      SaveAction
    ])

    # Assert output signals
    assert_receive {:signal, %{type: "jido.agent.out.instruction.result"}}
    assert_receive {:signal, %{type: "jido.agent.out.instruction.result"}}
    assert_receive {:signal, %{type: "jido.agent.out.instruction.result"}}
  end

  test "handles errors appropriately" do
    {:ok, agent} = MyAgent.new()

    # Trigger error condition
    {:error, _reason} = MyAgent.process(InvalidAction)

    # Assert error output
    assert_receive {:signal, %{
      type: "jido.agent.err.execution.error",
      data: %{reason: :invalid_action}
    }}
  end
end
```

## See Also

- [Signal Overview](../signals/overview.livemd)
- [Signal Testing](../signals/testing.md)
- [Agent Testing](../signals/testing.md)
- [Signal Dispatching](../signals/dispatching.md)
