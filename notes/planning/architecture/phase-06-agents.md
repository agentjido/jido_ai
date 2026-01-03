# Phase 6: Agent Types

This phase implements AI-capable agent types that leverage all previous phases. Each agent type provides specialized AI capabilities for different use cases.

## Module Structure

```
lib/jido_ai/
├── agents/
│   ├── ai_agent.ex         # Base AI-capable agent
│   ├── streaming_ai_agent.ex # Real-time streaming agent
│   ├── multi_model_agent.ex  # Multiple LLM support
│   ├── tool_enabled_agent.ex # Function calling agent
│   └── coordinator_agent.ex  # Sub-agent management
```

## Dependencies

- Phase 1: ReqLLM Integration Layer
- Phase 2: Tool System
- Phase 3: Algorithm Framework
- Phase 4: Strategy Implementations
- Phase 5: Skills System

---

## 6.1 AI Agent Base

Implement the base AI-capable agent that extends Jido.Agent with AI-specific capabilities.

### 6.1.1 Agent Definition

Create the base AI agent module.

- [ ] 6.1.1.1 Create `lib/jido_ai/agents/ai_agent.ex` with module documentation
- [ ] 6.1.1.2 Use `Jido.Agent` with name, description, schema
- [ ] 6.1.1.3 Define schema fields: ai_model, ai_config, reasoning_state, memory_context
- [ ] 6.1.1.4 Set default strategy to ReAct
- [ ] 6.1.1.5 Configure default skills: LLMSkill, ReasoningSkill

### 6.1.2 Think Method

Implement AI thinking/reasoning method.

- [ ] 6.1.2.1 Implement `think/2` function with agent and prompt
- [ ] 6.1.2.2 Use configured strategy for reasoning
- [ ] 6.1.2.3 Return thought result and updated agent

### 6.1.3 Plan Method

Implement AI planning method.

- [ ] 6.1.3.1 Implement `plan/2` function with agent and goal
- [ ] 6.1.3.2 Use PlanningSkill for goal decomposition
- [ ] 6.1.3.3 Return plan and updated agent

### 6.1.4 Reflect Method

Implement AI reflection/learning method.

- [ ] 6.1.4.1 Implement `reflect/2` function with agent and experience
- [ ] 6.1.4.2 Analyze experience for learnings
- [ ] 6.1.4.3 Update agent state with reflections

### 6.1.5 Configuration

Implement agent configuration.

- [ ] 6.1.5.1 Implement `configure/2` for runtime configuration
- [ ] 6.1.5.2 Support model switching
- [ ] 6.1.5.3 Support strategy switching
- [ ] 6.1.5.4 Validate configuration changes

### 6.1.6 Unit Tests for AI Agent Base

- [ ] Test agent creation with default config
- [ ] Test think/2 returns thought result
- [ ] Test plan/2 returns structured plan
- [ ] Test reflect/2 updates agent state
- [ ] Test configure/2 updates model
- [ ] Test configure/2 validates config
- [ ] Test default strategy is ReAct

---

## 6.2 Streaming AI Agent

Implement the streaming AI agent for real-time response handling.

### 6.2.1 Agent Definition

Create the streaming AI agent module.

- [ ] 6.2.1.1 Create `lib/jido_ai/agents/streaming_ai_agent.ex` with module documentation
- [ ] 6.2.1.2 Extend AIAgent or use Jido.Agent with streaming-specific schema
- [ ] 6.2.1.3 Add schema fields: current_stream, streaming_status, reqllm_config
- [ ] 6.2.1.4 Configure with StreamingSkill

### 6.2.2 Start Stream Method

Implement stream start functionality.

- [ ] 6.2.2.1 Implement `start_stream/3` with agent, prompt, opts
- [ ] 6.2.2.2 Initialize stream via Adapter.stream_text
- [ ] 6.2.2.3 Update agent state with stream handle
- [ ] 6.2.2.4 Set streaming_status to :active

### 6.2.3 Token Access Methods

Implement token access methods.

- [ ] 6.2.3.1 Implement `get_stream_tokens/1` to access token stream
- [ ] 6.2.3.2 Implement `get_stream_usage/1` for usage metrics
- [ ] 6.2.3.3 Implement `get_stream_metadata/1` for stream info

### 6.2.4 Stop Stream Method

Implement stream stop functionality.

- [ ] 6.2.4.1 Implement `stop_stream/1` to end streaming
- [ ] 6.2.4.2 Collect final metadata
- [ ] 6.2.4.3 Set streaming_status to :completed

### 6.2.5 Streaming Callbacks

Implement callback support for streaming.

- [ ] 6.2.5.1 Implement `on_token/2` callback registration
- [ ] 6.2.5.2 Implement `on_complete/2` callback registration
- [ ] 6.2.5.3 Invoke callbacks during stream processing

### 6.2.6 Unit Tests for Streaming AI Agent

