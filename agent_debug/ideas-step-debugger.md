# Jido Agent Step Debugger - Design Analysis and Implementation Strategy

## Executive Summary

This document analyzes the feasibility and design considerations for implementing a step debugger for Jido agents. Based on investigation of existing Elixir debugging tools and the current Jido architecture, we propose a multi-layered debugging system that leverages GenServer suspension, signal queue manipulation, and interactive debugging interfaces.

## Architecture Analysis

### Current Jido Agent Execution Flow

The Jido agent system follows this execution pattern:

1. **Signal Reception**: [`Jido.Agent.Server`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/agent/server.ex) receives signals via `handle_call/3`, `handle_cast/2`, or `handle_info/2`
2. **Signal Queuing**: Signals are enqueued in [`ServerState.pending_signals`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/agent/server_state.ex#L119) using `:queue.in/2`
3. **Queue Processing**: [`ServerRuntime.process_signals_in_queue/1`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/agent/server_runtime.ex#L22) processes signals in `:auto` mode
4. **Signal Execution**: Individual signals are processed through routing, instruction mapping, and agent command execution
5. **State Transitions**: [`ServerState`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/agent/server_state.ex#L73-L74) manages FSM transitions (`:idle`, `:running`, `:paused`, etc.)

### Key Integration Points for Debugging

1. **Mode Control**: The existing [`:step` mode](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/agent/server_runtime.ex#L40-L41) in `ServerRuntime` already pauses after single signal processing
2. **GenServer Suspension**: Standard `:sys.suspend/resume` for process-level control
3. **Signal Queue**: Direct manipulation of the `pending_signals` queue for breakpoint injection
4. **State Inspection**: Existing [`ServerState`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/agent/server_state.ex) provides comprehensive state access

## Implementation Strategy

### 1. Core Debugger Architecture

```elixir
defmodule Jido.Agent.Debugger do
  @moduledoc """
  Interactive step debugger for Jido agents.
  
  Provides breakpoint management, step-by-step execution,
  and state inspection capabilities.
  """
  
  defstruct [
    :agent_pid,
    :mode,
    :breakpoints,
    :current_signal,
    :step_count,
    :session_id,
    :ui_handler
  ]
  
  @type t :: %__MODULE__{
    agent_pid: pid(),
    mode: :attached | :detached | :suspended,
    breakpoints: MapSet.t(breakpoint()),
    current_signal: Jido.Signal.t() | nil,
    step_count: non_neg_integer(),
    session_id: String.t(),
    ui_handler: pid() | nil
  }
  
  @type breakpoint :: %{
    type: :signal_type | :signal_pattern | :state_condition,
    pattern: String.t() | Regex.t() | function(),
    enabled: boolean(),
    hit_count: non_neg_integer()
  }
end
```

### 2. Debugger Modes and Controls

#### Safe Process Suspension with `:sys` Module

```elixir
defmodule Jido.Agent.Debugger.Control do
  @moduledoc """
  Low-level process control using Erlang's :sys module.
  
  Provides safe suspension/resumption that preserves GenServer integrity.
  """
  
  def suspend_agent(agent_pid) do
    case :sys.suspend(agent_pid) do
      :ok -> 
        {:ok, :suspended}
      {:error, reason} -> 
        {:error, {:suspend_failed, reason}}
    end
  end
  
  def resume_agent(agent_pid) do
    case :sys.resume(agent_pid) do
      :ok -> 
        {:ok, :resumed}
      {:error, reason} -> 
        {:error, {:resume_failed, reason}}
    end
  end
  
  def step_agent(agent_pid) do
    with {:ok, :resumed} <- resume_agent(agent_pid),
         # Allow one message to be processed
         :ok <- Process.send_after(self(), {:suspend_agent, agent_pid}, 10) do
      {:ok, :stepped}
    end
  end
  
  def get_agent_state(agent_pid) do
    case :sys.get_state(agent_pid) do
      %ServerState{} = state -> {:ok, state}
      error -> {:error, error}
    end
  end
end
```

#### Enhanced Step Mode Integration

```elixir
# Extend ServerRuntime.process_signals_in_queue/1
defp process_signals_in_queue(%ServerState{mode: :debug} = state) do
  case ServerState.dequeue(state) do
    {:ok, signal, new_state} ->
      # Notify debugger before processing
      :debugger_pre_signal
      |> ServerSignal.event_signal(new_state, %{signal: signal})
      |> ServerOutput.emit(new_state)
      
      # Check for breakpoints
      case check_breakpoints(new_state, signal) do
        :continue ->
          case process_signal(new_state, signal) do
            {:ok, final_state, result} ->
              # Notify debugger after processing
              :debugger_post_signal
              |> ServerSignal.event_signal(final_state, %{signal: signal, result: result})
              |> ServerOutput.emit(final_state)
              
              # Wait for debugger command
              wait_for_debug_command(final_state)
            
            error -> error
          end
        
        :break ->
          # Suspend and wait for debugger
          {:debug_break, new_state, signal}
      end
    
    {:error, :empty_queue} ->
      {:ok, state}
  end
end

defp check_breakpoints(state, signal) do
  case Jido.Agent.Debugger.should_break?(state, signal) do
    true -> :break
    false -> :continue
  end
end
```

### 3. Breakpoint System

```elixir
defmodule Jido.Agent.Debugger.Breakpoints do
  @moduledoc """
  Breakpoint management for Jido agents.
  
  Supports signal-based, pattern-based, and state-condition breakpoints.
  """
  
  def create_signal_breakpoint(signal_type) when is_binary(signal_type) do
    %{
      id: generate_breakpoint_id(),
      type: :signal_type,
      pattern: signal_type,
      enabled: true,
      hit_count: 0,
      created_at: DateTime.utc_now()
    }
  end
  
  def create_pattern_breakpoint(regex_pattern) do
    %{
      id: generate_breakpoint_id(),
      type: :signal_pattern,
      pattern: Regex.compile!(regex_pattern),
      enabled: true,
      hit_count: 0,
      created_at: DateTime.utc_now()
    }
  end
  
  def create_state_breakpoint(condition_fn) when is_function(condition_fn, 1) do
    %{
      id: generate_breakpoint_id(),
      type: :state_condition,
      pattern: condition_fn,
      enabled: true,
      hit_count: 0,
      created_at: DateTime.utc_now()
    }
  end
  
  def should_break?(breakpoints, state, signal) do
    Enum.any?(breakpoints, fn bp ->
      bp.enabled and matches_breakpoint?(bp, state, signal)
    end)
  end
  
  defp matches_breakpoint?(%{type: :signal_type, pattern: pattern}, _state, %Signal{type: type}) do
    pattern == type
  end
  
  defp matches_breakpoint?(%{type: :signal_pattern, pattern: pattern}, _state, %Signal{type: type}) do
    Regex.match?(pattern, type)
  end
  
  defp matches_breakpoint?(%{type: :state_condition, pattern: condition_fn}, state, _signal) do
    condition_fn.(state)
  end
  
  defp generate_breakpoint_id, do: "bp_" <> Jido.Util.generate_id()
end
```

### 4. Interactive Debugging Interface

```elixir
defmodule Jido.Agent.Debugger.REPL do
  @moduledoc """
  Interactive REPL interface for agent debugging.
  
  Provides IEx-integrated debugging commands and state inspection.
  """
  
  def start_debug_session(agent_pid, opts \\ []) do
    case Jido.Agent.Debugger.attach(agent_pid, opts) do
      {:ok, debugger} ->
        IO.puts("🔍 Jido Agent Debugger attached to #{inspect(agent_pid)}")
        IO.puts("Type 'h' for help, 'q' to quit")
        debug_loop(debugger)
      
      {:error, reason} ->
        IO.puts("❌ Failed to attach debugger: #{inspect(reason)}")
    end
  end
  
  defp debug_loop(debugger) do
    command = IO.gets("(jido-debug) ") |> String.trim()
    
    case handle_command(debugger, command) do
      {:continue, new_debugger} ->
        debug_loop(new_debugger)
      
      {:exit, _debugger} ->
        IO.puts("👋 Debugger session ended")
      
      {:error, reason} ->
        IO.puts("❌ Error: #{reason}")
        debug_loop(debugger)
    end
  end
  
  defp handle_command(debugger, "s"), do: step_signal(debugger)
  defp handle_command(debugger, "c"), do: continue_execution(debugger)
  defp handle_command(debugger, "state"), do: show_state(debugger)
  defp handle_command(debugger, "queue"), do: show_queue(debugger)
  defp handle_command(debugger, "bp " <> pattern), do: add_breakpoint(debugger, pattern)
  defp handle_command(debugger, "clear"), do: clear_breakpoints(debugger)
  defp handle_command(debugger, "q"), do: {:exit, debugger}
  defp handle_command(debugger, "h"), do: show_help(debugger)
  defp handle_command(debugger, _), do: invalid_command(debugger)
end
```

## Technical Challenges and Solutions

### 1. Concurrent Signal Processing

**Challenge**: Jido agents may receive multiple signals concurrently, making step debugging complex.

**Solution**: 
- Use `:sys.suspend/2` to halt message processing entirely
- Implement queue manipulation to inject debugging signals
- Provide batch stepping for multiple concurrent signals

```elixir
def step_concurrent_signals(debugger, count \\ 1) do
  with {:ok, state} <- get_agent_state(debugger.agent_pid),
       signals <- preview_next_signals(state, count),
       :ok <- suspend_agent(debugger.agent_pid) do
    
    IO.puts("Next #{count} signals:")
    Enum.each(signals, fn signal ->
      IO.puts("  📨 #{signal.type} - #{signal.id}")
    end)
    
    case IO.gets("Process all? (y/n): ") |> String.trim() do
      "y" -> process_signals_batch(debugger, signals)
      _ -> {:continue, debugger}
    end
  end
end
```

### 2. Breakpoint Precision

**Challenge**: Ensuring breakpoints trigger at the right execution point without race conditions.

**Solution**:
- Integrate breakpoint checking directly into `ServerRuntime.process_signal/2`
- Use atomic operations for breakpoint state management
- Implement conditional breakpoints with state predicates

### 3. State Inspection During Suspension

**Challenge**: Safely inspecting agent state while preserving system integrity.

**Solution**:
- Use `:sys.get_state/1` for read-only state access
- Implement state diffing to show changes between steps
- Provide structured state viewers for complex agent states

```elixir
defmodule Jido.Agent.Debugger.Inspector do
  def diff_states(old_state, new_state) do
    changes = %{
      status: diff_field(old_state.status, new_state.status),
      queue_size: diff_field(:queue.len(old_state.pending_signals), :queue.len(new_state.pending_signals)),
      agent_state: diff_field(old_state.agent.state, new_state.agent.state)
    }
    
    changes
    |> Enum.reject(fn {_key, value} -> value == :unchanged end)
    |> Map.new()
  end
  
  defp diff_field(same, same), do: :unchanged
  defp diff_field(old, new), do: {:changed, old, new}
end
```

## User Experience Design

### 1. Command Interface

```
(jido-debug) s          # Step one signal
(jido-debug) s 5        # Step 5 signals
(jido-debug) c          # Continue execution
(jido-debug) state      # Show current agent state
(jido-debug) queue      # Show pending signal queue
(jido-debug) bp signal_type:instruction  # Breakpoint on signal type
(jido-debug) bp /error/  # Breakpoint on pattern
(jido-debug) clear      # Clear all breakpoints
(jido-debug) trace      # Enable/disable tracing
(jido-debug) q          # Quit debugger
```

### 2. Visual State Representation

```elixir
defmodule Jido.Agent.Debugger.Display do
  def format_agent_state(%ServerState{} = state) do
    """
    🤖 Agent State:
       ID: #{state.agent.id}
       Status: #{status_emoji(state.status)} #{state.status}
       Mode: #{state.mode}
       Queue: #{:queue.len(state.pending_signals)} pending signals
    
    📊 Current Signal:
    #{format_signal(state.current_signal)}
    
    🧠 Agent Internal State:
    #{inspect(state.agent.state, pretty: true, limit: 10)}
    """
  end
  
  defp status_emoji(:idle), do: "💤"
  defp status_emoji(:running), do: "🏃"
  defp status_emoji(:paused), do: "⏸️"
  defp status_emoji(:planning), do: "🤔"
  defp status_emoji(_), do: "❓"
end
```

## Implementation Phases

### Phase 1: Core Infrastructure
- [x] Analyze existing Jido architecture
- [ ] Implement basic debugger attachment/detachment
- [ ] Add `:debug` mode to ServerRuntime
- [ ] Create debugger state management

### Phase 2: Stepping and Control
- [ ] Implement step-by-step execution
- [ ] Add process suspension integration
- [ ] Create signal queue manipulation
- [ ] Build basic REPL interface

### Phase 3: Breakpoints and Inspection
- [ ] Implement breakpoint system
- [ ] Add pattern-based breakpoints
- [ ] Create state inspection tools
- [ ] Build state diffing capabilities

### Phase 4: Advanced Features
- [ ] Add concurrent signal debugging
- [ ] Implement trace logging
- [ ] Create visual debugging interface
- [ ] Add debugging session persistence

## Proof of Concept Code

### Basic Debugger Attachment

```elixir
defmodule Jido.Agent.Debugger do
  use GenServer
  
  def start_debug_session(agent_pid) do
    {:ok, debugger_pid} = GenServer.start_link(__MODULE__, %{agent_pid: agent_pid})
    
    # Put agent in debug mode
    GenServer.call(agent_pid, {:set_mode, :debug})
    
    # Suspend agent for initial inspection
    :sys.suspend(agent_pid)
    
    {:ok, debugger_pid}
  end
  
  def step(debugger_pid) do
    GenServer.call(debugger_pid, :step)
  end
  
  def init(%{agent_pid: agent_pid}) do
    state = %{
      agent_pid: agent_pid,
      breakpoints: MapSet.new(),
      step_count: 0
    }
    
    {:ok, state}
  end
  
  def handle_call(:step, _from, state) do
    # Resume agent for one message processing cycle
    :sys.resume(state.agent_pid)
    
    # Immediately suspend again after allowing one message
    Process.send_after(self(), {:suspend_agent}, 50)
    
    {:reply, :ok, %{state | step_count: state.step_count + 1}}
  end
  
  def handle_info({:suspend_agent}, state) do
    :sys.suspend(state.agent_pid)
    {:noreply, state}
  end
end
```

## Feasibility Assessment

### ✅ Strengths
1. **Existing Foundation**: Jido already has `:step` mode and comprehensive state management
2. **GenServer Integration**: `:sys` module provides robust suspension/resumption
3. **Signal Architecture**: Clean signal-based execution model is debugger-friendly
4. **State Accessibility**: Rich state inspection capabilities already exist

### ⚠️ Challenges
1. **Concurrency Complexity**: Managing multiple concurrent signals during debugging
2. **Performance Impact**: Debugging overhead on production-like workloads
3. **Breakpoint Precision**: Ensuring breakpoints trigger at exact execution points
4. **UI Complexity**: Creating intuitive debugging interface

### 🎯 Recommendations

1. **Start Simple**: Begin with basic stepping and state inspection
2. **Leverage Existing**: Build on current `:step` mode and state management
3. **Incremental Approach**: Implement in phases, validating each step
4. **Developer Experience**: Focus on intuitive commands and clear state visualization

## Conclusion

Implementing a step debugger for Jido agents is **highly feasible** given the existing architecture. The combination of:

- Existing `:step` mode support
- GenServer suspension capabilities via `:sys` module  
- Rich state management and inspection
- Clean signal-based execution model

Provides a solid foundation for a comprehensive debugging solution. The proposed multi-phase implementation approach ensures incremental progress while maintaining system stability.

The debugger would significantly improve developer experience when building and troubleshooting Jido agents, especially for complex signal processing scenarios and state transitions.
