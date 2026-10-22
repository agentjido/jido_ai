# 14_06 — Trace controls and repeated tools

Control emitted deltas and tool-start argument redaction.

## Read the code

Read [agent.ex](agent.ex), then [check.ex](check.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/14_resume/14_06_trace_and_cycles --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Repeated tool inputs produce a warning before the next model call. Different full inputs remain distinct. Actual tool arguments remain unchanged by event redaction.

## Limits

Repeated calls still execute. The trace cases opt in to stream content and to
stored/streamed reasoning. Credentials remain redacted even with these permissions
and with `redact_tool_args` disabled. The native tool still receives its original
input. Checkpoint export is withheld if it would retain excluded content or
credentials. These controls do not deduplicate tool execution.

## Files

- [14_06_trace_and_cycles_test.exs](../../../test/examples/14_resume/14_06_trace_and_cycles/14_06_trace_and_cycles_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [14_04](../14_04_standalone_actions/README.md) | Next: [14_07](../14_07_standalone_input/README.md)
