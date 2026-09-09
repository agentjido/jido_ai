# 02_01 — Request sessions

- [Agent](agent.ex)
- [Example tests](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs)
- [Fresh-runtime tool case](unloaded_tool_session.exs)

The AI profile declares `requests do` with `mode :session`, `on_busy :reject`,
and bounded request retention. `streaming true` selects real provider SSE.
The default is one-Turn execution with streaming off.

The public `Request.create_and_send/3` waits for an admission commit before it
returns a Handle. The example's `ask` and `ask_stream` functions call this API.
The core request Turn uses a direct Action because Flow step extras do not
become Agent directives. A Plugin starts the shared reasoning Flow after the
commit. A later Signal commits the answer and terminal request record.
That Turn preserves domain changes made while the model task was running.

`Request.await/2` reads committed state through the public core Plugin API.
Its timeout does not cancel the task. A finite event receive timeout also
does not cancel work. `Session.cancel/2` commits cancellation and stops owned
work. A repeated ID cannot send a false terminal event to the original stream.

The [09_07 example](../../09_reasoning/09_07_got_api/README.md) makes busy rejection consistent across
admission paths. Request helpers return `{:error, :busy}` and the rejected
request's stream carries the same reason. Other typed errors are retained.

Only portable records enter Agent state. Sinks, tasks, provider options and
tool context stay in the Plugin process. It assigns event sequence, run,
model-call and tool-call IDs. Stream text, tools and objects use the same
provider operation and result validator. An interrupted connection cannot
publish its partial text. A blank failed response fails without a successful
model-completed event. Non-empty incomplete content remains accepted.

The tests cover admission, busy and duplicate rejection, awaits, cancellation,
SSE, usage on success/failure/cancellation, source-format parity, real tool
results, route binding, state validation, retention and shutdown cleanup. A
fresh OS runtime loads a generated Action from a temporary BEAM file, then
executes it through the mock and the production session.

The Plugin can reconstruct pending records after its process crashes. It marks
them failed with `stream_interrupted` or `request_interrupted`. The next request
gets new resources. This proves runtime reconstruction within one Agent
activation. It does not prove durable checkpoint conversion or stream replay.
The old sink is lost with a crashed Plugin; delivery of a terminal event to that
old sink remains open. `await` can read the committed interruption failure.

Still required: steering/injection and history, early tool fragments, keepalives,
all legacy request options, public Agent macro helpers, full observation and
accounting, standalone methods, durable conversion and cross-runtime restore.
The root package still uses v2 dependencies. This example does not close the
live-request migration milestone.
