# 13_01 — Quota accounting

Share a supervised model-call budget across Agents.

## Read the code

Read [agent.ex](agent.ex), then [reasoning_flow.ex](reasoning_flow.ex).
Then read the matching tests below.

## Run it

From the package root:

```sh
mix test test/examples/13_policy/13_01_quota --include example --seed 0
```

The default test path needs no credentials or remote provider. Model cases use
[the local HTTP/SSE server](../../support/mock_llm.ex) with real ReqLLM transport.
Shared setup and fault fixtures stay in [test support](../../../test/examples/support).

## Expected result and failure behavior

Admission rejects exhausted budgets. Each guarded model invocation consumes a slot; HTTP retries do not create another invocation. Failed calls retain known cost.

The nested reasoning Flow accepts only a prompt. The host binds a session-mode
`Jido.AI.Profile` in `:jido_ai_callable_profile` and explicitly forwards that
context key to the tool. The model cannot choose the method or its limits.
The nested call shares the outer quota; it does not receive a new budget.

## Limits

Supervise `Jido.AI.Quota.Store` before the Agent. The ledger is process-owned and is not backed up by an Agent checkpoint. Token limits cannot cap unknown in-flight provider spending. Unknown usage must not be presented as zero cost.

## Files

- [13_01_quota_test.exs](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs)
- [Shared mock_llm.ex](../../support/mock_llm.ex)

See the [example catalog](../../README.md).
