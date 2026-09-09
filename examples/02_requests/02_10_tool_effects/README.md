# 02_10: Tool effects and complete candidate state

The [Agents and tools](agent.ex)
and [24 example tests](../../../test/examples/02_requests/02_10_tool_effects/02_10_tool_effects_test.exs)
use real core Actions, Agent commits, Dispatch and Scheduler Plugins, a local
file and the shared HTTP mock.

```sh
mix test --include example test/examples/02_requests/02_10_tool_effects/02_10_tool_effects_test.exs
```

A tool proposes complete state with `Jido.AI.Effects.state/1`:

```elixir
next = %{context.agent_state | count: context.agent_state.count + 1}
{:ok, %{count: next.count}, [Jido.AI.Effects.state(next), directive]}
```

The model receives the tool value. The runtime keeps the state proposal and
typed Directive until final output is accepted. Core commits the complete
candidate before it executes the Directives. Ordinary terminal Actions still
return their complete state directly.

The example proves these cases:

- Agent and reasoning policies intersect. A reasoning policy or caller context
  cannot widen the Agent policy. Dropped effects have recorded counts. The
  public `effect_policy` and `strategy_effect_policy` options use this code.
- Later model tool rounds receive the accepted candidate state before commit.
  Parallel proposals for different top-level fields combine in call order.
  Conflicting proposals for one field fail. Reversed completion does not change
  Directive order.
- Final assembly preserves unrelated changes made by an ordinary Agent command.
  A later write to a field changed by a tool causes a conflict instead of being
  overwritten. Nested values are complete top-level field replacements.
- Core checks state shape, schema, size and protected Plugin fields. A proposal
  cannot replace request records. Invalid state or an invalid Directive stops
  the request before the next model call, with no candidate/effect commit.
- Cancellation, output rejection and later provider failure discard pending
  state and Directives. Completed tool evidence remains available.
- A tool error with returned effects is not retried. Its error envelope still
  reaches the model. Allowed effects can commit with the later accepted answer.
- Native one-Turn and session Agents use the same reasoning Flow. A terminal
  Action carries the one-Turn candidate and Directives to core. The session
  completion Action performs the same assembly against current committed state.
- The real Dispatch Plugin sends only after final commit. Signal-prefix constraints filter its Directive. The retained Policy tests
  exercise dispatch-adapter constraints. The real Scheduler Plugin
  owns delayed work; maximum-delay constraints apply before scheduling.
- DSL, source data, Builder and source JSON retain the same policy and targets.
  The public Agent macro loads declared Plugins during compilation.
- A local file written by a tool remains after effect filtering or output
  rejection. This direct I/O is outside the Agent state transaction. The test
  notification sink receives no rejected post-commit work.

Stored tool values keep their native form when portable. Live Directive targets
stay in the runtime owner. Stored effect data uses a separate inspection form.
A state proposal records changed values and deleted keys, not a recursive copy
of earlier request records. `effects_storage: :inspection` identifies that form.
Nonportable values still use the bounded transport form. Inspection data must
not be used to replay effects.

The retained Policy and Applier tests cover canonical tuple arity, filtering,
policy constraints and direct immutable Agent assembly. These helpers do not
commit or dispatch by themselves. Old StateOp constructors are replaced by a
complete state proposal. Core Scheduler and Dispatch retain their own owners.

This is partial `API/effect-policy` and PR 318 evidence. Before/after tool
interceptors, every standalone facade and reasoning method, recovery of pending
work, default Plugin choice, all post-commit failure paths and root package
validation remain open. No new scheduler or StateOps interpreter was added.
