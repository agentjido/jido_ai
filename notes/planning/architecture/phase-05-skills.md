# Phase 5: Skills System

This phase implements the composable AI skills system. Skills are reusable capabilities that can be attached to agents, providing specific AI functionality like LLM interaction, reasoning, and planning.

## Design Principle

**Skills call ReqLLM directly.** Each skill implementation:
- Calls ReqLLM functions directly (`ReqLLM.stream_text/3`, `ReqLLM.generate_text/3`)
- Uses `Jido.AI.Config` for model resolution
- Uses `Jido.AI.Helpers` for common patterns
- No adapter/wrapper layer between skills and ReqLLM

## Module Structure

```
lib/jido_ai/
├── skills/
│   ├── llm_skill.ex        # LLM interaction skill
│   ├── reasoning_skill.ex  # Reasoning capabilities
│   ├── planning_skill.ex   # Goal decomposition
│   ├── streaming_skill.ex  # Stream handling
│   └── tool_calling_skill.ex # Tool integration
```

## Dependencies

- Phase 1: Foundation Enhancement
- Phase 2: Tool System

---

## 5.1 LLM Skill

Implement the core LLM interaction skill that provides text generation capabilities.

### 5.1.1 Skill Setup

Create the LLM skill module using Jido.Skill.

- [ ] 5.1.1.1 Create `lib/jido_ai/skills/llm_skill.ex` with module documentation
- [ ] 5.1.1.2 Use `Jido.Skill` with name, state_key, and actions
- [ ] 5.1.1.3 Define schema with model, api_key, temperature fields
- [ ] 5.1.1.4 List actions: Chat, Complete, Embed

### 5.1.2 Mount Callback

Implement skill mounting.

- [ ] 5.1.2.1 Implement `mount/2` callback with agent and config
- [ ] 5.1.2.2 Validate configuration (model, api_key)
- [ ] 5.1.2.3 Initialize skill state with config
- [ ] 5.1.2.4 Return `{:ok, initial_state}`

### 5.1.3 Chat Action

Implement chat completion action.

- [ ] 5.1.3.1 Create Chat action module
- [ ] 5.1.3.2 Accept messages, model, temperature parameters
- [ ] 5.1.3.3 Call `ReqLLM.generate_text/3` directly
- [ ] 5.1.3.4 Return formatted response

### 5.1.4 Complete Action

Implement text completion action.

- [ ] 5.1.4.1 Create Complete action module
- [ ] 5.1.4.2 Accept prompt, model, max_tokens parameters
- [ ] 5.1.4.3 Call `ReqLLM.generate_text/3` directly
- [ ] 5.1.4.4 Return completion text

### 5.1.5 Embed Action

Implement embedding generation action.

- [ ] 5.1.5.1 Create Embed action module
- [ ] 5.1.5.2 Accept texts, model parameters
- [ ] 5.1.5.3 Call ReqLLM embedding function directly
- [ ] 5.1.5.4 Return embedding vectors

### 5.1.6 Unit Tests for LLM Skill

- [ ] Test mount/2 validates configuration
- [ ] Test mount/2 initializes state correctly
- [ ] Test Chat action generates response
- [ ] Test Complete action returns text
- [ ] Test Embed action returns vectors
- [ ] Test error handling for API failures

---

## 5.2 Reasoning Skill

Implement the reasoning skill that provides analytical capabilities.

### 5.2.1 Skill Setup

Create the reasoning skill module.

- [ ] 5.2.1.1 Create `lib/jido_ai/skills/reasoning_skill.ex` with module documentation
- [ ] 5.2.1.2 Use `Jido.Skill` with name, state_key, and actions
- [ ] 5.2.1.3 Define schema with reasoning_model, depth fields
- [ ] 5.2.1.4 List actions: Analyze, Infer, Explain

### 5.2.2 Mount Callback

Implement skill mounting.

- [ ] 5.2.2.1 Implement `mount/2` callback
- [ ] 5.2.2.2 Configure reasoning model
- [ ] 5.2.2.3 Initialize reasoning context

### 5.2.3 Analyze Action

Implement analysis action.

- [ ] 5.2.3.1 Create Analyze action module
- [ ] 5.2.3.2 Accept topic, context, depth parameters
- [ ] 5.2.3.3 Build analysis prompt
- [ ] 5.2.3.4 Return structured analysis

### 5.2.4 Infer Action

Implement inference action.

- [ ] 5.2.4.1 Create Infer action module
- [ ] 5.2.4.2 Accept premises, question parameters
- [ ] 5.2.4.3 Build inference prompt
- [ ] 5.2.4.4 Return inference result with confidence

### 5.2.5 Explain Action

Implement explanation action.

