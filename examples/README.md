# Jido AI examples

This is the checked example catalog for `jido_ai`. Source files live under
`examples/`. Matching tests live under `test/examples/`. Each feature keeps its
source, notes, and test under the same group and example ID.

The examples use real Jido AI public features and a deterministic local model
server. They do not need provider credentials.

## Run

Run these commands from the repository root:

```sh
mix test                                      # Excludes examples
mix examples --seed 0                        # Runs all examples
mix test test/examples/02_requests/02_23_context_operations --include example --seed 0
```

Every example test has the `:example` tag. The default test command excludes
that tag. The `mix examples` alias is the supported full-suite command.

Example modules compile in the `:dev` and `:test` environments. Production
builds compile `lib/` only. The Hex package contains neither examples nor tests.

## Catalog

| Group | Features | Source and notes | Tests |
| --- | ---: | --- | --- |
| 01_authoring | 8 | [Agent and AI authoring](01_authoring/README.md) | [Tests](../test/examples/01_authoring/README.md) |
| 02_requests | 27 | [Requests, sessions, and context](02_requests/README.md) | [Tests](../test/examples/02_requests/README.md) |
| 03_tools | 3 | [Tool catalogs and context](03_tools/README.md) | [Tests](../test/examples/03_tools/README.md) |
| 07_retrieval | 1 | [Retrieval](07_retrieval/README.md) | [Tests](../test/examples/07_retrieval/README.md) |
| 08_planning | 1 | [Planning](08_planning/README.md) | [Tests](../test/examples/08_planning/README.md) |
| 09_reasoning | 16 | [Reasoning methods](09_reasoning/README.md) | [Tests](../test/examples/09_reasoning/README.md) |
| 13_policy | 1 | [Quota policy](13_policy/README.md) | [Tests](../test/examples/13_policy/README.md) |
| 14_resume | 12 | [Standalone runtime and resume](14_resume/README.md) | [Tests](../test/examples/14_resume/README.md) |
| 16_capabilities | 4 | [Capability plugins](16_capabilities/README.md) | [Tests](../test/examples/16_capabilities/README.md) |
| 18_skills | 2 | [Skill runtime and authoring](18_skills/README.md) | [Tests](../test/examples/18_skills/README.md) |

Each feature folder contains a `README.md`. Most folders also contain the
example Agent, Action, Flow, or support module. A direct API example can have
only a README and a matching test.

## Model server

[MockLLM](support/mock_llm.ex) delegates to the shared package test server. It
starts one local HTTP server per test. Scripts define model replies, tool calls,
objects, embeddings, errors, streams, and execution barriers.

The mock changes only provider responses. Tool outputs come from real Jido
Actions and Flows. It does not bypass Agent validation or create committed
state.

## Manual demos

The older files under `examples/lib/` and `examples/scripts/` remain manual
demos. They are not part of the checked example suite. New feature examples
must use the catalog structure and must include an `:example` test.
