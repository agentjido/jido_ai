# Multi-Turn Conversation Support for Jido AI Agents

## Executive Summary

This report analyzes the multi-turn conversation capabilities of the Jido AI ReAct agent system, using the WeatherAgent as a reference implementation. It identifies gaps in the current architecture, critiques the developer experience (DevEx), and proposes a clean design for robust multi-turn support.

**Status Update (Current)**: The Thread abstraction has been implemented:
- ✅ **`Jido.AI.Thread`** - Minimal conversation accumulator integrated into ReAct machine
- ✅ **`Jido.Thread`** - Provider-agnostic append-only log in core Jido (separate concern)
- ✅ **TUI Fix** - CLI now keeps agent process alive across queries
- ⏳ **Still Pending** - Thread ID routing, persistence, session-level usage, context pruning

**Original Finding** (now partially resolved): Multi-turn conversations *intentionally* work via `Jido.AI.Thread` in the ReAct machine. The TUI has been fixed to keep the agent alive.

---

## Table of Contents

1. [Current Architecture Analysis](#1-current-architecture-analysis)
2. [Thread Abstraction (Implemented)](#2-thread-abstraction-implemented)
3. [How Multi-Turn Works](#3-how-multi-turn-works)
4. [Context Management Deep Dive](#4-context-management-deep-dive)
5. [DevEx Analysis](#5-devex-analysis)
6. [Remaining Gaps](#6-remaining-gaps)
7. [Implementation Roadmap](#7-implementation-roadmap)

---

## 1. Current Architecture Analysis

### 1.1 ReAct Agent Stack

```
┌─────────────────────────────────────────────────────────────────┐
│                         User Code                                │
│                   WeatherAgent.ask(pid, query)                   │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ReActAgent Macro                            │
│   - ask/2,3 → RequestTracking.create_and_send                   │
│   - await/1,2 → RequestTracking.await                           │
│   - on_before_cmd, on_after_cmd hooks                           │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ReAct Strategy                                │
│   - signal_routes: user_query → :react_start                    │
│   - process/3: converts actions to Machine messages             │
│   - lifts Machine directives to SDK directive structs           │
│   - manages tool_context (base + run-scoped)                    │
└─────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                    ReAct Machine (Pure FSM)                      │
│   States: idle → awaiting_llm ⇄ awaiting_tool → completed/error │
│   Stores: thread (Jido.AI.Thread), pending_tool_calls[], usage{}│
│   Emits: telemetry events [:jido, :ai, :react, *]               │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 State Storage Hierarchy

| Layer | What's Stored | Lifetime |
|-------|--------------|----------|
| `agent.state` | Model, requests map, last_answer, completed | Agent process |
| `agent.state.__strategy__` | Machine state (thread, usage, iteration, etc.) | Agent process |
| `Machine` struct | Pure execution state with `Jido.AI.Thread` | Per update cycle |
| `RequestTracking` | Per-request metadata (query, status, timestamps, result) | Request lifetime |

### 1.3 Key Files

| File | Responsibility |
|------|---------------|
| `lib/jido_ai/thread.ex` | **NEW**: Conversation thread accumulator |
| `lib/jido_ai/agents/react_agent.ex` | Macro defining ask/await API and hooks |
| `lib/jido_ai/strategies/react.ex` | Strategy implementation, signal routing, config |
| `lib/jido_ai/strategies/react/machine.ex` | Pure state machine with Thread-based conversation |
| `lib/jido_ai/request_tracking.ex` | Request struct and await/polling logic |
| `lib/jido_ai/cli/tui.ex` | Terminal UI for interactive queries (keeps agent alive) |
| `lib/jido_ai/cli/adapters/react.ex` | CLI adapter: start/submit/await/stop agent |

---

## 2. Thread Abstraction (Implemented)

### 2.1 Two Thread Modules

The Jido ecosystem now has two complementary Thread abstractions:

#### `Jido.AI.Thread` (AI-specific, in jido_ai)

Minimal conversation accumulator that projects directly to ReqLLM message format:

```elixir
defmodule Jido.AI.Thread do
  @type t :: %__MODULE__{
    id: String.t(),
    entries: [Entry.t()],
    system_prompt: String.t() | nil
  }
end

defmodule Jido.AI.Thread.Entry do
  @type t :: %__MODULE__{
    role: :user | :assistant | :tool | :system,
    content: String.t() | nil,
    tool_calls: list() | nil,
    tool_call_id: String.t() | nil,
    name: String.t() | nil,
    timestamp: DateTime.t() | nil
  }
end
```

**Key API**:
- `new(system_prompt: "...")` - Create thread with system prompt
- `append_user/2`, `append_assistant/3`, `append_tool_result/4` - Add messages
- `to_messages/2` - Project to ReqLLM format (supports `limit:` option)
- `length/1`, `empty?/1`, `last_entry/1`, `last_assistant_content/1`

#### `Jido.Thread` (Core, in jido)

Provider-agnostic append-only event log with richer metadata:

```elixir
defmodule Jido.Thread do
  @type t :: %__MODULE__{
    id: String.t(),
    rev: non_neg_integer(),      # Monotonic revision
    entries: [Entry.t()],
    created_at: integer(),
    updated_at: integer(),
    metadata: map(),
    stats: %{entry_count: non_neg_integer()}
  }
end
```

**Design Note**: `Jido.Thread` is the canonical "what happened" log. LLM context is derived via projection functions, not stored directly. The AI-specific `Jido.AI.Thread` is the projection layer.

### 2.2 Integration with ReAct Machine

The ReAct machine now stores conversation state in `Jido.AI.Thread`:

```elixir
# In machine.ex
defstruct [
  # ...
  thread: nil,  # Jido.AI.Thread.t()
  # ...
]

# Fresh start - create new thread
def update(%{status: "idle"} = machine, {:start, query, call_id}, env) do
  thread = Thread.new(system_prompt: system_prompt)
           |> Thread.append_user(query)
  do_start_with_thread(machine, thread, call_id)
end

# Continue - append to existing thread
def update(%{status: status} = machine, {:start, query, call_id}, env)
    when status in ["completed", "error"] do
  thread = Thread.append_user(machine.thread, query)
  do_start_with_thread(machine, thread, call_id)
end
```

---

## 3. How Multi-Turn Works

### 3.1 Multi-Turn Is Now Intentional

The Machine explicitly supports conversation continuation via the Thread:

```elixir
# LLM context is always derived from the thread
messages = Thread.to_messages(thread)
{:call_llm_stream, call_id, messages}
```

**Result**: If you keep the same agent process alive, each `ask/2` after the first automatically continues with full conversation history.

### 3.2 TUI Now Keeps Agent Alive (Fixed)

The TUI has been updated to maintain the agent process:

```elixir
# Agent started once and reused
defstruct [
  # ...
  :agent_pid,  # Persists across queries
  # ...
]

# Agent only stopped on quit or explicit reset (Ctrl+R)
```

**Result**: Multi-turn now works correctly in the CLI/TUI.

### 3.3 Current Behavior

| What User Sees | What Actually Happens |
|---------------|----------------------|
| Continuous chat interface | Same agent, conversation accumulates in Thread |
| "You: What's the weather in Seattle?" <br> "Agent: It's 52°F..." <br> "You: What about tomorrow?" | Thread contains both turns, LLM sees full context ✓ |

---

## 4. Context Management Deep Dive

### 4.1 Thread Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                       THREAD LIFECYCLE                           │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ask("What's the weather in Seattle?")                          │
│    ├─ Machine status: idle → awaiting_llm                       │
│    ├─ Thread.new(system_prompt: "...") |> Thread.append_user()  │
│    │                                                             │
│    ├─ LLM requests tool: weather_by_location                    │
│    │   └─ Thread.append_assistant(nil, tool_calls)              │
│    │                                                             │
│    ├─ Tool executes, returns result                             │
│    │   └─ Thread.append_tool_result(id, name, content)          │
│    │                                                             │
│    ├─ LLM gives final answer                                    │
│    │   └─ Thread.append_assistant(answer, nil)                  │
│    │                                                             │
│    └─ Machine status: completed                                 │
│       Thread.to_messages() → [sys, user, asst, tool, asst]      │
│                                                                  │
│  ask("What about tomorrow?")  [SAME AGENT PROCESS]              │
│    ├─ Machine status: completed → awaiting_llm                  │
│    ├─ Thread.append_user(query) on existing thread              │
│    │   ↑ FULL HISTORY PRESERVED IN THREAD                       │
│    └─ LLM has context: knows "Seattle" from prior turn ✓        │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 4.2 Token Usage Handling

Current behavior per-turn (in `do_start_with_thread/3`):
```elixir
|> Map.put(:usage, %{})  # <-- RESETS USAGE EACH TURN
```

Accumulation happens only within a single turn (multiple LLM calls during tool loops):
```elixir
defp accumulate_usage(machine, result) do
  case Map.get(result, :usage) do
    nil -> machine
    new_usage when is_map(new_usage) ->
      merged = Map.merge(machine.usage, new_usage, fn _k, v1, v2 ->
        (v1 || 0) + (v2 || 0)
      end)
      %{machine | usage: merged}
  end
end
```

**Remaining Gap**: No session-level token accumulation in agent state. The TUI tracks `total_usage` locally in UI state, but this is not part of the Thread abstraction.

### 4.3 Context Size Visibility

Thread now provides basic introspection:
```elixir
Thread.length(thread)           # Entry count
Thread.empty?(thread)           # Boolean check
Thread.last_entry(thread)       # Most recent entry
Thread.last_assistant_content/1 # Last assistant response
Thread.to_messages(thread, limit: 10)  # Manual windowing
```

**Remaining Gaps**:
- No `char_count` or token estimation
- No `session_usage_total` stored in Thread
- No automatic context pruning/warning when approaching limits

---

## 5. DevEx Analysis

### 5.1 Available Lifecycle Hooks

| Hook | Location | Current Use | Future Potential |
|------|----------|-------------|---------------------|
| `on_before_cmd/2` | ReActAgent | Request tracking | Thread ID routing |
| `on_after_cmd/3` | ReActAgent | Request completion | Thread persistence trigger |
| `Strategy.process/3` | ReAct Strategy | Machine update | Multi-thread management |
| Machine telemetry | Machine | `:start/:complete/:iteration` | Session metrics |

### 5.2 Current Signal Flow

```
User calls ask(pid, "Question 2")
    │
    ▼
Signal: react.input
  payload: %{query: "Question 2", request_id: "req-abc"}
    │
    ▼
Strategy routes to :react_start
    │
    ├─ Machine.update with {:start, query, call_id}
    │   └─ status "completed" → do_start_continue (appends to thread)
    │
    ▼
[... ReAct loop with tool calls ...]
    │
    ▼
Machine reaches :completed
    └─ Thread stored in __strategy__ state (in-memory)
```

### 5.3 Future: Thread ID Routing (Not Yet Implemented)

```
User calls ask(pid, "Question 2", thread_id: "chat-123")
    │
    ▼
Signal: react.input
  payload: %{query: "Question 2", request_id: "req-abc", thread_id: "chat-123"}
    │
    ▼
Strategy routes to :react_start
    │
    ├─ Load thread "chat-123" from thread registry/store
    ├─ Initialize machine with loaded thread
    ├─ Run Machine.update with {:start, query, call_id}
    │
    ▼
Machine reaches :completed
    │
    ├─ Save thread "chat-123" back to registry/store
    └─ Emit result signal
```

### 5.4 Telemetry Events

| Event | Data | Notes |
|-------|------|-------|
| `[:jido, :ai, :react, :start]` | call_id, query | Turn started |
| `[:jido, :ai, :react, :iteration]` | iteration, status | ReAct loop step |
| `[:jido, :ai, :react, :complete]` | call_id, status, usage | Turn completed |
| `reqllm.result` | call_id, result, usage | Per-LLM-call |
| `ai.tool_result` | call_id, tool_name, result | Tool execution |

---

## 6. Remaining Gaps

### 6.1 What's Been Addressed

| Original Gap | Status | Implementation |
|-------------|--------|----------------|
| No Thread abstraction | ✅ **Resolved** | `Jido.AI.Thread` in jido_ai |
| CLI kills agent per query | ✅ **Resolved** | TUI keeps `agent_pid` alive |
| Conversation in Machine state | ✅ **Resolved** | Machine now holds `thread: Thread.t()` |
| Hidden multi-turn behavior | ✅ **Resolved** | Explicit Thread API with clear semantics |

### 6.2 What Remains

| Gap | Impact | Severity |
|-----|--------|----------|
| No `thread_id` parameter in `ask/3` | Cannot manage multiple conversations per agent | Medium |
| Usage resets per turn | No session-level cost visibility | Medium |
| No thread persistence | Conversation lost on agent restart | Medium |
| No context pruning | Unbounded context growth will hit limits | Medium |
| Single thread per agent | Cannot switch contexts in same agent | Low |

### 6.3 Resolved DevEx Pain Points

1. ~~**Hidden Behavior**~~: Thread abstraction is explicit with clear API
2. **Debugging**: Basic introspection via `Thread.length/1`, `Thread.last_entry/1`
3. ~~**TUI multi-turn broken**~~: Agent persists across queries
4. **Cost visibility**: TUI tracks `total_usage` (but not in Thread itself)

### 6.4 Remaining DevEx Improvements Needed

1. **Session-level usage** in Thread struct
2. **Token estimation** helpers
3. **Context pruning** policies
4. **Thread persistence** for crash recovery
5. **Multi-thread routing** via `ask(pid, query, thread_id: "...")`

### 6.5 Request vs Thread Clarification

| Concept | RequestTracking | Thread |
|---------|----------------|--------|
| Purpose | Correlation & async/await | Conversation history |
| Scope | Single query | Multiple queries |
| Stores | query, status, timestamps, result | entries, system_prompt, id |
| Lifetime | Until completion | Agent process (could be persisted) |

---

## 7. Implementation Roadmap

### Phase 1: ✅ COMPLETED - Basic Thread + TUI Fix

- [x] **`Jido.AI.Thread`** module with Entry struct
- [x] **Machine integration**: Thread replaces raw conversation array
- [x] **TUI fix**: Agent process persists across queries
- [x] **Basic introspection**: `length/1`, `empty?/1`, `last_entry/1`

### Phase 2: Thread ID Routing (Future, 2-4 hours)

Add `thread_id` parameter to `ask/3`:

```elixir
# Continue existing thread
{:ok, req} = WeatherAgent.ask(pid, "What about tomorrow?", thread_id: "chat-123")

# Start new thread explicitly  
{:ok, req} = WeatherAgent.ask(pid, "New question", thread_id: :new)

# Default behavior: single thread per agent (backward compatible)
{:ok, req} = WeatherAgent.ask(pid, "Question")
```

State structure for multi-thread:
```elixir
agent.state.__strategy__ = %{
  threads: %{
    "default" => %Jido.AI.Thread{...},
    "chat-123" => %Jido.AI.Thread{...}
  },
  current_thread_id: "default"
}
```

### Phase 3: Context Management (Future, 4-8 hours)

#### Context Pruning

```elixir
# Manual windowing already exists:
Thread.to_messages(thread, limit: 20)

# Future: automatic pruning module
defmodule Jido.AI.Thread.Pruning do
  def prune(thread, max_entries: 50, keep_recent: 10) do
    # Keep system prompt + last N entries
  end
end
```

#### Session-Level Usage

Add to Thread struct (optional enhancement):
```elixir
defstruct [
  # existing fields...
  usage_total: %{input_tokens: 0, output_tokens: 0}  # NEW
]
```

### Phase 4: Persistence (Future, 8-16 hours)

Options:
1. **Leverage `Jido.Thread`**: The core `Jido.Thread` has storage infrastructure - could project `Jido.AI.Thread` to/from it
2. **Simple file-based**: JSON/term file for crash recovery
3. **SessionStore behaviour**: Pluggable storage abstraction

### Phase 5: Advanced Features (Future)

- [ ] **Summarization**: Compress old messages into summaries
- [ ] **Branching**: Fork threads for "what-if" exploration  
- [ ] **Context warnings**: Signal when approaching token limits

---

## 8. Future CLI Enhancements

### Multi-Turn Mode Flag

```bash
# Single-turn (current default - backward compatible)
mix jido_ai.agent "What's the weather?"

# Multi-turn interactive (keeps agent alive)
mix jido_ai.agent --tui

# Future: Multi-turn with explicit session file
mix jido_ai.agent --tui --session ./chat.json
```

### Ideal Session Display

```
╭─────────────────────────────────────────────────────────╮
│ Jido AI Agent                                           │
├─────────────────────────────────────────────────────────┤
│ Agent: WeatherAgent │ Thread: chat-123 │ Msgs: 6        │
│ Tokens: 2.4k (2.1k in / 0.3k out) │ Status: Ready       │
├─────────────────────────────────────────────────────────┤
│ You: What's the weather in Seattle?                     │
│                                                         │
│ Agent (1234ms): It's currently 52°F and cloudy in       │
│ Seattle with a 30% chance of rain this afternoon...     │
│                                                         │
│ You: What about tomorrow?                               │
│                                                         │
│ Agent (892ms): Tomorrow in Seattle expect partly        │
│ cloudy skies with highs around 55°F...                  │
├─────────────────────────────────────────────────────────┤
│ ❯ Should I bring an umbrella?▌                          │
│ Enter: Submit │ Ctrl+R: Reset │ Ctrl+U: Clear │ Esc: Quit│
╰─────────────────────────────────────────────────────────╯
```

---

## 9. Future Signals

```elixir
defmodule Jido.AI.Signal.ThreadUpdated do
  use Jido.Signal,
    type: "ai.thread_updated",
    default_source: "/ai/thread",
    schema: [
      thread_id: [type: :string, required: true],
      message_count: [type: :integer, required: true],
      usage_total: [type: :map, required: true]
    ]
end

defmodule Jido.AI.Signal.ContextWarning do
  use Jido.Signal,
    type: "ai.context_warning",
    default_source: "/ai/thread",
    schema: [
      thread_id: [type: :string, required: true],
      message_count: [type: :integer, required: true],
      estimated_tokens: [type: :integer, required: true],
      warning: [type: :atom, required: true]  # :approaching_limit | :at_limit
    ]
end
```

---

## Appendix A: Actual Implementation

### A.1 `Jido.AI.Thread` (Implemented)

```elixir
# lib/jido_ai/thread.ex
defmodule Jido.AI.Thread do
  @moduledoc """
  Simple conversation thread that accumulates messages for LLM context projection.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    entries: [Entry.t()],
    system_prompt: String.t() | nil
  }
  
  defstruct [:id, entries: [], system_prompt: nil]

  defmodule Entry do
    @type t :: %__MODULE__{
      role: :user | :assistant | :tool | :system,
      content: String.t() | nil,
      tool_calls: list() | nil,
      tool_call_id: String.t() | nil,
      name: String.t() | nil,
      timestamp: DateTime.t() | nil
    }
    defstruct [:role, :content, :tool_calls, :tool_call_id, :name, :timestamp]
  end

  def new(opts \\ []) do
    %__MODULE__{
      id: Keyword.get(opts, :id, generate_id()),
      system_prompt: Keyword.get(opts, :system_prompt)
    }
  end
  
  def append_user(thread, content), do: append(thread, %Entry{role: :user, content: content})
  def append_assistant(thread, content, tool_calls \\ nil), do: ...
  def append_tool_result(thread, tool_call_id, name, content), do: ...
  def to_messages(thread, opts \\ []), do: ...  # Project to ReqLLM format
  def length(thread), do: Kernel.length(thread.entries)
  def empty?(thread), do: thread.entries == []
  def last_entry(thread), do: List.last(thread.entries)
  def last_assistant_content(thread), do: ...
end
```

### A.2 Machine Integration (Implemented)

```elixir
# lib/jido_ai/strategies/react/machine.ex (key changes)
defstruct [
  thread: nil,  # Jido.AI.Thread.t()
  # ...other fields
]

# Fresh start - create new thread
def update(%{status: "idle"} = machine, {:start, query, call_id}, env) do
  thread = Thread.new(system_prompt: system_prompt)
           |> Thread.append_user(query)
  do_start_with_thread(machine, thread, call_id)
end

# Continue - append to existing thread  
def update(%{status: status} = machine, {:start, query, call_id}, env)
    when status in ["completed", "error"] do
  thread = Thread.append_user(machine.thread, query)
  do_start_with_thread(machine, thread, call_id)
end
```

---

## Appendix B: Testing Multi-Turn

### B.1 Manual Test (IEx)

```bash
# Start IEx
cd projects/jido_ai && iex -S mix

# Start agent
{:ok, pid} = Jido.start_agent(JidoAi.CliJido, Jido.AI.Examples.WeatherAgent)

# First turn
{:ok, req1} = Jido.AI.Examples.WeatherAgent.ask(pid, "What's the weather in Seattle?")
{:ok, ans1} = Jido.AI.Examples.WeatherAgent.await(req1, timeout: 30_000)
IO.puts(ans1)

# Second turn (should reference Seattle automatically)
{:ok, req2} = Jido.AI.Examples.WeatherAgent.ask(pid, "What about tomorrow?")
{:ok, ans2} = Jido.AI.Examples.WeatherAgent.await(req2, timeout: 30_000)
IO.puts(ans2)

# ✓ If answer mentions Seattle: Multi-turn works!
```

### B.2 Verify Thread State

```elixir
# Inspect strategy state
{:ok, status} = Jido.AgentServer.status(pid)
strategy_state = status.raw_state.__strategy__

# View thread entries
thread = strategy_state.thread
IO.puts("Thread ID: #{thread.id}")
IO.puts("Entry count: #{Jido.AI.Thread.length(thread)}")

# View messages
Jido.AI.Thread.to_messages(thread)
|> Enum.each(fn msg ->
  IO.puts("#{msg.role}: #{String.slice(msg.content || "", 0, 80)}...")
end)
```

### B.3 Testing with TUI

```bash
cd projects/jido_ai
mix jido_ai.agent --tui --agent Jido.AI.Examples.WeatherAgent
```

Key behaviors:
- Agent process persists across queries (Thread accumulates entries)
- Token usage tracked per-turn (TUI shows totals)
- Ctrl+R resets conversation (stops agent, starts fresh)
- Agent remembers context from prior turns ✓

---

## Conclusion

The Jido AI ReAct agent system now has **explicit multi-turn support** through the `Jido.AI.Thread` abstraction.

**What's been accomplished**:
1. ✅ `Jido.AI.Thread` module with clear API for conversation accumulation
2. ✅ Machine integration storing conversation in Thread (not raw array)
3. ✅ TUI keeps agent alive for true multi-turn conversations
4. ✅ Basic introspection via `Thread.length/1`, `Thread.last_entry/1`, etc.

**What remains for future phases**:
1. ⏳ `thread_id` parameter in `ask/3` for multi-thread per agent
2. ⏳ Session-level usage tracking in Thread struct
3. ⏳ Thread persistence for crash recovery
4. ⏳ Context pruning/warning when approaching limits

This design aligns with OTP principles, maintains the elegant `ask/await` pattern, and delivers a high-quality developer experience for building conversational AI applications with Jido.
