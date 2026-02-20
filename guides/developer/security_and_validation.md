# Security And Validation

You need defense-in-depth for prompts, callbacks, stream IDs, and user-visible errors.

After this guide, you can apply the runtime security modules consistently.

## Core Protections

- `Jido.AI.Validation`:
  prompt validation + sanitization (`validate_and_sanitize_prompt/1`), custom prompt hardening (`validate_custom_prompt/2`), callback validation/wrapping (`validate_callback/1`, `validate_and_wrap_callback/2`), max turns capping (`validate_max_turns/1`), and bounded string validation (`validate_string/2`).
- `Jido.AI.Error.Sanitize`:
  user-safe error messages (`sanitize_error_message/2`) and split user/log payloads (`sanitize_error_for_display/1`).
- `Jido.AI.Observe`:
  telemetry payload key redaction via `sanitize_sensitive/1` before external metadata emission.
- `Jido.AI.Streaming.ID`:
  stream ID generation/validation (`generate_stream_id/0`, `validate_stream_id/1`).

## Example

```elixir
alias Jido.AI.{Error.Sanitize, Observe, Validation}

with {:ok, prompt} <- Validation.validate_and_sanitize_prompt(user_input),
     {:ok, max_turns} <- Validation.validate_max_turns(requested_turns) do
  %{
    prompt: prompt,
    max_turns: max_turns,
    safe_meta: Observe.sanitize_sensitive(%{api_key: "secret", request_id: "req-1"}),
    safe_error: Sanitize.sanitize_error_message({:validation_error, :bad_prompt})
  }
end
```

## Failure Mode: Prompt Injection Patterns Detected

Symptom:
- validation returns `{:error, :prompt_injection_detected}`

Fix:
- reject or request prompt rewrite
- do not bypass sanitization in user-facing flows
- keep custom prompt policy strict unless explicitly justified
- use `allow_injection_patterns: true` only for explicitly trusted/internal prompt sources

## Defaults You Should Know

- hard max turns: `50`
- default callback timeout: `5_000ms`
- prompt/input lengths are bounded (`max_prompt_length/0`, `max_input_length/0`)
- `sanitize_error_message/2` always returns a generic user-facing message and only includes codes when `verbose: true` and `include_code: true`
- telemetry redaction replaces sensitive values with `[REDACTED]`

## When To Use / Not Use

Use this guide when:
- accepting external user input
- exposing errors in UI/CLI/API responses

Do not use this guide when:
- working only with trusted internal fixed prompts

## Next

- [Error Model And Recovery](error_model_and_recovery.md)
- [Directives Runtime Contract](directives_runtime_contract.md)
- [Tool Calling With Actions](../user/tool_calling_with_actions.md)
