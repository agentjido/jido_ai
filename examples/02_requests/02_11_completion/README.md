# 02_11 — Completion and post-commit failure

Distinguish an answer commit from later Directive delivery.

## Read the code

Read [agent.ex](agent.ex), then [receipt.ex](receipt.ex), then [receipts.ex](receipts.ex), then [record_receipt.ex](record_receipt.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_11_completion --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The authored Agent commits a receipt count and its answer together. Both the
Agent and reasoning effect policies must permit the receipt Directive.
The fault tests separately prove that a failed completion commit retains a small failure record when space permits. A post-commit dispatch failure does not undo the answer or repeat tool work.

## Limits

A storage result can be uncertain even when data was saved. Await confirms request state, not delivery of every effect. Fault adapters in the tests are not durable storage.

## Files

- [02_11_completion_test.exs](../../../test/examples/02_requests/02_11_completion/02_11_completion_test.exs)
- [public_lessons_test.exs](../../../test/examples/02_requests/02_11_completion/public_lessons_test.exs)

Previous: [02_02](../02_02_steering/README.md) | Next: [02_13](../02_13_tool_limits/README.md)
