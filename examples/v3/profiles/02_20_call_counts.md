# 02_20: Model operation counts after failure

The [native Agent and controls](../lib/examples/02_requests/02_20_call_counts/agent.ex)
and [13 integration cases](../test/examples/02_requests/02_20_call_counts_test.exs)
exercise real Agent, Session, Flow and ReqLLM work against the shared mock.

```sh
mix test test/examples/02_requests/02_20_call_counts_test.exs --include integration --seed 0
```

A live request starts with a known `meta.model_calls` value of zero. Each
canonical `llm_started` event increases that count. Failure and cancellation
retain the count in the committed request and its terminal event. Successful
requests keep the shared Flow result metadata. No new counter owner or event
protocol is needed.

This is a count of started model operations. An HTTP retry stays inside one
operation. Invalid provider options can fail after the operation starts but
before HTTP. An inner Quota rejection can also occur after that start and
before a charged call. The examples check each boundary with actual mock
requests and the separate Quota record. Do not use `model_calls` as a cost or
HTTP-attempt total.

The tests cover failure on the first call for all eight reasoning methods,
failure after a real tool, HTTP retries, provider-option failure, model repair,
callback repair, shared call limits, cancellation before and during provider
work, and late duplicate observation Signals. Completed usage remains intact.
A new request starts its own count and cannot change the previous record.

Owner loss has a different boundary. Recovery retains committed metadata;
it cannot recover an uncommitted live counter. The owner-loss example expects
the count to be absent, rather than a false zero, and then completes a request
on the new owner. Durable checkpoint conversion and delivery still need their
full migration checks.

This supplies partial evidence for the failure, canonical event and retained
usage requirements from PRs 262, 314, 297 and 312. It does not claim that the
new v3 metadata key existed in those PRs. The full package and recovery gates
remain open.