- [ ] Test start_stream/3 initializes stream
- [ ] Test get_stream_tokens/1 returns token stream
- [ ] Test get_stream_usage/1 returns metrics
- [ ] Test stop_stream/1 ends stream
- [ ] Test on_token/2 callback invoked
- [ ] Test on_complete/2 callback invoked
- [ ] Test streaming_status transitions

---

## 6.3 Multi-Model Agent

Implement the multi-model agent for using multiple LLMs.

### 6.3.1 Agent Definition

Create the multi-model agent module.

- [ ] 6.3.1.1 Create `lib/jido_ai/agents/multi_model_agent.ex` with module documentation
- [ ] 6.3.1.2 Extend AIAgent with model management
- [ ] 6.3.1.3 Add schema fields: models, current_model, model_selection_strategy
- [ ] 6.3.1.4 Configure with ModelSelectionSkill

### 6.3.2 Model Management

Implement model management methods.

- [ ] 6.3.2.1 Implement `with_model/2` to switch model
- [ ] 6.3.2.2 Implement `add_model/3` to register model
- [ ] 6.3.2.3 Implement `remove_model/2` to unregister model
- [ ] 6.3.2.4 Implement `list_models/1` to get available models

### 6.3.3 Model Selection

Implement automatic model selection.

- [ ] 6.3.3.1 Implement `select_best_model/2` with agent and task
- [ ] 6.3.3.2 Analyze task requirements
- [ ] 6.3.3.3 Match to model capabilities
- [ ] 6.3.3.4 Consider cost/performance trade-offs

### 6.3.4 Model Fallback

Implement model fallback logic.

- [ ] 6.3.4.1 Implement `with_fallback/3` for fallback chain
- [ ] 6.3.4.2 Try primary model first
- [ ] 6.3.4.3 Fall back to secondary on failure
- [ ] 6.3.4.4 Track fallback statistics

### 6.3.5 Cost Tracking

Implement cost tracking across models.

- [ ] 6.3.5.1 Implement `get_usage_stats/1` for cost metrics
- [ ] 6.3.5.2 Track tokens per model
- [ ] 6.3.5.3 Track cost per model
- [ ] 6.3.5.4 Support budget limits

### 6.3.6 Unit Tests for Multi-Model Agent

- [ ] Test with_model/2 switches model
- [ ] Test add_model/3 registers model
- [ ] Test select_best_model/2 chooses appropriate model
- [ ] Test with_fallback/3 falls back on error
- [ ] Test get_usage_stats/1 returns metrics
- [ ] Test budget limit enforcement

---

## 6.4 Tool-Enabled Agent

Implement the tool-enabled agent for function calling.

### 6.4.1 Agent Definition

Create the tool-enabled agent module.

- [ ] 6.4.1.1 Create `lib/jido_ai/agents/tool_enabled_agent.ex` with module documentation
- [ ] 6.4.1.2 Extend AIAgent with tool capabilities
- [ ] 6.4.1.3 Add schema fields: available_tools, tool_execution_mode
- [ ] 6.4.1.4 Configure with ToolCallingSkill

### 6.4.2 Tool Management

Implement tool management methods.

- [ ] 6.4.2.1 Implement `available_tools/1` to list tools
- [ ] 6.4.2.2 Implement `add_tool/2` to add tool
- [ ] 6.4.2.3 Implement `remove_tool/2` to remove tool
- [ ] 6.4.2.4 Implement `get_tool/2` to get specific tool

### 6.4.3 Tool Execution

Implement tool execution methods.

- [ ] 6.4.3.1 Implement `execute_tool/3` with agent, tool_name, params
- [ ] 6.4.3.2 Validate parameters against tool schema
- [ ] 6.4.3.3 Execute via Registry
- [ ] 6.4.3.4 Return result and updated agent

### 6.4.4 Auto-Execution Mode

Implement automatic tool execution.

- [ ] 6.4.4.1 Implement `set_auto_execute/2` to enable/disable
- [ ] 6.4.4.2 Automatically execute tool calls from LLM
- [ ] 6.4.4.3 Feed results back to LLM
- [ ] 6.4.4.4 Support approval workflow

### 6.4.5 Tool Chaining

Implement tool chaining for complex workflows.

- [ ] 6.4.5.1 Implement `chain_tools/2` for sequential execution
- [ ] 6.4.5.2 Pass output of one tool to next
- [ ] 6.4.5.3 Handle errors in chain
- [ ] 6.4.5.4 Return combined result

### 6.4.6 Unit Tests for Tool-Enabled Agent

- [ ] Test available_tools/1 returns tools
- [ ] Test add_tool/2 registers tool
- [ ] Test execute_tool/3 runs tool
- [ ] Test auto-execute mode works
- [ ] Test chain_tools/2 sequences tools
- [ ] Test error handling in chains

---

## 6.5 Coordinator Agent

Implement the coordinator agent for sub-agent management.

### 6.5.1 Agent Definition

Create the coordinator agent module.

