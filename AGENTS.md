# AGENTS.md - Jido AI

## Purpose

Build graph-first AI behavior for Jido Agents. Keep model calls, tool use,
limits, context projection, and request evidence explicit.

## Runtime baseline

- Elixir `~> 1.18`
- OTP `27+` for release QA
- Compatible V3 versions of `jido`, `jido_action`, and `jido_signal`
- ReqLLM is the provider and model boundary
- Zoi is the schema boundary

Read dependency versions and sources from `mix.exs`. Do not copy version facts
into this file.

## Current architecture

- `Jido.AI.Agent` adds one AI Plugin to a normal Jido Agent.
- Each AI Agent has exactly one root reasoning Flow and an optional ordered
  set of tool Actions.
- The generated `jido.ai.request` route targets the reasoning Flow directly.
  Do not add a second AI runtime or a hidden orchestration pipeline.
- The reasoning Flow schema owns request fields, defaults, validation, and
  output shape.
- `Jido.Session` and `Jido.Thread` are immutable, portable conversation values.
- `Jido.AI.Thread.Projection` selects eligible Thread messages and builds the
  canonical `ReqLLM.Context`.
- `Jido.AI.Context` is the graph-independent lifecycle boundary for one ReqLLM
  call. It owns the exact request, result, transformations, digest, and
  snapshots for that call.
- Core Jido owns Agent processes, route execution, state commits, replies, and
  directives.

## Ownership rules

- Put AI Agent authoring in `Jido.AI.Agent` and its Plugin.
- Put reusable AI control behavior in explicit reasoning Flows and Actions.
- Put durable conversation data in Session and Thread.
- Put projection policy in `Jido.AI.Thread.Projection`.
- Put only model-call lifecycle behavior in `Jido.AI.Context`.
- Keep memory, skills, retrieval, and application policy outside Context.
  These features can use generic Context transformations.
- Keep provider-specific behavior behind ReqLLM.
- Define static model tools as Jido Actions. Trusted execution hosts can add
  dynamic tools through `Jido.AI.ToolSource`. Request data cannot add sources.

## Contract rules

- Use Zoi schemas for reasoning inputs, outputs, and tool parameters.
- Keep model selection, model options, context limits, budgets, retries, and
  tool policy explicit.
- Do not let request options add or replace Agent tools.
- Use stable operation IDs for idempotent Context transformations.
- Freeze the exact ReqLLM request with `Jido.AI.Context.prepare/2` before a
  model call.
- Complete the same Context with the exact ReqLLM result.
- Store portable, content-free or redacted Context snapshots for request
  evidence.
- Do not store processes, tasks, streams, callbacks, or provider clients in
  Agent, Session, or Thread state.
- Preserve tagged tuples and structured errors at public boundaries.
- Preserve complete tool-call and tool-result correlation in projected model
  history.

## Source of truth

- Current runtime code and tests are the primary contract.
- `examples/00_graph_first/` is the current graph-first example baseline.
- Removed V1 code, tests, and examples remain available in Git history. Do not
  restore them as current API evidence.
- Documents under `docs/design/` and `docs/v3-spike/` can contain plans or
  historical findings. Verify each claim against current code before use.
- Do not restore removed helper modules or APIs only because an old guide or
  example names them.

## Tests

- Mock ReqLLM directly for deterministic offline model tests.
- Test the exact model, `ReqLLM.Context`, and options sent to ReqLLM.
- Test Context snapshots before and after successful and failed calls.
- Test projection exclusions, incomplete tool exchanges, and context limits.
- Test tool allowlists, invalid calls, review, retries, budgets, and effects.
- Keep live provider tests tagged `:live`. Do not make the offline suite need
  provider credentials or network access.
- A live test must verify protocol and data shape. Do not depend on an exact
  answer to an open-ended prompt.

## Required checks

Run commands from this repository:

```sh
mix format --check-formatted
mix compile --force --warnings-as-errors
mix test --warnings-as-errors --seed 0
```

Run `mix test.live` when model request behavior changes and credentials are
available. Run `mix docs --warnings-as-errors` and `mix hex.build` before a
release merge.

## Release hygiene

- Keep commits scoped to this repository.
- Use Conventional Commits.
- Do not edit `CHANGELOG.md`. Release notes come from Git history.
- Update the README, usage rules, guides, and examples when a public contract
  changes.
- Do not merge generated files, local traces, credentials, or build output.

## References

- `README.md`
- `usage-rules.md`
- `mix.exs`
- https://hexdocs.pm/jido_ai
- https://hexdocs.pm/req_llm
