# 01_01 — Basic AI Agent

Use `Jido.AI.Agent` to define an AI Agent and generate one text answer.

## What you will learn

- Use `Jido.AI.Agent` to include `Jido.AI.Plugin` automatically.
- Use a top-level `ai` block to declare a model alias and instructions.
- Read the normalized configuration from an Agent definition or instance.
- Call `Agent.generate/2` and receive one text answer.

## Read the code

Read [the Agent](agent.ex), then read
[the test](../../../test/examples/01_basics/01_01_basic_agent/basic_agent_test.exs).

## Run it

From the package root:

```sh
mix test test/examples/01_basics/01_01_basic_agent --include example --seed 0
```

Expected result: two tests pass without an API key or network call.

To run the same Agent against OpenAI with credentials from `.env`:

```sh
mix test.live
```

The live test writes a small sanitized trace under `tmp/jido_ai_traces/`. The
trace is local run evidence. It is not a replay fixture and is not committed.

## Important behavior

The Plugin stores normalized AI configuration in the Agent definition.
The same configuration is available from an Agent instance. The example test
replaces only the ReqLLM request. It checks the complete path from the Agent
helper to the returned text.

The `:fast` model alias is resolved from `config :jido_ai, :model_aliases` when
an AI request starts. The Agent definition keeps the alias.

## Limits

This example does not start an AgentServer, update Agent state, or retain
conversation history.

## Files

- [Agent](agent.ex)
- [Test](../../../test/examples/01_basics/01_01_basic_agent/basic_agent_test.exs)

Next: [Action and Flow tools](../01_02_tool_flow/README.md).
