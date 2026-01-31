# Jido.AI SDK Architecture Map

> **Status**: Pre-release (post-refactor)  
> **Date**: 2025-01-30 (updated)  
> **Purpose**: Comprehensive map of primitives, gaps, overlaps, and upstream friction points

---

## Recent Changes Summary

The following refactoring work has been completed to simplify the architecture and upstream logic:

| Change | Description |
|--------|-------------|
| ✅ `Jido.AI.ToolCall` deleted | Now uses `ReqLLM.ToolCall.from_map/1` directly |
| ✅ `Jido.AI.Tools.Registry` deleted | Replaced with explicit tools map pattern |
| ✅ `Jido.AI.Helpers.Text` added | Centralized text extraction utilities |
| ✅ Int→float coercion upstreamed | Moved to `jido_action` |
| ✅ Empty schema JSON fix upstreamed | Fixed in `jido_action` Schema module |
| ✅ ToolCall normalization upstreamed | Moved to `req_llm` |
| ✅ Executor simplified | Uses explicit tools map, removed Registry dependency |

---

## Table of Contents

0. [Recent Changes Summary](#recent-changes-summary)
1. [Primitives Overview](#1-primitives-overview)
2. [Detailed Component Map](#2-detailed-component-map)
3. [Data Flow Diagrams](#3-data-flow-diagrams)
4. [Identified Gaps](#4-identified-gaps)
5. [Overlaps & Refactoring Opportunities](#5-overlaps--refactoring-opportunities)
6. [Upstream Friction Points](#6-upstream-friction-points)
7. [Recommended Upstream Patches](#7-recommended-upstream-patches) *(partially completed)*
8. [Risk Assessment](#8-risk-assessment)
9. [Action Items](#9-action-items) *(completed)*

---

## 1. Primitives Overview

| Category | Count | Location |
|----------|-------|----------|
| **Actions** | 13 | `lib/jido_ai/actions/` |
| **Signals** | 6 | `lib/jido_ai/signal.ex` |
| **Directives** | 4 | `lib/jido_ai/directive.ex` |
| **Skills** | 6 | `lib/jido_ai/skills/` (+ TaskSupervisorSkill internal) |
| **Strategies** | 6 | `lib/jido_ai/strategies/` |
| **Agents** | 11 | `lib/jido_ai/agents/` |
| **Tools** | 2 | `lib/jido_ai/tools/` (ToolAdapter, Executor) |
| **Helpers** | 1 | `lib/jido_ai/helpers/` (Text) |

---

## 2. Detailed Component Map

### 2.1 Actions

Actions are the atomic units of work that wrap ReqLLM calls or tool executions.

#### LLM Actions (`lib/jido_ai/actions/llm/`)
| Action | Purpose | Schema Type | Status |
|--------|---------|-------------|--------|
| `Chat` | Chat-style LLM interaction with system prompts | Zoi | ✓ |
| `Complete` | Simple text completion (no system prompt) | Zoi | ✓ |
| `Embed` | Text embedding generation | Zoi | ✓ |
| `GenerateObject` | Structured JSON output with schema validation | Zoi | ✓ |

#### Reasoning Actions (`lib/jido_ai/actions/reasoning/`)
| Action | Purpose | Schema Type |
|--------|---------|-------------|
| `Analyze` | Deep analysis (sentiment, topics, entities) | Zoi |
| `Explain` | Explanations at different detail levels | Zoi |
| `Infer` | Draw logical inferences from premises | Zoi |

#### Planning Actions (`lib/jido_ai/actions/planning/`)
| Action | Purpose | Schema Type |
|--------|---------|-------------|
| `Decompose` | Break problems into sub-tasks | Zoi |
| `Plan` | Generate execution plans | Zoi |
| `Prioritize` | Order tasks by importance | Zoi |

#### Streaming Actions (`lib/jido_ai/actions/streaming/`)
| Action | Purpose | Schema Type |
|--------|---------|-------------|
| `StartStream` | Initialize streaming session | Zoi |
| `ProcessTokens` | Handle streaming token chunks | Zoi |
| `EndStream` | Finalize streaming session | Zoi |

#### Tool Calling Actions (`lib/jido_ai/actions/tool_calling/`)
| Action | Purpose | Schema Type |
|--------|---------|-------------|
| `CallWithTools` | LLM call with tool execution loop | Zoi |
| `ExecuteTool` | Direct tool execution by name | Zoi |
| `ListTools` | List available registered tools | Zoi |

---

### 2.2 Signals

Signals are CloudEvents-based messages for async communication between components.

| Signal Type | Purpose | Emitted By |
|-------------|---------|------------|
| `reqllm.result` | LLM completion (streaming or non-streaming) | `ReqLLMStream`, `ReqLLMGenerate` directives |
| `reqllm.partial` | Streaming token chunks | `ReqLLMStream` directive |
| `reqllm.error` | Structured LLM errors | Directive error handlers |
| `ai.tool_result` | Tool execution completion | `ToolExec` directive |
| `ai.embed_result` | Embedding generation completion | `ReqLLMEmbed` directive |
| `ai.usage_report` | Token usage and cost tracking | (Not consistently integrated) |

**Helper Functions:**
- `extract_tool_calls/1` - Extract tool calls from result signal
- `tool_call?/1` - Check if signal contains tool calls
- `from_reqllm_response/2` - Create signal from ReqLLM response

---

### 2.3 Directives

Directives represent async side-effects that the AgentServer runtime executes.

| Directive | Purpose | Result Signal |
|-----------|---------|---------------|
| `ReqLLMStream` | Stream LLM response with tool support | `reqllm.partial`, `reqllm.result` |
| `ReqLLMGenerate` | Non-streaming LLM generation | `reqllm.result` |
| `ReqLLMEmbed` | Generate embeddings | `ai.embed_result` |
| `ToolExec` | Execute a Jido.Action as a tool | `ai.tool_result` |

**Directive Schema Pattern:**
```elixir
@schema Zoi.struct(__MODULE__, %{
  id: Zoi.string(description: "Correlation ID"),
  model: Zoi.string() |> Zoi.optional(),
  model_alias: Zoi.atom() |> Zoi.optional(),
  # ... other fields
})
```

**Execution Pattern:**
```elixir
defimpl Jido.AgentServer.DirectiveExec, for: Directive do
  def exec(directive, _input_signal, state) do
    task_supervisor = Helper.get_task_supervisor(state)
    Task.Supervisor.start_child(task_supervisor, fn ->
      # Execute and send result signal
      Jido.AgentServer.cast(agent_pid, result_signal)
    end)
    {:async, nil, state}
  end
end
```

---

### 2.4 Skills

Skills bundle related actions and provide signal routing.

| Skill | Actions | State Key | Signal Patterns |
|-------|---------|-----------|-----------------|
| `LLM` | Chat, Complete, Embed | `:llm` | `llm.*` |
| `Reasoning` | Analyze, Explain, Infer | `:reasoning` | `reasoning.*` |
| `Planning` | Decompose, Plan, Prioritize | `:planning` | `planning.*` |
| `Streaming` | StartStream, ProcessTokens, EndStream | `:streaming` | `streaming.*` |
| `ToolCalling` | CallWithTools, ExecuteTool, ListTools | `:tool_calling` | `tool.*` |
| `TaskSupervisorSkill` | (internal) | `__task_supervisor_skill__` | N/A |
| `BaseActionHelpers` | (shared utilities, not a skill) | N/A | N/A |

---

### 2.5 Strategies

Strategies define agent reasoning patterns via state machines.

| Strategy | Machine Module | Signal Routes | Use Case |
|----------|----------------|---------------|----------|
| `ReAct` | `Jido.AI.ReAct.Machine` | `react.user_query`, `reqllm.result`, `ai.tool_result`, `reqllm.partial` | Tool-using agents |
| `ChainOfThought` | `Jido.AI.ChainOfThought.Machine` | `cot.query`, `reqllm.result`, `reqllm.partial` | Step-by-step reasoning |
| `TreeOfThoughts` | `Jido.AI.TreeOfThoughts.Machine` | `tot.query`, etc. | Branching exploration |
| `GraphOfThoughts` | `Jido.AI.GraphOfThoughts.Machine` | `got.query`, etc. | Graph-based reasoning |
| `TRM` | `Jido.AI.TRM.Machine` | `trm.query`, `reqllm.result`, `reqllm.partial` | Recursive improvement |
| `Adaptive` | (meta-strategy) | varies | Strategy selection |

**Strategy Pattern:**
```elixir
use Jido.Agent.Strategy

# Signal routing
def signal_routes(_ctx) do
  [
    {"react.user_query", {:strategy_cmd, :react_start}},
    {"reqllm.result", {:strategy_cmd, :react_llm_result}},
    {"ai.tool_result", {:strategy_cmd, :react_tool_result}}
  ]
end

# Command processing
def cmd(agent, instructions, ctx) do
  # 1. Convert instruction to machine message
  # 2. Update machine state
  # 3. Lift machine directives to SDK directives
end
```

---

### 2.6 Agents

Pre-built agent implementations.

| Agent | Strategy | Purpose |
|-------|----------|---------|
| `ReActAgent` | ReAct | Base macro for tool-using agents |
| `CoTAgent` | ChainOfThought | Chain-of-thought reasoning |
| `ToTAgent` | TreeOfThoughts | Tree exploration |
| `GoTAgent` | GraphOfThoughts | Graph-based reasoning |
| `TRMAgent` | TRM | Recursive improvement |
| `AdaptiveAgent` | Adaptive | Meta-strategy selection |
| `WeatherAgent` | ReAct | Demo: weather queries |
| `ReactDemoAgent` | ReAct | Demo: basic ReAct |
| `IssueTriage` | ReAct | Demo: GitHub issue triage |
| `ReleaseNotes` | ReAct | Demo: release note generation |
| `APISmokeTest` | ReAct | Demo: API testing |

---

### 2.7 Tools Infrastructure

| Module | Purpose | Upstream Dependency |
|--------|---------|---------------------|
| `ToolAdapter` | Convert Actions → ReqLLM.Tool | `Jido.Action.Schema` |
| `Tools.Executor` | Execute actions, build tools map | `Jido.Exec` |

**Deleted Modules:**
- `Tools.Registry` - replaced by explicit tools map pattern
- `ToolCall` - replaced by `ReqLLM.ToolCall.from_map/1`

**Current Tool Pattern:**

```elixir
# 1. Build tools map from action modules
tools = Executor.build_tools_map([MyAction, OtherAction])
# => %{"my_action" => MyAction, "other_action" => OtherAction}

# 2. Convert to LLM-facing tools for API call
llm_tools = Enum.map(tools, fn {_, mod} -> ToolAdapter.to_tool(mod) end)

# 3. LLM returns tool calls, normalize with ReqLLM
tool_call = ReqLLM.ToolCall.from_map(raw_call)
# => %{id: "call_123", name: "my_action", arguments: %{...}}

# 4. Execute via Executor (or ToolExec directive)
Executor.execute(tool_call.name, tool_call.arguments, context, tools: tools)
```

**Tool Representation Layers:**
```
┌─────────────────────────────────────────────────────────────┐
│ 1. Jido.Action module                                       │
│    - name(), description(), schema(), run/2                 │
├─────────────────────────────────────────────────────────────┤
│ 2. ReqLLM.Tool (LLM-facing)                                 │
│    - Built by ToolAdapter.to_tool/1                         │
│    - name, description, parameter_schema                    │
├─────────────────────────────────────────────────────────────┤
│ 3. Tool Call (from LLM response)                            │
│    - ReqLLM.ToolCall.from_map/1 → %{id, name, arguments}    │
├─────────────────────────────────────────────────────────────┤
│ 4. Execution                                                │
│    - Executor.execute/4 with explicit tools map             │
│    - Or ToolExec directive (reads tools from agent state)   │
└─────────────────────────────────────────────────────────────┘
```

**Key Design Decisions:**
- No global registry - tools are passed explicitly or stored in agent state
- Tools map is `%{name => module}` for O(1) lookup
- `Executor.build_tools_map/1` accepts single module or list
- ToolExec directive reads tools from `state[:tools]` or `state[:tool_calling][:tools]`

---

### 2.8 Helpers

| Module | Purpose | Status |
|--------|---------|--------|
| `Jido.AI.Helpers.Text` | Centralized text extraction from LLM responses | ✓ NEW |

**Key Functions:**
- `extract_text/1` - Extract text from any response format (string, map, struct, list)
- `extract_from_content/1` - Handle content blocks (text blocks, iodata)
- Properly handles iodata vs list-of-integers edge cases

---

## 3. Data Flow Diagrams

### 3.1 ReAct Strategy Flow

```
User Query
    │
    ▼
┌──────────────────┐
│ react.user_query │ Signal
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│   ReAct.cmd/3    │ Strategy processes instruction
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ ReAct.Machine    │ Pure state machine
│   .update/3      │ Returns machine directives
└────────┬─────────┘
         │
         ▼
┌──────────────────┐
│ lift_directives  │ Convert to SDK directives
└────────┬─────────┘
         │
         ├──────────────────────────────┐
         ▼                              ▼
┌──────────────────┐        ┌──────────────────┐
│ ReqLLMStream     │        │    ToolExec      │
│   Directive      │        │   Directive      │
└────────┬─────────┘        └────────┬─────────┘
         │                           │
         ▼                           ▼
┌──────────────────┐        ┌──────────────────┐
│ DirectiveExec    │        │ DirectiveExec    │
│  (spawns task)   │        │  (spawns task)   │
└────────┬─────────┘        └────────┬─────────┘
         │                           │
         ▼                           ▼
┌──────────────────┐        ┌──────────────────┐
│  reqllm.result   │        │  ai.tool_result  │
│     Signal       │        │     Signal       │
└────────┬─────────┘        └────────┬─────────┘
         │                           │
         └─────────────┬─────────────┘
                       │
                       ▼
               ┌──────────────────┐
               │ ReAct.Machine    │
               │ (next iteration) │
               └──────────────────┘
```

### 3.2 Tool Execution Flow

```
LLM Response with tool_calls
    │
    ▼
┌──────────────────┐
│  ToolCall.       │ Normalize format
│  normalize/1     │ (JSON string → map, etc.)
└────────┬─────────┘
    │
    ▼
┌──────────────────┐
│ Strategy creates │
│ ToolExec         │ With action_module or tool_name
│ Directive        │
└────────┬─────────┘
    │
    ▼
┌──────────────────┐
│ DirectiveExec    │
│ for ToolExec     │
└────────┬─────────┘
    │
    ├── action_module provided ────┐
    │                              │
    ▼                              ▼
┌──────────────────┐    ┌──────────────────┐
│ Registry.get/1   │    │ Direct module    │
│ (if nil)         │    │ execution        │
└────────┬─────────┘    └────────┬─────────┘
    │                            │
    └──────────────┬─────────────┘
                   │
                   ▼
    ┌──────────────────┐
    │ Executor.        │
    │ execute_module/4 │
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │ normalize_params │ String keys → atoms
    │                  │ Type coercion
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │ Jido.Exec.run/3  │
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │ format_result    │ Truncate, JSON encode
    └────────┬─────────┘
             │
             ▼
    ┌──────────────────┐
    │ ai.tool_result   │
    │ Signal emitted   │
    └──────────────────┘
```

---

## 4. Identified Gaps

### 4.1 Core Functional Gaps

| Gap | Impact | Priority |
|-----|--------|----------|
| **No unified ToolSpec contract** | Three tool representations cause confusion | High |
| **No directive cancellation** | Long-running tasks can't be aborted | Medium |
| **No retry/backoff policy** | Rate limits cause failures, not recovery | Medium |
| **Inconsistent usage reporting** | Cost tracking is incomplete | Low |
| **Untyped context in directives** | `context: Zoi.any()` allows invalid data | Low |

### 4.2 Developer Experience Gaps

| Gap | Impact | Priority |
|-----|--------|----------|
| **No high-level LLM call helper** | Strategies must wire everything manually | Medium |
| **No testing harness for tool loops** | Hard to test ReAct-style agents | Medium |
| **Missing structured output action** | JSON schema-constrained generation | Medium |
| **No conversation memory action** | Must manually manage context | Low |

### 4.3 Missing Primitives

| Primitive | Purpose | Belongs In | Status |
|-----------|---------|------------|--------|
| `GenerateObject` action | JSON schema-constrained generation via `ReqLLM.generate_object/4` | `actions/llm/` | **TODO** |
| `Memory` skill | Conversation history management | N/A | **Out of scope** |
| `RateLimiter` directive wrapper | Automatic retry with backoff | N/A | **Use `Jido.Exec` opts** |
| `DirectiveCancellation` | Cancel in-flight async work | `jido` core | Deferred |

#### Notes on Missing Primitives

**GenerateObject Action**: ReqLLM already supports structured output via `ReqLLM.generate_object/4` and `generate_object!/4`. This should be exposed as a Jido.Action:

```elixir
# ReqLLM API (already available)
{:ok, response} = ReqLLM.generate_object(model, prompt, schema, opts)
object = ReqLLM.Response.object(response)

# Schema can be NimbleOptions keyword list or Zoi schema
schema = [
  name: [type: :string, required: true],
  age: [type: :integer, required: true]
]
```

**Rate Limiting**: Already supported in `jido_action` v2.0.0-rc.2 via `Jido.Exec.run/4` options:

```elixir
# Retry with exponential backoff (via Jido.Exec.Retry)
Jido.Exec.run(MyAction, params, context,
  max_retries: 3,      # Max retry attempts (default: 1)
  backoff: 250         # Initial backoff ms, doubles each retry (capped at 30s)
)
```

**Memory**: Out of scope for jido_ai - conversation management belongs in application layer.

---

## 5. Overlaps & Refactoring Opportunities

### 5.1 Param Normalization Duplication

**Current State:**
```
Jido.Action.Tool.convert_params_using_schema/2  (upstream)
    └── called by ──┐
                    ▼
Jido.AI.Tools.Executor.normalize_params/2  (adds float coercion)
```

**Update (v2.0.0-rc.2):** PR #56 in `jido_action` improved param normalization:
- Now accepts both atom and string keys (atom keys were previously ignored)
- Preserves unknown keys (open validation) matching Runtime behavior
- Unknown keys remain as strings to prevent atom table exhaustion
- When both atom and string versions of a key exist, atom value takes precedence

**Recommendation:** Review if `Executor.normalize_params/2` still needs float coercion or if upstream now handles it. Consider removing jido_ai's extra normalization layer.

---

### 5.2 JSON Schema Generation Duplication

**Current State:**
```
Jido.Action.Tool.build_parameters_schema/1  (upstream)
Jido.AI.ToolAdapter.build_json_schema/1     (handles empty schema edge case)
```

**Update (v2.0.0-rc.2):** PR #56 in `jido_action` improved JSON Schema generation:
- List schemas now include `items` typing (e.g., `{:list, :string}` → `{type: array, items: {type: string}}`)
- Added support for `{:in, choices}` enum constraints with type inference
- Added mappings for `:non_neg_integer` (minimum: 0), `:pos_integer` (minimum: 1), `:timeout` (oneOf with infinity)
- Fixed `:number` to map to JSON `number` type instead of `integer`

**Recommendation:** Check if empty schema edge case is now handled upstream. If so, simplify `ToolAdapter.build_json_schema/1`.

---

### 5.3 Response Text Extraction Duplication

**Current State:**
```
Jido.AI.Helpers.extract_response_text/1
Jido.AI.Signal.extract_response_text/1  (private, different impl)
Jido.AI.Skills.BaseActionHelpers.extract_text/1
```

**Recommendation:** Add `ReqLLM.Response.text/1` upstream, use everywhere.

---

### 5.4 Tool Call Normalization Duplication

**Current State:**
```
ReqLLM.ToolCall.from_map/1
Jido.AI.Helpers.classify_llm_response/1  (uses ReqLLM.ToolCall.from_map/1)
Jido.AI.Signal.from_reqllm_response/2   (uses ReqLLM.ToolCall.from_map/1)
```

**Note:** `Jido.AI.ToolCall` module removed - use `ReqLLM.ToolCall.from_map/1` directly.

---

### 5.5 Dual Tool Lookup Models

**Current State:**
- Per-strategy `actions_by_name` map
- Global `Jido.AI.Tools.Registry`

**Recommendation:** Keep both, but clarify: per-agent tools take precedence, registry is opt-in fallback only.

---

### 5.6 Skills Consolidation Opportunity

**Current Skills:**
| Skill | Actions | Could Consolidate? |
|-------|---------|-------------------|
| `LLM` | Chat, Complete, Embed | Keep separate (core) |
| `Reasoning` | Analyze, Explain, Infer | Consider merging with LLM |
| `Planning` | Decompose, Plan, Prioritize | Consider merging with Reasoning |
| `Streaming` | StartStream, ProcessTokens, EndStream | Internal, may not need exposure |
| `ToolCalling` | CallWithTools, ExecuteTool, ListTools | Keep separate (orchestration) |

**Potential Consolidation:**
1. **LLM + Reasoning + Planning** → Single "AI Capabilities" skill with categories
2. **Streaming** → Move to internal implementation detail, not user-facing skill

**Alternative: Multi-Agent Delegation**

Instead of consolidating into monolithic skills, leverage Jido's orchestration capabilities:

```elixir
# Parent agent delegates to specialized child agents
# See: https://hexdocs.pm/jido/2.0.0-rc.2/orchestration.html

# Pattern:
# 1. Parent spawns children via SpawnAgent directive
# 2. Parent sends work via emit_to_pid/2
# 3. Children process and reply via emit_to_parent/3
# 4. Parent aggregates results
```

**Recommendation:** Keep skills modular for now. Use multi-agent orchestration for complex workflows rather than skill consolidation. This provides:
- Better separation of concerns
- Parallel execution of independent tasks
- Cleaner testing (test each skill in isolation)
- Easier composition (agents pick skills they need)

---

## 6. Upstream Friction Points

### 6.1 Tool Representation Split (jido_action ↔ jido_ai ↔ req_llm) — PARTIALLY RESOLVED

| Layer | Representation | Issue | Status |
|-------|----------------|-------|--------|
| `jido_action` | `Jido.Action.Tool.tool()` map | Unused by jido_ai | Open |
| `jido_ai` | `ReqLLM.Tool` with noop callback | Ignores upstream | Open |
| `req_llm` | `ReqLLM.ToolCall` struct | ~~Inconsistent field access~~ | ✅ Fixed |

**What was fixed:**
- `ReqLLM.ToolCall.from_map/1` now properly normalizes tool calls with decoded arguments
- `Jido.AI.ToolCall` was deleted - uses `ReqLLM.ToolCall.from_map/1` directly

**Root Cause (remaining):** No unified "tool spec" protocol across the ecosystem.

---

### 6.2 Schema System Split (Zoi vs NimbleOptions) — UNCHANGED

| Component | Schema System | Notes |
|-----------|---------------|-------|
| **Actions** | NimbleOptions (legacy) or Zoi (new) | Via `use Jido.Action` |
| **Directives** | Zoi | `Zoi.struct()` |
| **Signals** | NimbleOptions | Via `use Jido.Signal` schema opt |
| **Strategy action specs** | Zoi | `Zoi.object()` |

**Root Cause:** Organic growth without unified schema strategy.

**Decision: Prioritize Zoi for all new work.** NimbleOptions is legacy only.

**Impact:**
- Parameter normalization must handle both (for legacy compatibility)
- JSON schema generation differs
- Type coercion logic ~~duplicated~~ now handled upstream in jido_action

**Migration Path:**
- All new actions should use Zoi schemas
- Existing NimbleOptions actions remain for backwards compatibility
- Signals may eventually migrate to Zoi

---

### 6.3 Task Supervisor Retrieval Pattern — UNCHANGED

**Current Code:**
```elixir
def get_task_supervisor(state) do
  case Map.get(state, :__task_supervisor_skill__) do
    %{supervisor: supervisor} -> supervisor
    _ ->
      case Map.get(state, :task_supervisor) do
        nil -> raise "Task supervisor not found..."
        supervisor -> supervisor
      end
  end
end
```

**Issue:** Requires either a skill or manual state setup. Brittle and error-prone.

---

### ~~6.4 ToolCall Argument Format Inconsistency~~ — ✅ RESOLVED

~~**From ReqLLM:**~~
~~```elixir~~
~~%ReqLLM.ToolCall{...}~~
~~```~~

**Resolution:** `ReqLLM.ToolCall.from_map/1` now:
- Decodes JSON string arguments to maps
- Returns consistent `%{id, name, arguments}` format
- `Jido.AI.ToolCall` module was deleted

---

## 7. Recommended Upstream Patches

### 7.1 jido_action Patches

| Patch | Effort | Impact | Description | Status |
|-------|--------|--------|-------------|--------|
| **Add `to_reqllm_tool/2`** | M | High | `Jido.Action.Tool.to_reqllm_tool(action, opts)` → `ReqLLM.Tool.t()` | Open |
| ~~**Move float coercion**~~ | S | Medium | ~~Add int→float coercion to `convert_params_using_schema/2`~~ | ✅ Done |
| ~~**Fix empty schema JSON**~~ | S | Medium | ~~`Schema.to_json_schema([])` now includes `"required": []`~~ | ✅ Done |

### 7.2 jido_signal Patches

| Patch | Effort | Impact | Description | Status |
|-------|--------|--------|-------------|--------|
| **Promote AI signals** | M | Medium | Add `Jido.Signal.AI.*` namespace for common AI signal types | Open |
| **Standard correlation convention** | S | Low | Document `call_id` as standard correlation field | Open |

### 7.3 jido (core) Patches

| Patch | Effort | Impact | Description | Status |
|-------|--------|--------|-------------|--------|
| **Per-agent TaskSupervisor** | L | High | Guarantee supervisor in `AgentServer.State` | Open |
| **Async directive helper** | L | High | `DirectiveExec.async(state, fn, opts)` with supervision | Open |
| **Directive cancellation** | L | Medium | Track task pids, support abort by call_id | Open |

### 7.4 req_llm Patches

| Patch | Effort | Impact | Description | Status |
|-------|--------|--------|-------------|--------|
| ~~**`ToolCall.to_map/1`**~~ | S | High | ~~Return `%{id, name, arguments}` with decoded args~~ | ✅ Done (`from_map/1`) |
| **`Response.text/1`** | S | Medium | Extract text content from any response format | Open |
| ~~**Guarantee args decoding**~~ | S | High | ~~`ToolCall.args_map/1` always returns map~~ | ✅ Done

---

## 8. Risk Assessment

### 8.1 Security Risks

| Risk | Current Mitigation | Recommendation |
|------|-------------------|----------------|
| **Atom exhaustion** | `convert_params_using_schema` uses known keys only | Audit all `String.to_atom` calls |
| **Credential leakage** | Telemetry sanitizes sensitive keys | Ensure error messages are sanitized |
| **Prompt injection** | `Security.validate_string` for inputs | Add more comprehensive sanitization |

### 8.2 Operational Risks

| Risk | Current State | Recommendation | Status |
|------|---------------|----------------|--------|
| **Task leaks** | No cancellation mechanism | Track tasks by call_id, add shutdown hooks | Open |
| ~~**Registry pollution**~~ | ~~Global registry can cross-contaminate~~ | ~~Prefer per-agent tool lists~~ | ✅ Fixed (Registry deleted) |
| **Rate limit storms** | Errors returned, no backoff | Add retry policy with exponential backoff | Open |

### 8.3 Migration Risks

| Change | Risk Level | Mitigation |
|--------|------------|------------|
| Schema unification | High | Provide adapters, migrate incrementally |
| Tool protocol change | Medium | Keep backwards-compat for one version |
| Task supervisor change | Low | New behavior is additive |

---

## Summary

### Completed Upstream Patches

| Package | Patch | Description |
|---------|-------|-------------|
| `req_llm` | `ToolCall.from_map/1` | Normalizes tool calls with decoded arguments |
| `jido_action` | Float coercion | Int→float coercion in `convert_params_using_schema/2` |
| `jido_action` | Empty schema JSON | `Schema.to_json_schema([])` now includes `"required": []` |

### Remaining Upstream Patches (Deferred)

These are documented for future consideration but not immediate priorities:

1. **jido_action**: Add `Tool.to_reqllm_tool/2` 
2. **jido**: Guarantee per-agent TaskSupervisor in AgentServer
3. **req_llm**: Add `Response.text/1` helper

---

## 9. Action Items

### Completed Tasks

| Priority | Task | Description | Status |
|----------|------|-------------|--------|
| **P0** | Add `GenerateObject` action | Wrap `ReqLLM.generate_object/4` as Jido.Action | ✅ DONE |
| **P1** | Audit param normalization | Check if `Executor.normalize_params/2` can be simplified | ✅ DONE (kept, still needed) |
| **P1** | Audit JSON schema generation | Check if `ToolAdapter.build_json_schema/1` edge case handling is still needed | ✅ DONE (kept, still needed) |
| **P2** | Consolidate text extraction | Single `extract_text/1` helper used everywhere | ✅ DONE |
| **P1** | Delete `Jido.AI.ToolCall` | Use `ReqLLM.ToolCall.from_map/1` directly | ✅ DONE |
| **P1** | Delete `Jido.AI.Tools.Registry` | Replace with explicit tools map | ✅ DONE |
| **P1** | Add `Jido.AI.Helpers.Text` | Centralize text extraction utilities | ✅ DONE |
| **P1** | Upstream int→float coercion | Move to `jido_action` | ✅ DONE |
| **P1** | Upstream empty schema fix | Fix in `jido_action` | ✅ DONE |
| **P1** | Upstream ToolCall normalization | Move to `req_llm` | ✅ DONE |

### Decisions Made

| Decision | Rationale |
|----------|-----------|
| **Zoi for all new work** | NimbleOptions is legacy only |
| **Memory out of scope** | Conversation management belongs in application layer |
| **Rate limiting via Jido.Exec** | Already supported with `max_retries` and `backoff` opts |
| **Keep skills modular** | Use multi-agent orchestration for complex workflows |
| **Explicit tools map over Registry** | Avoids global state pollution, better testability |
| **Upstream where possible** | Keep jido_ai thin, push logic to jido_action/req_llm |

### Files Changed (This Refactor)

| File | Change |
|------|--------|
| `lib/jido_ai/tool_call.ex` | ❌ DELETED |
| `lib/jido_ai/tools/registry.ex` | ❌ DELETED |
| `lib/jido_ai/helpers/text.ex` | ✅ NEW |
| `lib/jido_ai/tools/executor.ex` | Simplified, added `build_tools_map/1` |
| `lib/jido_ai/directive/tool_exec.ex` | Uses explicit tools from state |
| `lib/jido_ai/skills/tool_calling.ex` | Builds tools map from config |
| `lib/jido_ai/strategies/react.ex` | Uses `actions_by_name` from explicit tools |
