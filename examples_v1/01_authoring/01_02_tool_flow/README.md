# 01_02 — Action and Flow tools

Let the model select an Action or Flow, then use their results in an answer.

## Read the code

Read [the Agent](agent.ex), [Multiply](../../support/multiply.ex), then
[Quote](../support/quote.ex). Multiply is shared across sections. Quote is shared
within this section and has an explicit Flow output. Their named modules give
the tools stable identities.

## Run it

From the package root:

```sh
mix test test/examples/01_authoring/01_02_tool_flow --include example --seed 0
```

Expected result: tool execution and unknown-tool recovery checks pass. No
credentials or remote provider are needed.
They use the [local model server](../../support/mock_llm.ex) through real ReqLLM
transport and AgentServer, with [test setup](../../../test/examples/support/example_case.ex).

## Important behavior

The Agents set `store_content true` in their `observability` blocks to retain
tool arguments and results. This does not permit rich content in public streams
or private reasoning in storage. Without storage permission, tool work can run,
but a later request cannot resume a context with omitted tool content.

### Optional live Haiku demonstration

Read [MultiRoundAgent](multi_round_agent.ex), then [the launcher](demo.exs).
Set `ANTHROPIC_API_KEY` in your environment or the package `.env`. Do not commit
credentials. Run from the package root:

```sh
mix run examples/01_authoring/01_02_tool_flow/demo.exs
```

This makes paid requests to Claude Haiku 4.5. It asks for three dependent tool
rounds: `quote(7, 13)` → `multiply(91, 6)` → `multiply(546, 4)`, followed by a
final answer. Expected totals are 91, 546, and 2184 cents. The launcher prints
committed tool results, the answer, and elapsed time. It does not print private
model reasoning or credentials.

Limits: four model calls, three tool calls, 512 output tokens per call, and a
60-second runtime deadline. The core AgentServer Turn and caller wait have
65-second limits; the core default of five seconds is too short for this live
multi-round task. HTTP retries are disabled. Both runtime processes
are stopped on success or failure. Live model choices can vary; the prompt is
not an enforcement rule. The launcher checks the tool-result count, not answer
quality. [Deterministic tests](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs)
check result propagation, state commit, and failure after a tool round without
credentials. They bind the `:fast` application alias to the local test transport.

### Basic two-call example

The next model call receives results `6` and `20`, with their original call IDs.
The final answer enters Agent state. An unknown tool or invalid arguments in a
batch prevent every tool in that batch from starting. The model-call limit
stops further model calls without committing an answer.

## Design target checks

Read [the receipt Action and Flow](receipt.ex) for the direct-caller/Flow
boundary. Core Exec returns the Action's receipt extras. The Flow tool returns
only its explicit price output to the next model call.

[The target checks](../../../test/examples/01_authoring/01_02_tool_flow/design_requirements_test.exs)
also exercise `TLS-REQ-007`: an unknown tool must return a correlated error to
the model without a fallback Action. The runtime rejects a mixed known/unknown
batch before any tool runs and returns a correlated error for each call. The
next model round can recover within the existing request limits. See
[tool alignment](../../../docs/design/03_tool_bridge/alignment.md#acceptance-matrix).

## Limits

These tools have no external side effects. A later model failure does not undo
a tool's external work. The tests do not prove rollback for such work.

## Files

- [Agent](agent.ex)
- [Tests](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs)

Previous: [01_01](../01_01_authoring_formats/README.md) | Next: [01_03](../01_03_structured_output/README.md)
