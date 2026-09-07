# 02_13: Tool preflight and time limits

The [Agent and tools](../lib/examples/02_requests/02_13_tool_limits/agent.ex)
and [integration tests](../test/examples/02_requests/02_13_tool_limits_test.exs)
use the shared model mock and real core execution. The long case holds three
real tool processes for more than 31 seconds. It is part of the full acceptance
run and is excluded with the other integration cases by default.

```sh
mix test --include integration test/examples/02_requests/02_13_tool_limits_test.exs
```

Native tools can declare their attempt and retry limits:

```elixir
tools do
  action MyApp.Lookup,
    as: :lookup,
    timeout: 45_000,
    max_retries: 1,
    retry_backoff: 150
end
```

All time values are milliseconds. A timeout must be positive; retry count and
backoff can be zero. Omitted retry settings keep the native catalog defaults
of zero. DSL, source data, Builder and source JSON produce the same definition
and execute the same retries. The total request deadline bounds all attempts,
backoff and callbacks. Each attempt also has its own shorter tool timeout.

Core execution owns cleanup. A core Action timeout or Flow timeout stops the
actual child work and carries `retry: false`. AI retains that decision, even
when the tool has unused retries. A tool that permits another attempt can
return `Jido.Action.Error.timeout_error(message, %{retry: true})`. The example
executes two such attempts and a backoff whose total exceeds one attempt
budget. Killing a tool does not reverse I/O that already occurred.

This is a v3 behavior change for core timeouts. The v2 execution layer returned
a timeout without the new explicit no-retry flag, which allowed AI timeout
retries. The v3 port retains core's explicit decision. The migration guide
must state this change and explain how a tool can signal a permitted retry.

The PR 260 case checks the complete batch before tool start:

- Resolve tool identities, prepare arguments, and validate the full batch.
- Run all native operation controls, then the request's legacy preflight
  callback for each prepared call. A rejection on the second call starts no
  tool. Native rejection prevents all legacy preflight callbacks.
- The transient `context.__tool_guardrail_callback__` retains its original
  input fields: `tool_name`, `tool_call_id`, prepared `arguments`, and `context`.
  An added `validated_arguments` field exposes the schema-converted values.
  Trusted request identity and candidate state remain in the context.
- `:ok` permits execution. `{:error, reason}` fails the request, and
  `{:interrupt, value}` fails it with `{:interrupt, value}`. The failed event
  records `error_type: :tool_guardrail`. No successful result or tool-start
  event occurs. This does not add durable approval or resume.
- Malformed returns, exceptions, throws and exits become controlled failures.
  Non-function values and functions with another arity keep the old no-op
  behavior. Callbacks stay outside portable Agent state and apply to one
  request. Cancellation and the total deadline stop held callback processes.

Native operation controls can also return `{:interrupt, value}`. Other control
stages still accept only `:ok` or `{:error, reason}`.

The PR 331 case runs named Action and Flow tools plus direct `Jido.Exec.run/4`
for more than the old 30-second inner limit. Monitors and elapsed times prove
that actual work survives and completes inside the configured 45-second
budget. Shorter tests prove attempt timeout cleanup and total-deadline cleanup.

This is partial history evidence. Pending-work preflight, approval/resume,
standalone ReAct, legacy `Turn.execute_module` and Directive facades, and
recovery still need their port. Direct core Exec does not prove those legacy
AI APIs. The old error-map retry input forms also need their compatibility
decision and examples. Keepalives and stream idle limits are a separate case.
