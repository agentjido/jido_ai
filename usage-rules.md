# Jido AI Usage Rules

## Intent

Build tool-using AI behavior with explicit model policy, bounded execution,
portable state, and inspectable request evidence.

## Core contracts

- Use `Jido.AI.Agent` for the normal Agent form.
- Keep model selection, time limits, call limits, and tool access explicit.
- Use Zoi schemas for structured output, controls, and tools.
- Use `initialize/2` for fresh Session or Thread instance data.
- Keep `initial_state` static. The initializer receives declared and explicit
  state. Preserve an explicit Session or Thread and add one only when absent.
- Use `preflight/2` to inspect the exact prepared request without execution.
- Use `visible_tools:` to reduce one request to declared tools.
- Do not accept raw provider `tools:` from request options.
- Use `reason/2` for a completed result and the normal raw error contract.
- Use `run/2` when a failed request must also return a `Jido.AI.Result`.
- Treat `result.events` as the canonical ordered AI event sequence.
- Keep `result.trace` only as the compatibility alias for those events.
- Keep provider-specific behavior behind ReqLLM.

## State and context

- Treat Session and Thread as immutable source values.
- Project model messages with `Jido.AI.Context`.
- Send only complete correlated conversation pairs to the model.
- Do not use a second durable conversation store inside Jido AI.
- Do not store processes, tasks, clients, streams, or callbacks in Agent state.
- A direct AI request must not change Agent state.
- A routed turn must create candidate state only from a completed result.
- Core Jido owns the final state commit and Directive delivery.

## Tools

- Define tools as Jido Actions or Flows.
- Give each tool a stable model-facing name.
- Reject hidden, undeclared, or invalid calls before tool execution.
- Treat tool descriptions as model guidance, not authorization.
- Add application authorization and idempotency for external effects.
- Do not assume that final-output failure can undo a completed tool effect.

## Tests

- Test preflight and execution through the same request preparation path.
- Test one permitted tool and one hidden tool.
- Test request and run ID correlation across all events.
- Test one terminal event and no event after it.
- Test provider, control, output, and tool failures.
- Test that a failed routed request leaves Session or Thread state unchanged.
- Run example and live suites when request behavior changes.

## Avoid

- A second AI Agent runtime beside Jido AgentServer and Flow.
- Prompt-only access rules.
- Provider options that can replace declared tools.
- A model Context stored as the durable conversation source.
- Unbounded model, tool, or repair loops.

## References

- `README.md`
- `examples/README.md`
- `guides/v3/`
- `AGENTS.md`
- https://hexdocs.pm/jido_ai
- https://hexdocs.pm/req_llm
