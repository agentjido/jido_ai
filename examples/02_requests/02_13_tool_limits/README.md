# 02_13: Tool preflight and time limits

The [Agent and tools](agent.ex)
and [example tests](../../../test/examples/02_requests/02_13_tool_limits/02_13_tool_limits_test.exs)
use the shared model mock and real core execution. The long case holds three
real tool processes for more than 31 seconds. It is part of the full acceptance
run and is excluded with the other example cases by default.

```sh
mix test --include example test/examples/02_requests/02_13_tool_limits/02_13_tool_limits_test.exs
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

Core timeout errors prevent an automatic retry. A tool can permit another
attempt when it returns `Jido.Action.Error.timeout_error/2` with `retry: true`.

The PR 260 case checks the complete batch before tool start:

- Resolve tool identities, prepare arguments, and validate the full batch.
- Run all native operation controls for each prepared call. A rejection on the
  second call starts no tool.
- `:ok` permits execution. `{:error, reason}` fails the request, and
  `{:interrupt, value}` fails it with `{:interrupt, value}`. No successful
  result or tool-start event occurs.

Native operation controls can also return `{:interrupt, value}`. Other control
stages still accept only `:ok` or `{:error, reason}`.

The long-running case runs named Action and Flow tools plus direct
`Jido.Exec.run/4`. Monitors and elapsed times prove that actual work survives
and completes inside the configured 45-second budget. Shorter tests prove
attempt timeout cleanup and total-deadline cleanup.

This example covers request tool limits and preflight controls. Approval,
resume, recovery, keepalives, and stream idle limits have separate examples.
