# Proposed example backlog

This document is a working backlog for the Jido AI example catalog. It is not
a stable public contract. The examples should show a clear capability ladder.
They should not copy the internal module layout.

Each example should add one main public feature. It should use the public API,
include one important failure case, and have a matching test. Detailed error
matrices belong in unit and contract tests.

The catalog uses the current core Jido model:

- `Jido.Agent.Route` owns the accepted Signal type, executable, state
  projection, and optional correlated reply projection.
- Actions and Flows own executable input and output schemas.
- Standalone typed Signal Action wrappers are not part of the current design.
- A reasoning policy is a normal Jido Flow. It can be a module or an inline
  `reasoning do` Flow.
- Jido Agent and AgentServer remain the only Agent runtime.

## Implemented architecture and request-contract checkpoint

The local core Jido compatibility update passed the technical gate below on
October 24, 2026. The catalog includes these foundations:

- typed request and reply operations through core Agent Routes
- explicit completed and failed `Jido.AI.Result` values
- atomic routed-turn state rules through `Jido.AI.Turn`
- pure `preflight/2` request preparation
- Session and Thread projection through `Jido.AI.Context`
- request-specific `visible_tools:` selection
- correlated ordered `Jido.AI.Event` Maps
- fresh Session and Thread data through core `initialize/2`
- module and inline reasoning Flows through one `reasoning` declaration

See `01_basics/01_06_request_contract` and
`02_conversations/02_04_conversation_history`.

## Capability ladder

| Rung | Capability | Main lesson | Current source |
| --- | --- | --- | --- |
| 1. Generate | Produce one answer | Agent, model, instructions, and default reasoning | `01_01_basic_agent` |
| 2. Structure | Produce a typed reply | Agent Route reply projection and structured output | `01_03_structured_output` |
| 3. Act | Use tools | Action tools, Flow tools, and the ReAct loop | `01_02_tool_flow` |
| 4. Govern | Bound one turn | One input control, one output control, time limits, and call limits | `01_04_controls` |
| 5. Remember | Keep conversation state | Thread, Session, `initialize/2`, and history | Current `02_*` examples |
| 6. Run | Execute long work | Synchronous, asynchronous, streaming, await, and cancel | `01_05_streaming` and `02_05_request_modes` |
| 7. Correct | Change active work | Steering and injected input | Old `02_02_steering` |
| 8. Observe | Inspect work | Usage, semantic trace, request status, and failure position | Old call-count and inspection examples |
| 9. Recover | Handle failure safely | Output failure, tool failure, commit boundary, checkpoint, and resume | Old completion and resume examples |
| 10. Compose | Build a larger Agent | Plugins, core routes, topology, and child Agents | Current composition examples |
| 11. Specialize | Add domain capability | Routing, retrieval, planning, reasoning methods, and skills | Old capability tracks |
| 12. Integrate | Build a complete application Agent | Research Agent capstone | `99_proposed/research_agent` |

The complete story is:

> A Jido AI Agent can generate, structure, act, govern, remember, run, accept
> corrections, expose evidence, recover, compose, specialize, and integrate.

## 01 — Foundations

### 01_01_basic_agent

- Make one model call.
- Return one text answer.
- Show the smallest valid AI Agent.

### 01_02_structured_reply

- Add a routed Action or Flow.
- Declare a core Agent Route reply projection.
- Derive the structured output contract from the selected executable output.
- Return typed application data.
- Do not add a second reply schema or a Signal-specific executable type.

### 01_03_tool_agent

- Add one Action tool.
- Add one Flow tool.
- Show one tool round and the final reply.

### 01_04_controls_and_limits

- Add one module input control.
- Add one inline output control.
- Set time and call limits.

### 01_05_agent_composition

- Use `Jido.AI.Plugin` from a core Agent.
- Add core state, routes, and another Plugin.
- Replace the separate Plugin composition and core composition lessons.

### 01_06_portable_definition

- Define an Agent with a Map.
- Encode and decode JSON.
- Resolve Registry references.
- Validate the complete definition.

Model aliases and direct model names do not need a separate ladder step. Put
them in the basic Agent guide or in a reference page.

## 02 — Conversations

### 02_01_thread_and_session

- Compare the two immutable values.
- Explain identity, lifecycle state, and entries.

### 02_02_initialized_session_agent

- Use `initialize/2`.
- Create a fresh Session for each Agent instance.
- Show explicit caller-state precedence.

### 02_03_multi_turn_agent

- Append request and correlated Route reply Signals.
- Use prior conversation in the next turn.

### 02_04_context_projection

- Separate stored evidence from model Context.
- Exclude failed or incomplete turns.
- Show the exact data sent to the model.

### 02_05_request_modes

- Run a direct reasoning call.
- Run a routed Agent turn.
- Run work through AgentServer.

Reorganize the current Session value, Session Agent, and conversation history
lessons into this sequence.

## 03 — Active requests

### 03_01_async_request

- Start work and return a request handle.
- Await the result.
- Keep caller timeout separate from cancellation.

### 03_02_stream_and_cancel

- Stream response content.
- Close or cancel the request.
- Preserve completed evidence.

### 03_03_steer_a_request

- Queue corrective input.
- Consume it at a defined boundary.
- Reject late input.

### 03_04_usage_and_trace

- Show model calls, tool calls, iterations, provider usage, and semantic trace.
- Keep diagnostics separate from model content.

## 04 — Failure and recovery

### 04_01_failed_output

- Handle a blank response.
- Handle invalid structured output.
- Handle output-control rejection.
- Do not commit the conversation or send a reply after these failures.

### 04_02_tool_limits

