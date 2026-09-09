# 14_10: Reasoning position on failure and cancellation

[Example](agent.ex) and
[tests](../../../test/examples/14_resume/14_10_failure_position/14_10_failure_position_test.exs) use the real
standalone Agent, Session, tools and shared MockLLM. The 18 example cases
are excluded by default.

## Counter contract

| Value | Meaning |
| --- | --- |
| Event `iteration` | Number of started model operations; repair model calls count. |
| Boundary-event data and request metadata `reasoning_iteration` | Current reasoning position. A tool round or new input advances it; output repair does not. |
| Standalone `State.iteration` | The same reasoning position, including failure and cancellation. |
| Native checkpoint `runtime.iterations` | Completed reasoning calls. |
| Native checkpoint `runtime.model_calls` | Saved model calls; separate from reasoning calls. |

Session starts with position 1, or the native checkpoint position on resume.
CallModel reports its actual position before limits, queued input, request
transformation and model controls. Model repair keeps the current position.
The existing checkpoint step reports the next position after tools. Successful
completion records the terminal position. Request-transformer State views and
the model step use the same position function.

Session includes the position in request, model-start and checkpoint events,
and terminal metadata. Stream chunks keep their existing payload fields. The standalone
adapter reads that field instead of treating every model call as another
reasoning step. It also reads committed terminal metadata. Its own terminal
checkpoint event includes the saved position. On parent loss, it retains the
last observed position without inventing a completed model or tool operation.

## Cases

The cases cover first and later provider failures; request transformation before
the first model and after tools; first and second failed repair calls; typed
validation failure; repair transformation and local callback failure; and repair
after a complete tool round. They keep model-call counts and observed usage.

Blocked repair is cancelled through the real Session, killed through its actual
worker Task, and stopped through its parent Agent. All three stop the held
provider process and retain State position 1 after two started model calls.
The parent-loss case uses the last received model event because the committed
Agent is gone. It does not claim a durable count after owner loss.

Refinement cases cover new input during a final response and append after a
saved repair response. A later rejected transformer keeps the next position
without starting another model. Existing ReAct/CoT worker tests also send a
wrong-run position update and prove it cannot change the current request.
Successful repair checks that terminal metadata and State still agree.

An initial fixture had a nil boolean and used the wrong cancellation and callback
forms. These were corrected before the valid red run. All 16 valid initial
cases then failed. After the port, 15 passed; the successful path exposed a
missing terminal metadata field. Adding that field made 83 focused checks pass.
Two more cases and the wrong-run check passed in the 40-check refinement set.
The first full run passed 1,018 of 1,019 tests. The remaining case proved that
early tool activity must keep its three-field payload. Position metadata was
limited to boundary events; that existing test remains unchanged.
Full validation is in [implementation](../../../docs/v3-spike/implementation.md).

## Scope and next work

This is a counter correction. It does not turn an interrupted tool into safe
retry work or restore a lost Session owner. Failed standalone tokens still need
[explicit State conversion](../14_09_state_migration/README.md) and external evidence for
missing counters/domain data. Old active Agent state, sink fields and custom
persistence still need their migration paths. Complete owner-loss and durable
recovery gates remain open.

The next parent port must cover the old inspection data, bounded per-request
traces, context replacement/switching, operation deduplication, compaction and
skill/resource entries. Core `AgentServer.snapshot/2` returns the committed
Agent and revision; it is not the old Strategy Snapshot. Add AI inspection
through the common Session/record model and keep live process references out
of stored state. Root package, consumer, minimum-runtime and rollback checks
remain required.
