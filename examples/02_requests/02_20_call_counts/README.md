# 02_20: Model Operation Counts

This example proves how a Session records started model operations. It covers
control rejection, provider failure after a tool call, HTTP retries, invalid
provider options, cancellation, a shared model-call limit, owner loss, and late
duplicate observation Signals.

An HTTP retry stays inside one model operation. A new request starts its own
count. Committed request metadata is the source of truth after completion.

```sh
mix test test/examples/02_requests/02_20_call_counts --include example --seed 0
```
