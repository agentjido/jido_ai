# Jido.AI SDK Architecture Map v2

> **Status**: Pre-release (post-refactor)  
> **Date**: 2025-01-30  
> **Purpose**: Comprehensive map of primitives, gaps, overlaps, and proposed orchestration layer

---

## Executive Summary

This document updates JIDO_AI_MAP.md with:
1. **Corrected primitive inventory** (actual file counts and locations)
2. **New "Accuracy" subsystem** discovered during audit
3. **Proposed AI-powered orchestration primitives** for multi-agent delegation
4. **Updated gaps analysis** with orchestration focus

---

## Table of Contents

1. [Primitives Overview](#1-primitives-overview)
2. [Detailed Component Map](#2-detailed-component-map)
3. [New: Accuracy Subsystem](#3-accuracy-subsystem)
4. [Proposed Orchestration Layer](#4-proposed-orchestration-layer)
5. [Data Flow Diagrams](#5-data-flow-diagrams)
6. [Identified Gaps](#6-identified-gaps)
7. [Overlaps & Refactoring Opportunities](#7-overlaps--refactoring-opportunities)
8. [Upstream Friction Points](#8-upstream-friction-points)
9. [Risk Assessment](#9-risk-assessment)
10. [Action Items](#10-action-items)

---

## 1. Primitives Overview

| Category | Count | Location | Notes |
|----------|-------|----------|-------|
| **Actions** | 16 | `lib/jido_ai/actions/` | 4 LLM + 3 Reasoning + 3 Planning + 3 Streaming + 3 ToolCalling |
| **Signals** | 6 | `lib/jido_ai/signal.ex` | CloudEvents-based messaging |
| **Directives** | 4 | `lib/jido_ai/directive.ex` | Async side-effects |
| **Skills** | 6 | `lib/jido_ai/skills/` | + 1 utility module (BaseActionHelpers) |
| **Strategies** | 6 | `lib/jido_ai/strategies/` | + helpers (StateOpsHelpers, machine modules) |
| **Agents** | 11 | `lib/jido_ai/agents/` | Pre-built implementations |
| **Tools Infra** | 2 | Split: `tools/executor.ex` + `tool_adapter.ex` | Tool execution pipeline |
| **Helpers** | 2 | `lib/jido_ai/helpers.ex` + `helpers/text.ex` | Shared utilities |
| **Support** | 2 | `security.ex`, `error.ex` | Cross-cutting concerns |
| **Accuracy** | 15+ | `lib/jido_ai/accuracy/` | **NEW** - Quality/reliability subsystem |
| **GEPA** | 6 | `lib/jido_ai/gepa/` | Genetic prompt optimization |
| **Algorithms** | 6 | `lib/jido_ai/algorithms/` | Execution patterns |
| **CLI** | 8 | `lib/jido_ai/cli/` | Interactive adapters |

---

## 2. Detailed Component Map

### 2.1 Actions (16 total)

#### LLM Actions (`lib/jido_ai/actions/llm/`)
| Action | Purpose | Status |
|--------|---------|--------|
| `Chat` | Chat-style LLM interaction with system prompts | ✓ |
| `Complete` | Simple text completion (no system prompt) | ✓ |
| `Embed` | Text embedding generation | ✓ |
| `GenerateObject` | Structured JSON output with schema validation | ✓ |

#### Reasoning Actions (`lib/jido_ai/actions/reasoning/`)
| Action | Purpose |
|--------|---------|
| `Analyze` | Deep analysis (sentiment, topics, entities) |
| `Explain` | Explanations at different detail levels |
| `Infer` | Draw logical inferences from premises |

#### Planning Actions (`lib/jido_ai/actions/planning/`)
| Action | Purpose |
|--------|---------|
| `Decompose` | Break problems into sub-tasks |
| `Plan` | Generate execution plans |
| `Prioritize` | Order tasks by importance |

#### Streaming Actions (`lib/jido_ai/actions/streaming/`)
| Action | Purpose |
|--------|---------|
| `StartStream` | Initialize streaming session |
| `ProcessTokens` | Handle streaming token chunks |
| `EndStream` | Finalize streaming session |

#### Tool Calling Actions (`lib/jido_ai/actions/tool_calling/`)
| Action | Purpose |
|--------|---------|
| `CallWithTools` | LLM call with tool execution loop |
| `ExecuteTool` | Direct tool execution by name |
| `ListTools` | List available registered tools |

---

### 2.2 Signals (6 types)

| Signal Type | Purpose | Emitted By |
|-------------|---------|------------|
| `reqllm.result` | LLM completion | `ReqLLMStream`, `ReqLLMGenerate` |
| `reqllm.partial` | Streaming token chunks | `ReqLLMStream` |
| `reqllm.error` | Structured LLM errors | Directive error handlers |
| `ai.tool_result` | Tool execution completion | `ToolExec` |
| `ai.embed_result` | Embedding completion | `ReqLLMEmbed` |
| `ai.usage_report` | Token usage/cost tracking | (inconsistent) |

---

### 2.3 Directives (4 types)

| Directive | Purpose | Result Signal |
|-----------|---------|---------------|
| `ReqLLMStream` | Stream LLM response | `reqllm.partial`, `reqllm.result` |
| `ReqLLMGenerate` | Non-streaming generation | `reqllm.result` |
| `ReqLLMEmbed` | Generate embeddings | `ai.embed_result` |
| `ToolExec` | Execute a Jido.Action as tool | `ai.tool_result` |

---

### 2.4 Skills (6 + 1 utility)

| Skill | Actions | State Key | Signal Patterns |
|-------|---------|-----------|-----------------|
| `LLM` | Chat, Complete, Embed | `:llm` | `llm.*` |
| `Reasoning` | Analyze, Explain, Infer | `:reasoning` | `reasoning.*` |
| `Planning` | Decompose, Plan, Prioritize | `:planning` | `planning.*` |
| `Streaming` | StartStream, ProcessTokens, EndStream | `:streaming` | `streaming.*` |
| `ToolCalling` | CallWithTools, ExecuteTool, ListTools | `:tool_calling` | `tool.*` |
| `TaskSupervisorSkill` | (internal supervision) | `__task_supervisor_skill__` | N/A |

**Utility Module:**
- `BaseActionHelpers` - Shared helper functions (not a skill)

---

### 2.5 Strategies (6 + helpers)

| Strategy | Machine Module | Use Case |
|----------|----------------|----------|
| `ReAct` | `ReAct.Machine` | Tool-using agents |
| `ChainOfThought` | `ChainOfThought.Machine` | Step-by-step reasoning |
| `TreeOfThoughts` | `TreeOfThoughts.Machine` | Branching exploration |
| `GraphOfThoughts` | `GraphOfThoughts.Machine` | Graph-based reasoning |
| `TRM` | `TRM.Machine` | Recursive improvement |
| `Adaptive` | (meta-strategy) | Strategy selection |

**Helper Modules:**
- `StateOpsHelpers` - State manipulation utilities
- `TRM.Helpers`, `TRM.Reasoning`, `TRM.Act`, `TRM.Supervision` - TRM internals

---

### 2.6 Agents (11 total)

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

| Module | Location | Purpose |
|--------|----------|---------|
| `Tools.Executor` | `lib/jido_ai/tools/executor.ex` | Execute actions, build tools map |
| `ToolAdapter` | `lib/jido_ai/tool_adapter.ex` | Convert Actions → ReqLLM.Tool |

**Deleted in Refactor:**
- `Tools.Registry` - Replaced by explicit tools map pattern
- `ToolCall` - Uses `ReqLLM.ToolCall.from_map/1` directly

---

### 2.8 Helpers & Support

| Module | Location | Purpose |
|--------|----------|---------|
| `Helpers` | `lib/jido_ai/helpers.ex` | General utilities |
| `Helpers.Text` | `lib/jido_ai/helpers/text.ex` | Text extraction utilities |
| `Security` | `lib/jido_ai/security.ex` | Input validation, sanitization |
| `Error` | `lib/jido_ai/error.ex` | Splode-based error handling |

---

## 3. Accuracy Subsystem

**Location:** `lib/jido_ai/accuracy/`

A sophisticated quality/reliability layer that was not documented in v1:

### 3.1 Core Components

| Module | Purpose |
|--------|---------|
| `Aggregator` | Combine multiple responses |
| `SelfConsistency` | Multi-sample consistency checking |
| `UncertaintyQuantification` | Confidence scoring |
| `DifficultyEstimate` | Task complexity assessment |
| `RateLimiter` | Request throttling |
| `SearchController` | Search-based refinement |
| `StrategyAdapter` | Adapt strategies for accuracy |
| `Telemetry` | Accuracy metrics |
| `Presets` | Pre-configured accuracy profiles |

### 3.2 Stages (Pipeline Components)

| Stage | Purpose |
|-------|---------|
| `DifficultyEstimationStage` | Assess task difficulty |
| `GenerationStage` | Primary generation |
| `ReflectionStage` | Self-reflection |
| `VerificationStage` | Output verification |
| `CalibrationStage` | Confidence calibration |
| `RAGStage` | Retrieval augmentation |
| `SearchStage` | Search refinement |

### 3.3 Aggregators

| Aggregator | Purpose |
|------------|---------|
| `BestOfN` | Select best from N samples |
| `MajorityVote` | Consensus via voting |
| `Weighted` | Weighted combination |

### 3.4 Result Types

| Type | Purpose |
|------|---------|
| `PipelineResult` | Full pipeline output |
| `RoutingResult` | Routing decision |
| `DecisionResult` | Classification decision |

---

## 4. Proposed Orchestration Layer

### 4.1 Overview

Jido's core provides multi-agent orchestration primitives that Jido.AI doesn't currently wrap:

**Available in Jido Core (not wrapped):**
- `SpawnAgent` directive - Spawn child agents
- `StopChild` directive - Stop children gracefully
- `emit_to_pid/2` - Parent → child communication
- `emit_to_parent/3` - Child → parent communication
- `await/2`, `await_all/2`, `await_any/2` - Coordination
- `cancel/2` - Task cancellation
- `get_children/1`, `get_child/2` - Child management

**Missing in Jido.AI:**
- AI-powered delegation decisions
- Capability discovery for routing
- Standardized task delegation protocol
- Result aggregation patterns

---

### 4.2 Proposed Actions

Create: `lib/jido_ai/actions/orchestration/`

#### SpawnChildAgent
Wrap Jido's `SpawnAgent` directive with AI-friendly interface.

```elixir
@schema Zoi.object(%{
  child_module: Zoi.atom(description: "Agent module to spawn"),
  child_opts: Zoi.map() |> Zoi.optional(),
  tag: Zoi.string(description: "Correlation tag for tracking"),
  timeout: Zoi.integer() |> Zoi.default(30_000),
  metadata: Zoi.map() |> Zoi.optional()
})
```

**Output:** `%{tag, child_pid, call_id}`

#### StopChildAgent
Wrap `StopChild` directive for graceful shutdown.

```elixir
@schema Zoi.object(%{
  child: Zoi.any(description: "Child pid or tag"),
  reason: Zoi.atom() |> Zoi.default(:normal),
  timeout: Zoi.integer() |> Zoi.default(5_000)
})
```

#### DelegateTask (LLM-Powered)
**The key AI orchestration primitive.** Uses LLM to decide routing.

```elixir
@schema Zoi.object(%{
  task: Zoi.string(description: "Task description"),
  available_agents: Zoi.list(Zoi.map(), description: "Agent capability descriptors"),
  constraints: Zoi.object(%{
    max_time_ms: Zoi.integer() |> Zoi.optional(),
    max_cost: Zoi.float() |> Zoi.optional(),
    required_capabilities: Zoi.list(Zoi.string()) |> Zoi.optional()
  }) |> Zoi.optional(),
  mode: Zoi.enum([:spawn, :reuse, :auto]) |> Zoi.default(:auto),
  model: Zoi.string() |> Zoi.optional()
})
```

**Output:** 
```elixir
{:delegate, %{
  target: :spawn | {:existing, pid},
  agent_module: Module,
  task_signal: Signal.t(),
  reasoning: String.t()
}} 
| {:local, %{plan: list(), reasoning: String.t()}}
```

#### RouteToSpecialist (LLM-Powered)
Classify task and route to appropriate specialist agent.

```elixir
@schema Zoi.object(%{
  task: Zoi.string(),
  specialists: Zoi.list(Zoi.object(%{
    name: Zoi.string(),
    capabilities: Zoi.list(Zoi.string()),
    agent_module: Zoi.atom() |> Zoi.optional(),
    agent_pid: Zoi.any() |> Zoi.optional()
  })),
  model: Zoi.string() |> Zoi.optional()
})
```

#### AggregateResults
Collect and merge results from multiple children.

```elixir
@schema Zoi.object(%{
  results: Zoi.list(Zoi.map()),
  strategy: Zoi.enum([:merge, :best, :vote, :llm_summarize]) |> Zoi.default(:merge),
  model: Zoi.string() |> Zoi.optional()  # For :llm_summarize
})
```

**Output:** `%{aggregated: any(), sources: list(), errors: list(), missing: list()}`

#### DiscoverCapabilities
Extract capability descriptors from agent modules.

```elixir
@schema Zoi.object(%{
  agent_modules: Zoi.list(Zoi.atom()),
  include_tools: Zoi.boolean() |> Zoi.default(true),
  include_skills: Zoi.boolean() |> Zoi.default(true)
})
```

**Output:** List of capability descriptors for routing decisions.

#### AwaitChildren
Wait for child agent results with timeout handling.

```elixir
@schema Zoi.object(%{
  tags: Zoi.list(Zoi.string(), description: "Tags to wait for"),
  mode: Zoi.enum([:all, :any, :first_n]) |> Zoi.default(:all),
  n: Zoi.integer() |> Zoi.optional(),  # For :first_n
  timeout: Zoi.integer() |> Zoi.default(30_000),
  on_timeout: Zoi.enum([:error, :partial, :cancel_remaining]) |> Zoi.default(:partial)
})
```

---

### 4.3 Proposed Signals

Add to `lib/jido_ai/signal.ex`:

| Signal Type | Purpose | Payload |
|-------------|---------|---------|
| `ai.delegation.request` | Task delegation request | `%{task, constraints, call_id}` |
| `ai.delegation.result` | Delegation completion | `%{result, source_agent, call_id}` |
| `ai.delegation.error` | Delegation failure | `%{error, source_agent, call_id}` |
| `ai.capability.query` | Capability discovery request | `%{required_capabilities}` |
| `ai.capability.response` | Capability discovery response | `%{capabilities, agent_ref}` |

---

### 4.4 Proposed Skill: Orchestration

Create: `lib/jido_ai/skills/orchestration.ex`

```elixir
defmodule Jido.AI.Skills.Orchestration do
  use Jido.Skill,
    name: "orchestration",
    description: "Multi-agent coordination and delegation",
    state_key: :orchestration

  # State structure
  @type state :: %{
    children: %{tag => %{pid: pid(), status: atom(), spawned_at: DateTime.t()}},
    inflight: %{call_id => %{tags: [String.t()], started_at: DateTime.t()}},
    capability_cache: %{module => capability_descriptor()}
  }

  # Signal routing
  def signal_routes(_ctx) do
    [
      {"jido.agent.child.started", {:skill_cmd, :child_started}},
      {"jido.agent.child.exit", {:skill_cmd, :child_exited}},
      {"ai.delegation.request", {:skill_cmd, :handle_delegation}},
      {"ai.delegation.result", {:skill_cmd, :handle_result}},
      {"ai.delegation.error", {:skill_cmd, :handle_error}}
    ]
  end

  # Commands
  def cmd(:spawn_child, agent, params, ctx) do
    # Build SpawnAgent directive, track in state
  end

  def cmd(:delegate_task, agent, params, ctx) do
    # Use DelegateTask action, spawn if needed, track correlation
  end

  def cmd(:scatter, agent, %{task: task, targets: targets}, ctx) do
    # Fan-out to multiple children
  end

  def cmd(:gather, agent, %{call_id: call_id}, ctx) do
    # Collect results from inflight request
  end

  def cmd(:scatter_gather, agent, params, ctx) do
    # Combined fan-out + await_all + aggregate
  end
end
```

---

### 4.5 Proposed Directive: AIDelegate

A high-level directive that combines LLM routing + spawn + send.

```elixir
defmodule Jido.AI.Directive.AIDelegate do
  @schema Zoi.struct(__MODULE__, %{
    id: Zoi.string(),
    task: Zoi.string(),
    available_agents: Zoi.list(Zoi.map()),
    model: Zoi.string() |> Zoi.optional(),
    timeout: Zoi.integer() |> Zoi.default(30_000)
  })

  # Execution:
  # 1. Call DelegateTask action to get routing decision
  # 2. If :spawn, create SpawnAgent directive + track
  # 3. If :existing, emit_to_pid
  # 4. Return {:async, correlation_info, state}
end
```

---

### 4.6 Workflow Patterns

#### Scatter-Gather
Fan-out work to multiple children, await all, aggregate.

```elixir
# Usage
Orchestration.scatter_gather(agent, %{
  task: "Analyze these documents",
  subtasks: ["doc1.pdf", "doc2.pdf", "doc3.pdf"],
  worker_module: DocumentAnalyzer,
  aggregation: :llm_summarize
})
```

#### Race/Hedged Requests
Send to multiple, take first response, cancel others.

```elixir
Orchestration.race(agent, %{
  task: "Get weather",
  targets: [WeatherAPI1, WeatherAPI2, WeatherAPI3],
  timeout: 5_000
})
```

#### Hierarchical Delegation
Parent delegates to specialist children who may delegate further.

```elixir
# Parent receives complex task
# → Routes to "ResearchAgent" child
#   → ResearchAgent spawns SearchWorker children
#   → Workers report back
#   → ResearchAgent aggregates and reports to parent
# → Parent receives final result
```

---

### 4.7 Capability Discovery Protocol

Agents can expose capabilities for routing:

```elixir
defmodule MySpecialistAgent do
  use Jido.Agent

  @impl true
  def capabilities do
    %{
      name: "document_analyzer",
      description: "Analyzes PDF and text documents",
      capabilities: ["pdf_parsing", "text_extraction", "summarization"],
      input_types: ["application/pdf", "text/plain"],
      estimated_latency_ms: 5_000,
      cost_per_call: 0.01
    }
  end
end
```

---

## 5. Data Flow Diagrams

### 5.1 Current Tool Execution Flow

```
User Query
    │
    ▼
┌─────────────────┐
│  Strategy.cmd   │ (e.g., ReAct)
└────────┬────────┘
         │ builds ReqLLMGenerate/Stream directive
         ▼
┌─────────────────┐
│ DirectiveExec   │
└────────┬────────┘
         │ async execution
         ▼
┌─────────────────┐     ┌─────────────────┐
│   ReqLLM call   │────▶│ reqllm.result   │
└─────────────────┘     │    signal       │
                        └────────┬────────┘
                                 │
         ┌───────────────────────┴────────────────────┐
         │                                            │
         ▼                                            ▼
┌─────────────────┐                          ┌─────────────────┐
│  Has tool_calls │──No──▶                   │   Return text   │
└────────┬────────┘                          └─────────────────┘
         │Yes
         ▼
┌─────────────────────────────────────────┐
│ For each tool_call:                     │
│   1. Look up in state[:actions_by_name] │
│   2. Build ToolExec directive           │
│   3. Execute via Jido.Exec              │
│   4. Emit ai.tool_result signal         │
└────────────────────┬────────────────────┘
                     │
                     ▼
         ┌─────────────────┐
         │ Continue loop   │
         │ until no tools  │
         └─────────────────┘
```

### 5.2 Proposed Orchestration Flow

```
Complex Task
    │
    ▼
┌─────────────────────────┐
│  Orchestration Skill    │
│  (or DelegateTask action)│
└───────────┬─────────────┘
            │ LLM routing decision
            ▼
    ┌───────┴───────┐
    │               │
    ▼               ▼
┌────────┐    ┌──────────────┐
│ :local │    │  :delegate   │
└────┬───┘    └──────┬───────┘
     │               │
     ▼               ▼
┌─────────┐   ┌─────────────────┐
│ Execute │   │ SpawnAgent or   │
│ locally │   │ emit_to_pid     │
└─────────┘   └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ Child executes  │
              │ reports result  │
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ ai.delegation   │
              │ .result signal  │
              └────────┬────────┘
                       │
                       ▼
              ┌─────────────────┐
              │ Parent receives │
              │ and aggregates  │
              └─────────────────┘
```

---

## 6. Identified Gaps

### 6.1 Critical Gaps (Blocking Orchestration)

| Gap | Description | Priority |
|-----|-------------|----------|
| **No orchestration actions** | SpawnAgent/StopChild not wrapped | P0 |
| **No delegation protocol** | No standard task/result message format | P0 |
| **No capability discovery** | Can't route based on agent capabilities | P1 |
| **No coordination utilities** | No scatter/gather/race patterns | P1 |

### 6.2 Existing Gaps (Still Valid)

| Gap | Description | Status |
|-----|-------------|--------|
| **Task supervisor retrieval** | Brittle pattern in `get_task_supervisor/1` | Open |
| **Usage report integration** | Not consistently integrated | Open |
| **Schema system split** | Zoi vs NimbleOptions coexistence | Managed |

### 6.3 New Gaps Discovered

| Gap | Description | Priority |
|-----|-------------|----------|
| **Accuracy ↔ Strategy integration** | Accuracy subsystem seems parallel to strategies | P2 |
| **GEPA integration** | Prompt optimization not integrated with actions | P3 |
| **Algorithm ↔ Orchestration** | Algorithms could inform orchestration patterns | P2 |

---

## 7. Overlaps & Refactoring Opportunities

### 7.1 Fixed in v1 Refactor

| Overlap | Resolution |
|---------|------------|
| Dual Tool Lookup | ✅ Registry deleted, explicit tools map only |
| Helpers duplication | ✅ Centralized in `Helpers.Text` |

### 7.2 Remaining Overlaps

| Overlap | Description | Recommendation |
|---------|-------------|----------------|
| **Accuracy vs Strategy** | Both define "how to reason" | Clarify: Strategy = control flow, Accuracy = quality layer |
| **Algorithms vs Strategies** | Sequential/Parallel/Composite overlap with orchestration | Consider: Algorithms for execution, Orchestration for multi-agent |
| **Skills state patterns** | Each skill manages own state | OK - composition is intentional |

### 7.3 Documentation Drift

| Issue | Description |
|-------|-------------|
| **ToolCalling skill docs** | Still references deleted Registry |
| **Map v1 primitive counts** | Several counts were incorrect |

---

## 8. Upstream Friction Points

### 8.1 Resolved

| Issue | Resolution |
|-------|------------|
| ToolCall normalization | ✅ `ReqLLM.ToolCall.from_map/1` |
| Int→float coercion | ✅ In `jido_action` |
| Empty schema JSON | ✅ In `jido_action` |

### 8.2 Open

| Issue | Package | Impact |
|-------|---------|--------|
| No unified tool spec protocol | All | Medium |
| Per-agent TaskSupervisor | jido | High (for orchestration) |
| `Response.text/1` helper | req_llm | Low |

### 8.3 New for Orchestration

| Issue | Package | Description |
|-------|---------|-------------|
| Child lifecycle events | jido | Need consistent signal format |
| Correlation ID propagation | jido | Need standard `call_id` in all messages |
| Capability protocol | jido | Standard `@callback capabilities()` |

---

## 9. Risk Assessment

### 9.1 Orchestration-Specific Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **Child agent leaks** | High | Track all spawned children, cleanup on parent exit |
| **Deadlock in await** | Medium | Timeouts + cancel_remaining option |
| **LLM routing loops** | Medium | Max delegation depth, cycle detection |
| **Cost explosion** | High | Budget constraints in DelegateTask |

### 9.2 Existing Risks (Still Valid)

| Risk | Mitigation |
|------|------------|
| Atom exhaustion | Use known keys only |
| Credential leakage | Sanitize error messages |
| Task leaks | Track by call_id |

---

## 10. Action Items

### 10.1 Phase 1: Orchestration Foundation (P0)

| Task | Effort | Description |
|------|--------|-------------|
| Create `actions/orchestration/spawn_child_agent.ex` | S | Wrap SpawnAgent directive |
| Create `actions/orchestration/stop_child_agent.ex` | S | Wrap StopChild directive |
| Create `actions/orchestration/await_children.ex` | M | Wrap await utilities |
| Add orchestration signals to `signal.ex` | S | delegation.request/result/error |
| Create `skills/orchestration.ex` | L | State + routing + commands |

### 10.2 Phase 2: AI-Powered Routing (P1)

| Task | Effort | Description |
|------|--------|-------------|
| Create `actions/orchestration/delegate_task.ex` | L | LLM-powered routing |
| Create `actions/orchestration/route_to_specialist.ex` | M | Classification-based routing |
| Create `actions/orchestration/discover_capabilities.ex` | M | Extract agent capabilities |
| Define capability descriptor format | S | Standard metadata shape |

### 10.3 Phase 3: Aggregation & Patterns (P2)

| Task | Effort | Description |
|------|--------|-------------|
| Create `actions/orchestration/aggregate_results.ex` | M | Result merging |
| Add scatter/gather commands to skill | M | Fan-out patterns |
| Add race/hedged commands | M | First-response patterns |
| Create `directive/ai_delegate.ex` | L | High-level delegation |

### 10.4 Documentation & Cleanup

| Task | Effort | Description |
|------|--------|-------------|
| Fix ToolCalling skill docs | S | Remove Registry references |
| Document Accuracy subsystem | M | It's undocumented |
| Add orchestration guide | L | Usage examples |

---

## Summary

### Current State
- **Strong LLM primitives**: Actions, Directives, Strategies work well
- **Undocumented complexity**: Accuracy, GEPA, Algorithms subsystems
- **Missing orchestration**: No multi-agent primitives despite Jido support

### Proposed Additions
1. **5 Orchestration Actions**: SpawnChildAgent, StopChildAgent, DelegateTask, RouteToSpecialist, AggregateResults, AwaitChildren, DiscoverCapabilities
2. **5 Orchestration Signals**: delegation.request/result/error, capability.query/response
3. **1 Orchestration Skill**: State management + signal routing + workflow patterns
4. **1 High-Level Directive**: AIDelegate for LLM-powered delegation

### Impact
This transforms Jido.AI from an "LLM wrapper" to a complete "AI agent orchestration layer" capable of:
- Dynamic task delegation based on LLM reasoning
- Multi-agent coordination patterns (scatter/gather, race, hierarchical)
- Capability-based routing
- Automatic result aggregation