- [ ] 6.5.1.1 Create `lib/jido_ai/agents/coordinator_agent.ex` with module documentation
- [ ] 6.5.1.2 Extend AIAgent with coordination capabilities
- [ ] 6.5.1.3 Add schema fields: sub_agents, coordination_strategy
- [ ] 6.5.1.4 Configure with SubagentSkill

### 6.5.2 Sub-Agent Spawning

Implement sub-agent spawning.

- [ ] 6.5.2.1 Implement `spawn_subagent/3` with agent, module, config
- [ ] 6.5.2.2 Create sub-agent with specified config
- [ ] 6.5.2.3 Register in coordinator's sub_agents
- [ ] 6.5.2.4 Return sub-agent handle

### 6.5.3 Task Distribution

Implement task distribution to sub-agents.

- [ ] 6.5.3.1 Implement `distribute_task/3` with agent, task, strategy
- [ ] 6.5.3.2 Support :round_robin distribution
- [ ] 6.5.3.3 Support :capability_based distribution
- [ ] 6.5.3.4 Support :parallel distribution

### 6.5.4 Result Collection

Implement result collection from sub-agents.

- [ ] 6.5.4.1 Implement `collect_results/2` with agent, timeout
- [ ] 6.5.4.2 Wait for all sub-agent results
- [ ] 6.5.4.3 Handle timeouts gracefully
- [ ] 6.5.4.4 Merge results per strategy

### 6.5.5 Coordination Strategies

Implement coordination strategies.

- [ ] 6.5.5.1 Implement `coordinate/3` with agent, task, strategy
- [ ] 6.5.5.2 Support :sequential coordination
- [ ] 6.5.5.3 Support :parallel coordination
- [ ] 6.5.5.4 Support :hierarchical coordination

### 6.5.6 Sub-Agent Communication

Implement inter-agent communication.

- [ ] 6.5.6.1 Implement `send_to_subagent/3` for messaging
- [ ] 6.5.6.2 Implement `broadcast/2` for all sub-agents
- [ ] 6.5.6.3 Handle responses from sub-agents

### 6.5.7 Unit Tests for Coordinator Agent

- [ ] Test spawn_subagent/3 creates sub-agent
- [ ] Test distribute_task/3 with round_robin
- [ ] Test distribute_task/3 with capability_based
- [ ] Test collect_results/2 gathers results
- [ ] Test coordinate/3 with parallel strategy
- [ ] Test send_to_subagent/3 delivers message
- [ ] Test broadcast/2 reaches all sub-agents

---

## 6.6 Phase 6 Integration Tests

Comprehensive integration tests verifying all Phase 6 components work together.

### 6.6.1 Agent Lifecycle Integration

Verify agent lifecycle with AI capabilities.

- [ ] 6.6.1.1 Create `test/jido_ai/integration/agents_phase6_test.exs`
- [ ] 6.6.1.2 Test: AIAgent → think → plan → reflect cycle
- [ ] 6.6.1.3 Test: StreamingAIAgent complete streaming flow
- [ ] 6.6.1.4 Test: ToolEnabledAgent tool execution cycle

### 6.6.2 Multi-Agent Integration

Test multi-agent scenarios.

- [ ] 6.6.2.1 Test: Coordinator spawns and manages sub-agents
- [ ] 6.6.2.2 Test: Task distribution to multiple agents
- [ ] 6.6.2.3 Test: Result collection and merging
- [ ] 6.6.2.4 Test: Hierarchical coordination

### 6.6.3 Strategy and Agent Integration

Test agents with different strategies.

- [ ] 6.6.3.1 Test: AIAgent with ReAct strategy
- [ ] 6.6.3.2 Test: AIAgent with CoT strategy
- [ ] 6.6.3.3 Test: Agent strategy switching
- [ ] 6.6.3.4 Test: Adaptive strategy selection

---

## Phase 6 Success Criteria

1. **AI Agent Base**: Think, plan, reflect methods working
2. **Streaming AI Agent**: Real-time token streaming with callbacks
3. **Multi-Model Agent**: Model switching and fallback working
4. **Tool-Enabled Agent**: Tool execution and chaining
5. **Coordinator Agent**: Sub-agent spawning and coordination
6. **Test Coverage**: Minimum 80% for Phase 6 modules

---

## Phase 6 Critical Files

**New Files:**
- `lib/jido_ai/agents/ai_agent.ex`
- `lib/jido_ai/agents/streaming_ai_agent.ex`
- `lib/jido_ai/agents/multi_model_agent.ex`
- `lib/jido_ai/agents/tool_enabled_agent.ex`
- `lib/jido_ai/agents/coordinator_agent.ex`
- `test/jido_ai/agents/ai_agent_test.exs`
- `test/jido_ai/agents/streaming_ai_agent_test.exs`
- `test/jido_ai/agents/multi_model_agent_test.exs`
- `test/jido_ai/agents/tool_enabled_agent_test.exs`
- `test/jido_ai/agents/coordinator_agent_test.exs`
- `test/jido_ai/integration/agents_phase6_test.exs`

**Modified Files:**
- `lib/jido_ai/react_agent.ex` - Enhance base implementation
