# Checkpoint and resume

There are two forms of continuation. Importing initial Context restores
portable conversation data before an Agent starts. An execution checkpoint
continues a paused ReAct request from a supported boundary. They solve
different problems and do not restore the same live resources.

For initial Context, declare a Session field with `memory history:` and pass
that field through `Jido.AI.Agent.from_initial_state/3`. The import validates
the Session and complete exchanges. It does not replay tools or model calls.
It also does not restore pending request workers, input queues, or Plugin
state. The [initial-state example](../../examples/14_resume/14_11_initial_state/README.md)
shows both the Session value and its encoded form.

A ReAct checkpoint can pause after a model response or a complete tool round.
Resume checks the code, permissions, and remaining budgets. Completed tool
results are retained, so a resumed request need not run those tools again.
Partial tool batches and rollback of external effects are not supported.
Tokens are caller-owned and replayable; put durable single-use rules in your
application if the business process needs them.

Decide which form you need before you save data. If the goal is “start a new
Agent with the prior conversation,” save a `Jido.Session`. If the goal is
“continue this paused request,” use an execution checkpoint at an allowed
boundary. A raw request trace is neither form. Test resume after a complete
tool exchange and test rejection of malformed or mismatched input.

Read the [checkpoint example](../../examples/14_resume/14_03_checkpoint_resume/README.md)
and run [Resume Context](../livebooks/resume_context.livemd) for the simpler
initial-import case. The notebook does not claim to restore a live worker.
