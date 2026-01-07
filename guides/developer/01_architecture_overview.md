# Jido.AI Architecture Overview

**Jido.AI** is the AI integration layer for the Jido ecosystem, providing LLM orchestration capabilities for building sophisticated AI agents.

## Table of Contents

1. [Overview](#overview)
2. [Core Principles](#core-principles)
3. [Architecture](#architecture)
4. [Component Relationships](#component-relationships)
5. [Data Flows](#data-flows)
6. [Directory Structure](#directory-structure)
7. [Related Guides](#related-guides)

---

## Overview

Jido.AI provides:

- **Multi-Strategy Reasoning**: ReAct, Chain-of-Thought, Graph-of-Thoughts, Tree-of-Thoughts, TRM, Adaptive
- **Tool Execution**: Unified tool system with registry and executor
- **Prompt Optimization**: GEPA (Genetic-Pareto Prompt Evolution) for automated prompt improvement
- **Streaming Support**: Real-time streaming of LLM responses
- **Extensibility**: Plugin architecture for custom strategies and tools

---

## Core Principles

### 1. Separation of Concerns

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Strategy      │────▶│  State Machine  │────▶│   Directives    │
│   (Orchestration)│     │   (Pure Logic)  │     │  (Effects)       │
└─────────────────┘     └─────────────────┘     └─────────────────┘
```

- **Strategies**: Orchestrate agent behavior, handle I/O
- **State Machines**: Pure functional logic, no side effects
- **Directives**: Describe external effects (LLM calls, tool execution)

### 2. Pure State Machines

All strategies use Fsmx-based state machines:

```elixir
# Pure state transitions
{machine, directives} = Machine.update(machine, message, env)

# No side effects in machine
# All effects described in directives
```

### 3. Type Safety

- **Zoi schemas** for parameter validation
- **TypeSpecs** for all public functions
- **Structured errors** via Splode

### 4. Observability

Comprehensive telemetry throughout:

```elixir
:telemetry.execute([:jido, :ai, :event], measurements, metadata)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Jido.AI Architecture                          │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                         Strategy Layer                               │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │   │
│  │  │  ReAct   │ │    CoT   │ │    GoT   │ │    ToT   │ │   TRM    │  │   │
│  │  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘  │   │
│  └───────┼────────────┼────────────┼────────────┼────────────┼──────────┘   │
│          │            │            │            │            │            │
│          ▼            ▼            ▼            ▼            ▼            │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                        State Machine Layer                           │ │
│  │  Pure functional state machines (Fsmx)                               │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                  │                                        │
│                                  ▼                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                          Directive Layer                             │ │
│  │  ReqLLMStream │ ToolExec │ ReqLLMGenerate │ ReqLLMEmbed             │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                  │                                        │
│                                  ▼                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                           Signal Layer                               │ │
│  │  ReqLLMResult │ ReqLLMPartial │ ToolResult │ UsageReport            │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                  │                                        │
│                                  ▼                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                           Tool System                                │ │
│  │  Registry │ Executor │ ToolAdapter │ ToolBase                      │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                          GEPA System                                 │ │
│  │  Optimizer │ Evaluator │ Reflector │ Selection │ PromptVariant       │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐ │
│  │                          Skills System                               │ │
│  │  LLM │ Planning │ Reasoning │ Streaming │ ToolCalling               │ │
│  └──────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Component Relationships

### Strategy → State Machine → Directive Flow

```elixir
# 1. Strategy receives instruction
def cmd(agent, instructions, _ctx) do
  # 2. Convert to machine message
  msg = to_machine_msg(instruction)

  # 3. Update state machine
  {machine, directives} = Machine.update(machine, msg, env)

  # 4. Convert directives to SDK structs
  sdk_directives = lift_directives(directives, config)

  {agent, sdk_directives}
end
```

### Signal Flow

```elixir
# 1. Strategy defines signal routes
def signal_routes(_ctx) do
  [
    {"reqllm.result", {:strategy_cmd, :react_llm_result}},
    {"ai.tool_result", {:strategy_cmd, :react_tool_result}}
  ]
end

# 2. AgentServer routes signals automatically
# 3. Strategy receives as instruction
```

### Tool Execution Flow

```
┌──────────────┐
│ Strategy     │ Issues ToolExec directive
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ AgentServer  │ Executes directive
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Executor     │ Normalizes params, calls action
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ Jido.Action  │ User-defined action
└──────┬───────┘
       │
       ▼
┌──────────────┐
│ ToolResult   │ Signal sent back
│ Signal       │
└──────────────┘
```

---

## Data Flows

### ReAct Reasoning Flow

```
User Query
    │
    ▼
┌─────────────────┐
│ ReAct Strategy  │ Start with query
└────────┬────────┘
         │
         ▼
┌─────────────────┐     call_llm_stream
│ ReAct Machine   │─────────────────────▶ LLM
└────────┬────────┘
         │
         │ ◀─ tool_calls ────────────────┤
         │
         ▼
┌─────────────────┐     exec_tool
│ ToolExec        │─────────────────────▶ Tool
└────────┬────────┘
         │
         │ ◀─ tool_result ───────────────┤
         │
         ▼
    Loop until final_answer
```

### Chain-of-Thought Flow

```
User Query
    │
    ▼
┌─────────────────────┐
│ CoT Strategy        │ "Think step by step"
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐     call_llm_stream
│ CoT Machine         │─────────────────────▶ LLM
└────────┬────────────┘
         │
         │ ◀─ reasoning with steps ───────┤
         │
         ▼
┌─────────────────────┐
│ Extract Steps       │ Parse "Step 1:", "Step 2:"
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐
│ Format Conclusion   │ "Conclusion: ..."
└─────────────────────┘
```

### GEPA Optimization Flow

```
Initial Prompt
    │
    ▼
┌─────────────────────┐
│ GEPA Optimizer      │
└────────┬────────────┘
         │
         ▼
┌─────────────────────┐     Evaluate     ┌──────────────┐
│ Reflector           │─────────────────▶│ Evaluator    │
│ (Mutate/Crossover)  │                 │ (Test tasks) │
└─────────────────────┘                 └──────┬───────┘
         │                                         │
         │                                         │
         ▼                                         ▼
┌─────────────────────┐     Select       ┌──────────────┐
│ Selection           │◀────────────────│ Variants     │
│ (Pareto-optimal)    │                 └──────────────┘
└────────┬────────────┘
         │
         ▼
    Next Generation
```

---

## Directory Structure

```
lib/jido_ai/
├── jido_ai.ex                    # Main facade module
├── config.ex                     # Configuration & model aliases
├── directive.ex                  # Directive definitions
├── signal.ex                     # Signal types
├── tool_adapter.ex               # Action → Tool conversion
│
├── strategies/                   # Strategy implementations
│   ├── react.ex                  # ReAct (Reason-Act)
│   ├── chain_of_thought.ex       # Chain-of-Thought
│   ├── graph_of_thoughts.ex      # Graph-of-Thoughts
│   ├── tree_of_thoughts.ex       # Tree-of-Thoughts
│   ├── trm.ex                    # Tree-Reasoning-Machine
│   └── adaptive.ex               # Adaptive strategy selection
│
├── react/                        # ReAct components
│   └── machine.ex                # Pure ReAct state machine
│
├── chain_of_thought/             # CoT components
│   └── machine.ex                # Pure CoT state machine
│
├── tree_of_thoughts/             # ToT components
│   └── machine.ex                # Pure ToT state machine
│
├── trm/                          # TRM components
│   ├── machine.ex                # Pure TRM state machine
│   ├── act.ex                    # TRM action execution
│   ├── reasoning.ex              # TRM reasoning components
│   └── supervision.ex            # TRM quality supervision
│
├── tools/                        # Tool system
│   ├── registry.ex               # Tool registration
│   ├── executor.ex               # Tool execution
│   └── tool.ex                   # Base tool behavior
│
├── gepa/                         # GEPA system
│   ├── optimizer.ex              # Main optimization loop
│   ├── evaluator.ex              # Variant evaluation
│   ├── reflector.ex              # Mutations & crossovers
│   ├── selection.ex              # Pareto selection
│   ├── prompt_variant.ex         # Variant representation
│   ├── task.ex                   # Evaluation tasks
│   └── helpers.ex                # Utility functions
│
├── skills/                       # Capability-based skills
│   ├── llm/                      # LLM skills
│   │   ├── chat.ex
│   │   ├── complete.ex
│   │   └── embed.ex
│   ├── planning/                 # Planning skills
│   ├── reasoning/                # Reasoning skills
│   ├── streaming/                # Streaming skills
│   └── tool_calling/             # Tool calling skills
│
├── algorithms/                   # Supporting algorithms
│   ├── base.ex
│   ├── composite.ex
│   ├── hybrid.ex
│   ├── parallel.ex
│   ├── sequential.ex
│   └── helpers.ex
│
└── error.ex                      # Structured error handling
```

---

## Related Guides

- [Strategies Guide](./strategies.md) - Detailed strategy implementations
- [State Machines Guide](./state_machines.md) - Pure state machine patterns
- [Directives Guide](./directives.md) - Directive system
- [Signals Guide](./signals.md) - Signal types and routing
- [Tool System Guide](./tool_system.md) - Tool registry and execution
- [GEPA Guide](./gepa.md) - Prompt optimization
- [Skills Guide](./skills.md) - Capability-based skills
