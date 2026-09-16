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

`Jido.AI.Orchestration.steer/3` and `Jido.AI.Orchestration.inject/3` queue input in order. Consumed text reaches the next model call. A closed queue rejects late input.

## Design target checks

[The target checks](../../../test/examples/02_requests/02_02_steering/design_requirements_test.exs)
separate queued steering from completed conversation. Queued input stays out
until consumption (`SES-REQ-046`).

Pending, failed, and cancelled request input stays
out of the default completed-conversation projection (`VAL-REQ-023`,
`SES-REQ-045`). The failed-request case inspects the next actual model request.
Request records and raw Thread entries retain execution evidence. Successful
settlement promotes the request's messages into completed conversation. See
[request alignment](../../../docs/design/07_request_sessions/alignment.md#acceptance-matrix).

## Limits

Acceptance means queued, not consumed or durably delivered. Input cannot extend request limits. Process loss can lose queued input.

## Files

- [02_02_steering_test.exs](../../../test/examples/02_requests/02_02_steering/02_02_steering_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [02_01](../02_01_session/README.md) | Next: [02_11](../02_11_completion/README.md)