- [ ] 5.2.5.1 Create Explain action module
- [ ] 5.2.5.2 Accept concept, audience parameters
- [ ] 5.2.5.3 Build explanation prompt
- [ ] 5.2.5.4 Return explanation with examples

### 5.2.6 Unit Tests for Reasoning Skill

- [ ] Test mount/2 configures reasoning model
- [ ] Test Analyze action returns structured analysis
- [ ] Test Infer action returns inference with confidence
- [ ] Test Explain action returns explanation
- [ ] Test reasoning depth affects output
- [ ] Test error handling

---

## 5.3 Planning Skill

Implement the planning skill for goal decomposition and planning.

### 5.3.1 Skill Setup

Create the planning skill module.

- [x] 5.3.1.1 Create `lib/jido_ai/skills/planning_skill.ex` with module documentation
- [x] 5.3.1.2 Use `Jido.Skill` with name, state_key, and actions
- [x] 5.3.1.3 Define schema with planning_model, max_steps fields
- [x] 5.3.1.4 List actions: Plan, Decompose, Prioritize

### 5.3.2 Mount Callback

Implement skill mounting.

- [x] 5.3.2.1 Implement `mount/2` callback
- [x] 5.3.2.2 Configure planning model
- [x] 5.3.2.3 Initialize plan state

### 5.3.3 Plan Action

Implement planning action.

- [x] 5.3.3.1 Create Plan action module
- [x] 5.3.3.2 Accept goal, constraints, resources parameters
- [x] 5.3.3.3 Generate structured plan with steps
- [x] 5.3.3.4 Return plan with dependencies

### 5.3.4 Decompose Action

Implement goal decomposition action.

- [x] 5.3.4.1 Create Decompose action module
- [x] 5.3.4.2 Accept goal, max_depth parameters
- [x] 5.3.4.3 Break goal into sub-goals
- [x] 5.3.4.4 Return hierarchical goal structure

### 5.3.5 Prioritize Action

Implement task prioritization action.

- [x] 5.3.5.1 Create Prioritize action module
- [x] 5.3.5.2 Accept tasks, criteria parameters
- [x] 5.3.5.3 Order tasks by priority
- [x] 5.3.5.4 Return ordered task list with scores

### 5.3.6 Unit Tests for Planning Skill

- [x] Test mount/2 configures planning model
- [x] Test Plan action returns structured plan
- [x] Test Decompose action breaks down goals
- [x] Test Prioritize action orders tasks
- [x] Test max_steps limit respected
- [x] Test error handling

---

## 5.4 Streaming Skill

Implement the streaming skill for real-time response handling.

### 5.4.1 Skill Setup

Create the streaming skill module.

- [ ] 5.4.1.1 Create `lib/jido_ai/skills/streaming_skill.ex` with module documentation
- [ ] 5.4.1.2 Use `Jido.Skill` with name, state_key, and actions
- [ ] 5.4.1.3 Define schema with buffer_size, on_token fields
- [ ] 5.4.1.4 List actions: StartStream, ProcessTokens, EndStream

### 5.4.2 Mount Callback

Implement skill mounting.

- [ ] 5.4.2.1 Implement `mount/2` callback
- [ ] 5.4.2.2 Configure token buffer
- [ ] 5.4.2.3 Set up token callback

### 5.4.3 StartStream Action

Implement stream start action.

- [ ] 5.4.3.1 Create StartStream action module
- [ ] 5.4.3.2 Accept prompt, model parameters
- [ ] 5.4.3.3 Call `ReqLLM.stream_text/3` directly
- [ ] 5.4.3.4 Return stream handle

### 5.4.4 ProcessTokens Action

Implement token processing action.

- [ ] 5.4.4.1 Create ProcessTokens action module
- [ ] 5.4.4.2 Accept stream_handle, callback parameters
- [ ] 5.4.4.3 Iterate over token stream
- [ ] 5.4.4.4 Invoke callback for each token

### 5.4.5 EndStream Action

Implement stream end action.

- [ ] 5.4.5.1 Create EndStream action module
- [ ] 5.4.5.2 Accept stream_handle parameter
- [ ] 5.4.5.3 Collect final usage/metadata
- [ ] 5.4.5.4 Return complete response

### 5.4.6 Unit Tests for Streaming Skill

- [ ] Test mount/2 configures buffer
- [ ] Test StartStream action initializes stream
- [ ] Test ProcessTokens action invokes callbacks
- [ ] Test EndStream action collects metadata
- [ ] Test token buffering works correctly
- [ ] Test error handling during streaming

---

## 5.5 Tool Calling Skill

Implement the tool calling skill for function execution.

### 5.5.1 Skill Setup

Create the tool calling skill module.

- [ ] 5.5.1.1 Create `lib/jido_ai/skills/tool_calling_skill.ex` with module documentation
- [ ] 5.5.1.2 Use `Jido.Skill` with name, state_key, and actions
- [ ] 5.5.1.3 Define schema with available_tools, auto_execute fields
- [ ] 5.5.1.4 List actions: CallWithTools, ExecuteTool, ListTools

