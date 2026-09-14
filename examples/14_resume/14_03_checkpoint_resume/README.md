# 14_03: Model and tool checkpoint resume

[Example](agent.ex),
[new-VM script](resume_vm.exs)
and [tests](../../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs) use the
public ReAct API, real tools and the shared MockLLM server.

## Checkpoint boundaries

The shared native Flow can pause after a model response and after a complete
tool round. The Session signs the saved AI state and emits a checkpoint event.
The next stream pull releases the Flow. If the consumer stops at the event,
the private Agent stops before the next operation starts.

Resume creates a new Agent and Session. An after-model checkpoint enters the
existing decision step with the saved response. An after-tools checkpoint
enters the next model step with the completed tool history. No second model or
tool loop was added. Core Exec values are never saved.

Saved data includes conversation and committed-history changes, pending calls,
proposed domain state, pending directives, usage, model/tool counts, output
repair state, request/run IDs and sequence. Provider stream handles and tool
definition callbacks are removed from provider responses. The ToolCatalog
rebuilds provider definitions. Other live values cause validation to fail.
Provider credentials, HTTP options and caller resources must be supplied again.

Current tool permission and native limits apply on resume. The saved contract
and module code hashes must match. The tests reject a changed tool target under
the same alias and changed code under the same module name. This binding does
not replace the complete code-upgrade and permission test matrix.

Resume retains the remaining execution budget. A larger new timeout cannot
extend it. Time spent in offline storage is not subtracted from that budget;
token expiry controls later continuation. Token expiry does not stop a Flow
that is already running. Cancel returns a replacement terminal token.

## Evidence and limits

The example cases prove both boundaries, completed-tool history, new-process
domain state, new HTTP transport, saved
limits and usage, typed repair, invalid signed phase data, code binding,
cancellation, exhausted time and expiry. One test launches a new operating-system
VM with the same code and fresh runtime resources. It resumes after tools,
produces the final answer and confirms that the completed tool does not run again.

This is caller-owned checkpoint data. A copied token can still replay
work. There is no durable single-consumer record or general exactly-once claim.
Partial tool batches, query append, and external pending-input queues are
outside this example. Pending directives that contain live values
need a resource-rebinding contract before they can be saved.

This does not prove the Agent persistence API, durable backup/restore, rollback,
or all provider/media forms. Trace/redaction, cycles, worker and standalone
Action ports, skills/resources, root dependencies, full package and consumer
checks, and the minimum supported runtime remain required.

## Validation

The focused run includes the example cases and the Token and PendingToolCall
contract cases. The new-VM fixture loads known application modules before safe
token decoding.

Run from the repository root:

```sh
mix test test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs --include example --seed 0
```

See the [implementation record](../../../docs/v3-spike/implementation.md) for
design history.

## Later native continuation work

[14_07](../14_07_standalone_input/README.md) adds caller-supplied input queues.
[14_08](../14_08_query_append/README.md) adds query append for initial State and native
checkpoints, including new terminal continuation data. Native checkpoint
version 2 keeps reasoning iteration separate from model-call count. Restart
from failure or cancellation is not supported.
