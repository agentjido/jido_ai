# Security And Validation

You need defense-in-depth for prompts, callbacks, stream IDs, and user-visible errors.

After this guide, you can apply `Jido.AI.Security` systematically.

## Core Protections

- prompt validation + sanitization (`validate_and_sanitize_prompt/1`)
- custom prompt hardening (`validate_custom_prompt/2`)
- callback validation (`validate_callback/1`)
- max turns capping (`validate_max_turns/1`)
- error sanitization (`sanitize_error_message/2`)
- stream ID generation/validation (`generate_stream_id/0`, `validate_stream_id/1`)

## Example

```elixir
with {:ok, prompt} <- Jido.AI.Security.validate_and_sanitize_prompt(user_input),
     {:ok, max_turns} <- Jido.AI.Security.validate_max_turns(requested_turns) do
  %{prompt: prompt, max_turns: max_turns}
end
```

## Failure Mode: Prompt Injection Patterns Detected

Symptom:
- validation returns `{:error, :prompt_injection_detected}`

Fix:
- reject or request prompt rewrite
- do not bypass sanitization in user-facing flows
- keep custom prompt policy strict unless explicitly justified

## Defaults You Should Know

- hard max turns: `50`
- default callback timeout: `5_000ms`
- max prompt length and input length are bounded constants

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
