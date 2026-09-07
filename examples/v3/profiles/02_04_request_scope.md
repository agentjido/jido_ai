# 02_04: Request-specific tools, output and limits

The [Agent modules](../lib/examples/02_requests/02_04_request_scope/agent.ex)
and [10 integration tests](../test/examples/02_requests/02_04_request_scope_test.exs)
use the public Agent helpers, one mock server and real Action execution.

```sh
mix test --include integration test/examples/02_requests/02_04_request_scope_test.exs
```

Session preparation validates an effective profile for one request. It does
not change the Agent definition, stored default profile, or a later request.
Tools, output and limits use the same Profile and ToolCatalog validation as
the DSL and direct authoring paths. Runtime options remain transient.

The example proves these cases:

- `tools` accepts a module, module list or named map. A named map changes the
  advertised tool name and the lookup used for actual execution. `allowed_tools`
  filters that selected catalog. An empty list exposes no tools.
- Invalid tools, unknown allowed names and invalid output schemas fail before
  admission or provider work. The Agent state remains unchanged.
- `output: :raw` disables the default typed output for one request. A custom
  schema also applies to one request. A later request uses the default schema.
  Imported JSON schemas and the older `object_schema` option remain accepted.
- Positive iteration overrides can increase or decrease the public macro's
  configured count. Invalid values keep the default. Real model and tool calls
  establish the count; a later request keeps its original policy.
- The legacy Agent limit result remains a completed raw answer with
  `termination_reason: :max_iterations`. Typed output still validates and can
  repair the limit result. No extra model call is made to invent a raw answer.
- A non-strict tool advertises an open nested object, executes with a dynamic
  field, and retains that field in the next model request.

The native profile's separate model-call and elapsed-time limits still apply.
The legacy option adapter maps its one iteration budget to model calls plus
the permitted repair calls. It retains the legacy limit completion rule.
Native profiles retain their explicit limit failure rule.

The existing ToolAdapter and ToolSelection modules moved to the shared source
directory. ToolAdapter no longer depends on the removed Action schema module.
It uses Zoi's schema export before the ReqLLM JSON boundary, because ReqLLM's
direct Zoi conversion closes all objects. Strict conversion closes open
objects; non-strict conversion preserves them. The native ToolCatalog uses
this same converter. Existing ToolAdapter tests keep all 32 assertions, with
complete v3 Actions and Zoi schemas in their fixtures.

Remaining cases include request transformers on every normal/repair model
call, configured repair callbacks, output events/metadata, early tool events,
heartbeats and inactivity timeouts. Full DSL/data/source-JSON parity for the
new retry/context options and durable recovery of request policy remain open.
The root package still uses v2 dependencies.
