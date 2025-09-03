# Agent Debugging Improvements

## Problem Statement
The current Jido Agent debugging experience is difficult and frustrating. Key issues:
- No end-to-end correlation IDs across signal cascades
- Missing queue visibility and state transitions
- Flat logs with no hierarchy showing signal flow
- Recursive While loops with invisible parameter evolution
- Tool execution paths that are hard to trace
- Interleaved concurrent signal processing logs
- Error propagation loses context across process boundaries

## Core Ideas for Investigation

### 1. Step Debugger for Agents
**Concept**: Interactive debugging where agents can be paused, stepped through signal by signal
- Pause agent execution at signal boundaries
- Step through individual action executions
- Inspect current state, queue, and message history
- Set breakpoints on specific actions or signal types
- REPL-like interface for live agent introspection

**Implementation approaches**:
- GenServer call-based stepping with `:sys.suspend/1`
- Special "debug mode" signal that toggles step-by-step execution
- Interactive terminal UI with keypress controls
- Integration with existing Elixir debugger tools

### 2. Tree Visualization & Structured Display
**Concept**: Visual representation of signal cascades and action hierarchies
- Terminal-based tree rendering of signal flow
- Real-time updating display of agent execution
- Collapsible/expandable nodes for detailed inspection
- Color coding for success/error/pending states

**Implementation approaches**:
- ASCII tree rendering in terminal
- Phoenix LiveView dashboard for web-based visualization
- JSON export format for external visualization tools
- Integration with existing Elixir observer tools

### 3. Enhanced Signal I/O Tracing
**Concept**: Comprehensive tracking of signal flow with correlation IDs
- Trace ID generation and propagation
- Signal genealogy tracking (parent/child relationships)
- Input/output parameter diffing between iterations
- Queue state snapshots at each transition

**Implementation approaches**:
- OpenTelemetry integration with spans and traces
- Custom tracing protocol built into Jido.Agent.Server
- Structured logging with correlation metadata
- Signal middleware for automatic tracing injection

### 4. Telemetry Integration
**Concept**: Rich instrumentation for monitoring and debugging
- Performance metrics for action execution times
- Queue length and processing rate monitoring
- Error rate tracking and categorization
- Custom telemetry events for domain-specific debugging

**Implementation approaches**:
- `:telemetry` events throughout agent lifecycle
- Metrics collection and aggregation
- Integration with existing observability tools
- Custom telemetry handlers for debugging workflows

## Secondary Ideas

### 5. Interactive Agent Console
- Hot-reload agent definitions without restart
- Live configuration changes (log levels, debug modes)
- Real-time queue inspection and manipulation
- Agent state snapshots and restoration

### 6. Replay and Time Travel
- Record all signal interactions for later replay
- Deterministic reproduction of agent behaviors
- State snapshots for rewinding execution
- Differential debugging between runs

### 7. Logging Enhancements
- Structured JSON logging with filtering capabilities
- Log level controls per subsystem (agent vs OTP vs tools)
- Contextual log aggregation by trace ID
- Pretty-printing helpers for complex data structures

### 8. Error Context Preservation
- Error chain tracking across process boundaries
- Automatic context attachment to failures
- Stack trace enhancement with agent-specific info
- Integration with crash dump analysis

## Implementation Strategy

Each idea will be investigated by a dedicated subagent that will:
1. Research existing solutions in Elixir ecosystem
2. Analyze integration points with current Jido architecture
3. Create proof-of-concept implementations
4. Evaluate feasibility and developer experience impact
5. Provide implementation recommendations

Results will be documented in `agent_debug/ideas-{idea}.md` files.

## Success Criteria

The ideal debugging solution should:
- Make signal flow visually comprehensible
- Reduce time to identify root causes of issues
- Enable interactive exploration of agent state
- Scale to complex multi-agent scenarios
- Integrate seamlessly with existing Jido patterns
- Provide both real-time and post-mortem debugging capabilities
