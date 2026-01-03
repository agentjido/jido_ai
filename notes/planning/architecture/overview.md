# Jido AI Extension Architecture - Implementation Plan

This document outlines the implementation plan for extending Jido v2 with AI and Large Language Model (LLM) capabilities, leveraging ReqLLM as the primary LLM access layer.

## Architecture Reference

See [Architecture Research Document](../../research/jido_ai_extension_architecture.md) for detailed design specifications and code examples.

## Core Design Principle

**Use ReqLLM directly - no wrapper layers.**

ReqLLM is a direct dependency of Jido.AI. All components should call ReqLLM functions directly:

```elixir
# Correct: Direct ReqLLM usage
ReqLLM.stream_text(model, messages, tools: tools)
ReqLLM.generate_text(model, messages, opts)

# Incorrect: Wrapper/adapter pattern (DON'T DO THIS)
Jido.AI.Adapter.stream_text(model, messages, opts)  # NO!
Jido.AI.Client.generate(model, messages)             # NO!
```

The existing codebase already follows this pattern:
- `Jido.AI.Directive.ReqLLMStream` calls `ReqLLM.stream_text/3` directly
- `Jido.AI.ToolAdapter` converts Jido.Actions to `ReqLLM.Tool` structs
- Strategies and skills should follow the same pattern

## Phase Overview

| Phase | Name | Description | Dependencies |
|-------|------|-------------|--------------|
| 1 | Foundation Enhancement | Configuration, directives, signals, helpers | None |
| 2 | Tool System | Tool behavior, registry, unified execution | Phase 1 |
| 3 | Algorithm Framework | Algorithm behaviors and implementations | Phase 1 |
| 4 | Strategy Implementations | AI strategies (ReAct, CoT, ToT, etc.) | Phase 1, 2, 3 |
| 5 | Skills System | Composable AI skills | Phase 1, 2 |
| 6 | Support Systems | Telemetry, performance, security | Phase 1-5 |

## Phase Details

### Phase 1: Foundation Enhancement
**Focus:** Enhance existing ReqLLM integration, not wrap it.

- Configuration module (model aliases, provider settings)
- Enhanced directives (ReqLLMGenerate, ReqLLMEmbed)
- Enhanced signals (EmbedResult, UsageReport)
- Tool adapter improvements (registry, schema conversion)
- Helper utilities (message building, response processing)

**Key Files:**
- `lib/jido_ai/config.ex` (NEW)
- `lib/jido_ai/helpers.ex` (NEW)
- `lib/jido_ai/directive.ex` (ENHANCE)
- `lib/jido_ai/signal.ex` (ENHANCE)

### Phase 2: Tool System
**Focus:** Manage Jido.Actions and simple tools for LLM function calling.

- Tool behavior for lightweight tools
- Registry for actions and tools
- Unified executor with error handling
- ToolExec directive enhancement

**Key Files:**
- `lib/jido_ai/tools/tool.ex`
- `lib/jido_ai/tools/registry.ex`
- `lib/jido_ai/tools/executor.ex`

### Phase 3: Algorithm Framework
**Focus:** Pluggable algorithm system for different execution patterns.

- Algorithm behavior callbacks
- Sequential, parallel, hybrid algorithms
- Algorithm composition

**Key Files:**
- `lib/jido_ai/algorithms/algorithm.ex`
- `lib/jido_ai/algorithms/sequential.ex`
- `lib/jido_ai/algorithms/parallel.ex`

### Phase 4: Strategy Implementations
**Focus:** AI reasoning strategies using ReqLLM directly.

- ReAct (Reasoning + Acting) - enhance existing
- Chain-of-Thought
- Tree-of-Thoughts
- Graph-of-Thoughts
- Adaptive strategy selection

**Key Files:**
- `lib/jido_ai/strategies/react.ex` (ENHANCE)
- `lib/jido_ai/strategies/chain_of_thought.ex`
- `lib/jido_ai/strategies/adaptive.ex`

### Phase 5: Skills System
**Focus:** Composable AI capabilities calling ReqLLM directly.

- LLM Skill (chat, complete, embed)
- Reasoning Skill
- Planning Skill
- Streaming Skill
- Tool Calling Skill

**Key Files:**
- `lib/jido_ai/skills/llm_skill.ex`
- `lib/jido_ai/skills/reasoning_skill.ex`
- `lib/jido_ai/skills/planning_skill.ex`

### Phase 6: Support Systems
**Focus:** Infrastructure for production deployment.

- Telemetry integration
- Performance optimization (caching, pooling)
- Security (API keys, content filtering)
- Configuration management

**Key Files:**
- `lib/jido_ai/telemetry/telemetry.ex`
- `lib/jido_ai/cache/cache.ex`
- `lib/jido_ai/security/security.ex`

## Success Criteria

1. **Direct ReqLLM Usage**: No wrapper/adapter layers around ReqLLM
2. **Streaming Support**: Real-time response streaming with metadata
3. **Tool Calling**: Native function calling via ReqLLM
4. **Structured Output**: Schema-based response generation
5. **Cost Tracking**: Usage and cost monitoring via telemetry
6. **Test Coverage**: Minimum 80% coverage per phase
7. **Documentation**: Complete API documentation

## Existing Files (Reference)

These files already exist and should be enhanced, not replaced:

- `lib/jido_ai.ex` - Main facade module
- `lib/jido_ai/directive.ex` - ReqLLMStream, ToolExec directives
- `lib/jido_ai/signal.ex` - ReqLLMResult, ReqLLMPartial, ToolResult signals
- `lib/jido_ai/tool_adapter.ex` - Action → ReqLLM.Tool conversion
- `lib/jido_ai/error.ex` - Splode-based error handling
- `lib/jido_ai/react_agent.ex` - Base ReAct agent
- `lib/jido_ai/strategy/react.ex` - ReAct strategy
- `lib/jido_ai/react/machine.ex` - Fsmx state machine
