# Jido AI Guide TODO

This is the source list for the new Jido AI guides. The structure follows the
current `jido_action` and `jido` guides:

- Use flat, descriptive filenames without number prefixes.
- Use Livebook Markdown for lessons that readers must run.
- Use Markdown for concepts, contracts, operations, and reference material.
- Use task-based ExDoc groups and explicit page titles.
- Keep the learning order in `@guide_toc` in `mix.exs`, not in filenames.

## Start Here

- [x] **Livebook Markdown** — Getting Started (`getting-started.livemd`) — Define an AI Agent, run one request, and read the response.
- [x] **Markdown** — Core Concepts (`core-concepts.md`) — Explain Agent, reasoning Flow, Session, Thread, Context, model call, and tool boundaries.
- [x] **Markdown** — Choose a Reasoning Flow (`choose-a-reasoning-flow.md`) — Select ReAct, a single-call Flow, a multi-stage Flow, or Adaptive.

## Author AI Agents

- [x] **Livebook Markdown** — Define an AI Agent (`define-an-ai-agent.livemd`) — Declare the root Flow, schemas, defaults, and tools.
- [x] **Markdown** — Agent Authoring (`agent-authoring.md`) — Cover inline and referenced Flows, preflight checks, and portable definitions.
- [x] **Livebook Markdown** — Structured Output (`structured-output.livemd`) — Use Zoi schemas, validation, repair, and typed result data.
- [x] **Markdown** — Pure or Live Execution (`pure-or-live-execution.md`) — Compare direct commands with AgentServer state commits.

## Context and Conversation

- [x] **Markdown** — Sessions and Threads (`sessions-and-threads.md`) — Explain portable conversation state, entries, sources, and observations.
- [x] **Livebook Markdown** — Project a Thread (`project-a-thread.livemd`) — Select eligible entries, apply limits, and explain projection choices.
- [x] **Markdown** — Context Lifecycle (`context-lifecycle.md`) — Prepare, transform, complete, and reuse an idempotent model-call boundary.
- [x] **Livebook Markdown** — Inspect Model Context (`inspect-model-context.livemd`) — Capture and compare snapshots, shapes, token counts, cache facts, and provider metadata.

## Use Models

- [x] **Markdown** — Models and Options (`models-and-options.md`) — Use ReqLLM model names, request options, providers, and fallbacks.
- [x] **Livebook Markdown** — Embeddings (`embeddings.livemd`) — Run single and batch embedding requests.
- [x] **Livebook Markdown** — Stream Model Output (`stream-model-output.livemd`) — Stream output with stable sequence and request correlation.

## Use Tools

- [x] **Livebook Markdown** — Action Tools (`action-tools.livemd`) — Expose Jido Actions and control the static tool allowlist.
- [x] **Markdown** — Dynamic Tool Sources (`dynamic-tool-sources.md`) — Load trusted tools from host execution context.
- [x] **Markdown** — Tool Execution and Results (`tool-execution-and-results.md`) — Validate calls, run tools, bound model-visible data, and keep local results.
- [x] **Livebook Markdown** — Tool Review and Cycle Limits (`tool-review-and-cycle-limits.livemd`) — Approve or deny calls, handle timeouts, and stop repeated cycles.

## Reasoning Flows

- [x] **Livebook Markdown** — ReAct (`react.livemd`) — Run model rounds, tool rounds, fallbacks, and final result selection.
- [x] **Livebook Markdown** — Single-Call Reasoning (`single-call-reasoning.livemd`) — Compare Chain of Thought, Chain of Draft, and Algorithm of Thoughts.
- [x] **Livebook Markdown** — Multi-Stage Reasoning (`multi-stage-reasoning.livemd`) — Compare Tree of Thoughts, Graph of Thoughts, and TRM.
- [x] **Livebook Markdown** — Adaptive Reasoning (`adaptive-reasoning.livemd`) — Use local selection and explicit Flow overrides.

## Custom Flows

- [ ] **Livebook Markdown** — Custom Flows (`custom-flows.livemd`) — Build a root reasoning Flow from the public Jido AI Actions and add your own controls and guardrails.

## Run and Operate

- [x] **Markdown** — Budgets, Retries, and Fallbacks (`budgets-retries-and-fallbacks.md`) — Limit model calls, tools, retries, time, tokens, and cost.
- [x] **Markdown** — Usage, Cache, and Cost (`usage-cache-and-cost.md`) — Read normalized token counts, prompt cache facts, and cost data.
- [x] **Livebook Markdown** — Telemetry and Tracing (`telemetry-and-tracing.livemd`) — Observe events, metadata, spans, and correlation identifiers.
- [x] **Markdown** — Errors and Recovery (`errors-and-recovery.md`) — Handle provider, output, tool, budget, and guard failures.
- [x] **Markdown** — Security and Portability (`security-and-portability.md`) — Apply tool trust, allowlists, redaction, portable data, and effect idempotency.

## Test Jido AI

- [x] **Livebook Markdown** — Test AI Agents (`test-ai-agents.livemd`) — Test Flows, Context values, tool results, and Agent state without a live provider.
- [x] **Livebook Markdown** — Mock Model Calls with ReqLLM (`mock-model-calls-with-reqllm.livemd`) — Use ReqLLM Mimic and assert the exact model boundary.

## Reference

- [x] **Markdown** — Public API Reference (`public-api-reference.md`) — List the DSL fields, Flow schemas, response fields, Signal names, and public modules.

## Upgrade

- [x] **Markdown** — Migrating from V2 (`v2-to-v3-migration.md`) — Map supported V2 concepts to V3 and list removed concepts.

## Page Style

Use the same page shape as the sibling packages.

### Livebook Markdown

1. Start with `Overview`.
2. Add an `Install` section when the page can run outside the repository.
3. Build one complete example in small runnable steps.
4. Show exact result values after important calls.
5. End with `Summary` or `What You Learned`.
6. End with `Next` and link to the next useful guide.

### Markdown

1. Start with one short paragraph that states scope and prerequisite guides.
2. Put the mental model or contract before detailed options.
3. Use small tables for comparisons and exact result shapes.
4. Use complete public API examples.
5. Link to related guides where a topic changes ownership.

## Acceptance Checks

- [ ] Use only public V3 APIs.
- [ ] Use one stable example domain across related guides.
- [ ] Make each code sample compile.
- [ ] Give each model-call guide an offline ReqLLM Mimic path.
- [ ] Mark live provider calls clearly and keep them out of the default test path.
- [ ] Use Zoi for public data and output schemas.
- [ ] Keep Context independent of all reasoning Flows.
- [ ] Keep detailed field lists in module documentation or the public API reference.
- [ ] Run `mix format --check-formatted`.
- [ ] Run `mix compile --warnings-as-errors`.
- [ ] Run the package test suite.
- [ ] Run `mix docs --warnings-as-errors`.
