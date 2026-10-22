# Jido AI examples

This is the checked example catalog for `jido_ai`. Source files live under
`examples/`. Matching tests live under `test/examples/`. Each feature keeps its
source, notes, and test under the same group and example ID.

The examples use real Jido AI public features and a deterministic local model
server. They do not need provider credentials.

## What the examples can do

These are executable contract examples, not only prompt demonstrations. See the [package maturity report](../docs/v3-spike/status.md)
for dated test results and release checks.

| Group | Demonstrated capability |
| --- | --- |
| Authoring | Define an AI Agent in multiple forms; use Action and Flow tools, typed output, controls, streams, and the core AI extension. |
| Requests | Run successive session requests; steer and cancel work; inspect requests; preserve context and thread values; handle completion failures, limits, and usage. |
| Tools | Validate numeric tool inputs. Action/Flow execution is also covered by the authoring group. |
| Retrieval | Store and retrieve memory and enrich Agent requests. |
| Planning | Call planning Actions and expose planning through a capability Plugin. |
| Reasoning | Select linear methods; run Algorithm, Tree, and Graph of Thoughts, TRM, and Adaptive methods; call reasoning with prompt-only input and a host-bound Profile. |
| Policy | Account for quota and accept or reject Agent requests. |
| Resume | Run standalone ReAct; resume model/tool checkpoints; supply input queues; append queries; retain trace and failure position; restore initial and terminal state. |
| Capabilities | Compose Profile-bound reasoning and chat Plugins with model routing and policy; keep their result fields separate. |
| Skills | Author and activate skills and access their resources. This is not dynamic tool-source adapter support. |

The separate [AI authoring suite](../test/authoring/README.md) checks multiple
construction paths. It checks complete definitions
and state, invalid source, Plugin composition, recovery, state limits, imports,
and same-source transport to a separate BEAM. Run it with `mix test.authoring`.
It is not included in `mix examples`.

`jido_ai` owns `Jido.Session` and `Jido.Thread`. Their module names do not imply
that applications must get these values from core Jido.

### What these examples do not prove

Provider responses are scripted. The examples exercise the HTTP/SSE client,
real Actions, Flows, AgentServer, and session code, but do not measure model
answer quality or verify every remote provider. They do not establish load
capacity, long-running reliability, or migration between source versions.
Checkpoint examples do not establish durable distributed orchestration.
The retrieval store is process-owned ETS; an Agent checkpoint does not back up
that external memory. Automatic skill authoring requires a ReAct session profile
and a live owner. See each feature guide for its configuration limits.

Dynamic native `tool_sources` remain on hold and are explicitly rejected.
Public rich-model export is out of scope; use model IDs or aliases. Core Registry
references require values supplied by the receiving host. Native AI requests
use AgentServer; direct native `Agent.cmd` execution is not supported.

## Run

Run these commands from the repository root:

```sh
mix test                                    # Excludes examples
mix examples --seed 0 --warnings-as-errors   # Runs all example tests
mix test test/examples/02_requests/02_27_thread_session_values --include example --seed 0
```

Every example test has the `:example` tag. The default test command excludes
that tag. The `mix examples` alias is the supported suite command. The catalog
rejects skipped example tests.

Example modules compile in the `:dev` and `:test` environments. Production
builds compile `lib/` only. The Hex package contains neither examples nor tests.

## Verification

Run the commands above for current evidence. The catalog checks local links,
matching test groups, guide structure, and source layout. Historical port results
remain in [the status report](../docs/v3-spike/status.md), not in lesson guides.

Test observers, failure injection, definition matrices, and new-VM launchers live
in [test support](../test/examples/support). Named tools and Plugins remain beside
the lesson, or in shared support when more than one section uses them.

The default suite includes the [ReqLLM usage regression](02_requests/02_24_stream_usage/README.md).
The pinned ReqLLM revision includes its upstream fix.

The provider-wire lessons select the Chat Completions format with
[`MockLLM.model/0`](support/mock_llm.ex). It returns a real ReqLLM model record;
only the provider responses are fixtures. Use a model ID or alias for normal
application configuration. Transport test fixtures are not portable model exports.

The checkpoint test runs in a fresh VM in the normal suite. Coverage runs omit
that check because coverage instrumentation changes code fingerprints. Run the
normal suite as well as coverage when you verify checkpoint compatibility.

## Catalog

| Group | Source and notes | Tests |
| --- | --- | --- |
| 01_authoring | [Agent and AI authoring](01_authoring/README.md) | [Tests](../test/examples/01_authoring/README.md) |
| 02_requests | [Requests, sessions, and context](02_requests/README.md) | [Tests](../test/examples/02_requests/README.md) |
| 03_tools | [Tool catalogs and context](03_tools/README.md) | [Tests](../test/examples/03_tools/README.md) |
| 07_retrieval | [Retrieval](07_retrieval/README.md) | [Tests](../test/examples/07_retrieval/README.md) |
| 08_planning | [Planning](08_planning/README.md) | [Tests](../test/examples/08_planning/README.md) |
| 09_reasoning | [Reasoning methods](09_reasoning/README.md) | [Tests](../test/examples/09_reasoning/README.md) |
| 13_policy | [Quota policy](13_policy/README.md) | [Tests](../test/examples/13_policy/README.md) |
| 14_resume | [Standalone runtime and resume](14_resume/README.md) | [Tests](../test/examples/14_resume/README.md) |
| 16_capabilities | [Capability plugins](16_capabilities/README.md) | [Tests](../test/examples/16_capabilities/README.md) |
| 18_skills | [Skill runtime and authoring](18_skills/README.md) | [Tests](../test/examples/18_skills/README.md) |

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

New examples must use the catalog structure and include an `:example` test.