### 5.5.2 Mount Callback

Implement skill mounting.

- [ ] 5.5.2.1 Implement `mount/2` callback
- [ ] 5.5.2.2 Load available tools from Registry
- [ ] 5.5.2.3 Configure auto-execution setting

### 5.5.3 CallWithTools Action

Implement tool-enabled LLM call action.

- [ ] 5.5.3.1 Create CallWithTools action module
- [ ] 5.5.3.2 Accept prompt, tools parameters
- [ ] 5.5.3.3 Call `ReqLLM.generate_text/3` with `tools:` option directly
- [ ] 5.5.3.4 Return response with tool calls

### 5.5.4 ExecuteTool Action

Implement tool execution action.

- [ ] 5.5.4.1 Create ExecuteTool action module
- [ ] 5.5.4.2 Accept tool_name, params parameters
- [ ] 5.5.4.3 Execute via Registry.execute_tool
- [ ] 5.5.4.4 Return tool result

### 5.5.5 ListTools Action

Implement tool listing action.

- [ ] 5.5.5.1 Create ListTools action module
- [ ] 5.5.5.2 Get tools from Registry
- [ ] 5.5.5.3 Return tool list with schemas

### 5.5.6 Auto-Execution

Implement automatic tool execution.

- [ ] 5.5.6.1 Implement `handle_tool_call/2` for auto-execution
- [ ] 5.5.6.2 Parse tool call from LLM response
- [ ] 5.5.6.3 Execute and return result to LLM
- [ ] 5.5.6.4 Support multi-turn tool conversations

### 5.5.7 Unit Tests for Tool Calling Skill

- [ ] Test mount/2 loads available tools
- [ ] Test CallWithTools action includes tools
- [ ] Test ExecuteTool action runs tool
- [ ] Test ListTools action returns tool list
- [ ] Test auto-execution handles tool calls
- [ ] Test multi-turn tool conversations
- [ ] Test error handling during execution

---

## 5.6 Phase 5 Integration Tests

Comprehensive integration tests verifying all Phase 5 components work together.

### 5.6.1 Skill Composition Integration

Verify skills compose correctly on agents.

- [ ] 5.6.1.1 Create `test/jido_ai/integration/skills_phase5_test.exs`
- [ ] 5.6.1.2 Test: Agent with multiple skills mounted
- [ ] 5.6.1.3 Test: Skills access shared agent state
- [ ] 5.6.1.4 Test: Skill actions invoked through agent

### 5.6.2 LLM Skill Integration

Test LLM skill with streaming and tools.

- [ ] 5.6.2.1 Test: LLM skill → Streaming skill flow
- [ ] 5.6.2.2 Test: LLM skill → Tool calling skill flow
- [ ] 5.6.2.3 Test: Combined streaming + tool calling

### 5.6.3 Reasoning and Planning Integration

Test reasoning and planning skill interaction.

- [ ] 5.6.3.1 Test: Reasoning skill informs planning
- [ ] 5.6.3.2 Test: Planning skill decomposes reasoning tasks
- [ ] 5.6.3.3 Test: Full analysis → plan → execute flow

---

## Phase 5 Success Criteria

1. **LLM Skill**: Chat, complete, and embed actions working
2. **Reasoning Skill**: Analysis, inference, and explanation actions
3. **Planning Skill**: Plan, decompose, and prioritize actions
4. **Streaming Skill**: Token-by-token streaming with callbacks
5. **Tool Calling Skill**: Tool execution with auto-execution
6. **Test Coverage**: Minimum 80% for Phase 5 modules

---

## Phase 5 Critical Files

**New Files:**
- `lib/jido_ai/skills/llm_skill.ex`
- `lib/jido_ai/skills/reasoning_skill.ex`
- `lib/jido_ai/skills/planning_skill.ex`
- `lib/jido_ai/skills/streaming_skill.ex`
- `lib/jido_ai/skills/tool_calling_skill.ex`
- `lib/jido_ai/skills/actions/chat.ex`
- `lib/jido_ai/skills/actions/complete.ex`
- `lib/jido_ai/skills/actions/embed.ex`
- `lib/jido_ai/skills/actions/analyze.ex`
- `lib/jido_ai/skills/actions/plan.ex`
- `test/jido_ai/skills/llm_skill_test.exs`
- `test/jido_ai/skills/reasoning_skill_test.exs`
- `test/jido_ai/skills/planning_skill_test.exs`
- `test/jido_ai/skills/streaming_skill_test.exs`
- `test/jido_ai/skills/tool_calling_skill_test.exs`
- `test/jido_ai/integration/skills_phase5_test.exs`
