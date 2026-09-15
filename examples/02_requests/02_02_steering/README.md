# 02_02 — Steering and consumed history

Add corrections to a running request and retain consumed input in history.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/02_requests/02_02_steering --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

`Session.steer/3` and `Session.inject/3` queue input in order. Consumed text reaches the next model call. A closed queue rejects late input.

## Limits

Acceptance means queued, not consumed or durably delivered. Input cannot extend request limits. Process loss can lose queued input.

## Files

- [02_02_steering_test.exs](../../../test/examples/02_requests/02_02_steering/02_02_steering_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_01](../02_01_session/README.md) | Next: [02_11](../02_11_completion/README.md)
