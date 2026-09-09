# 14_09: Explicit standalone State conversion

[Example](agent.ex) and
[tests](../../../test/examples/14_resume/14_09_state_migration/14_09_state_migration_test.exs) use the public
State conversion, common native Agent/Flow and shared MockLLM. The 22 integration
cases are excluded by default.

## Public conversion

```elixir
alias Jido.AI.Reasoning.ReAct
alias ReAct.{State, Token}

# Decode with the original compatible Config and signing secret first.
{:ok, saved, _payload} = Token.decode_state(old_token, config)

{:ok, state} = State.migrate(saved, config,
  phase: :after_tools,
  counters: %{iterations: 1, model_calls: 1, tool_calls: 1},
  domain: %{count: 9},
  remaining_ms: 5_000
)

result =
  state
  |> ReAct.stream_from_state(config, context: %{jido: MyJido})
  |> ReAct.collect_stream()
```

The values above are example evidence. Use the saved event log, remaining
budget and reconciled application state for the actual run. Conversion requires
all four fields. It does not infer hidden model calls or domain changes from
one State iteration. A failed provider call and old output-repair calls can be
absent from assistant history. The separate model-call count must include them.
The overall time bound is supplied because old standalone State did not save it.

The source is the released **State format version 3** in **Jido AI v2**.
The old `rt2` token uses payload version 2. The new native checkpoint also uses
data version 2. These numbers identify separate formats. The fixture map follows
[the captured v2 State source](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/state.ex).
One test signs that exact old field shape, with neither of the added native
fields, before decoding and converting it. It is a contract fixture, not a
claim that the full old package ran in this test.

## Positions and retained data

| Position | Conversion and next action |
| --- | --- |
| `before_llm` | Complete saved history; next model uses the current Config instructions. |
| `after_llm` | Last entry must be the saved assistant reply. Its tools run next, or its saved answer enters output validation. |
| `after_tools` | Complete tool exchange and next reasoning position; the next model sees saved results once. |
| `terminal` | Keep completed/failed/cancelled status. Without new input, replay the saved result. With `query:`, start the next model within the retained budget. |

The old Runner emitted `after_llm` **before** setting status and pending tools.
Conversion reads the assistant tool declarations from saved history. It does
not use an empty pending list as proof that there is no tool work. Saved pending
calls, when present, must match that history and have no attempts or results.
A saved final model reply completes without another provider call. Typed output
still passes through the native validator.

Request/run IDs, sequence, user/assistant/tool history, content parts, refs,
usage, stream fields and prior tool signature remain available. Terminal result,
error and output data remain available for replay. For an old iteration-limit
result, supply `termination_reason: :max_iterations` from its terminal event.
It cannot exceed the current model, iteration, tool or time limit on resume.

The supplied domain is the application state after reconciliation. No pending
effect is imported, and no tool runs during conversion. Old standalone State
did not contain its worker's evolving domain snapshot. A caller must supply it.
The next token binds current executable code and Config. Old active tool names
and targets must exist in that Config; new permission checks still run before
execution. Provider credentials and live runtime resources are rebound normally.
A synthetic response ID is used only when an old active point has no saved
response ID; it has the explicit `migrated:` prefix.

## Failure and refinement checks

Complete history can restart after failure or cancellation. A real test completes
a tool, fails the next HTTP model call, then converts the failed State with
observed call counts. The next query succeeds without repeating the tool.
A failure before the first model can also accept new input after conversion.

An open tool exchange at restart, partial tool execution, missing evidence,
invalid call order/IDs/names, changed tool bindings, unsupported State version,
reserved domain fields and live values return a structured conversion error.
Reconcile uncertain tool effects before restart. Conversion cannot determine
whether an external side effect occurred from an unfinished tool call alone.
It does not clear or overwrite the source. A native checkpoint cannot be
imported again to replace its existing binding.

The simplification pass shares the normal tool defaults and checkpoint validator.
There is one new public State function and a pure data converter. It adds no
executor, queue, mock, storage record or second checkpoint format. New checkpoints
can represent terminal failure/cancellation with zero completed reasoning calls.
The initial 18 cases failed before the port and passed after it. Four refinement
cases added actual failure recovery, retained limits and malformed-history checks.
The focused append/resume/runtime set passes 72 checks; 11 retained token tests
also pass. See [implementation](../../../docs/v3-spike/implementation.md) for
full results.

## Remaining scope

This converts standalone State with explicit caller evidence. Automatic failure
counter projection and the complete failure-phase matrix still need work.
Partly executed tools need reconciliation, and replayable tokens do not provide
exactly-once external work. Old Agent/Strategy namespaces, persisted sink fields,
custom persistence, skills/resources and core restore are separate conversion
work. In particular, this does not close PR 332's Agent persistence cases.
The root package, consumer, minimum-runtime, migration and rollback gates remain
open. Keep the original v2 payload and package version for rollback; a new native
token is not an input format supported by the old Runner.
