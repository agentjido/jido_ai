# Jido AI live tests

Live tests prove the integration between Jido AI, ReqLLM, and a real model.
They do not repeat deterministic Jido behavior that an offline test can prove.

## Run

ReqLLM reads provider credentials from the local `.env` file. No environment
variable enables or disables this suite.

Run all live tests:

```sh
mix test.live
```

Run one live test file:

```sh
mix test.live test/live/tool_round_test.exs
```

The normal `mix test` command excludes the `:live` tag.

## What belongs here

A live test must prove behavior that a mocked ReqLLM response cannot prove:

- a real text request completes;
- a model emits valid tool calls and uses their results;
- a provider accepts the reply schema from a routed Signal Action;
- a stream produces content and closes;
- an imported JSON Agent can make a routed request.

Model aliases, Plugin composition, controls, validation, limits, JSON codecs,
and Agent state changes stay in the offline suite. These are deterministic
Jido behaviors.

Use one inexpensive canonical model for the normal live suite. ReqLLM owns the
broad provider compatibility matrix. Add a model here only when a Jido AI
feature depends on a model capability such as tools, structured output, or
streaming.

## Assertions

Assert facts that Jido AI owns. Check that an Action ran, structured data is
valid, a reply has the correct Signal type, or a tool result reached the final
answer. Do not require exact prose, token counts, chunk counts, latency, or
provider metadata.

Each run writes a sanitized trace under `tmp/jido_ai_traces`. Traces are local
diagnostic artifacts. They are not golden fixtures and are not committed.
