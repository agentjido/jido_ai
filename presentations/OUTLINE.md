# Jido: An introduction to Autonomous Agents with Elixir

- Goals & audience: Elixir engineers new to Jido; what you’ll build in this series
- Package map: jido (agents/workflows), jido_signal (events), jido_action (actions/tools), jido_ai (LLMs)
- How parts fit together: Signal → Action → Workflow → Agent → AI
- What is an agent? (Anthropic framing): a simple loop of observe → think/plan → act that can use tools; autonomy bounded by goals and policies; can be stateless or stateful; focus on reliability and guardrails, not “magic.”
- Install and docs: add deps from Hex, links to HexDocs, where examples live
- Overview of the Jido ecosystem:
  - jido_signal: messaging
  - jido_action: actions/tools
  - jido: agents
  - jido_ai: LLMs
- Complete Agent example: Github Issue Watcher / Commenter

# Jido Signals — Core

- Signal model: CloudEvents structure, required fields, metadata, validation
- Bus basics: start/link bus, publish/subscribe, delivery semantics
- Minimal dispatch: PID/console; sync vs async
- Basic lifecycle: create signal, publish, receive, ack
- Debugging: simple logging, printing signal types and IDs

# Jido Actions — Part 1: Defining & Validating

- Defining actions: `use Jido.Action` with name/description/schema
- Parameter validation with NimbleOptions; output shape basics
- `run(params, context)` contract; success/error tuples
- Error surfaces and common validation pitfalls
- Unit testing actions directly (happy path and failure cases)

# Workflows in Jido — Fundamentals

- Workflow mental model: sequences and context; when to use workflows
- `Jido.Instruction`: formats, normalization, shared context
- Executing a simple sequence (sequential only, no branching)
- Allowlist basics for safe execution
- Minimal telemetry/observability for a sequential flow

# Guided Exercise 1 — Your First Action (Hands-on)

- Create `GreetUser` action with schema and `run/2`
- Execute via `Jido.Exec.run/2` and assert output
- Add one negative test for validation error
- Add short notes on extending schema (enum/default)

# Jido Stateless Agents

- Concept: plan/execute without persistent agent state
- Using workflows to implement stateless behavior
- Integrating Signals & Actions without keeping state
- When to prefer stateless over stateful; tradeoffs
- Example: simple compute pipeline agent

# Guided Exercise 2 — Compose a Stateless Workflow

- Compose 2–3 actions with `Jido.Instruction`
- Provide shared context; run end-to-end; assert result
- Add a log/telemetry assertion (if applicable)
- Discuss extending with another action

# Jido Sensors — Bridging External Events to Agents

- Purpose: bridge external events (HTTP/WebSocket/PubSub) into a Jido Agent
- Defining sensors: `use Jido.Sensor`; schema, `mount/1`, `handle_info/2`
- Emitting signals into the Bus that your agent consumes
- Example sources: webhook handler, Phoenix PubSub, external queue
- Testing sensors: deterministic timing, state updates

# Guided Exercise 3 — Build a Sensor for External Events

- Implement a minimal sensor that forwards an HTTP-triggered event
- Wire: Sensor → Signal Bus → Agent command/workflow
- Verify via a simple test that the agent receives and processes
- Discuss retries/backpressure considerations

# Jido Skills — Reusable Agent Capabilities

- Concept: skills as composable, reusable behavior modules (agent plugins)
- Registration/structure: versioning, capabilities, naming
- Exposing actions/tools via skills
- Composition patterns: layering skills, resolving conflicts
- Testing/documenting skills

# Guided Exercise 4 — Create and Attach a Skill

- Implement a simple skill (e.g., logging or formatting)
- Register the skill with an agent and expose an action
- Call the action through the agent; test the behavior
- Notes on namespacing and version bumps

# Jido Actions — Part 2: Execution, Composition, Tooling

- `Jido.Exec`: sync/async, retries, backoff, timeouts
- `Jido.Instruction`: chaining, context sharing, safety patterns
- AI tool conversion: `to_tool/0` for OpenAI-style function calling
- Telemetry hooks and structured error handling
- Advanced testing patterns (async, awaits, compensation)

# Jido Signals — Advanced

- Router & patterns: exact, wildcard, function match; priority/ordering
- Dispatch adapters: PID/PubSub/HTTP/Logger/Console; batching
- Persistence: persistent subscriptions, ack/replay
- Causality & Journal: cause/effect graphs, conversation tracking, snapshots
- Middleware pipeline: logging, auth, metrics

# Jido AI — LLM Actions, Tools & Responses

- Providers/models: Anthropic/OpenAI/OpenRouter/Google/Cloudflare; keys and setup
- Message/response structures: content, streaming, tool results
- Tool execution flow: request → LLM → tool call → result mapping
- Structured outputs: Ecto schemas with Instructor; validation
- Playground: `mix jido.ai.playground` for streaming demo

# Jido AI — Prompting

- MessageItem API: roles, multipart content (text, image, file)
- Prompt templates with EEx; parameterization and reuse
- System prompts & guardrails: style, constraints, safe defaults
- Tool-aware prompts; few-shot examples
- Streaming vs batch: temperature, tokens, limits

# Jido AI — Evaluations

- What to evaluate: correctness, structure, safety, cost/time
- Response-model validation (Ecto structs; nested/enum types)
- Test strategies: HTTP mocking, fixtures, property tests
- Provider key handling and configuration
- CI patterns: golden responses, regression tests, cost budgets

# Jido Stateful Agents — Part 1: Basics

- `use Jido.Agent`: schema, actions, skills, directives overview
- Supervision & deployment: child specs, IDs
- Commanding agents: `cmd/2`, instructions, state mutation
- Observability: telemetry, metrics, logs
- Local dev & test patterns for stateful flows

# Jido Agent Directives

- What directives are: runtime control of agent behavior
- Common directives: register/unregister actions, reconfigure
- Safety: allowlists, authorization, isolation
- Examples: hot-reloading capabilities in a running agent
- Testing directives and rollback strategies

# Jido Stateful Agents — Part 2: Multi-Agent & Production

- Multi-agent patterns: collaboration, pub/sub, routing
- Production concerns: supervision trees and clustering
- Persistence & recovery considerations
- Distributed topics and scaling strategies
- Advanced observability and metrics

# Putting It All Together — End-to-End Agent

- Scenario: external event → Signal → Action → Workflow → Agent decision → (optional) AI tool
- Project wiring: supervision tree, bus, agent, skills
- Demo walkthrough: event to result with logs/telemetry
- Failure modes: retries, compensation, replays
- Extensions: distributed topics, webhooks, backpressure

# Guided Exercise 5 — Add AI to Your Agent

- Convert an existing action to an AI tool (`to_tool/0`)
- Configure provider and keys; pick a model
- Execute a tool-enabled workflow via the agent
- Validate structured output and handle errors

# Guided Exercise 6 — Directives in Action

- Add/remove an action at runtime with directives
- Reconfigure a parameter and verify behavior change
- Demonstrate safe rollback for misconfiguration
- Discuss audit trail and observability of directives
