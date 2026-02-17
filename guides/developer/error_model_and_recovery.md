# Error Model And Recovery

You need consistent error taxonomy and retry behavior across provider, tool, and validation failures.

After this guide, you can classify failures and pick the right recovery path.

## Error Types

`Jido.AI.Error` uses Splode classes:

- API errors (`Jido.AI.Error.API.*`)
  - `RateLimit`
  - `Auth`
  - `Request` (`:timeout`, `:network`, `:provider`)
- Validation errors (`Jido.AI.Error.Validation.Invalid`)
- Unknown fallback (`Jido.AI.Error.Unknown`)

## Recovery Strategy

- `RateLimit`: retry with backoff, respect provider hints
- `Request` timeout/network: retry with capped attempts
- `Auth`: fail fast, rotate credentials/config
- Validation: fail fast and return actionable messages
- Unknown: sanitize user response, log full detail

## Example: Sanitized User Message + Full Log

```elixir
err = %{file: "/srv/app/lib/secret.ex", line: 18}

%{user_message: user_message, log_message: log_message} =
  Jido.AI.Error.Sanitize.for_display(err)

IO.puts(user_message)
Logger.error(log_message)
```

## Failure Mode: Retrying Non-Retryable Errors

Symptom:
- repeated failures with no chance of success

Fix:
- do not retry auth/validation errors
- only retry transient transport/provider failures
- cap retries and emit terminal error signal

## Defaults You Should Know

- `ToolExec` supports explicit retry fields (`max_retries`, `retry_backoff_ms`)
- request timeout and strategy iteration limits are separate controls

## When To Use / Not Use

Use this guide when:
- defining error handling policy in agents, directives, or actions

Do not use this guide when:
- debugging one-off local failures without operational impact

## Next

- [Security And Validation](security_and_validation.md)
- [Directives Runtime Contract](directives_runtime_contract.md)
- [Observability Basics](../user/observability_basics.md)
