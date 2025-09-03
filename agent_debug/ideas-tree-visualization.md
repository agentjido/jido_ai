# Tree Visualization for Jido Agent Execution Flow

## Executive Summary

This document outlines a comprehensive approach for implementing tree visualization of Jido agent execution flow, building on the existing signal cascade system and telemetry infrastructure. The proposed solution leverages ASCII/Unicode tree rendering with color coding for real-time and post-mortem execution analysis.

## Research Findings

### Existing Elixir Tree Libraries
Current searches reveal limited specialized Elixir tree visualization libraries. Most solutions rely on:
- Custom ASCII art generation using box-drawing Unicode characters (`├`, `└`, `│`, `─`)
- Terminal escape sequences for colors (ANSI codes)
- Manual tree structure traversal and formatting

Popular approaches in other languages:
- **Rust**: `tree-view` crate with TUI support
- **JavaScript**: Various NPM packages for terminal tree rendering
- **Python**: `anytree` with ASCII rendering capabilities

**Recommendation**: Build custom Elixir tree renderer using Unicode box-drawing characters and ANSI color codes.

## Architecture Analysis

### Current Execution Flow Structure

From codebase analysis, Jido has excellent hierarchical execution tracking:

#### 1. Signal Cascade System
- **Journal**: [`projects/jido_signal/lib/jido_signal/journal.ex`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido_signal/lib/jido_signal/journal.ex)
  - Tracks causal relationships between signals
  - `trace_chain/3` follows complete causal chains forward/backward
  - `get_effects/2` and `get_cause/2` provide parent-child relationships
  - Prevents cycles and maintains temporal ordering

#### 2. Agent Runtime Processing
- **Server Runtime**: [`projects/jido/lib/jido/agent/server_runtime.ex`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/agent/server_runtime.ex)
  - Sequential signal processing with queue management
  - Nested instruction execution with state tracking
  - Reply reference tracking for async operations

#### 3. Middleware Pipeline
- **Bus Middleware**: [`projects/jido_signal/lib/jido_signal/bus/middleware_pipeline.ex`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido_signal/bus/middleware_pipeline.ex)
  - Before/after hooks for signal transformation
  - Cascading middleware execution chains
  - Context preservation across pipeline stages

