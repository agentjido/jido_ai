# Jido AI Extension Architecture - Implementation Plan

This document outlines the implementation plan for extending Jido v2 with AI and Large Language Model (LLM) capabilities, leveraging ReqLLM as the primary LLM access layer.

## Architecture Reference

See [Architecture Research Document](../../research/jido_ai_extension_architecture.md) for detailed design specifications and code examples.

## Phase Overview

| Phase | Name | Description | Dependencies |
|-------|------|-------------|--------------|
| 1 | ReqLLM Integration Layer | Core adapter and client for LLM access | None |
| 2 | Tool System | Tool behavior, registry, and execution | Phase 1 |
| 3 | Algorithm Framework | Algorithm behaviors and implementations | Phase 1 |
| 4 | Strategy Implementations | AI strategies (ReAct, CoT, ToT, etc.) | Phase 1, 2, 3 |
| 5 | Skills System | Composable AI skills | Phase 1, 2 |
| 6 | Agent Types | AI-capable agent implementations | Phase 1-5 |
| 7 | Support Systems | Telemetry, performance, security | Phase 1-6 |

## Phase Details

### Phase 1: ReqLLM Integration Layer
**Files:** `lib/jido_ai/req_llm/`

Foundation layer providing Jido-friendly interface to ReqLLM capabilities:
- Adapter module for unified LLM access
- Client wrapper for request handling
- Streaming response processing
- Metadata extraction and processing

### Phase 2: Tool System
**Files:** `lib/jido_ai/tools/`

Tool calling infrastructure for LLM function execution:
- Tool behavior definition
- Tool registry (GenServer)
- Tool executor with context
- ReqLLM tool format conversion

### Phase 3: Algorithm Framework
**Files:** `lib/jido_ai/algorithms/`

Pluggable algorithm system for different execution patterns:
- Algorithm behavior callbacks
- Sequential, parallel, hybrid algorithms
- Algorithm composition

### Phase 4: Strategy Implementations
**Files:** `lib/jido_ai/strategies/`

AI reasoning strategies implementing Jido.Agent.Strategy:
- ReAct (Reasoning + Acting)
- Chain-of-Thought
- Tree-of-Thoughts
- Graph-of-Thoughts
- Adaptive strategy selection

### Phase 5: Skills System
**Files:** `lib/jido_ai/skills/`

Composable AI capabilities as Jido skills:
- LLM interaction skill
- Reasoning skill
- Planning skill
- Streaming skill
- Tool calling skill

### Phase 6: Agent Types
**Files:** `lib/jido_ai/agents/`

AI-capable agent implementations:
- Base AI agent
- Streaming AI agent
- Multi-model agent
- Tool-enabled agent
- Coordinator agent

### Phase 7: Support Systems
**Files:** `lib/jido_ai/telemetry/`, `lib/jido_ai/cache/`, `lib/jido_ai/security/`

Infrastructure for production deployment:
- Telemetry integration
- Performance optimization (caching, pooling)
- Security (API keys, content filtering)
- Configuration management

## Success Criteria

1. **Unified LLM Access**: Single interface for multiple providers via ReqLLM
2. **Streaming Support**: Real-time response streaming with metadata
3. **Tool Calling**: Native function calling support
4. **Structured Output**: Schema-based response generation
5. **Cost Tracking**: Usage and cost monitoring
6. **Test Coverage**: Minimum 80% coverage per phase
7. **Documentation**: Complete API documentation

## Critical Files

### Core Dependencies
- `lib/jido_ai.ex` - Main facade module
- `lib/jido_ai/error.ex` - Error handling

### Existing Files to Extend
- `lib/jido_ai/directive.ex` - Add AI directives
- `lib/jido_ai/signal.ex` - Add AI signals
- `lib/jido_ai/react_agent.ex` - Enhance with ReqLLM
- `lib/jido_ai/strategy/react.ex` - Update strategy
- `lib/jido_ai/tool_adapter.ex` - Extend tool conversion

### New Files by Phase
See individual phase documents for complete file listings.
