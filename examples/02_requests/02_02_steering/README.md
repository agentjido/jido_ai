# 02_02 — Steering and consumed history

- [Agent](agent.ex)
- [Example tests](../../../test/examples/02_requests/02_02_steering/02_02_steering_test.exs)

The AI block enables `requests do steering true end` in session mode.
`memory do history :messages end` selects a declared domain field containing
message maps. Steering is off and no history field is selected by default.

`Session.steer/3` and `Session.inject/3` accept a server or request Handle. Both
add visible user text to the existing `PendingInputServer` queue. A Handle
supplies an expected request ID. Each result contains a control ID, input ID,
request ID, kind, status and time. Rejections also contain a reason. A queued
result means acceptance by the queue, not model consumption or durable delivery.
The legacy Agent/ReAct wrappers still need to call this common implementation.

The queue keeps its 64-item default, FIFO order, text trimming and atomic
`seal_if_empty` operation. Its process monitors the session owner. Completion,
failure and cancellation seal or stop it. A closed queue rejects late input,
including while output repair runs. Input queued before closure makes the
same request continue, within its remaining model and reasoning limits.

The initial query commits with admission. Successful model responses, real tool
results and consumed input use later core history Turns. The worker waits for
each history commit. One drain produces one history batch; each input still
gets its own canonical event. Signal payloads contain only batch IDs. The
Plugin supplies the actual entries from its runtime resources. The final result
Turn preserves all current domain history. One-Turn mode commits history with
its final candidate and leaves it unchanged on rejection.

History uses the existing `Jido.AI.Context` projection, followed by ReqLLM
normalization. This preserves real tool-call/result pairs when another request
uses that history. Caller message refs retain their compatibility precedence;
event request/run IDs keep their actual runtime identity. Both steering kinds
have user role. Source markers do not grant a system role.

The 13 tests prove held model and tool cases, consumed versus queued history,
both close orders, repair closure, guards, the 64-item bound, queue loss,
cancellation, hard limits, timeout uncertainty, history reuse, one-Turn state
preservation and authoring errors. The default test command excludes them.

Still open: legacy wrapper and generated-helper parity; source JSON execution
with an enabled history policy; interruption in every history/tool state;
compaction and context edits; queue loss at every boundary; durable conversion;
and full observation/event compatibility. A control timeout can leave input in
the queue. There is no automatic retry or durable input receipt. A process crash
can lose queued input or a staged history batch before its commit.
