# Inspect Adaptive selection during a request

The [Agent example](../lib/examples/09_reasoning/09_13_active_selection/agent.ex)
and [8 integration cases](../test/examples/09_reasoning/09_13_active_selection_test.exs)
restore inspection of the current selected method. After input controls and
method preparation succeed, the existing Session owner grants one progress
update. Core commits it before the first provider call.

```elixir
agent = Jido.AgentServer.agent(server)

Jido.AI.Reasoning.Adaptive.get_selected_strategy(agent)
Jido.AI.Reasoning.Adaptive.get_complexity_score(agent)
agent.state.selected_strategy
```

The getters read canonical request metadata. The public Adaptive Agent also
projects `selected_strategy` into its compatibility state. A native Agent can
read the same selection from `state.requests[id].meta.adaptive`. It does not
need that public convenience field. Optional request IDs still inspect older
records. The existing public API test now proves an active TRM selection while
an older CoD result remains unchanged.

Before input controls finish, selection remains absent. An input rejection
makes no model call and publishes no active selection. After selection commits,
the request stays pending, `completed` stays false and `last_result` stays empty.
The first provider barrier gives a stable point at which to inspect that state.
The three-phase TRM case commits selection once, not once per phase.

The progress update uses the current request ID and run ID, plus a one-use
ticket held by the Session owner. Signal data cannot supply the selection.
The Plugin replaces any caller-supplied progress grant with the owner's grant.
An invalid ticket, a consumed ticket or a finished request fails without a
state change. The test replays the actual committed Signal and also supplies
forged progress data and context.

This is an ordinary core Turn. Host Plugins receive the caller's policy
context. Core supplies the new Turn's Agent state and bindings; the old worker
snapshot is not sent back as caller context. A host rejection stops before the
provider call. Another test closes a domain case during input control, then
proves that both selection and final result commits preserve that change.

Only known pre-execution busy and reentry errors are retried, within the request
deadline. A timeout has an unknown commit outcome and is not replayed. The
existing history update keeps its separate bounded retry policy. Selection adds
no new process, model call, tool executor or request store.

If the owner stops, recovery retains the already committed metadata and marks
the request interrupted. It does not replay the method. Cancellation closes the
provider connection, keeps the selection and permits a new request. A late
progress update cannot reopen the cancelled request. These are interruption
checks; they do not establish durable phase resume or complete stream delivery
after owner loss.

The full suite exposed a core readiness deadlock on this recovery path. The
[core lifecycle wrapper](../../../../jido/lib/jido/agent_server/plugin_child.ex)
now keeps lookup responsive while an owned task waits for replacement readiness.
Core tests check the state-read cycle, failed readiness, task loss and owner
shutdown. With that fix, the full AI acceptance run passes all 622 cases.

This closes active Adaptive method/score inspection. Active ToT/GoT/TRM phase
data, old worker/phase-input and state conversion, runtime Agent-state overrides,
CLI/capability and skill paths, full provider contracts, durable recovery and
root package/release gates remain open. The rejected-admission method-identity
gap also remains open.
