# Multi-Turn Conversation Support for Jido AI Agents

## Executive Summary

This report analyzes the multi-turn conversation capabilities of the Jido AI ReAct agent system, using the WeatherAgent as a reference implementation. It identifies gaps in the current architecture, critiques the developer experience (DevEx), and proposes a clean design for robust multi-turn support.

**Key Finding**: Multi-turn conversations *accidentally* work within a single long-lived agent process, but the CLI/TUI defeats this by restarting the agent between queries. A missing "Thread/Session" abstraction is needed for production-quality multi-turn support.

---

## Table of Contents

1. [Current Architecture Analysis](#1-current-architecture-analysis)
2. [How Multi-Turn Currently Works (and Breaks)](#2-how-multi-turn-currently-works-and-breaks)
3. [Context Management Deep Dive](#3-context-management-deep-dive)
4. [DevEx Analysis](#4-devex-analysis)
5. [Critiques & Gap Analysis](#5-critiques--gap-analysis)
6. [Recommendations](#6-recommendations)
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
│   Stores: conversation[], pending_tool_calls[], usage{}         │
│   Emits: telemetry events [:jido, :ai, :react, *]               │
└─────────────────────────────────────────────────────────────────┘
```

### 1.2 State Storage Hierarchy

| Layer | What's Stored | Lifetime |
|-------|--------------|----------|
| `agent.state` | Model, requests map, last_answer, completed | Agent process |
| `agent.state.__strategy__` | Machine state (conversation, usage, iteration, etc.) | Agent process |
| `Machine` struct | Pure execution state (loaded from/saved to strategy state) | Per update cycle |
| `RequestTracking` | Per-request metadata (query, status, timestamps, result) | Request lifetime |

### 1.3 Key Files

| File | Responsibility |
|------|---------------|
| `lib/jido_ai/agents/react_agent.ex` | Macro defining ask/await API and hooks |
| `lib/jido_ai/strategies/react.ex` | Strategy implementation, signal routing, config |
| `lib/jido_ai/strategies/react/machine.ex` | Pure state machine with conversation handling |
| `lib/jido_ai/request_tracking.ex` | Request struct and await/polling logic |
| `lib/jido_ai/cli/tui.ex` | Terminal UI for interactive queries |
| `lib/jido_ai/cli/adapters/react.ex` | CLI adapter: start/submit/await/stop agent |

---

## 2. How Multi-Turn Currently Works (and Breaks)

### 2.1 The Hidden Multi-Turn Support

The Machine already supports conversation continuation! In `machine.ex`:

```elixir
# Fresh start - only when status is "idle"
def update(%{status: "idle"} = machine, {:start, query, call_id}, env) do
  do_start_fresh(machine, query, call_id, env)
end

# Continue - when status is "completed" or "error"
def update(%{status: status} = machine, {:start, query, call_id}, env)
    when status in ["completed", "error"] do
  do_start_continue(machine, query, call_id, env)
end
```

`do_start_continue/4` appends to existing conversation:
```elixir
defp do_start_continue(machine, query, call_id, _env) do
  conversation = machine.conversation ++ [user_message(query)]
  do_start_with_conversation(machine, conversation, call_id)
end
```

**This means**: If you keep the same agent process alive, each `ask/2` after the first will automatically continue the conversation with full history.

### 2.2 Why the CLI Breaks Multi-Turn

The TUI (`lib/jido_ai/cli/tui.ex`) does this per query:

```elixir
defp run_query(query, adapter, agent_module, config) do
  case adapter.start_agent(JidoAi.CliJido, agent_module, config) do
    {:ok, pid} ->
      try do
        :ok = adapter.submit(pid, query, config)
        adapter.await(pid, config.timeout, config)
      after
        adapter.stop(pid)  # <-- KILLS THE AGENT!
      end
  end
end
```

**Result**: Every query starts a fresh agent with `status: "idle"` and empty conversation. The TUI shows a "multi-turn" interface but provides single-turn semantics.

### 2.3 The Disconnect

| What User Sees | What Actually Happens |
|---------------|----------------------|
| Continuous chat interface | New agent per message |
| "You: What's the weather in Seattle?" <br> "Agent: It's 52°F..." <br> "You: What about tomorrow?" | Second query: "What about tomorrow?" has NO context about Seattle |

---

## 3. Context Management Deep Dive

### 3.1 Conversation Array Lifecycle

```
┌─────────────────────────────────────────────────────────────────┐
│                    CONVERSATION LIFECYCLE                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ask("What's the weather in Seattle?")                          │
│    ├─ Machine status: idle → awaiting_llm                       │
│    ├─ conversation: [system_prompt, user_msg_1]                 │
│    │                                                             │
│    ├─ LLM requests tool: weather_by_location                    │
│    │   └─ conversation: [..., assistant_tool_call]              │
│    │                                                             │
│    ├─ Tool executes, returns result                             │
│    │   └─ conversation: [..., tool_result]                      │
│    │                                                             │
│    ├─ LLM gives final answer                                    │
│    │   └─ conversation: [..., assistant_answer]                 │
│    │                                                             │
│    └─ Machine status: completed                                 │
│       conversation: [sys, user1, asst_tool, tool_res, asst_ans] │
│                                                                  │
│  ask("What about tomorrow?")  [IF SAME PROCESS]                 │
│    ├─ Machine status: completed → awaiting_llm                  │
│    ├─ conversation: [sys, user1, ..., asst_ans, user2]          │
│    │   ↑ FULL HISTORY PRESERVED                                 │
│    └─ LLM has context: knows "Seattle" from prior turn          │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Token Usage Handling

Current behavior per-turn (in `do_start_with_conversation/3`):
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

**Gap**: No session-level token accumulation. You cannot answer "how many tokens have I used in this conversation?"

### 3.3 Context Size Visibility

Currently exposed in snapshot:
```elixir
defp build_snapshot_details(state, config) do
  %{
    # ... 
    conversation: Map.get(state, :conversation, []),
    usage: state[:usage],
    # ...
  }
end
```

**Gaps**:
- No `conversation_message_count`
- No `conversation_char_count` (approximate token estimate)
- No `context_tokens_estimate` (input token count before LLM call)
- No `session_usage_total` (accumulated across turns)

---

## 4. DevEx Analysis

### 4.1 Available Lifecycle Hooks

| Hook | Location | Current Use | Multi-Turn Potential |
|------|----------|-------------|---------------------|
| `on_before_cmd/2` | ReActAgent | Request tracking | Thread ID injection |
| `on_after_cmd/3` | ReActAgent | Request completion | Thread state persistence |
| `Strategy.process/3` | ReAct Strategy | Machine update | Thread load/save |
| Machine telemetry | Machine | `:start/:complete/:iteration` | Session metrics |

### 4.2 Signal Flow for Multi-Turn

```
User calls ask(pid, "Question 2", thread_id: "chat-123")
    │
    ▼
Signal: react.user_query
  payload: %{query: "Question 2", request_id: "req-abc", thread_id: "chat-123"}
    │
    ▼
Strategy routes to :react_start
    │
    ├─ Load thread "chat-123" conversation from agent state
    ├─ Initialize machine with loaded conversation
    ├─ Run Machine.update with {:start, query, call_id}
    │   └─ do_start_continue appends to conversation
    │
    ▼
[... ReAct loop with tool calls ...]
    │
    ▼
Machine reaches :completed
    │
    ├─ Save updated conversation back to thread "chat-123"
    ├─ Accumulate usage into thread session totals
    └─ Emit result signal
```

### 4.3 Current Signals Emitted

| Signal | Data | Multi-Turn Relevance |
|--------|------|---------------------|
| `reqllm.result` | call_id, result, usage | Per-LLM-call usage |
| `reqllm.partial` | call_id, delta | Streaming tokens |
| `ai.tool_result` | call_id, tool_name, result | Tool execution |
| `ai.usage_report` | call_id, model, tokens | Per-call reporting |

**Missing for Multi-Turn**:
- `react.session_updated` (thread state changed)
- `react.context_warning` (approaching token limit)

---

## 5. Critiques & Gap Analysis

### 5.1 Architectural Gaps

| Gap | Impact | Severity |
|-----|--------|----------|
| No Thread/Session abstraction | Cannot persist conversations across agent restarts | **High** |
| CLI kills agent per query | Multi-turn UI is misleading | **High** |
| Usage resets per turn | No session-level cost visibility | Medium |
| No conversation pruning | Unbounded context growth will hit limits | Medium |
| Conversation in Machine state | Conflates execution and domain state | Low |

### 5.2 DevEx Pain Points

1. **Hidden Behavior**: Multi-turn "works" but only accidentally. No documentation or explicit API.

2. **Debugging Opacity**: Can't easily inspect:
   - Current conversation length
   - Approximate token count
   - Which messages are in context

3. **No Session Control**: Cannot:
   - Reset conversation without restarting agent
   - Switch between multiple threads
   - Resume a conversation after crash

4. **Cost Blindness**: After a long session, no way to know total tokens consumed.

### 5.3 Request vs Thread Confusion

| Concept | RequestTracking | Thread/Session (missing) |
|---------|----------------|-------------------------|
| Purpose | Correlation & concurrency | Conversation persistence |
| Scope | Single query | Multiple queries |
| Stores | query, status, timestamps | conversation, usage_total, metadata |
| Lifetime | Until completion | Across agent restarts (optionally) |

---

## 6. Recommendations

### 6.1 Immediate Fix: Keep Agent Alive in TUI

**Effort**: Small (~1h)

Modify `lib/jido_ai/cli/tui.ex`:

```elixir
# In init/1:
%__MODULE__{
  # ...
  agent_pid: nil,  # NEW: persistent agent handle
}

# In update/2 for {:submit, query}:
# Start agent once if not started
state = maybe_start_agent(state)
spawn_query(query, state.agent_pid, state)
{state, []}

# In update/2 for :quit:
stop_agent_if_running(state)
{state, [TermUI.Command.quit()]}
```

This alone enables multi-turn for interactive sessions.

### 6.2 Thread Abstraction Design

**Effort**: Medium (~4-8h)

#### 6.2.1 Thread Struct

```elixir
defmodule Jido.AI.Thread do
  defstruct [
    id: nil,
    conversation: [],
    usage_total: %{input_tokens: 0, output_tokens: 0},
    message_count: 0,
    created_at: nil,
    updated_at: nil,
    metadata: %{}
  ]
end
```

#### 6.2.2 Extended ask/3 API

```elixir
# Continue existing thread
{:ok, req} = WeatherAgent.ask(pid, "What about tomorrow?", thread_id: "chat-123")

# Start new thread explicitly
{:ok, req} = WeatherAgent.ask(pid, "New question", thread_id: :new)

# Default behavior: use "default" thread (backward compatible)
{:ok, req} = WeatherAgent.ask(pid, "Question")  # Uses thread "default"
```

#### 6.2.3 State Structure

```elixir
agent.state = %{
  # Existing fields...
  __strategy__: %{
    # Existing Machine state (execution state)...
    
    # NEW: Thread storage
    threads: %{
      "default" => %Jido.AI.Thread{...},
      "chat-123" => %Jido.AI.Thread{...}
    },
    current_thread_id: "default"
  }
}
```

#### 6.2.4 Strategy Integration

In `react.ex`, modify `process/3`:

```elixir
# On :react_start
thread_id = params[:thread_id] || "default"
thread = get_thread(state, thread_id)

# Initialize machine with thread's conversation
machine = Machine.from_map(%{
  status: if(thread.conversation == [], do: :idle, else: :completed),
  conversation: thread.conversation,
  # ... other fields
})

# After machine update, if completed:
thread = update_thread(thread, machine)
state = put_thread(state, thread_id, thread)
```

### 6.3 Context Management

#### 6.3.1 Pruning Strategy

```elixir
defmodule Jido.AI.Thread.Pruning do
  @default_max_messages 50
  @default_keep_system true
  @default_keep_recent 10
  
  def prune(conversation, opts \\ []) do
    max = Keyword.get(opts, :max_messages, @default_max_messages)
    
    if length(conversation) <= max do
      conversation
    else
      system_msgs = Enum.filter(conversation, &(&1.role == :system))
      non_system = Enum.reject(conversation, &(&1.role == :system))
      recent = Enum.take(non_system, -@default_keep_recent)
      
      system_msgs ++ recent
    end
  end
end
```

#### 6.3.2 Context Size Introspection

Add to snapshot:
```elixir
%{
  # Existing...
  thread_id: current_thread_id,
  thread_message_count: length(thread.conversation),
  thread_usage_total: thread.usage_total,
  context_size_estimate: estimate_tokens(thread.conversation),
  context_warning: length(thread.conversation) > warn_threshold
}
```

### 6.4 CLI Enhancements

#### 6.4.1 Multi-Turn Mode Flag

```bash
# Single-turn (current default - backward compatible)
mix jido_ai.agent "What's the weather?"

# Multi-turn interactive (keeps agent alive)
mix jido_ai.agent --tui --multi-turn

# Multi-turn with explicit session file
mix jido_ai.agent --tui --session ./chat.json
```

#### 6.4.2 Session Display

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
│ Enter: Submit │ Ctrl+N: New Thread │ Ctrl+U: Clear │    │
╰─────────────────────────────────────────────────────────╯
```

### 6.5 New Signals

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

## 7. Implementation Roadmap

### Phase 1: Quick Wins (1-2 hours)

- [ ] **TUI Agent Persistence**: Keep agent alive across queries in TUI
- [ ] **Usage Display**: Show cumulative usage in TUI header
- [ ] **Message Count**: Add `conversation_length` to snapshot

### Phase 2: Thread Foundation (4-8 hours)

- [ ] **Thread Struct**: Define `Jido.AI.Thread` module
- [ ] **Strategy Integration**: Load/save thread in process/3
- [ ] **API Extension**: Add `thread_id` option to ask/3
- [ ] **Default Thread**: Maintain backward compatibility with implicit "default" thread

### Phase 3: Context Management (4-8 hours)

- [ ] **Pruning Module**: Implement configurable conversation trimming
- [ ] **Context Introspection**: Token estimation helpers
- [ ] **Warning Signals**: Emit when approaching limits
- [ ] **Snapshot Enhancement**: Full context visibility

### Phase 4: Persistence (Optional, 8-16 hours)

- [ ] **SessionStore Behaviour**: Pluggable storage abstraction
- [ ] **DETS Implementation**: File-based persistence for CLI
- [ ] **Resume Support**: Load thread from file on startup
- [ ] **Export/Import**: Thread serialization for debugging

### Phase 5: Advanced Features (Future)

- [ ] **Summarization**: Compress old messages into summaries
- [ ] **Branching**: Fork threads for "what-if" exploration
- [ ] **Multi-Thread Per Agent**: Concurrent conversation management

---

## Appendix A: Code Snippets

### A.1 Quick TUI Fix (Phase 1)

```elixir
# lib/jido_ai/cli/tui.ex - Modified struct
defstruct [
  :adapter,
  :agent_module,
  :config,
  :agent_pid,  # NEW
  status: :idle,
  input: "",
  output: [],
  error: nil,
  start_time: nil
]

# Modified spawn_query
defp spawn_query(query, state) do
  pid = state.agent_pid
  config = state.config
  caller = self()

  spawn(fn ->
    result = run_query_on_pid(query, pid, config)
    send(caller, {:query_result, result})
  end)
end

defp run_query_on_pid(query, pid, config) do
  agent_module = config.agent_module
  
  case agent_module.ask(pid, query) do
    {:ok, request} ->
      agent_module.await(request, timeout: config.timeout)
      |> case do
        {:ok, result} -> {:ok, %{answer: result, meta: %{}}}
        error -> error
      end
    error -> error
  end
end

# Start agent in init or on first query
defp ensure_agent_started(state) do
  case state.agent_pid do
    nil ->
      adapter = state.adapter
      case adapter.start_agent(JidoAi.CliJido, state.agent_module, state.config) do
        {:ok, pid} -> %{state | agent_pid: pid}
        {:error, _} -> state
      end
    _pid -> state
  end
end
```

### A.2 Thread Module (Phase 2)

```elixir
defmodule Jido.AI.Thread do
  @moduledoc """
  Represents a multi-turn conversation session.
  
  Threads persist conversation history and accumulated usage
  across multiple calls to `ask/2`, enabling true multi-turn
  conversations.
  """
  
  @type t :: %__MODULE__{
    id: String.t(),
    conversation: [map()],
    usage_total: usage(),
    message_count: non_neg_integer(),
    created_at: integer(),
    updated_at: integer(),
    metadata: map()
  }
  
  @type usage :: %{
    input_tokens: non_neg_integer(),
    output_tokens: non_neg_integer()
  }
  
  defstruct [
    id: nil,
    conversation: [],
    usage_total: %{input_tokens: 0, output_tokens: 0},
    message_count: 0,
    created_at: nil,
    updated_at: nil,
    metadata: %{}
  ]
  
  def new(id \\ nil) do
    now = System.system_time(:millisecond)
    %__MODULE__{
      id: id || generate_id(),
      created_at: now,
      updated_at: now
    }
  end
  
  def append_conversation(thread, messages) when is_list(messages) do
    %{thread |
      conversation: thread.conversation ++ messages,
      message_count: length(thread.conversation) + length(messages),
      updated_at: System.system_time(:millisecond)
    }
  end
  
  def accumulate_usage(thread, usage) when is_map(usage) do
    merged = Map.merge(thread.usage_total, usage, fn _k, v1, v2 ->
      (v1 || 0) + (v2 || 0)
    end)
    %{thread | usage_total: merged}
  end
  
  defp generate_id, do: "thread_" <> Jido.Util.generate_id()
end
```

---

## Appendix B: Testing Multi-Turn

### B.1 Manual Test (Current State)

```bash
# Start IEx
cd projects/jido_ai && iex -S mix

# Start agent
{:ok, pid} = Jido.start_agent(JidoAi.CliJido, Jido.AI.Examples.WeatherAgent)

# First turn
{:ok, req1} = Jido.AI.Examples.WeatherAgent.ask(pid, "What's the weather in Seattle?")
{:ok, ans1} = Jido.AI.Examples.WeatherAgent.await(req1, timeout: 30_000)
IO.puts(ans1)

# Second turn (should reference Seattle automatically if multi-turn works)
{:ok, req2} = Jido.AI.Examples.WeatherAgent.ask(pid, "What about tomorrow?")
{:ok, ans2} = Jido.AI.Examples.WeatherAgent.await(req2, timeout: 30_000)
IO.puts(ans2)

# Check if it understood context
# If answer mentions Seattle: ✓ Multi-turn works
# If answer asks "which city?": ✗ Context lost
```

### B.2 Verify Conversation State

```elixir
# Inspect strategy state
{:ok, status} = Jido.AgentServer.status(pid)
strategy_state = status.raw_state.__strategy__

# View conversation
strategy_state.conversation
|> Enum.each(fn msg ->
  IO.puts("#{msg.role}: #{String.slice(msg.content || "", 0, 80)}...")
end)

# View usage
IO.inspect(strategy_state.usage, label: "Usage this turn")
```

---

## Appendix C: Testing Multi-Turn with TUI

After the TUI fix is applied, test multi-turn conversations:

```bash
cd projects/jido_ai
mix jido_ai.agent --tui --agent Jido.AI.Examples.WeatherAgent
```

Example session:
```
╭─────────────────────────────────────────────────────────────────╮
│ Jido AI Agent (Multi-Turn)                                      │
├─────────────────────────────────────────────────────────────────┤
│ Agent: WeatherAgent │ Turns: 2 │ Tokens: 4.2k │ Status: Ready   │
├─────────────────────────────────────────────────────────────────┤
│ You: What's the weather in Seattle?                             │
│                                                                 │
│ Agent (1523ms, 3 iter, 2.1k tok):                              │
│   It's currently 52°F and cloudy in Seattle with a 30%...       │
│                                                                 │
│ You: What about tomorrow?                                       │
│                                                                 │
│ Agent (892ms, 2 iter, 2.1k tok):                               │
│   Tomorrow in Seattle expect partly cloudy skies...             │
│   ↑ Agent remembered Seattle from prior turn!                   │
├─────────────────────────────────────────────────────────────────┤
│ ❯ ▌                                                             │
│ Enter: Submit │ Ctrl+R: Reset │ Ctrl+U: Clear │ Esc: Quit       │
╰─────────────────────────────────────────────────────────────────╯
```

Key behaviors:
- Agent process persists across queries (conversation history maintained)
- Token usage accumulates across session
- Turn counter tracks conversation depth
- Ctrl+R resets conversation (stops agent, starts fresh)

---

## Conclusion

The Jido AI ReAct agent system has latent multi-turn capability hidden in the Machine's `do_start_continue` logic, but this potential is unrealized due to the CLI's practice of killing and restarting agents between queries.

**The immediate fix** is simple: keep the agent process alive in the TUI. This unlocks multi-turn conversations without any architectural changes.

**The recommended enhancement** is to introduce an explicit Thread/Session abstraction that:
1. Separates execution state (Machine) from conversation state (Thread)
2. Enables session-level usage tracking
3. Supports optional persistence for crash recovery
4. Provides context size visibility and pruning

This design aligns with OTP principles, maintains the elegant `ask/await` pattern, and delivers a high-quality developer experience for building conversational AI applications with Jido.