#### 4. Telemetry Integration
- **Core Telemetry**: [`projects/jido/lib/jido/telemetry.ex`](file:///Users/mhostetler/Source/Jido/jido_workspace/projects/jido/lib/jido/telemetry.ex)
  - Operation span tracking with start/stop/exception events
  - Duration measurements and metadata collection
  - Existing `:telemetry.execute/3` integration points

## Tree Structure Design

### Hierarchical Representation

```
Agent Execution Tree Structure:

Root Agent
├─ Initial Signal [type:start] ⚡ 150ms
│  ├─ Action: LoadConfig [status:success] ✅ 45ms
│  └─ Action: InitState [status:success] ✅ 32ms
├─ Request Signal [type:http_request] 🌐 2.3s
│  ├─ Middleware Pipeline
│  │  ├─ Auth Validator [status:success] ✅ 12ms
│  │  ├─ Rate Limiter [status:success] ✅ 8ms
│  │  └─ Request Parser [status:success] ✅ 15ms
│  ├─ Action: ProcessRequest [status:running] ⏳ 1.8s...
│  │  ├─ Sub-Action: ValidateInput [status:success] ✅ 23ms
│  │  ├─ Sub-Action: DatabaseQuery [status:success] ✅ 156ms
│  │  └─ Sub-Action: FormatResponse [status:pending] ⏸️
│  └─ Response Signal [type:http_response] [status:pending] ⏸️
└─ Error Signal [type:timeout] ❌ 0ms
   └─ Action: HandleTimeout [status:failed] ❌ 5ms
```

### Node Types and Visual Indicators

#### Node Categories
1. **Signals**: Primary execution triggers
2. **Actions**: Discrete operations or tasks
3. **Middleware**: Cross-cutting concerns
4. **Sub-processes**: Nested execution contexts
5. **Errors**: Exception handling flows

#### Status Indicators
- ✅ Success (green)
- ❌ Error/Failed (red) 
- ⏳ Running (yellow/amber)
- ⏸️ Pending/Waiting (blue)
- ⏹️ Stopped/Cancelled (gray)
- ⚡ Signal events (cyan)
- 🌐 External interactions (magenta)

#### Timing Information
- Duration for completed operations: `150ms`
- Running time for active operations: `1.8s...`
- Start timestamps (optional): `[14:32:15]`

## Implementation Strategy

### Core Components

#### 1. Tree Data Structure
```elixir
defmodule Jido.Visualization.Tree do
  @moduledoc "Tree node structure for execution flow visualization"
  
  defstruct [
    :id,
    :type,           # :signal | :action | :middleware | :error
    :name,
    :status,         # :success | :error | :running | :pending | :stopped  
    :duration,       # in milliseconds
    :started_at,     # DateTime
    :metadata,       # Additional context
    :children,       # [Tree.t()]
    :parent_id       # Reference to parent node
  ]
end
```

#### 2. Tree Builder
```elixir
defmodule Jido.Visualization.TreeBuilder do
  @moduledoc "Builds execution trees from signal journal data"
  
  def build_tree(journal, root_signal_id, opts \\ []) do
    # Traverse journal using trace_chain and get_effects
    # Build hierarchical tree structure
    # Apply filters and transformations
  end
  
  def build_live_tree(agent_pid, opts \\ []) do
    # Connect to agent telemetry stream
    # Build incremental tree updates
  end
end
```

#### 3. ASCII Renderer
```elixir
defmodule Jido.Visualization.TreeRenderer do
  @moduledoc "Renders trees as ASCII art with colors"
  
  @box_chars %{
    vertical: "│",
    horizontal: "─", 
    branch: "├",
    last_branch: "└",
    continuation: "│  ",
    spacing: "   "
  }
  
  def render(tree, opts \\ []) do
    # Recursive tree traversal
    # Apply box-drawing characters
    # Add ANSI color codes
    # Format timing and metadata
  end
  
  def render_compact(tree, max_depth \\ 10) do
    # Collapsed view for large trees
    # Show only critical path
    # Expandable sections
  end
end
```

#### 4. Live Update System
```elixir
defmodule Jido.Visualization.LiveRenderer do
  use GenServer
  
  # Subscribe to agent telemetry events
  # Maintain current tree state
  # Stream updates to terminal/web interface
  # Handle real-time tree expansion
end
```

### Integration Points

#### 1. Telemetry Events
Extend existing telemetry with tree-specific events:
```elixir
# In agent execution
:telemetry.execute(
  [:jido, :tree, :node_start],
  %{system_time: System.system_time()},
  %{
    node_id: signal.id,
    parent_id: cause_signal_id,
    type: :signal,
    name: signal.type,
    metadata: %{...}
  }
)
```

#### 2. Journal Integration
Extend the existing journal with tree-aware queries:
```elixir
defmodule Jido.Signal.Journal do
  def get_execution_tree(journal, root_signal_id, opts \\ []) do
    # Build tree from causal relationships
    # Include timing and status information
    # Apply depth/breadth limits
  end
end
```

#### 3. Agent Server Integration
Add tree visualization endpoints to agent server:
```elixir
# In agent GenServer
def handle_call({:get_execution_tree, opts}, _from, state) do
  tree = TreeBuilder.build_live_tree(self(), opts)
  {:reply, {:ok, tree}, state}
end
```

## Display Options

### Terminal-Based Visualization

#### Advantages
- ✅ Low latency, immediate feedback
- ✅ Works in any terminal environment
- ✅ Suitable for debugging and development
- ✅ Easy integration with existing tools

#### Implementation
- Use ANSI escape sequences for colors
- Unicode box-drawing characters for structure
- Cursor positioning for live updates
- Terminal size detection for responsive layout

#### Example Terminal Output
```
Jido Agent Execution [PID: <0.123.45>] - Live View                    [14:32:18]
─────────────────────────────────────────────────────────────────────────────────
└─ 🚀 Agent Start [signal:init] ✅ 45ms                            [14:32:15.123]
   ├─ ⚙️  LoadConfig [action:config] ✅ 12ms                       [14:32:15.145]
   ├─ 📊 InitTelemetry [action:telemetry] ✅ 8ms                   [14:32:15.157]
   └─ 🌐 HTTP Request [signal:http] ⏳ 1.2s...                     [14:32:16.890]
      ├─ 🔐 Auth Check [middleware:auth] ✅ 23ms                   [14:32:16.913]
      ├─ 🔄 Rate Limit [middleware:rate] ✅ 5ms                    [14:32:16.936]
      └─ 📋 Process Request [action:handler] ⏳ 856ms...           [14:32:16.941]
         ├─ ✓ Validate Input ✅ 34ms                              [14:32:16.975]
         └─ 🗄️  Database Query ⏳ 422ms...                         [14:32:17.009]

[q]uit [r]efresh [f]ilter [e]xpand [c]ollapse                         Auto-refresh: ON
```

### Web-Based Dashboard

#### Advantages
- ✅ Rich interactive features
- ✅ Better visual hierarchy representation
- ✅ Suitable for monitoring and operations
- ✅ Shareable views and permalinks

#### Implementation
- Phoenix LiveView for real-time updates
- D3.js or similar for interactive tree rendering
- WebSocket connection for live data streaming
- Responsive design for different screen sizes

#### Features
- Expandable/collapsible tree nodes
- Zoom and pan for large execution trees
- Filter by status, type, or time range
- Historical playback of execution flows
- Export capabilities (PNG, PDF, JSON)

## Performance Considerations

### Real-Time Visualization

#### Challenges
- High-frequency telemetry events can overwhelm rendering
- Large execution trees may impact performance
- Terminal refresh rates and screen buffer limitations

#### Solutions
1. **Event Batching**: Collect events in time windows (100ms-1s)
2. **Tree Pruning**: Limit depth and node count with configurable thresholds
3. **Differential Updates**: Only render changed portions of the tree
4. **Lazy Loading**: Load tree sections on-demand for deep hierarchies
5. **Sampling**: For high-throughput scenarios, sample subset of executions

#### Configurable Limits
```elixir
config :jido_visualization,
  max_tree_depth: 15,
  max_nodes_per_level: 50,
  refresh_interval_ms: 250,
  history_retention_minutes: 60,
  auto_prune_threshold: 1000
```

### Memory Management
- Implement LRU cache for historical trees
- Periodic cleanup of completed execution trees
- Configurable retention policies
- Memory usage monitoring and alerts

## Integration with Existing Systems

### Logging Enhancement
Extend existing logger middleware to include tree context:
```elixir
# In jido_signal/lib/jido_signal/bus/middleware/logger.ex
def before_dispatch(signal, subscriber, context, state) do
  tree_context = %{
    tree_id: get_tree_id(context),
    parent_node: get_parent_node(signal),
    depth: calculate_depth(signal)
  }
  
  # Enhanced logging with tree position
  Logger.info("Dispatching signal", 
    signal: signal.type,
    tree_context: tree_context
  )
end
```

### Debug Integration
Connect with existing debug utilities in Sparq:
```elixir
# In sparq/lib/sparq/debug.ex
def watch_execution_tree(agent_pid, opts \\ []) do
  # Subscribe to agent tree events
  # Show tree updates in debug console
  # Set breakpoints on specific tree nodes
end
```

### Mix Tasks
Add convenient Mix tasks for tree visualization:
```elixir
# mix jido.tree --agent <pid> --live
# mix jido.tree --journal <file> --root-signal <id>
# mix jido.tree --export <format> --output <file>
```

## Proof of Concept Implementation

### Phase 1: Basic Tree Renderer
```elixir
defmodule Jido.Visualization.ProofOfConcept do
  @moduledoc "Basic proof of concept for tree visualization"
  
  def demo_tree do
    %Jido.Visualization.Tree{
      id: "root",
      type: :signal,
      name: "Agent Start",
      status: :success,
      duration: 150,
      children: [
        %Jido.Visualization.Tree{
          id: "config",
          type: :action,
          name: "Load Config", 
          status: :success,
          duration: 45,
          children: []
        },
        %Jido.Visualization.Tree{
          id: "request",
          type: :signal,
          name: "HTTP Request",
          status: :running,
          duration: 1200,
          children: [
            %Jido.Visualization.Tree{
              id: "auth",
              type: :middleware,
              name: "Auth Check",
              status: :success,
              duration: 23,
              children: []
            }
          ]
        }
      ]
    }
  end
  
  def render_demo do
    demo_tree()
    |> Jido.Visualization.TreeRenderer.render()
    |> IO.puts()
  end
end
```

### Phase 2: Live Integration
1. Add telemetry hooks to existing agent execution
2. Implement basic tree builder using journal data
3. Create simple terminal renderer with colors
4. Test with real agent scenarios

### Phase 3: Advanced Features
1. Web dashboard with Phoenix LiveView
2. Historical playback and analysis
3. Performance optimizations
4. Export and sharing capabilities

## Usage Examples

### Development Workflow
```elixir
# Start agent with tree visualization
iex> {:ok, agent} = Jido.Agent.start_link()
iex> Jido.Visualization.watch_agent(agent, live: true)

# View specific execution tree
iex> Jido.Visualization.show_tree(agent, root_signal: "signal-123")

# Export execution history
iex> Jido.Visualization.export_tree(agent, format: :json, file: "execution.json")
```

### Debugging Scenarios
```elixir
# Find slow operations
iex> Jido.Visualization.find_slow_paths(agent, min_duration: 500)

# Trace error propagation
iex> Jido.Visualization.trace_errors(agent, from: ~U[2023-12-01 10:00:00Z])

# Monitor real-time execution
iex> Jido.Visualization.monitor(agent, 
      filter: %{types: [:action, :signal]}, 
      auto_refresh: true)
```

## Recommendations

### Implementation Priority
1. **High Priority**: Basic ASCII tree renderer with journal integration
2. **Medium Priority**: Real-time telemetry integration and live updates  
3. **Low Priority**: Web dashboard and advanced interactive features

### Technical Approach
- Start with post-mortem analysis using existing journal data
- Build incremental real-time capabilities
- Focus on developer experience and debugging workflows
- Consider performance implications early

### Integration Strategy  
- Leverage existing telemetry infrastructure
- Extend journal system with tree-aware queries
- Add optional tree visualization to existing workflows
- Maintain backward compatibility

This comprehensive approach provides a solid foundation for implementing tree visualization in the Jido ecosystem, building on existing strengths while adding powerful new debugging and monitoring capabilities.
