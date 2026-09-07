# 14_04: Standalone ReAct Actions

[Example](../lib/examples/14_resume/14_04_standalone_actions/agent.ex) and
[tests](../test/examples/14_resume/14_04_standalone_actions_test.exs) use the
public Start, Continue, Collect and Cancel Actions through v3 Exec. Model
responses come from the shared MockLLM server; tools execute real code.

## Public API and Flow composition

The Actions retain their modules, names, schemas and tagged result shapes.
The old category, tags and version declarations are explicit public functions
because v3 Action configuration no longer accepts those options. Exec accepts
known string keys through the shared schema normalizer.

Start delegates to `ReAct.start/3`. It returns a lazy stream with request/run
IDs and a nil initial checkpoint token. Continue delegates to `ReAct.continue/3`.
Collect consumes events or a signed token. Data-only collection does no model
or tool work. Cancel returns a replacement cancelled token; this is separate
from cancellation of an active Exec execution.

The example Flow connects Start to Collect with a result reference. Its portable
definition contains no stream. The live stream exists only during execution.
An Agent route runs the same Flow and commits selected aggregate fields. This
proves the normal Agent/Flow composition path without storing live handles in
Agent state.

## Runtime resources and controls

Start, Continue and token Collect now use one option builder. It carries IDs,
Task supervisor, runtime context and explicit native limits. Runtime context
parameters take precedence over caller context, as before. Collect previously
lost that context when it resumed a token. The current tool now receives it.

The optional `limits` map controls total timeout and tool count. The same
native admission and batch limits apply to direct ReAct and Action callers.
The example reduces the bound below a saved two-tool batch and confirms that
neither tool starts. Without explicit limits, the public Runner defaults apply.

The helper no longer compiles against the removed AgentServer State struct.
It can still read a transient supervisor from supported context and nested
legacy maps. This does not restore the old Task-supervisor Skill or permit live
supervisors in portable Agent state.

Cancelling a collecting Exec stops its held real tool, private Agent and
supervised stream owner. Process monitors prove cleanup. Resume after a complete
tool round retains the result without executing that tool again.

## Evidence and remaining work

Thirteen integration cases cover all four Actions, direct calls, Exec, Flow,
Agent commits, string input, metadata, multimodal input, IDs, lazy execution,
saved tool work, runtime resources, limits and cancellation. The focused run
also passes 15 retained root helper cases.

Seven retained wrapper tests pass in a separate run with the installed Mimic
test dependency. They check delegation only. The 13 integration cases above
provide the real runtime evidence.

Query append on resume and old progressed-state conversion remain open. The
remaining Runner trace, redaction, cycle, provider and worker requirements also
apply to these Actions. Token replay is still caller-controlled. These examples
do not prove durable Agent persistence or every provider/media combination.

Run from `examples/v3`:

```sh
mix test test/examples/14_resume/14_04_standalone_actions_test.exs ../../test/jido_ai/react/actions/helpers_test.exs --include integration --seed 0
```

See the [implementation record](../../../docs/v3-spike/implementation.md) for
full acceptance, retained wrapper tests, package limits and next steps.
