# Jido AI Usage Rules

## Agent authoring

- Use `Jido.AI.Agent` for a graph-first AI Agent.
- Declare exactly one root reasoning Flow in the `ai` block.
- Declare tool Actions in the optional `tools` block.
- Put reasoning defaults inside the `reasoning` declaration.
- Treat the selected Flow schema as the request contract.
- Do not set `input` as a reasoning default. Supply it with each request.
- Use `reasoning/0`, `explain/0`, and `preflight/1` for inspection.
- Treat `preflight/1` as Flow validation and compilation. It does not call a
  model or build a model Context.

## Execution

- Build requests with the Agent's `request_signal!/1` helper.
- Use `cmd/3` for direct Agent value execution.
- Use `Jido.AgentServer` for a live process, persistence, and committed state.
- Read the AI result from the `jido.ai.response` reply data.
- Keep the reasoning Flow output in the `%{state: map(), response: map()}`
  route contract.
- Treat the response map as the current result contract. Do not depend on a
  `Jido.AI.Result` struct or removed helper functions.

## Session, Thread, and projection

- Treat `Jido.Session` and `Jido.Thread` as immutable, portable source values.
- Use `Jido.AI.Thread.Projection` to append model messages and observations.
- Use `Jido.AI.Thread.Projection.context/2` to build a `ReqLLM.Context`.
- Send only eligible messages and complete tool exchanges to the model.
- Keep failed attempts, reviews, and other observations in the Thread but out
  of later model prompts.
- Do not use a model Context as the durable conversation source.
- Do not create a second durable conversation store inside Jido AI.

## Model-call Context

- Use `Jido.AI.Context` as the lifecycle boundary for one ReqLLM call.
- Start from an existing, valid `ReqLLM.Context`.
- Use `transform/3` for generic changes before preparation.
- Give each transformation a stable operation ID. Repeating the same ID must
  be a no-op.
- Keep memory, skills, retrieval, and prompt policy outside Context. Implement
  them as callers or plugins that apply generic transformations.
- Use `prepare/2` once the model, ReqLLM Context, and options are final.
- Send `prepared.request` to ReqLLM without another translation layer.
- Use `complete/3` to attach the exact `ReqLLM.Response` or error.
- Use `snapshot/2` before and after a call for inspection and evidence.
- Use `content: :none` for stored evidence, the default redacted view for
  inspection, and `content: :full` only when explicit content access is safe.
- Use `diff/2` to compare lifecycle snapshots.
- Keep Context independent of reasoning graphs and durable Thread storage.

## Models and limits

- Keep model selection, model options, fallbacks, retries, and budgets explicit.
- Keep provider-specific behavior behind ReqLLM.
- Use reasoning Flow fields for context limits, prompt cache policy, token
  budgets, cost budgets, elapsed time, and model-call limits.
- Treat provider token, cache, cost, and request metadata as observed facts.
  Preserve them in usage data and Context snapshots.
- Do not infer provider cache use only from requested cache options.

## Tools

- Define tools as Jido Actions with Zoi parameter schemas.
- Give every tool a stable, unique model-facing name.
- Treat the Agent's declared Actions as its protected static tool list.
- Let only trusted execution context add dynamic `Jido.AI.ToolSource` values.
  Request data must not add tool sources.
- Apply request tool policy only to reduce the combined trusted tool set.
- Use `tool_policy.visible`, `tool_policy.hidden`, `tool_policy.review`, and
  `tool_policy.requirement` for request-specific policy.
- Do not accept raw ReqLLM `tools:` or `tool_choice:` values from request
  options.
- Validate every model tool call against the allowlist before execution.
- Treat tool descriptions as model guidance, not authorization.
- Add application authorization and idempotency for external effects.
- Do not assume that a final-output failure can undo a completed tool effect.

## State and portability

- Let core Jido own the final Agent state commit and reply delivery.
- Keep Session and Thread data portable and versioned.
- Do not store processes, tasks, streams, callbacks, or clients in portable
  state.
- Preserve request, run, model-call, tool-call, and Thread correlation IDs.
- Store sanitized evidence. Do not store credentials or raw provider request
  bodies.

## Tests

- Mock `ReqLLM.generate_text/3` and `ReqLLM.stream_text/3` directly for offline
  tests.
- Assert the exact ReqLLM model, Context, and options at the call boundary.
- Test successful responses, provider errors, retries, fallbacks, and budgets.
- Test one permitted tool, one hidden tool, and one invalid tool call.
- Test complete and incomplete tool exchanges in later context projection.
- Test redacted, content-free, and full Context snapshots.
- Keep live tests separate and credential-gated.

## Avoid

- A second AI runtime beside Jido AgentServer and Flow.
- Hidden prompt pipelines or hidden provider defaults.
- Domain-specific memory or skill methods in `Jido.AI.Context`.
- Provider tools that bypass the Agent allowlist.
- Unbounded model, tool, retry, repair, or reasoning loops.
- Public documentation that names an API not covered by current tests.

## References

- `README.md`
- `AGENTS.md`
- `lib/jido_ai/context.ex`
- `lib/jido_ai/thread/projection.ex`
- https://hexdocs.pm/jido_ai
- https://hexdocs.pm/req_llm