- Handle a tool timeout.
- Enforce the tool-call limit.
- Enforce the complete request deadline.
- Explain that Jido AI cannot undo an external effect.

### 04_03_commit_and_reply

- Commit Agent state first.
- Deliver the Route Reply Directive after the commit.
- Do not repeat model or tool work after a delivery failure.

### 04_04_checkpoint_restore

- Encode and restore terminal Agent state.
- Preserve Session identity and history.
- Do not restore a live worker.

### 04_05_flow_resume

- Add this example only when active Flow checkpoint and resume is stable.
- Keep it separate from ordinary Session restoration.

## 05 — Composition and policy

### 05_01_model_routing

- Select a model from application policy.
- Keep model selection outside model-controlled input.

### 05_02_budgets_and_quota

- Share request budgets across model and tool work.
- Reject work before a budget is exceeded.

### 05_03_tool_policy

- Permit or reject tool access.
- Keep access policy separate from tool schemas.

### 05_04_child_agents

- Start and address child Agents.
- Keep child state and identity explicit.

### 05_05_agent_topology

- Connect Agents with core topology definitions.
- Show message flow between members.

These examples must use the core Jido runtime. They must not add a second AI
runtime.

## Capability tracks

These tracks branch from the main ladder. Start each track with one example.
Add another example only when the public contract needs a separate lesson.

### 06 — Retrieval

- Store and find memory.
- Project selected results into model Context.

### 07 — Planning

- Build a plan with an Action or Flow.
- Keep plan state visible to the application.

### 08 — Reasoning strategies

- Select a reasoning Flow.
- Use the same contract for a reasoning module and `reasoning do`.
- Use a reasoning Flow as a tool when needed.
- Keep strategy and execution policy outside model-controlled input.

### 09 — Skills

- Load one declared skill.
- Apply its prompt and resources.
- Keep skill trust and resource access explicit.

## 99 — Capstones

### 99_01_research_agent

- Combine tools, structured output, controls, Session state, routes, and
  topology.

Possible later capstones:

- research with retrieval
- planning and execution
- supervised child Agents
- resumable long-running work

## Old catalog review

Retain the behavior from these old lessons, but do not retain every old
example file:

- request steering
- result completion compared with post-commit Route reply delivery
- tool limits
- incomplete response handling
- call counts and request inspection
- checkpoint restore
- initial state import
- reasoning as a tool

Move detailed failure permutations to unit and contract tests. Keep one
important failure in each teaching example.

## Gate before new feature work

The local technical gate passed on October 24, 2026. Commit and merge the
`explore/jido-ai-restart` branch before parallel feature work starts.

The gate is:

1. Remove all active references to the retired typed Signal Action wrapper.
2. Compile with warnings as errors against the sibling V3 packages.
3. Pass deterministic unit and integration tests.
4. Pass all executable example tests.
5. Pass Covenant checks with complete obligation coverage.
6. Pass formatting, Credo, Doctor, Dialyzer, and the package quality gate.
7. Build the documentation without warnings.
8. Run the selected live AI tests when credentials are available.
9. Confirm that direct requests and routed turns use the same prepared request
   contract.
10. Confirm that failed or incomplete results cannot commit Agent state or send
    a reply.
11. Confirm that the exploration branch has a clear merge and release path.

## Stack-ranked feature backlog

Build these as small independent changes. Do not change the main Agent or
reasoning DSL unless the feature requires it.

1. **Limit evidence**
   - Add structured limit failures to Results and Events.
   - Include the metric, actual value, configured limit, and phase.

2. **Incomplete response and public error normalization**
   - Distinguish token limits, request timeouts, invalid output, provider
     failures, and cancellation.
   - Use one stable public error shape with kind, phase, path, retry status,
     and request ID.

3. **Tool evidence**
   - Record the tool name, call ID, safe arguments, duration, status, and safe
     output.
   - Keep tool evidence separate from the final application output.

4. **Semantic tool requirements**
   - Add `requirement :optional | :required` to `tools do`.
   - Make `:required` apply to the complete request, not every model call.

5. **Explicit model options**
   - Support declared model options and request overrides.
   - Reject unknown top-level options instead of passing arbitrary options to
     ReqLLM.

6. **Operation control**
   - Add one operation control for selected tool calls and arguments.
   - Keep it separate from input and output controls.

7. **Bounded output repair**
   - Add a small output-repair limit.
   - Use the existing model-call, deadline, and event contracts.

8. **Context report and limits**
   - Report included and omitted Signals, omission reasons, and estimated size.
   - Add `max_turns` and `reserve_tokens` only after the report is stable.

9. **Safe trace capture**
   - Always produce a bounded summary.
   - Permit larger capture only through an explicit bounded option.

10. **Evaluation helpers**
    - Add typed checks for status, tool calls, output, and call limits.
    - Use the public runtime and shared ReqLLM mock support.

11. **Trusted model policy**
    - Select models from an explicit application-owned alias list.
    - Record the selected model and selection reason.

12. **Richer control decisions**
    - Add explicit allow, rewrite, and deny decisions.
    - Defer review and wait decisions until core Jido owns durable suspension.

Defer child-Agent inheritance, handoffs, skill loading, retrieval stores,
context graphs, and multimodal input until the request contract and the first
three evidence features are stable.

## Next example sequence

1. Add `04_01_failed_output` while implementing normalized failure evidence.
2. Add `04_02_tool_limits` while implementing limit and tool evidence.
3. Add `04_03_commit_and_reply` to prove the final Route commit boundary.
4. Add deterministic ReAct script support for later evaluation examples.
5. Add request event streaming after the core stream boundary is stable.
6. Add active request steering and inspection.
