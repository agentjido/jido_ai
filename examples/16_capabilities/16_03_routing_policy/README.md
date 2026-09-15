# 16_03 — Model routing and request policy

Compose model selection and policy checks with native AI and callable routes.

## Read the code

Read [agent.ex](agent.ex), then [capture.ex](capture.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/16_capabilities/16_03_routing_policy --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Explicit model input wins over route defaults. Enforced rejection prevents provider work and a domain commit. Monitor mode permits the request while retaining normalization.

## Limits

Caller context cannot replace declared policy state. This is not dynamic configuration or a complete provider-transport matrix. Domain routes retain their own input contract.

## Files

- [16_03_routing_policy_test.exs](../../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

Previous: [16_02](../16_02_chat/README.md)
