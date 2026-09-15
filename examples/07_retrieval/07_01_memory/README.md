# 07_01 — Retrieval memory

Store text and enrich an Agent request with recalled data.

## Read the code

Read [agent.ex](agent.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/07_retrieval/07_01_memory --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

A supervised retrieval store supplies real recalled entries to the model. Shared namespaces share memory. Missing stores fail enrichment unless the request explicitly opts out.

## Limits

The store is process-owned ETS, not durable memory. An Agent checkpoint does not back it up. Ranking uses token overlap, not embeddings. Completed external writes are not rolled back by an Agent failure.

## Files

- [07_01_memory_test.exs](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

See the [example catalog](../../README.md).
