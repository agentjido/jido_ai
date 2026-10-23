# Jido AI examples

This catalog starts with the smallest public Jido AI contract and grows one
working example at a time.

The previous example catalog is retained in
[`examples_v1/`](../examples_v1/README.md). It uses the previous Jido AI API and
does not compile as part of this catalog.

## Run

Run all current examples from the package root:

```sh
mix examples --seed 0
```

The example suite is offline. Live provider tests use `mix test.live` and are
not part of this catalog.

## Learning path

1. [Basic AI Agent](01_basics/01_01_basic_agent/README.md) — use
   `Jido.AI.Agent`, inspect its configuration, and generate one text response.
2. [Action and Flow tools](01_basics/01_02_tool_flow/README.md) — expose core
   Jido executables as model tools.
3. [Structured output](01_basics/01_03_structured_output/README.md) — derive a
   parsed response object from a routed Signal Action reply contract.
4. [Input and output controls](01_basics/01_04_controls/README.md) — check a
   request before and after the model call.
5. [Streaming and cancellation](01_basics/01_05_streaming/README.md) — read
   response chunks and close the stream.
6. [Core composition](01_basics/01_07_core_composition/README.md) — combine AI
   configuration with core Agent data and another extension.
7. [Model helpers](01_basics/01_08_model_helpers/README.md) — use model aliases
   and direct model names.
8. [JSON AI Agent](01_basics/01_09_json_agent/README.md) — export and import a
   complete AI definition through the shared Jido authoring Registry.

## Proposed

- [Plug-in composition](99_proposed/plugin_composition/README.md) — compare the
  explicit AI Plugin with the convenience Agent wrapper.
- [Research Agent](99_proposed/research_agent/README.md) — inspect one
  kitchen-sink definition that combines the current core Jido and Jido AI DSL.
