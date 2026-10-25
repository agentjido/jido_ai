# Jido AI V3 learning path

Start with one direct answer. Then add tools, request evidence, and committed
conversation state.

## 1. Generate

- [Basic AI Agent](../../examples/01_basics/01_01_basic_agent/README.md)
- [First Agent guide](01_first_agent.md)

Learn the Agent wrapper, model selection, instructions, and `generate/2`.

## 2. Act

- [Action and Flow tools](../../examples/01_basics/01_02_tool_flow/README.md)
- [Tools and ReAct guide](02_tools_and_react.md)

Declare core Jido executables as model tools and run the bounded ReAct Flow.

## 3. Structure and govern

- [Structured output](../../examples/01_basics/01_03_structured_output/README.md)
- [Input and output controls](../../examples/01_basics/01_04_controls/README.md)
- [Controls and limits](11_controls_and_limits.md)

Derive output from a route reply projection. Add one input control, one output
control, and total request limits.

## 4. Inspect one request

- [Request contract](../../examples/01_basics/01_06_request_contract/README.md)
- [Results and state](03_results_and_state.md)
- [Turn sequence](09_turn_sequence.md)
- [Failures and recovery](13_failures_and_recovery.md)
- [Observability and events](16_observability.md)

Use preflight, explicit results, request IDs, run IDs, and canonical events.

## 5. Limit tool access

- [Tool policy](14_tool_policy.md)

Select a declared tool subset for one request. Hidden tools cannot execute.

## 6. Remember complete turns

- [Conversation examples](../../examples/02_conversations/README.md)
- [Session, Thread, and Context](17_session_thread_context.md)
- [Context projection](18_context_projection.md)

Create fresh Session and Thread values with `initialize/2`. Project only
complete correlated turns into model messages. Commit state only after the AI
result is complete and valid.

## Reference

- [AI Agent DSL](22_dsl_reference.md)
- Example backlog: `examples/BACKLOG.md`

Guides for steering, quotas, multiple Context lanes, and active Flow resume are
future design material until their public V3 contracts are implemented.
