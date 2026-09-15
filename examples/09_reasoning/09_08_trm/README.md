# 09_08 — TRM

Run bounded reasoning, supervision and improvement cycles.

## Read the code

Read [agent.ex](agent.ex), then [check.ex](check.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/09_reasoning/09_08_trm --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

The result is the latest completed improvement. Metadata separately retains the highest reviewed answer and score. A failed phase retains prior usage without a domain result commit.

## Limits

The final improvement may not have been reviewed. Tools, rich input, typed output and steering are rejected. Cancellation is not durable phase resumption.

## Files

- [09_08_trm_test.exs](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [09_06](../09_06_got/README.md) | Next: [09_10](../09_10_adaptive/README.md)
