# 09_16: Reasoning as a raw model tool

The [native and public Agents](agent.ex)
expose `Jido.AI.Actions.Reasoning.RunStrategy` directly as a model tool. The
[ten example cases](../../../test/examples/09_reasoning/09_16_reasoning_tool/09_16_reasoning_tool_test.exs)
use the shared HTTP/SSE mock and real core Exec, Agent and Session work.

```sh
mix test test/examples/09_reasoning/09_16_reasoning_tool/09_16_reasoning_tool_test.exs --include example --seed 0
```

The native definition uses the existing DSL:

```elixir
tools do
  action Jido.AI.Actions.Reasoning.RunStrategy,
    as: :reason,
    forward_context: [:default_model, :model_options, :ai, :jido],
    timeout: 8_000
end
```

The model calls `reason` with JSON parameters such as `strategy: "cot"`,
`prompt: "Explain this answer"` and `request_policy: "reject"`. The Action
runs the chosen method in its existing private Agent. The outer request
receives the canonical tool result, then uses another model call to answer.
The examples check all seven methods and retain their full result envelopes.
No wrapper Flow or new reasoning executor is required for this path.

The export failure came from a generic `Zoi.atom` field. The tool adapter now
uses Zoi's schema traversal to convert atom nodes to strings for JSON export.
It keeps their metadata and preserves open and strict object behavior. The
original Action schema is unchanged. Direct validation still accepts the
same atoms and rejects strings; it is not reduced to a finite enum.

At model-input validation, a string in an atom field can resolve only to an
atom already present on the host. An unknown name stays a string and fails
normal Action validation before tool work. No new atom is created. Finite
enums keep their declared label map. Default values, atom fields in arrays,
and open object data are also exercised. Existing atoms are a type rule;
the Action and request policy still determine which values are valid for work.

| Boundary | Evidence |
| --- | --- |
| Native DSL, data, Builder and trusted source JSON | Equal definitions; each completes actual outer/inner/outer requests |
| Public Agent macro | Lists the raw Action and completes a real model tool call |
| Model and tool metadata | Provider schema, function-call ID, full method result and portable Agent state |
| Nested Quota | Three actual calls charge one shared scope; a one-call limit stops further work |
| Cancellation | A held inner provider and private Agent stop; the outer Agent handles its next request |
| Provider failure | The outer model receives a canonical tool error; private provider text stays out of that message |
| Atom safety and schema stability | Unknown model names fail without atom creation; original direct validation and schema remain intact |

These cases close the raw RunStrategy schema-export gap found during the Quota
port. The existing bounded Flow example remains a valid composition example.
They add related evidence for PR 341 open-schema preservation and the audited
method-dispatch and portable-state cases. Dynamic tool registration, direct
facades, skills/resources, worker and state conversion, recovery, and root
package/consumer/runtime checks remain required.
