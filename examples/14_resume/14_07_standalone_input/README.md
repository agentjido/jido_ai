# 14_07: Caller-supplied input queues

[Example](agent.ex) and
[tests](../../../test/examples/14_resume/14_07_standalone_input/14_07_standalone_input_test.exs) use standalone
ReAct through the native Agent, Session and common Flow. The shared MockLLM
server supplies every model response. Real tools and a real local output
repair callback execute. The 13 cases are example tests excluded by default.

## One queue and an explicit owner

`ReAct.Config.new(pending_input_server: queue, ...)` binds an existing
`Jido.AI.PendingInputServer` to the native Session. The Session creates no second
queue for that run. Direct enqueue and the public steering helpers reach the
same queue. Accepted order defines FIFO order. Existing size limits, text
trimming, source markers and refs remain available.

The caller queue keeps its declared owner. Standalone completion, failure,
stream halt, consumer loss and parent shutdown seal it against new input.
They do not stop its process or erase undrained items. The caller can inspect
or stop the sealed queue. When the declared owner exits, the queue's existing
monitor stops it. Native Sessions still stop the queues they create.

Use one queue per active run. Reusing the same queue does not reopen it.
A lazy stream that has never been consumed does not drain or seal a queue.
This option is a live runtime resource. It is not an Agent DSL field or stored
Agent data.

## Consumption and closure

Queued input joins history before a model step. Input received during real
tool work reaches the next model request after that tool result. Input accepted
while a final response is held causes another model call and one terminal
request outcome. It retains the intermediate answer in the conversation.

The empty-queue seal is atomic. Once it succeeds, later input is rejected,
even while output repair runs. Consumption cannot increase model or iteration
limits. The standalone API keeps its legacy maximum-iteration result and
termination reason when consumed input would require another forbidden call.
It does not report the prior answer as the answer to that new input.

Queue loss before a model call or before final closure produces
`{:pending_input_server, :unavailable}` with `error_type: :runtime`. Known usage
is retained. A missing queue is not treated as an empty queue.

`ReAct.steer/3` returns `{:ok, agent}`. `Session.steer/3` returns an
acknowledgement. Both formats keep their existing contract. Accepted input
means queued, not consumed or durably delivered.

## Checkpoint resume

Only consumed history enters a checkpoint. Queue process handles and undrained
items are not saved. A real pending-tool checkpoint resumes with a newly bound
queue, retains prior consumed input, executes its saved tool once and consumes
new input before the next model call. Config fingerprint and code checks remain
in force; the live queue address is not a stored contract field.

Stopping at a checkpoint seals the old borrowed queue. To accept new input
while continuing, bind a new queue in Config. The old queue's undrained items
remain the caller's responsibility. There is no automatic replay or durable
input log. Fresh-VM Agent persistence and input delivery remain separate gates.

## Validation

Run from the repository root:

```sh
mix test --include example --seed 0 test/examples/14_resume/14_07_standalone_input/14_07_standalone_input_test.exs test/examples/02_requests/02_02_steering/02_02_steering_test.exs test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs test/examples/14_resume/14_05_worker_lifecycle/14_05_worker_lifecycle_test.exs test/jido_ai/pending_input_server_test.exs
```

The focused set passes 57 checks. This includes the retained root queue tests.
The [implementation record](../../../docs/v3-spike/implementation.md) records
full acceptance results. Query append, old progressed-state conversion, parent
inspection and context lanes/compaction, skills/resources, provider variants,
durable recovery and full package gates remain open.
