# Failures and recovery

Treat the final AI result as a candidate until validation and AgentServer
commit succeed. A provider error, invalid tool input, tool error, exhausted
repair, limit, or cancellation can fail a request. The caller gets an error;
the prior domain answer stays valid. Request records and raw Thread evidence
may still show the attempt. This is not a contradiction: audit evidence and
completed conversation Context serve different purposes.

For a failed request, inspect four facts in order: its request ID and status,
the last completed operation, the limit or error that stopped it, and the
current committed Agent state. Use public request inspection and AgentServer
snapshot APIs. Do not inspect a Coordinator's private process state. A trace
can be a retained prefix, not a durable full event log.

Retry at the application boundary after you classify the error. A transient
provider failure may justify another request. A schema failure usually needs
a changed prompt or result contract. A tool effect may already have happened;
do not replay a non-idempotent tool without a key or an application check.
Keep new request IDs for independent attempts so an observer can distinguish
them. Never treat a caller timeout as proof that the server cancelled work.

Test one success and one important failure for each teaching Agent. The
[first-answer test](../../test/examples/01_authoring/01_01_authoring_formats/01_01_authoring_formats_test.exs)
checks provider failure and later recovery. The [resume examples](../../examples/14_resume/README.md)
check harder failure positions. Continue with [tool policy](14_tool_policy.md).
